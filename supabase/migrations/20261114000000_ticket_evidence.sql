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
