-- Story 15: when an inspector approves a submitted fix, the flagged item is
-- marked resolved (story 14) and the store owner is notified of the approval.
--
-- owner_notifications previously held exactly one row per ticket (the
-- "ticket issued" notice). It now has a kind, the item it refers to, and a
-- read_at timestamp so owners can clear notifications they have seen.

alter table public.owner_notifications
  add column kind text not null default 'ticket_issued'
    check (kind in ('ticket_issued', 'item_approved')),
  add column item text,
  add column read_at timestamptz;

alter table public.owner_notifications
  add constraint owner_notifications_item_matches_kind
    check ((kind = 'ticket_issued' and item is null) or (kind = 'item_approved' and item is not null));

-- Still at most one "ticket issued" notice per ticket; approvals can be many.
alter table public.owner_notifications drop constraint owner_notifications_ticket_id_key;
create unique index owner_notifications_ticket_issued_key
on public.owner_notifications(ticket_id) where kind = 'ticket_issued';

create index owner_notifications_unread_idx
on public.owner_notifications(owner_id, created_at desc) where read_at is null;

-- Owners have no UPDATE grant on notifications; they mark them read through this.
create function public.mark_owner_notifications_read(p_ids uuid[] default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  updated integer;
begin
  update public.owner_notifications
  set read_at = now()
  where owner_id = (select auth.uid())
    and read_at is null
    and (p_ids is null or id = any(p_ids));
  get diagnostics updated = row_count;
  return updated;
end;
$$;

revoke execute on function public.mark_owner_notifications_read(uuid[]) from public, anon;
grant execute on function public.mark_owner_notifications_read(uuid[]) to authenticated;

create or replace function public.review_ticket_evidence(
  p_ticket_id uuid,
  p_item text,
  p_decision text,
  p_comment text default null,
  p_new_deadline date default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  ticket public.remediation_tickets%rowtype;
  target_item jsonb;
  comment text := nullif(btrim(coalesce(p_comment, '')), '');
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

  -- Only the inspector who raised the ticket may review it. A missing ticket
  -- gets the same error so ticket IDs cannot be probed.
  if not found or caller is null then
    raise exception 'You are not authorized to review evidence for this ticket'
      using errcode = '42501';
  end if;

  if ticket.status <> 'open' then
    raise exception 'This ticket is already resolved' using errcode = 'P0001';
  end if;

  if p_decision is null or p_decision not in ('resolved', 'not_resolved') then
    raise exception 'Choose whether the issue is resolved or not resolved' using errcode = '22023';
  end if;

  if comment is not null and char_length(comment) > 500 then
    raise exception 'Review comments must be 500 characters or fewer' using errcode = '22023';
  end if;

  if p_decision = 'not_resolved' and comment is null then
    raise exception 'Explain what still needs to be fixed' using errcode = '22023';
  end if;

  if p_new_deadline is not null and (p_decision = 'resolved' or p_new_deadline < current_date) then
    raise exception 'A new deadline can only be set for an unresolved issue and must be today or later'
      using errcode = '22023';
  end if;

  select item into target_item
  from jsonb_array_elements(ticket.flagged_items) as item
  where item ->> 'item' = p_item;

  if target_item is null then
    raise exception 'That item is not flagged on this ticket' using errcode = 'P0002';
  end if;

  if target_item ->> 'status' is distinct from 'pending_inspector_review' then
    raise exception 'This item has no evidence waiting for review' using errcode = 'P0001';
  end if;

  select jsonb_agg(
    case
      when item ->> 'item' = p_item then item || jsonb_build_object(
        'status', case when p_decision = 'resolved' then 'resolved' else 'open' end,
        'review_decision', p_decision,
        'review_comment', comment,
        'reviewed_at', now(),
        'remediation_deadline', coalesce(p_new_deadline::text, item ->> 'remediation_deadline')
      )
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

  -- AC15.1: the store owner is notified when the inspector approves a fix.
  -- Written in the same transaction, so an approval is never left un-notified.
  if p_decision = 'resolved' then
    insert into public.owner_notifications (owner_id, ticket_id, kind, item)
    values (ticket.owner_id, ticket.id, 'item_approved', p_item);
  end if;

  return jsonb_build_object(
    'item_status', case when p_decision = 'resolved' then 'resolved' else 'open' end,
    'ticket_status', ticket_status
  );
end;
$$;
