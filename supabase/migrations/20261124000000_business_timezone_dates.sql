-- Fix: date checks used the database's UTC date (current_date). From 6 PM
-- (7 PM in summer) until midnight US Central time UTC is already on the next
-- day, so an inspection with a remediation deadline of "today" was rejected
-- as a past date, and evidence, new deadlines and the daily deadline check
-- were judged a day early.
--
-- SafePlate's deadlines are calendar dates in US Central time, the same date
-- the app shows. private.business_today() returns that date, and every
-- deadline check now uses it instead of current_date.

create function private.business_today()
returns date
language sql
stable
set search_path = ''
as $$
  select (now() at time zone 'America/Chicago')::date;
$$;

revoke execute on function private.business_today() from public, anon, authenticated;

create or replace function private.create_remediation_ticket()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  failed_items jsonb;
begin
  if exists (
    select 1
    from jsonb_array_elements(new.checklist) as checklist_item
    where checklist_item ->> 'result' = 'fail'
      and (
        coalesce(btrim(checklist_item ->> 'comment'), '') = ''
        or coalesce(checklist_item ->> 'remediation_deadline', '') = ''
        or checklist_item ->> 'remediation_deadline' < private.business_today()::text
      )
  ) then
    raise exception 'Every failed checklist item must include a comment and a remediation deadline that is today or later';
  end if;

  select jsonb_agg(checklist_item) into failed_items
  from jsonb_array_elements(new.checklist) as checklist_item
  where checklist_item ->> 'result' = 'fail';

  if failed_items is not null then
    insert into public.remediation_tickets (inspection_id, store_id, owner_id, flagged_items)
    select new.id, new.store_id, stores.owner_id, failed_items
    from public.stores as stores
    where stores.id = new.store_id;
  end if;

  return new;
end;
$$;

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
  is_late := deadline is not null and private.business_today() > deadline;

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

create or replace function public.review_ticket_evidence(
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

  if p_new_deadline is not null and (p_decision <> 'not_resolved' or p_new_deadline < private.business_today()) then
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

create or replace function private.run_deadline_check(p_today date default private.business_today())
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  warning_days constant integer := 3;
  ticket record;
  newly_overdue text[];
  to_warn jsonb;
  flagged integer := 0;
  warned integer := 0;
begin
  for ticket in
    select tickets.id, tickets.owner_id, tickets.flagged_items, inspections.inspector_id
    from public.remediation_tickets as tickets
    join public.inspections as inspections on inspections.id = tickets.inspection_id
    where tickets.status = 'open'
      and exists (
        select 1 from jsonb_array_elements(tickets.flagged_items) as item
        where coalesce(item ->> 'status', 'open') = 'open'
          and nullif(item ->> 'remediation_deadline', '')::date < p_today + warning_days + 1
      )
    for update of tickets
  loop
    -- Story 17: deadline passed with no evidence -> overdue + inspector notified.
    select array_agg(item ->> 'item') into newly_overdue
    from jsonb_array_elements(ticket.flagged_items) as item
    where coalesce(item ->> 'status', 'open') = 'open'
      and nullif(item ->> 'remediation_deadline', '')::date < p_today;

    -- Story 19: deadline today or within warning_days, not yet warned for it.
    select jsonb_agg(jsonb_build_object('item', item ->> 'item', 'deadline', item ->> 'remediation_deadline'))
    into to_warn
    from jsonb_array_elements(ticket.flagged_items) as item
    where coalesce(item ->> 'status', 'open') = 'open'
      and nullif(item ->> 'remediation_deadline', '')::date between p_today and p_today + warning_days
      and (item ->> 'deadline_warning_sent_for') is distinct from (item ->> 'remediation_deadline');

    if newly_overdue is null and to_warn is null then
      continue;
    end if;

    update public.remediation_tickets
    set flagged_items = (
      select jsonb_agg(
        case
          when item ->> 'item' = any(coalesce(newly_overdue, '{}'))
            then item || jsonb_build_object('status', 'overdue', 'overdue_since', p_today)
          when to_warn @> jsonb_build_array(jsonb_build_object('item', item ->> 'item'))
            then item || jsonb_build_object('deadline_warning_sent_for', item ->> 'remediation_deadline', 'deadline_warning_sent_at', now())
          else item
        end
        order by position
      )
      from jsonb_array_elements(ticket.flagged_items) with ordinality as items(item, position)
    )
    where id = ticket.id;

    if newly_overdue is not null then
      insert into public.inspector_notifications (inspector_id, ticket_id, kind, item)
      select ticket.inspector_id, ticket.id, 'item_overdue', overdue_item
      from unnest(newly_overdue) as overdue_item;
      flagged := flagged + array_length(newly_overdue, 1);
    end if;

    if to_warn is not null then
      insert into public.owner_notifications (owner_id, ticket_id, kind, item, deadline)
      select ticket.owner_id, ticket.id, 'deadline_warning', warning ->> 'item', (warning ->> 'deadline')::date
      from jsonb_array_elements(to_warn) as warning;
      warned := warned + jsonb_array_length(to_warn);
    end if;
  end loop;

  return jsonb_build_object('overdue', flagged, 'warnings', warned);
end;
$$;
