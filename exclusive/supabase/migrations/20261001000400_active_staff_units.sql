-- An assignment never grants access to an inactive unit, including its
-- configuration, history and legacy draft.
create or replace function public.staff_can_access_unit(p_unit_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.staff_users s
    join public.units u on u.id = p_unit_id and u.active
    where s.user_id = (select auth.uid()) and s.active
      and (s.role = 'admin' or (
        s.role = 'architect' and exists (
          select 1 from public.staff_unit_assignments a
          where a.user_id = s.user_id and a.unit_id = p_unit_id and a.active
        )
      ))
  );
$$;
