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
