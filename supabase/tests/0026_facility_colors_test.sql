begin;
create extension if not exists pgtap with schema extensions;

select plan(9);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000070',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'color-owner@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Colour Owner"}', now(), now()
);

select has_column('app_finance', 'credit_facility_settings', 'color_hex',
  'facility settings carry a colour');
select col_is_null('app_finance', 'credit_facility_settings', 'color_hex',
  'the colour is optional');

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000070","role":"authenticated"}';

-- A facility saved without a colour keeps the default look.
select app_finance.save_credit_facility(
  'Plain Card', 'credit_card', 'EGP', 500000, 10::smallint,
  25::smallint, '1111', 3::smallint, null, null);

select results_eq(
  $$select color_hex from app_finance.credit_facility_summaries
    where name = 'Plain Card'$$,
  $$values (null::text)$$,
  'a facility saved without a colour has none'
);

-- Colours are accepted on both roles and normalized to upper case.
select app_finance.save_credit_facility(
  'Blue Card', 'credit_card', 'EGP', 500000, 10::smallint,
  25::smallint, '2222', 3::smallint, null, null,
  'active', 'full', null, null, '#1f3a5f');
select app_finance.save_credit_facility(
  'Green BNPL', 'bnpl', 'EGP', 300000, 5::smallint,
  null, null, 5::smallint, null, null,
  'active', 'full', null, null, '#0B6E4F');

select results_eq(
  $$select color_hex from app_finance.credit_facility_summaries
    where name = 'Blue Card'$$,
  $$values ('#1F3A5F'::text)$$,
  'a lower-case colour is stored normalized'
);
select results_eq(
  $$select color_hex from app_finance.credit_facility_summaries
    where name = 'Green BNPL'$$,
  $$values ('#0B6E4F'::text)$$,
  'BNPL facilities take a colour too'
);

-- Editing keeps every other field and can clear the colour again.
select app_finance.save_credit_facility(
  'Blue Card', 'credit_card', 'EGP', 500000, 10::smallint,
  25::smallint, '2222', 3::smallint, null,
  (select id from app_finance.accounts where name = 'Blue Card'),
  'active', 'full', null, null, null);

select results_eq(
  $$select color_hex, credit_limit_minor
    from app_finance.credit_facility_summaries where name = 'Blue Card'$$,
  $$values (null::text, 500000::bigint)$$,
  'clearing the colour leaves the rest of the facility intact'
);

select throws_ok(
  $$select app_finance.save_credit_facility(
      'Bad Card', 'credit_card', 'EGP', 100000, 10::smallint,
      25::smallint, null, 3::smallint, null, null,
      'active', 'full', null, null, 'not-a-colour')$$,
  'P0001', null, 'a malformed colour is rejected'
);

-- The colour is presentation only: no money figure moves because of it.
select results_eq(
  $$select outstanding_minor, available_credit_minor
    from app_finance.credit_facility_summaries where name = 'Green BNPL'$$,
  $$values (0::bigint, 300000::bigint)$$,
  'a coloured facility reports the same figures as any other'
);

-- The constraint also guards direct writes, not just the RPC.
select throws_ok(
  $$update app_finance.credit_facility_settings set color_hex = '#zzzzzz'
    where account_id =
      (select id from app_finance.accounts where name = 'Green BNPL')$$,
  '23514', null, 'the check constraint rejects a malformed colour'
);

select * from finish();
rollback;
