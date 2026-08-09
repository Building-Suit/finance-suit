## Summary

Describe the user-visible or operational change.

## Version impact

The PR title is the release signal:

- `feat:` → minor version
- `fix:`, `perf:`, or `refactor:` → patch version
- `type!:` or `BREAKING CHANGE:` → major version
- `docs:`, `test:`, `ci:`, `build:`, or `chore:` → no app-version bump unless runtime files change

For PRs into `dev`, update `pubspec.yaml` to the exact version CI derives from
the current `dev` version and this title. Release-impact changes increment the
build number once. Promotion PRs preserve the version already tested in `dev`.

## User-facing release notes

When the app version changes, update both files with the same real user-visible
improvements. Describe benefits in plain language; omit implementation, CI,
database-migration, and internal architecture details.

- English: `distribution/whatsnew/whatsnew-en-US`
- Arabic: `distribution/whatsnew/whatsnew-ar`

## Validation

- [ ] Relevant Flutter tests pass
- [ ] Supabase migrations replay and pgTAP passes when database files change
- [ ] No secrets or generated signing files are committed
- [ ] English and Arabic release notes accurately match the user-visible changes
