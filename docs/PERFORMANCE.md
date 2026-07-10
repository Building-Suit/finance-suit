# Performance

Performance choices:

- Dashboard summaries use RPCs.
- History filters are applied server-side.
- Default history pagination uses keyset cursor: `record_date DESC, id DESC`.
- Report charts use server-side aggregates.
- Account balance history is computed in PostgreSQL with window functions.
- Realtime invalidation is debounced.

Local seed helper:

```sql
select app_private.seed_performance_sample();
```

Use the helper only in local development with non-sensitive sample data. It is
not exposed through the client API.
