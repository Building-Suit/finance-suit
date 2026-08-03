## Summary

Describe the user-visible or operational change.

## Version impact

The PR title is the release signal:

- `feat:` → minor version
- `fix:`, `perf:`, or `refactor:` → patch version
- `type!:` or `BREAKING CHANGE:` → major version
- `docs:`, `test:`, `ci:`, `build:`, or `chore:` → no app-version bump unless runtime files change

## Validation

- [ ] Relevant Flutter tests pass
- [ ] Supabase migrations replay and pgTAP passes when database files change
- [ ] No secrets or generated signing files are committed
