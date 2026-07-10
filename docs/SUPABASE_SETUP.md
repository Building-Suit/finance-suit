# Supabase Setup

Linked remote project:

- Project: `finance tracker`
- Project ref: `kedjrbwnznvfqlzszawa`
- Postgres major version: `15`

The app exposes these schemas through the Supabase Data API:

- `app_core`
- `app_finance`
- `app_work`
- `app_salary`
- `app_reports`

`app_private` contains trigger/helper functions and is not exposed to the
client API. Product data is intentionally not stored in the default Supabase
schema.

Local workflow:

```bash
supabase start
supabase migration up --local
supabase test db
```

Use `supabase db reset` only when local development data can be discarded.

Production setup:

1. Link the CLI to the `finance tracker` project.
2. Apply migrations intentionally from version control.
3. Configure Auth redirect URLs.
4. Configure custom SMTP with Resend.
5. Use the anon key in Flutter config only.
6. Never ship service-role keys in the client.
