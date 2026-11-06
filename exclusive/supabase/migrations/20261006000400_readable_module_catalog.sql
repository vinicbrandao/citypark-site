-- Expose the new catalog only through base plans assigned to a visible unit.
-- Keep the legacy policies during the UI transition.
create policy readable_base_plan_module_options
  on public.customization_options for select to authenticated
  using (exists (
    select 1 from public.base_plan_option_availability a
    join public.unit_base_plan_assignments assignment
      on assignment.base_plan_id = a.base_plan_id
    join public.units u on u.id = assignment.unit_id
    where a.option_id = customization_options.id
  ));

create policy readable_base_plan_module_groups
  on public.customization_groups for select to authenticated
  using (exists (
    select 1 from public.customization_options o
    join public.base_plan_option_availability a on a.option_id = o.id
    join public.unit_base_plan_assignments assignment
      on assignment.base_plan_id = a.base_plan_id
    join public.units u on u.id = assignment.unit_id
    where o.group_id = customization_groups.id
  ));
