-- Story 14: the inspector who raised a ticket reviews evidence submitted by the
-- store owner and decides whether each flagged item is resolved.
--
-- Decision fields on the flagged item in remediation_tickets.flagged_items:
--   status           -> 'resolved' or back to 'open' when not resolved
--   review_decision  -> 'resolved' | 'not_resolved'
--   review_comment   -> inspector feedback (required when not resolved)
--   reviewed_at      -> decision time
--   remediation_deadline may be extended when the item is not resolved.
-- The ticket becomes 'resolved' once every flagged item is resolved.

create function public.review_ticket_evidence(
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

  return jsonb_build_object(
    'item_status', case when p_decision = 'resolved' then 'resolved' else 'open' end,
    'ticket_status', ticket_status
  );
end;
$$;

revoke execute on function public.review_ticket_evidence(uuid, text, text, text, date) from public, anon;
grant execute on function public.review_ticket_evidence(uuid, text, text, text, date) to authenticated;

-- An owner must not be able to reopen an item the inspector has already resolved
-- by submitting new evidence. Same function as story 12 plus that one check.
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
