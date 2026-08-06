-- Salaries accepted before partial acceptance existed recorded only what
-- arrived. A 44,000 salary paid as 40,000 left no trace of the missing
-- 4,000, so the pending list jumped straight to next month instead of
-- showing the money still owed.
--
-- Give those acceptances the remainder occurrence they would get today.
-- The backfill is idempotent (an acceptance that already spawned a
-- remainder is skipped) and bounded to the window the automation still
-- prompts on, so old history is never reopened.

create or replace function app_private.backfill_untracked_salary_shortfalls(
  p_within_days integer default 62
)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_inserted integer;
begin
  insert into app_finance.income_occurrences (
    user_id, income_source_id, scheduled_on, expected_amount_minor,
    remainder_of_occurrence_id, status
  )
  select
    o.user_id,
    o.income_source_id,
    coalesce(o.received_on, o.scheduled_on),
    owed.total_minor - o.actual_amount_minor,
    o.id,
    'pending'
  from app_finance.income_occurrences o
  join app_finance.income_sources s
    on s.id = o.income_source_id and s.user_id = o.user_id
  join app_salary.salary_periods p
    on p.id = o.salary_period_id and p.user_id = o.user_id
  cross join lateral (
    select coalesce(
      (p.snapshot ->> 'total_minor')::bigint,
      coalesce((p.snapshot ->> 'base_salary_minor')::bigint, 0)
        + coalesce((p.snapshot ->> 'extra_day_amount_minor')::bigint, 0)
        + coalesce((p.snapshot ->> 'overtime_amount_minor')::bigint, 0)
        + coalesce((p.snapshot ->> 'holiday_amount_minor')::bigint, 0)
        + coalesce((p.snapshot ->> 'bonuses_minor')::bigint, 0)
        - coalesce((p.snapshot ->> 'deductions_minor')::bigint, 0)
    ) as total_minor
  ) owed
  where s.source_kind = 'salary'
    and o.status = 'accepted'
    and o.remainder_of_occurrence_id is null
    and o.actual_amount_minor is not null
    and owed.total_minor > o.actual_amount_minor
    and coalesce(o.received_on, o.scheduled_on)
      >= current_date - greatest(coalesce(p_within_days, 62), 0)
    and not exists (
      select 1 from app_finance.income_occurrences r
      where r.remainder_of_occurrence_id = o.id
    );

  get diagnostics v_inserted = row_count;
  return v_inserted;
end;
$$;

revoke execute on function app_private.backfill_untracked_salary_shortfalls(
  integer
) from public, anon, authenticated;

select app_private.backfill_untracked_salary_shortfalls();

notify pgrst, 'reload schema';
