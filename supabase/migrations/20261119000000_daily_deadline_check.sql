-- Story 17: the system flags any issue not resolved by its deadline so the
-- inspector can initiate suspension procedures.
--
-- AC17.1: a daily check flags an item whose deadline has passed with no
--         evidence submitted as 'overdue' and notifies the assigned inspector.
-- AC17.2: an item whose evidence is already waiting for review is left alone
--         and stays 'pending_inspector_review'.
--
-- A deadline is the last day to fix the issue, so an item becomes overdue on
-- the following day (deadline < current_date, UTC). The job runs at 06:05 UTC,
-- just after midnight in US Central time.

create table public.inspector_notifications (
  id uuid primary key default gen_random_uuid(),
  inspector_id uuid not null references public.profiles(id) on delete cascade,
  ticket_id uuid not null references public.remediation_tickets(id) on delete cascade,
  kind text not null check (kind in ('item_overdue')),
  item text not null,
  created_at timestamptz not null default now(),
  read_at timestamptz
);

create index inspector_notifications_unread_idx
on public.inspector_notifications(inspector_id, created_at desc) where read_at is null;
create index inspector_notifications_ticket_idx on public.inspector_notifications(ticket_id);

alter table public.inspector_notifications enable row level security;
revoke all on public.inspector_notifications from anon;
grant select on public.inspector_notifications to authenticated;

create policy "Inspectors can read their own notifications"
on public.inspector_notifications for select to authenticated
using ((select auth.uid()) = inspector_id);

create function public.mark_inspector_notifications_read(p_ids uuid[] default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  updated integer;
begin
  update public.inspector_notifications
  set read_at = now()
  where inspector_id = (select auth.uid())
    and read_at is null
    and (p_ids is null or id = any(p_ids));
  get diagnostics updated = row_count;
  return updated;
end;
$$;

revoke execute on function public.mark_inspector_notifications_read(uuid[]) from public, anon;
grant execute on function public.mark_inspector_notifications_read(uuid[]) to authenticated;

-- The daily deadline check. Only items still waiting on the store owner can
-- become overdue: no status yet, or 'open' (sent back for new evidence).
-- Items pending review, awaiting a follow-up visit, resolved or already
-- overdue are not touched, so running the check twice changes nothing.
create function private.run_deadline_check(p_today date default current_date)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  ticket record;
  newly_overdue text[];
  flagged integer := 0;
begin
  for ticket in
    select tickets.id, tickets.flagged_items, inspections.inspector_id
    from public.remediation_tickets as tickets
    join public.inspections as inspections on inspections.id = tickets.inspection_id
    where tickets.status = 'open'
      and exists (
        select 1 from jsonb_array_elements(tickets.flagged_items) as item
        where coalesce(item ->> 'status', 'open') = 'open'
          and nullif(item ->> 'remediation_deadline', '')::date < p_today
      )
    for update of tickets
  loop
    select array_agg(item ->> 'item') into newly_overdue
    from jsonb_array_elements(ticket.flagged_items) as item
    where coalesce(item ->> 'status', 'open') = 'open'
      and nullif(item ->> 'remediation_deadline', '')::date < p_today;

    update public.remediation_tickets
    set flagged_items = (
      select jsonb_agg(
        case
          when item ->> 'item' = any(newly_overdue)
            then item || jsonb_build_object('status', 'overdue', 'overdue_since', p_today)
          else item
        end
        order by position
      )
      from jsonb_array_elements(ticket.flagged_items) with ordinality as items(item, position)
    )
    where id = ticket.id;

    insert into public.inspector_notifications (inspector_id, ticket_id, kind, item)
    select ticket.inspector_id, ticket.id, 'item_overdue', overdue_item
    from unnest(newly_overdue) as overdue_item;

    flagged := flagged + coalesce(array_length(newly_overdue, 1), 0);
  end loop;

  return flagged;
end;
$$;

revoke execute on function private.run_deadline_check(date) from public, anon, authenticated;

-- Schedule the check daily with pg_cron where it is available (Supabase).
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron with schema pg_catalog;
    perform cron.schedule('safeplate-daily-deadline-check', '5 6 * * *', 'select private.run_deadline_check()');
  else
    raise notice 'pg_cron is not available; schedule private.run_deadline_check() daily another way';
  end if;
end;
$$;
