-- Story 18: an inspector suspends a store's operating status so the suspension
-- is officially recorded and visible to relevant parties.
--
-- * stores.operating_status is 'active' or 'suspended'.
-- * store_suspensions is the official record: who suspended the store, when,
--   why, the overdue issue it relates to (optional), and when/why/by whom the
--   suspension was lifted. Records cannot be edited or deleted by users.
-- * Status changes happen only through suspend_store / lift_store_suspension,
--   which only inspectors can use. The store owner is notified of both.

alter table public.stores
  add column operating_status text not null default 'active'
    check (operating_status in ('active', 'suspended'));

-- Owners may still edit their store's name and address, but not its operating
-- status (or owner). Column privileges enforce this alongside the RLS policies.
revoke insert, update on public.stores from authenticated;
grant insert (name, address) on public.stores to authenticated;
grant update (name, address) on public.stores to authenticated;

create table public.store_suspensions (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete restrict,
  owner_id uuid not null references public.profiles(id) on delete restrict,
  suspended_by uuid not null references public.profiles(id) on delete restrict,
  reason text not null check (char_length(btrim(reason)) between 1 and 1000),
  ticket_id uuid references public.remediation_tickets(id) on delete set null,
  item text,
  suspended_at timestamptz not null default now(),
  lifted_at timestamptz,
  lifted_by uuid references public.profiles(id) on delete restrict,
  lift_reason text check (lift_reason is null or char_length(btrim(lift_reason)) between 1 and 1000),
  check ((lifted_at is null) = (lifted_by is null) and (lifted_at is null) = (lift_reason is null))
);

-- At most one active suspension per store.
create unique index store_suspensions_one_active_idx on public.store_suspensions(store_id) where lifted_at is null;
create index store_suspensions_store_idx on public.store_suspensions(store_id, suspended_at desc);
create index store_suspensions_owner_idx on public.store_suspensions(owner_id);

alter table public.store_suspensions enable row level security;
revoke all on public.store_suspensions from anon;
grant select on public.store_suspensions to authenticated;

create policy "Inspectors can read all store suspensions"
on public.store_suspensions for select to authenticated
using (
  exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role = 'inspector'
  )
);

create policy "Store owners can read suspensions of their stores"
on public.store_suspensions for select to authenticated
using ((select auth.uid()) = owner_id);

-- Suspension notices are about a store, not a ticket.
alter table public.owner_notifications alter column ticket_id drop not null;
alter table public.owner_notifications
  add column store_suspension_id uuid references public.store_suspensions(id) on delete cascade;

alter table public.owner_notifications drop constraint owner_notifications_kind_check;
alter table public.owner_notifications drop constraint owner_notifications_item_matches_kind;
alter table public.owner_notifications
  add constraint owner_notifications_kind_check
    check (kind in ('ticket_issued', 'item_approved', 'item_rejected', 'store_suspended', 'suspension_lifted')),
  add constraint owner_notifications_item_matches_kind
    check (
      (kind = 'ticket_issued' and ticket_id is not null and item is null and follow_up_inspection_id is null and store_suspension_id is null)
      or (kind = 'item_approved' and ticket_id is not null and item is not null and follow_up_inspection_id is null and store_suspension_id is null)
      or (kind = 'item_rejected' and ticket_id is not null and item is not null and follow_up_inspection_id is not null and store_suspension_id is null)
      or (kind in ('store_suspended', 'suspension_lifted') and store_suspension_id is not null and follow_up_inspection_id is null)
    );

create index owner_notifications_suspension_idx on public.owner_notifications(store_suspension_id);

create function public.suspend_store(
  p_store_id uuid,
  p_reason text,
  p_ticket_id uuid default null,
  p_item text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller uuid := (select auth.uid());
  store public.stores%rowtype;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  suspension_id uuid;
begin
  if caller is null or not exists (
    select 1 from public.profiles where id = caller and role = 'inspector'
  ) then
    raise exception 'Only inspectors can suspend a store' using errcode = '42501';
  end if;

  select * into store from public.stores where id = p_store_id for update;
  if not found then
    raise exception 'Store not found' using errcode = 'P0002';
  end if;

  if v_reason is null then
    raise exception 'Provide a reason for suspending this store' using errcode = '22023';
  end if;
  if char_length(v_reason) > 1000 then
    raise exception 'Suspension reasons must be 1000 characters or fewer' using errcode = '22023';
  end if;

  if store.operating_status = 'suspended' then
    raise exception 'This store is already suspended' using errcode = 'P0001';
  end if;

  if p_ticket_id is not null and not exists (
    select 1 from public.remediation_tickets where id = p_ticket_id and store_id = p_store_id
  ) then
    raise exception 'That ticket does not belong to this store' using errcode = '22023';
  end if;

  insert into public.store_suspensions (store_id, owner_id, suspended_by, reason, ticket_id, item)
  values (store.id, store.owner_id, caller, v_reason, p_ticket_id, nullif(btrim(coalesce(p_item, '')), ''))
  returning id into suspension_id;

  update public.stores set operating_status = 'suspended' where id = store.id;

  insert into public.owner_notifications (owner_id, ticket_id, kind, store_suspension_id)
  values (store.owner_id, p_ticket_id, 'store_suspended', suspension_id);

  return suspension_id;
end;
$$;

create function public.lift_store_suspension(p_store_id uuid, p_reason text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller uuid := (select auth.uid());
  store public.stores%rowtype;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  suspension public.store_suspensions%rowtype;
begin
  if caller is null or not exists (
    select 1 from public.profiles where id = caller and role = 'inspector'
  ) then
    raise exception 'Only inspectors can lift a store suspension' using errcode = '42501';
  end if;

  select * into store from public.stores where id = p_store_id for update;
  if not found then
    raise exception 'Store not found' using errcode = 'P0002';
  end if;

  if v_reason is null then
    raise exception 'Provide a reason for lifting this suspension' using errcode = '22023';
  end if;
  if char_length(v_reason) > 1000 then
    raise exception 'Reasons must be 1000 characters or fewer' using errcode = '22023';
  end if;

  select * into suspension from public.store_suspensions
  where store_id = p_store_id and lifted_at is null
  for update;

  if not found or store.operating_status <> 'suspended' then
    raise exception 'This store is not suspended' using errcode = 'P0001';
  end if;

  update public.store_suspensions
  set lifted_at = now(), lifted_by = caller, lift_reason = v_reason
  where id = suspension.id;

  update public.stores set operating_status = 'active' where id = store.id;

  insert into public.owner_notifications (owner_id, ticket_id, kind, store_suspension_id)
  values (store.owner_id, suspension.ticket_id, 'suspension_lifted', suspension.id);

  return suspension.id;
end;
$$;

revoke execute on function public.suspend_store(uuid, text, uuid, text) from public, anon;
grant execute on function public.suspend_store(uuid, text, uuid, text) to authenticated;
revoke execute on function public.lift_store_suspension(uuid, text) from public, anon;
grant execute on function public.lift_store_suspension(uuid, text) to authenticated;
