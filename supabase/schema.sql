-- SafePlate Project 1 - Account & Access foundation
-- Run this once in the Supabase SQL editor, or turn it into a migration after
-- linking this repository to the team's Supabase project.

create type public.app_role as enum ('inspector', 'store_owner');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  role public.app_role not null,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- A person can only read their own profile. No client-side UPDATE policy is
-- provided, so a role selected at registration cannot be changed by the client.
create policy "Users can read their own profile"
on public.profiles for select to authenticated
using ((select auth.uid()) = id);

create function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
declare
  selected_role public.app_role;
begin
  selected_role := (new.raw_user_meta_data ->> 'role')::public.app_role;
  if selected_role is null then
    raise exception 'A registration role is required';
  end if;

  insert into public.profiles (id, full_name, role)
  values (new.id, new.raw_user_meta_data ->> 'full_name', selected_role);
  return new;
exception
  when invalid_text_representation then
    raise exception 'Registration role must be inspector or store_owner';
end;
$$;

-- Prevent public execution of a privileged trigger helper.
revoke execute on function public.handle_new_user() from public;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- Each store is linked to exactly one store-owner account. An owner may link
-- many stores, while RLS makes every store row invisible to other accounts.
create table public.stores (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 2 and 120),
  address text check (char_length(address) <= 240),
  created_at timestamptz not null default now()
);

create index stores_owner_id_idx on public.stores(owner_id);

alter table public.stores enable row level security;

-- Explicit grants keep this table reachable through the Data API while RLS
-- restricts every operation to the account that owns the store.
revoke all on public.stores from anon;
grant select, insert, update, delete on public.stores to authenticated;

create policy "Store owners can read their own stores"
on public.stores for select to authenticated
using ((select auth.uid()) = owner_id);

create policy "Store owners can link their own stores"
on public.stores for insert to authenticated
with check (
  (select auth.uid()) = owner_id
  and exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role = 'store_owner'
  )
);

create policy "Store owners can update their own stores"
on public.stores for update to authenticated
using ((select auth.uid()) = owner_id)
with check ((select auth.uid()) = owner_id);

create policy "Store owners can delete their own stores"
on public.stores for delete to authenticated
using ((select auth.uid()) = owner_id);
