-- Story 19: a store owner receives a warning notification as a deadline
-- approaches, so they have a chance to fix the issue before suspension.
--
-- The daily deadline check (story 17) now also warns the store owner about
-- every item still waiting on them whose deadline is today or within the next
-- 3 days. Each deadline is warned about once (the item records which deadline
-- it was warned for), so an extended deadline gets a fresh warning. Items with
-- evidence submitted, awaiting a follow-up visit, resolved or overdue are not
-- warned about.

alter table public.owner_notifications add column deadline date;

alter table public.owner_notifications drop constraint owner_notifications_kind_check;
alter table public.owner_notifications drop constraint owner_notifications_item_matches_kind;
alter table public.owner_notifications
  add constraint owner_notifications_kind_check
    check (kind in ('ticket_issued', 'item_approved', 'item_rejected', 'store_suspended', 'suspension_lifted', 'deadline_warning')),
  add constraint owner_notifications_item_matches_kind
    check (
      (kind = 'ticket_issued' and ticket_id is not null and item is null and follow_up_inspection_id is null and store_suspension_id is null and deadline is null)
      or (kind = 'item_approved' and ticket_id is not null and item is not null and follow_up_inspection_id is null and store_suspension_id is null and deadline is null)
      or (kind = 'item_rejected' and ticket_id is not null and item is not null and follow_up_inspection_id is not null and store_suspension_id is null and deadline is null)
      or (kind in ('store_suspended', 'suspension_lifted') and store_suspension_id is not null and follow_up_inspection_id is null and deadline is null)
      or (kind = 'deadline_warning' and ticket_id is not null and item is not null and deadline is not null and follow_up_inspection_id is null and store_suspension_id is null)
    );

-- The check now reports both counts, so its return type changes.
drop function private.run_deadline_check(date);

create function private.run_deadline_check(p_today date default current_date)
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

revoke execute on function private.run_deadline_check(date) from public, anon, authenticated;
