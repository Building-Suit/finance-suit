# Branching and versioning

Finance Suit uses one promotion path:

```text
feature/fix branch -> dev -> stg -> main
```

- Feature and fix pull requests target `dev`.
- Only `dev` may be promoted into `stg`.
- `stg` is the Google Play Internal Testing and production-Supabase migration
  stage.
- Only `stg` may be promoted into `main`.
- `main` publishes the production Google Play release.
- Direct pushes to `dev`, `stg`, and `main` should be disabled with GitHub
  branch protection; require the matching policy and test checks instead.

## Version rule

Pull-request titles use Conventional Commit types. The highest unreleased
impact since `main` determines the next version:

| Change                                 | Version impact |
| -------------------------------------- | -------------- |
| `type!:` or `BREAKING CHANGE:`         | Major          |
| `feat:`                                | Minor          |
| `fix:`, `perf:`, `refactor:`           | Patch          |
| Docs, tests, CI, build, or chores only | None           |

Runtime-file changes with no recognized commit type conservatively count as a
patch. `tool/check_release_version.sh origin/main report` prints the required
version. Promotion to `stg` or `main` fails unless `pubspec.yaml` matches it.
The build number increments once per release version; GitHub's run number is
still used as the monotonically increasing Android `versionCode`.

`0.5.0+10` was prepared on the staging line before the current production
`main` caught up, so `tool/release_baseline.env` records that commit as a
temporary release floor. The checker automatically uses `main` again as soon
as production contains a newer version.

## User-facing release notes

Every app-version change must update both Google Play locale files:

- `distribution/whatsnew/whatsnew-en-US`
- `distribution/whatsnew/whatsnew-ar`

Both versions must describe the same user-visible changes in natural, friendly
language. Explain what users can now do or what became easier or more reliable.
Do not describe commits, CI/CD, migrations, schemas, APIs, or implementation
details. Google Play limits each locale to 500 characters.

`tool/check_play_release_notes.sh origin/main check` validates that both notes
exist, use the expected language, fit the store limit, and were updated when the
app version changed. The branch-policy job also shows both notes in its workflow
summary for human accuracy review. The Play upload publishes both files, while
the production GitHub release combines them into one bilingual description.

## CI/CD behavior

- Pull requests into `dev` run cached Flutter checks only when app files
  change. Supabase migration replay and pgTAP run only when `supabase/**`
  changes.
- Pushes to `stg` back up the shared production Supabase project, apply any
  pending migrations, verify schema/RLS, deploy `delete-account`, and then
  publish to Google Play Internal Testing.
- Pushes to `main` repeat the idempotent Supabase check before publishing the
  production AAB and GitHub release.

GitHub Actions caches are branch-scoped for security. A cache written on the
`dev` branch cannot safely seed a sibling `stg` push. Instead, Flutter/pub and
Gradle caches are retained for repeated runs on each branch, and the quality
job warms the same cache used by the delivery job in that `stg` or `main` run.
