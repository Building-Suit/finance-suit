-- Categories become deletable, but only when nothing references them:
-- no transactions, no subcategories, no installment plans, no fee rules,
-- no held amounts, no macro items, and no income sources. Anything in use
-- keeps the archive path instead, so history never loses its labels.

create or replace function app_finance.delete_transaction_category(
  p_category_id uuid
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_category record;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;
  select c.id into v_category
    from app_finance.transaction_categories c
    where c.id = p_category_id and c.user_id = v_user_id
    for update;
  if v_category is null then
    raise exception 'not_found: category';
  end if;

  if exists (
    select 1 from app_finance.transaction_categories child
    where child.parent_category_id = p_category_id
  ) then
    raise exception
      'category_in_use: delete or move its subcategories first';
  end if;
  if exists (
    select 1 from app_finance.financial_transactions t
    where t.category_id = p_category_id
  ) or exists (
    select 1 from app_finance.transaction_macro_items m
    where m.category_id = p_category_id
  ) or exists (
    select 1 from app_finance.held_amounts h
    where h.category_id = p_category_id
  ) or exists (
    select 1 from app_finance.installment_plans p
    where p.category_id = p_category_id
  ) or exists (
    select 1 from app_finance.credit_card_fee_rules r
    where r.category_id = p_category_id
  ) or exists (
    select 1 from app_finance.income_sources s
    where s.category_id = p_category_id
  ) or exists (
    select 1 from app_finance.recurring_rules rr
    where rr.category_id = p_category_id
  ) then
    raise exception
      'category_in_use: this category still labels existing records';
  end if;

  delete from app_finance.transaction_categories
    where id = p_category_id and user_id = v_user_id;
end;
$$;

revoke execute on function app_finance.delete_transaction_category(uuid)
from public, anon;
grant execute on function app_finance.delete_transaction_category(uuid)
to authenticated, service_role;

notify pgrst, 'reload schema';
