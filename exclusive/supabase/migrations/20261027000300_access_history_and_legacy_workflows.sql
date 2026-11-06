create or replace function public.record_unit_access(p_unit_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v_first boolean;
begin
  -- Serialize access against activation/link changes and concurrent first opens.
  perform 1 from public.units where id=p_unit_id for update;
  if not found or (select auth.uid()) is null or not (
    coalesce(public.staff_can_access_unit(p_unit_id),false) or public.customer_can_access_unit(p_unit_id)
  ) then raise exception 'Unit access denied' using errcode='42501'; end if;
  v_first := not exists(select 1 from public.unit_activity_events
    where unit_id=p_unit_id and actor_user_id=(select auth.uid())
      and action in ('unit_opened','unit_first_opened'));
  insert into public.unit_activity_events(unit_id,actor_user_id,actor_role,action)
  values(p_unit_id,(select auth.uid()),coalesce(public.current_staff_role(),'customer'),
    case when v_first then 'unit_first_opened' else 'unit_opened' end);
end; $$;

-- The old consent/assistance workflow no longer grants access or drives the UI.
revoke execute on function public.set_architect_authorization(uuid,uuid,uuid,boolean),
  public.request_architect_assistance(uuid,uuid,uuid,text),
  public.cancel_architect_assistance(uuid),public.accept_architect_assistance(uuid),
  public.resolve_architect_assistance(uuid,text),public.list_unit_architects(uuid)
  from authenticated;
