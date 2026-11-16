-- Story 16: an inspector rejects a submitted fix and schedules a follow-up
-- physical inspection to verify it in person.
--
-- AC16.1: the item's status becomes 're_inspection_required', a follow-up
--         inspection is scheduled and the owner is notified with the reason.
-- AC16.2: a rejection without a reason is refused.
--
-- After the visit the inspector can approve the item ("verified in person"),
-- which completes the follow-up and notifies the owner as in story 15.

create table public.follow_up_inspections (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid not null references public.remediation_tickets(id) on delete cascade,
  store_id uuid not null references public.stores(id) on delete restrict,
  owner_id uuid not null references public.profiles(id) on delete restrict,
  inspector_id uuid not null references public.profiles(id) on delete restrict,
  item text not null,
  reason text not null check (char_length(btrim(reason)) between 1 and 500),
  scheduled_for timestamptz not null,
  status text not null default 'scheduled' check (status in ('scheduled', 'completed')),
  completed_at timestamptz,
  created_at timestamptz not null default now()
);

create index follow_up_inspections_inspector_idx on public.follow_up_inspections(inspector_id, scheduled_for);
create index follow_up_inspections_owner_idx on public.follow_up_inspections(owner_id, scheduled_for);
create index follow_up_inspections_ticket_idx on public.follow_up_inspections(ticket_id);

alter table public.follow_up_inspections enable row level security;
revoke all on public.follow_up_inspections from anon;
grant select on public.follow_up_inspections to authenticated;

-- Rows are only written by review_ticket_evidence.
create policy "Inspectors can read follow-ups they scheduled"
on public.follow_up_inspections for select to authenticated
using ((select auth.uid()) = inspector_id);

create policy "Store owners can read follow-ups for their stores"
on public.follow_up_inspections for select to authenticated
using ((select auth.uid()) = owner_id);

-- Rejection notices link to the follow-up, which holds the reason and visit time.
alter table public.owner_notifications
  add column follow_up_inspection_id uuid references public.follow_up_inspections(id) on delete cascade;

alter table public.owner_notifications drop constraint owner_notifications_kind_check;
alter table public.owner_notifications drop constraint owner_notifications_item_matches_kind;
alter table public.owner_notifications
  add constraint owner_notifications_kind_check
    check (kind in ('ticket_issued', 'item_approved', 'item_rejected')),
  add constraint owner_notifications_item_matches_kind
    check (
      (kind = 'ticket_issued' and item is null and follow_up_inspection_id is null)
      or (kind = 'item_approved' and item is not null and follow_up_inspection_id is null)
      or (kind = 'item_rejected' and item is not null and follow_up_inspection_id is not null)
    );

create index owner_notifications_follow_up_idx on public.owner_notifications(follow_up_inspection_id);

-- The signature gains p_follow_up_at, so the old version is replaced.
drop function public.review_ticket_evidence(uuid, text, text, text, date);

create function public.review_ticket_evidence(
  p_ticket_id uuid,
  p_item text,
  p_decision text,
  p_comment text default null,
  p_new_deadline date default null,
  p_follow_up_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  ticket public.remediation_tickets%rowtype;
  target_item jsonb;
  item_status text;
  new_status text;
  comment text := nullif(btrim(coalesce(p_comment, '')), '');
  follow_up_id uuid;
  updated_items jsonb;
  ticket_status text;
  caller uuid := (select auth.uid());
begin
  select tickets.* into ticket
  from public.remediation_tickets as tickets
  join public.inspections as inspections on inspections.id = tickets.inspection_id
  where tickets.id = p_ticket_id
    and inspections.inspector_id = caller
  for update of tickets;

  if not found or caller is null then
    raise exception 'You are not authorized to review evidence for this ticket'
      using errcode = '42501';
  end if;

  if ticket.status <> 'open' then
    raise exception 'This ticket is already resolved' using errcode = 'P0001';
  end if;

  if p_decision is null or p_decision not in ('resolved', 'not_resolved', 're_inspection') then
    raise exception 'Choose whether to approve, reject, or request new evidence' using errcode = '22023';
  end if;

  if comment is not null and char_length(comment) > 500 then
    raise exception 'Review comments must be 500 characters or fewer' using errcode = '22023';
  end if;

  -- AC16.2: a rejection must state a reason.
  if p_decision = 're_inspection' and comment is null then
    raise exception 'Provide a reason for rejecting this fix' using errcode = '22023';
  end if;

  if p_decision = 'not_resolved' and comment is null then
    raise exception 'Explain what still needs to be fixed' using errcode = '22023';
  end if;

  if p_decision = 're_inspection' and (p_follow_up_at is null or p_follow_up_at <= now()) then
    raise exception 'Choose a future date and time for the follow-up inspection' using errcode = '22023';
  end if;

  if p_follow_up_at is not null and p_decision <> 're_inspection' then
    raise exception 'A follow-up inspection can only be scheduled when rejecting a fix' using errcode = '22023';
  end if;

  if p_new_deadline is not null and (p_decision <> 'not_resolved' or p_new_deadline < current_date) then
    raise exception 'A new deadline can only be set when requesting new evidence and must be today or later'
      using errcode = '22023';
  end if;

  select item into target_item
  from jsonb_array_elements(ticket.flagged_items) as item
  where item ->> 'item' = p_item;

  if target_item is null then
    raise exception 'That item is not flagged on this ticket' using errcode = 'P0002';
  end if;

  -- Evidence waiting for review can get any decision. An item awaiting a
  -- follow-up visit can only be approved once verified in person.
  item_status := target_item ->> 'status';
  if not (
    item_status = 'pending_inspector_review'
    or (item_status = 're_inspection_required' and p_decision = 'resolved')
  ) then
    raise exception 'This item has no evidence waiting for review' using errcode = 'P0001';
  end if;

  new_status := case p_decision
    when 'resolved' then 'resolved'
    when 're_inspection' then 're_inspection_required'
    else 'open'
  end;

  if p_decision = 're_inspection' then
    insert into public.follow_up_inspections (ticket_id, store_id, owner_id, inspector_id, item, reason, scheduled_for)
    values (ticket.id, ticket.store_id, ticket.owner_id, caller, p_item, comment, p_follow_up_at)
    returning id into follow_up_id;
  end if;

  if item_status = 're_inspection_required' then
    update public.follow_up_inspections
    set status = 'completed', completed_at = now()
    where id = nullif(target_item ->> 'follow_up_inspection_id', '')::uuid
      and status = 'scheduled';
  end if;

  select jsonb_agg(
    case
      when item ->> 'item' = p_item then
        (item - 'follow_up_inspection_id' - 'follow_up_scheduled_for' - 'verified_in_person')
        || jsonb_build_object(
          'status', new_status,
          'review_decision', p_decision,
          'review_comment', comment,
          'reviewed_at', now(),
          'remediation_deadline', coalesce(p_new_deadline::text, item ->> 'remediation_deadline')
        )
        || case
          when p_decision = 're_inspection' then jsonb_build_object(
            'follow_up_inspection_id', follow_up_id,
            'follow_up_scheduled_for', p_follow_up_at
          )
          when item_status = 're_inspection_required' then jsonb_build_object('verified_in_person', true)
          else '{}'::jsonb
        end
      else item
    end
    order by position
  ) into updated_items
  from jsonb_array_elements(ticket.flagged_items) with ordinality as items(item, position);

  ticket_status := case
    when not exists (
      select 1 from jsonb_array_elements(updated_items) as item
      where item ->> 'status' is distinct from 'resolved'
    ) then 'resolved'
    else 'open'
  end;

  update public.remediation_tickets
  set flagged_items = updated_items,
      status = ticket_status
  where id = p_ticket_id;

  if p_decision = 'resolved' then
    insert into public.owner_notifications (owner_id, ticket_id, kind, item)
    values (ticket.owner_id, ticket.id, 'item_approved', p_item);
  elsif p_decision = 're_inspection' then
    -- AC16.1: the owner is notified with the reason (held on the follow-up).
    insert into public.owner_notifications (owner_id, ticket_id, kind, item, follow_up_inspection_id)
    values (ticket.owner_id, ticket.id, 'item_rejected', p_item, follow_up_id);
  end if;

  return jsonb_build_object(
    'item_status', new_status,
    'ticket_status', ticket_status,
    'follow_up_inspection_id', follow_up_id
  );
end;
$$;

revoke execute on function public.review_ticket_evidence(uuid, text, text, text, date, timestamptz) from public, anon;
grant execute on function public.review_ticket_evidence(uuid, text, text, text, date, timestamptz) to authenticated;

-- While a follow-up visit is scheduled the item is verified in person, so the
-- owner cannot replace it with new photo evidence.
create or replace function public.submit_ticket_evidence(
  p_ticket_id uuid,
  p_item text,
  p_photo_path text,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  ticket public.remediation_tickets%rowtype;
  target_item jsonb;
  deadline date;
  is_late boolean;
  updated_items jsonb;
  caller uuid := (select auth.uid());
begin
  select * into ticket
  from public.remediation_tickets
  where id = p_ticket_id
  for update;

  if not found or caller is null or ticket.owner_id <> caller then
    raise exception 'You are not authorized to submit evidence for this ticket'
      using errcode = '42501';
  end if;

  if ticket.status <> 'open' then
    raise exception 'This ticket is no longer open' using errcode = 'P0001';
  end if;

  if p_note is not null and char_length(p_note) > 500 then
    raise exception 'Evidence notes must be 500 characters or fewer' using errcode = '22023';
  end if;

  if p_photo_path is null
    or (storage.foldername(p_photo_path))[1] is distinct from caller::text
    or (storage.foldername(p_photo_path))[2] is distinct from p_ticket_id::text
    or not exists (
      select 1 from storage.objects
      where bucket_id = 'remediation-evidence' and name = p_photo_path
    )
  then
    raise exception 'Upload an evidence photo for this ticket before submitting'
      using errcode = '22023';
  end if;

  select item into target_item
  from jsonb_array_elements(ticket.flagged_items) as item
  where item ->> 'item' = p_item;

  if target_item is null then
    raise exception 'That item is not flagged on this ticket' using errcode = 'P0002';
  end if;

  if target_item ->> 'status' = 'resolved' then
    raise exception 'The inspector has already marked this item as resolved' using errcode = 'P0001';
  end if;

  if target_item ->> 'status' = 're_inspection_required' then
    raise exception 'A follow-up inspection is scheduled for this item; the inspector will verify the fix in person'
      using errcode = 'P0001';
  end if;

  deadline := nullif(target_item ->> 'remediation_deadline', '')::date;
  is_late := deadline is not null and current_date > deadline;

  select jsonb_agg(
    case
      when item ->> 'item' = p_item then item || jsonb_build_object(
        'status', 'pending_inspector_review',
        'evidence_photo_path', p_photo_path,
        'evidence_note', nullif(btrim(coalesce(p_note, '')), ''),
        'evidence_submitted_at', now(),
        'resolved_late', is_late
      )
      else item
    end
    order by position
  ) into updated_items
  from jsonb_array_elements(ticket.flagged_items) with ordinality as items(item, position);

  update public.remediation_tickets
  set flagged_items = updated_items
  where id = p_ticket_id;

  return jsonb_build_object('status', 'pending_inspector_review', 'resolved_late', is_late);
end;
$$;
