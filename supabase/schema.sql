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
