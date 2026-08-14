begin;
create extension if not exists pgtap with schema extensions;
select plan(9);

select has_function('app_finance', 'enqueue_catalog_discovery_candidates',
  array['jsonb','integer'], 'bounded discovery enqueue RPC exists');
select ok(has_function_privilege('service_role',
  'app_finance.enqueue_catalog_discovery_candidates(jsonb,integer)', 'execute'),
  'service role can enqueue discovery candidates');
select ok(not has_function_privilege('authenticated',
  'app_finance.enqueue_catalog_discovery_candidates(jsonb,integer)', 'execute'),
  'ordinary users cannot enqueue global discovery batches');
select ok(not has_function_privilege('anon',
  'app_finance.enqueue_catalog_discovery_candidates(jsonb,integer)', 'execute'),
  'anonymous callers cannot enqueue global discovery batches');
select ok(not has_function_privilege('service_role',
  'app_finance.enqueue_catalog_research_automation(app_finance.account_type,text,text,text,text,text,text,text,app_finance.catalog_queue_reason,integer)',
  'execute'), 'the obsolete scheduled enqueue is removed from curator access');
select ok(has_function_privilege('authenticated',
  'app_finance.enqueue_catalog_research(app_finance.account_type,text,text,text,text,text,text,text,app_finance.catalog_queue_reason,integer)',
  'execute'), 'the existing user-requested enqueue remains available');
select ok(has_function_privilege('service_role',
  'app_finance.get_catalog_research_work(integer)', 'execute'),
  'service role can lease bounded work');
select ok(not has_function_privilege('authenticated',
  'app_finance.get_catalog_research_work(integer)', 'execute'),
  'ordinary users cannot lease curator work');
select ok(not has_function_privilege('service_role',
  'app_private.enqueue_catalog_research_common(app_finance.account_type,text,text,text,text,text,text,text,app_finance.catalog_queue_reason,integer,uuid)',
  'execute'), 'the curator cannot bypass the approved enqueue wrapper');

select * from finish();
rollback;
