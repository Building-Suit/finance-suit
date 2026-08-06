-- Per-account Home visibility. The Home tab's balance section is a summary,
-- not an inventory: an account the user does not want on that first screen
-- (a rarely-touched deposit box, someone else's card they track) can now be
-- hidden there while staying fully visible and usable everywhere else —
-- Money tab, pickers, transfers, and reports are unaffected.

alter table app_finance.accounts
  add column if not exists hide_from_home boolean not null default false;

-- Appending a column keeps every existing reader of the view valid; the
-- column list is otherwise unchanged (42P16 forbids inserting mid-view).
create or replace view app_finance.account_balances
with (security_invoker = on) as
  select
    a.id as account_id,
    a.user_id,
    a.name,
    a.account_type,
    a.currency_code,
    a.is_default,
    a.is_archived,
    a.allow_negative_balance,
    a.opening_balance_minor,
    (a.opening_balance_minor + coalesce(f.net, 0))::bigint as balance_minor,
    coalesce(f.total_in, 0)::bigint as total_incoming_minor,
    coalesce(f.total_out, 0)::bigint as total_outgoing_minor,
    a.hide_from_home
  from app_finance.accounts a
  left join (
    select
      account_id,
      sum(signed_amount_minor) as net,
      sum(signed_amount_minor) filter (where signed_amount_minor > 0) as total_in,
      -sum(signed_amount_minor) filter (where signed_amount_minor < 0) as total_out
    from app_finance.account_flows
    group by account_id
  ) f on f.account_id = a.id;

notify pgrst, 'reload schema';
