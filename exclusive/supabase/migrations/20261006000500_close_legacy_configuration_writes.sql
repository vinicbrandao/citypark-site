-- The dashboard now saves only through save_unit_module_choices.
-- Keep historical data and functions for migration, but remove customer/staff
-- access to write paths that do not enforce per-module deadlines.
revoke execute on function public.save_unit_draft(uuid, jsonb, integer)
  from authenticated;
revoke execute on function public.save_unit_configuration(uuid, uuid, uuid, uuid[], integer)
  from authenticated;
revoke execute on function public.save_partial_unit_configuration(uuid, uuid, jsonb, integer)
  from authenticated;
revoke execute on function public.save_staff_unit_configuration(uuid, uuid, uuid[], jsonb, integer)
  from authenticated;
