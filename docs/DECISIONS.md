# Decisions

- Use Flutter Material 3 for Android/iOS with future web compatibility.
- Use Riverpod for unidirectional state and provider-scoped data fetching.
- Use go_router with an indexed shell to preserve tab state.
- Use Supabase Auth and PostgreSQL with RLS as the security boundary.
- Store money as integer minor units in Dart and PostgreSQL.
- Store business dates as date-only values and map them to `PlainDate`.
- Use server-side SQL views/RPCs for dashboard, history, and reports.
- Use fl_chart for report charts.
- Use Supabase Realtime only as an invalidation signal; aggregates are re-fetched from server-side functions.
