-- AI card/BNPL research request metadata (server-side AI autofill feature).
--
-- Stores only sanitized request/response metadata for the AI research Edge
-- Function: no provider secrets, no raw provider payloads, no PAN/CVV/PIN.
-- This table exists to support server-side rate limiting, short-lived
-- duplicate-request caching, and auditability of what the AI researched —
-- it is never read by any financial RPC and never authorizes account
-- creation on its own. The existing `save_credit_facility` RPC remains the
-- only path that creates a Credit Card or BNPL account.

create table app_finance.ai_card_research_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  request_id text not null,
  account_type app_finance.account_type not null,
  request_hash text not null,
  provider text not null,
  model text not null,
  prompt_version text not null,
  status text not null default 'pending'
    check (status in ('pending', 'completed', 'failed')),
  normalized_result jsonb,
  error_message text,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  constraint ai_card_research_requests_account_type_check
    check (account_type in ('credit_card', 'bnpl'))
);

create unique index ai_card_research_requests_user_request_id_key
  on app_finance.ai_card_research_requests (user_id, request_id);

create index ai_card_research_requests_user_created_at_idx
  on app_finance.ai_card_research_requests (user_id, created_at desc);

-- Recent-duplicate lookup: same user + same normalized inputs, so a
-- double-tap of "Find and fill" can reuse an in-flight/just-completed
-- result instead of re-querying the AI provider.
create index ai_card_research_requests_user_hash_idx
  on app_finance.ai_card_research_requests (user_id, request_hash, created_at desc);

alter table app_finance.ai_card_research_requests enable row level security;

create policy ai_card_research_requests_select
  on app_finance.ai_card_research_requests
  for select to authenticated using ((select auth.uid()) = user_id);
create policy ai_card_research_requests_insert
  on app_finance.ai_card_research_requests
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy ai_card_research_requests_update
  on app_finance.ai_card_research_requests
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy ai_card_research_requests_delete
  on app_finance.ai_card_research_requests
  for delete to authenticated using ((select auth.uid()) = user_id);

notify pgrst, 'reload schema';
