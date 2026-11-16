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
