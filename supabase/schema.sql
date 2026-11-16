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

-- Inspectors need a directory of stores to start an inspection. This does not
-- give them write access to stores, and store owners still only see their own.
create policy "Inspectors can view stores"
on public.stores for select to authenticated
using (
  exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role = 'inspector'
  )
);

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

-- An inspection is an immutable checklist submitted by an inspector for one
-- store. The JSON array keeps the individual checklist responses together
-- while the status supports concise reporting in later stories.
create table public.inspections (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete restrict,
  inspector_id uuid not null default auth.uid() references public.profiles(id) on delete restrict,
  checklist jsonb not null default '[]'::jsonb check (jsonb_typeof(checklist) = 'array'),
  overall_status text not null check (overall_status in ('pass', 'fail')),
  notes text check (char_length(notes) <= 1000),
  created_at timestamptz not null default now()
);

create index inspections_store_id_idx on public.inspections(store_id);
create index inspections_inspector_id_idx on public.inspections(inspector_id);

alter table public.inspections enable row level security;
revoke all on public.inspections from anon;
grant select, insert on public.inspections to authenticated;

create policy "Inspectors can read their own inspections"
on public.inspections for select to authenticated
using ((select auth.uid()) = inspector_id);

create policy "Store owners can read inspections for their stores"
on public.inspections for select to authenticated
using (
  exists (
    select 1 from public.stores
    where id = store_id and owner_id = (select auth.uid())
  )
);

create policy "Inspectors can submit their own inspections"
on public.inspections for insert to authenticated
with check (
  (select auth.uid()) = inspector_id
  and exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role = 'inspector'
  )
  and exists (select 1 from public.stores where id = store_id)
);

-- A ticket is created automatically for an inspection with failed items. It is
-- visible only to the associated store owner and the inspector who submitted it.
create table public.remediation_tickets (
  id uuid primary key default gen_random_uuid(),
  inspection_id uuid not null unique references public.inspections(id) on delete cascade,
  store_id uuid not null references public.stores(id) on delete restrict,
  owner_id uuid not null references public.profiles(id) on delete restrict,
  flagged_items jsonb not null check (jsonb_typeof(flagged_items) = 'array' and jsonb_array_length(flagged_items) > 0),
  status text not null default 'open' check (status in ('open', 'resolved')),
  created_at timestamptz not null default now()
);

create index remediation_tickets_owner_id_idx on public.remediation_tickets(owner_id);
create index remediation_tickets_inspection_id_idx on public.remediation_tickets(inspection_id);

alter table public.remediation_tickets enable row level security;
revoke all on public.remediation_tickets from anon;
grant select on public.remediation_tickets to authenticated;

create policy "Store owners can read their remediation tickets"
on public.remediation_tickets for select to authenticated
using ((select auth.uid()) = owner_id);

create policy "Inspectors can read tickets they submitted"
on public.remediation_tickets for select to authenticated
using (
  exists (
    select 1 from public.inspections
    where id = inspection_id and inspector_id = (select auth.uid())
  )
);

create schema if not exists private;

create function private.create_remediation_ticket()
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
        or checklist_item ->> 'remediation_deadline' < current_date::text
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

revoke execute on function private.create_remediation_ticket() from public, anon, authenticated;

create trigger create_remediation_ticket_after_inspection
after insert on public.inspections
for each row execute function private.create_remediation_ticket();

-- A notification is created with each remediation ticket so a store owner can
-- immediately see that a new issue needs attention in their workspace.
create table public.owner_notifications (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  ticket_id uuid not null unique references public.remediation_tickets(id) on delete cascade,
  created_at timestamptz not null default now()
);

create index owner_notifications_owner_created_idx
on public.owner_notifications(owner_id, created_at desc);

alter table public.owner_notifications enable row level security;
revoke all on public.owner_notifications from anon;
grant select on public.owner_notifications to authenticated;

create policy "Store owners can read their ticket notifications"
on public.owner_notifications for select to authenticated
using ((select auth.uid()) = owner_id);

create function private.create_ticket_notification()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.owner_notifications (owner_id, ticket_id)
  values (new.owner_id, new.id);
  return new;
end;
$$;

revoke execute on function private.create_ticket_notification() from public, anon, authenticated;

create trigger create_ticket_notification_after_ticket
after insert on public.remediation_tickets
for each row execute function private.create_ticket_notification();

-- Photos are private evidence for failed checklist items. Files are stored
-- outside the database and the first path segment must be the inspector's ID.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('inspection-photos', 'inspection-photos', false, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create policy "Inspectors can upload their own inspection photos"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'inspection-photos'
  and (storage.foldername(name))[1] = (select auth.uid()::text)
  and exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role = 'inspector'
  )
);

create policy "Inspectors can read their own inspection photos"
on storage.objects for select to authenticated
using (
  bucket_id = 'inspection-photos'
  and owner_id = (select auth.uid()::text)
  and exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role = 'inspector'
  )
);

create policy "Store owners can read ticket inspection photos"
on storage.objects for select to authenticated
using (
  bucket_id = 'inspection-photos'
  and exists (
    select 1
    from public.remediation_tickets
    where owner_id = (select auth.uid())
      and flagged_items @> jsonb_build_array(jsonb_build_object('photo_path', name))
  )
);

-- Story 12: a store owner uploads evidence (a photo) that a flagged item has
-- been fixed and submits it for inspector review.
--
-- Evidence is attached to the flagged item inside remediation_tickets.flagged_items:
--   status                -> 'pending_inspector_review'
--   evidence_photo_path   -> path in the private remediation-evidence bucket
--   evidence_note         -> optional note from the owner
--   evidence_submitted_at -> submission time
--   resolved_late         -> true when submitted after the remediation deadline
--
-- Owners have no UPDATE grant on remediation_tickets. Submission is only possible
-- through submit_ticket_evidence, which checks that the caller owns the ticket.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('remediation-evidence', 'remediation-evidence', false, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

-- Paths are <owner id>/<ticket id>/<file>. An owner can only upload into their
-- own folder, and only for a ticket that belongs to them.
create policy "Store owners can upload evidence for their own tickets"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'remediation-evidence'
  and (storage.foldername(name))[1] = (select auth.uid()::text)
  and exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role = 'store_owner'
  )
  and exists (
    select 1 from public.remediation_tickets
    where id::text = (storage.foldername(name))[2]
      and owner_id = (select auth.uid())
  )
);

create policy "Store owners can read their own evidence"
on storage.objects for select to authenticated
using (
  bucket_id = 'remediation-evidence'
  and (storage.foldername(name))[1] = (select auth.uid()::text)
);

-- The inspector who raised the ticket can read evidence that was submitted on it.
create policy "Inspectors can read evidence submitted on their tickets"
on storage.objects for select to authenticated
using (
  bucket_id = 'remediation-evidence'
  and exists (
    select 1
    from public.remediation_tickets as tickets
    join public.inspections as inspections on inspections.id = tickets.inspection_id
    where inspections.inspector_id = (select auth.uid())
      and tickets.flagged_items @> jsonb_build_array(jsonb_build_object('evidence_photo_path', name))
  )
);

create function public.submit_ticket_evidence(
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

  -- AC12.3: deny anyone who is not the ticket's store owner. A missing ticket
  -- gets the same error so other stores' ticket IDs cannot be probed.
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

  -- The photo must already be uploaded to this owner's folder for this ticket.
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

  -- AC12.2: a submission after the deadline is still accepted but marked late.
  deadline := nullif(target_item ->> 'remediation_deadline', '')::date;
  is_late := deadline is not null and current_date > deadline;

  -- AC12.1: attach the evidence to the item and move it to inspector review.
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

revoke execute on function public.submit_ticket_evidence(uuid, text, text, text) from public, anon;
grant execute on function public.submit_ticket_evidence(uuid, text, text, text) to authenticated;

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

-- Story 20: an inspector retrieves the full inspection history for any store,
-- to review past violations and trends before a new inspection.
--
-- AC20.1: for a logged-in inspector and a valid store ID, the full list of past
-- inspections for that store is returned, whichever inspector carried them out.
--
-- Inspectors can otherwise only read inspections they submitted (and cannot
-- read other inspectors' profiles), so the history is served by one function
-- that checks the caller's role and returns everything the history needs:
-- the store, every inspection (newest first) with its inspector's name, and the
-- store's suspension record.

create function public.get_store_inspection_history(p_store_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller uuid := (select auth.uid());
  caller_role text;
  store public.stores%rowtype;
begin
  select role into caller_role from public.profiles where id = caller;

  if caller is null or caller_role is distinct from 'inspector' then
    raise exception 'You are not authorized to view this store''s inspection history'
      using errcode = '42501';
  end if;

  select * into store from public.stores where id = p_store_id;
  if not found then
    raise exception 'Store not found' using errcode = 'P0002';
  end if;

  return jsonb_build_object(
    'store', jsonb_build_object(
      'id', store.id,
      'name', store.name,
      'address', store.address,
      'operating_status', store.operating_status,
      'linked_at', store.created_at
    ),
    'inspections', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', inspections.id,
          'created_at', inspections.created_at,
          'overall_status', inspections.overall_status,
          'notes', inspections.notes,
          'checklist', inspections.checklist,
          'inspector_name', coalesce(nullif(btrim(profiles.full_name), ''), 'Inspector'),
          'conducted_by_viewer', inspections.inspector_id = caller,
          'ticket', case when tickets.id is null then null else jsonb_build_object(
            'id', tickets.id,
            'status', tickets.status,
            'items', tickets.flagged_items
          ) end
        )
        order by inspections.created_at desc
      )
      from public.inspections as inspections
      join public.profiles as profiles on profiles.id = inspections.inspector_id
      left join public.remediation_tickets as tickets on tickets.inspection_id = inspections.id
      where inspections.store_id = store.id
    ), '[]'::jsonb),
    'suspensions', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', suspensions.id,
          'reason', suspensions.reason,
          'item', suspensions.item,
          'suspended_at', suspensions.suspended_at,
          'lifted_at', suspensions.lifted_at,
          'lift_reason', suspensions.lift_reason
        )
        order by suspensions.suspended_at desc
      )
      from public.store_suspensions as suspensions
      where suspensions.store_id = store.id
    ), '[]'::jsonb)
  );
end;
$$;

revoke execute on function public.get_store_inspection_history(uuid) from public, anon;
grant execute on function public.get_store_inspection_history(uuid) to authenticated;

-- Story 21: a store owner retrieves the inspection history for their own
-- store only, to track compliance over time.
--
-- AC21.1: an owner requesting the history of a store they own gets the full
--         list of its past inspections.
-- AC21.2: an owner requesting another store's history is denied with an
--         authorization error (42501).
--
-- get_store_inspection_history (story 20) now also accepts store owners, for
-- stores they own. Inspectors keep access to every store.

create or replace function public.get_store_inspection_history(p_store_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller uuid := (select auth.uid());
  caller_role text;
  store public.stores%rowtype;
begin
  select role into caller_role from public.profiles where id = caller;

  if caller is null or caller_role is null or caller_role not in ('inspector', 'store_owner') then
    raise exception 'You are not authorized to view this store''s inspection history'
      using errcode = '42501';
  end if;

  select * into store from public.stores where id = p_store_id;

  -- AC21.2: a store owner may only see their own stores. Another owner's store
  -- and a store that does not exist get the same authorization error, so
  -- owners cannot discover which store IDs exist.
  if caller_role = 'store_owner' and (not found or store.owner_id <> caller) then
    raise exception 'You are not authorized to view this store''s inspection history'
      using errcode = '42501';
  end if;

  if not found then
    raise exception 'Store not found' using errcode = 'P0002';
  end if;

  return jsonb_build_object(
    'store', jsonb_build_object(
      'id', store.id,
      'name', store.name,
      'address', store.address,
      'operating_status', store.operating_status,
      'linked_at', store.created_at
    ),
    'inspections', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', inspections.id,
          'created_at', inspections.created_at,
          'overall_status', inspections.overall_status,
          'notes', inspections.notes,
          'checklist', inspections.checklist,
          'inspector_name', coalesce(nullif(btrim(profiles.full_name), ''), 'Inspector'),
          'conducted_by_viewer', inspections.inspector_id = caller,
          'ticket', case when tickets.id is null then null else jsonb_build_object(
            'id', tickets.id,
            'status', tickets.status,
            'items', tickets.flagged_items
          ) end
        )
        order by inspections.created_at desc
      )
      from public.inspections as inspections
      join public.profiles as profiles on profiles.id = inspections.inspector_id
      left join public.remediation_tickets as tickets on tickets.inspection_id = inspections.id
      where inspections.store_id = store.id
    ), '[]'::jsonb),
    'suspensions', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', suspensions.id,
          'reason', suspensions.reason,
          'item', suspensions.item,
          'suspended_at', suspensions.suspended_at,
          'lifted_at', suspensions.lifted_at,
          'lift_reason', suspensions.lift_reason
        )
        order by suspensions.suspended_at desc
      )
      from public.store_suspensions as suspensions
      where suspensions.store_id = store.id
    ), '[]'::jsonb)
  );
end;
$$;
