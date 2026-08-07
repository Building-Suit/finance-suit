begin;
create extension if not exists pgtap with schema extensions;

select plan(10);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000d01',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'ai-research-owner@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Owner"}', now(), now()
), (
  '00000000-0000-0000-0000-000000000d02',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'ai-research-other@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Other"}', now(), now()
);

select has_table('app_finance', 'ai_card_research_requests',
  'ai_card_research_requests table exists');

-- ---------------------------------------------------------------------------
-- Owner writes a row without specifying user_id; the column default takes
-- it from auth.uid(), same as every RLS-scoped Edge Function insert will.
-- ---------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000d01","role":"authenticated"}';

insert into app_finance.ai_card_research_requests (
  request_id, account_type, request_hash, provider, model, prompt_version,
  status, normalized_result
) values (
  'req-owner-1', 'credit_card', 'hash-1', 'openai', 'gpt-test',
  'finance-card-autofill-v1', 'completed', '{"status":"resolved"}'::jsonb
);

select is(
  (select user_id from app_finance.ai_card_research_requests
    where request_id = 'req-owner-1'),
  '00000000-0000-0000-0000-000000000d01'::uuid,
  'user_id defaults to auth.uid() on insert'
);

select is(
  (select count(*)::int from app_finance.ai_card_research_requests),
  1,
  'owner sees their own row'
);

select throws_ok(
  $$insert into app_finance.ai_card_research_requests (
      request_id, account_type, request_hash, provider, model,
      prompt_version, status
    ) values (
      'req-owner-1', 'credit_card', 'hash-2', 'openai', 'gpt-test',
      'finance-card-autofill-v1', 'pending'
    )$$,
  'duplicate key value violates unique constraint "ai_card_research_requests_user_request_id_key"',
  'a second row with the same (user, request_id) is rejected'
);

-- ---------------------------------------------------------------------------
-- A different authenticated user cannot see, spoof, edit, or delete the
-- owner's row.
-- ---------------------------------------------------------------------------

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000d02","role":"authenticated"}';

select is(
  (select count(*)::int from app_finance.ai_card_research_requests),
  0,
  'a different user sees no rows via select RLS'
);

select throws_ok(
  $$insert into app_finance.ai_card_research_requests (
      user_id, request_id, account_type, request_hash, provider, model,
      prompt_version, status
    ) values (
      '00000000-0000-0000-0000-000000000d01', 'req-spoofed', 'credit_card',
      'hash-3', 'openai', 'gpt-test', 'finance-card-autofill-v1', 'pending'
    )$$,
  'new row violates row-level security policy for table "ai_card_research_requests"',
  'inserting a row with someone else''s user_id is rejected'
);

update app_finance.ai_card_research_requests
  set status = 'failed'
  where request_id = 'req-owner-1';

set local role postgres;
select is(
  (select status from app_finance.ai_card_research_requests
    where request_id = 'req-owner-1'),
  'completed',
  'a different user''s update RLS-filters to zero matching rows'
);

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000d02","role":"authenticated"}';
delete from app_finance.ai_card_research_requests
  where request_id = 'req-owner-1';

set local role postgres;
select is(
  (select count(*)::int from app_finance.ai_card_research_requests
    where request_id = 'req-owner-1'),
  1,
  'a different user''s delete RLS-filters to zero matching rows'
);

-- ---------------------------------------------------------------------------
-- The owner can update and delete their own row.
-- ---------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000d01","role":"authenticated"}';

update app_finance.ai_card_research_requests
  set status = 'failed', error_message = 'provider timeout'
  where request_id = 'req-owner-1';

select is(
  (select status from app_finance.ai_card_research_requests
    where request_id = 'req-owner-1'),
  'failed',
  'the owner can update their own row'
);

delete from app_finance.ai_card_research_requests
  where request_id = 'req-owner-1';

select is(
  (select count(*)::int from app_finance.ai_card_research_requests),
  0,
  'the owner can delete their own row'
);

select * from finish();
rollback;
