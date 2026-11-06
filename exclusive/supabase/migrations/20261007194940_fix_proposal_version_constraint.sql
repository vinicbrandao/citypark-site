alter table public.unit_proposal_versions
  drop constraint if exists unit_proposal_versions_check;

alter table public.unit_proposal_versions
  add constraint unit_proposal_versions_check
  check (
    (
      action = 'submitted'
      and revision = 1
      and source_module_code is null
      and source_module_revision is null
    )
    or
    (
      action = 'choices_updated'
      and revision > 1
      and (
        (
          source_module_code is null
          and source_module_revision is null
        )
        or
        (
          source_module_code is not null
          and source_module_revision > 0
        )
      )
    )
  );