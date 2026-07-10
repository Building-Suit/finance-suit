# GitHub APK Release

The workflow at `.github/workflows/android-apk-release.yml` builds a production
Android APK and uploads it to a GitHub Release.

Required repository secrets:

- `SUPABASE_URL`: `https://kedjrbwnznvfqlzszawa.supabase.co`
- `SUPABASE_ANON_KEY`: the `anon` API key for the Supabase project

Do not add the Supabase `service_role` key to this mobile build workflow.

To read the current anon key from an authenticated local Supabase CLI session:

```bash
supabase projects api-keys --project-ref kedjrbwnznvfqlzszawa -o json
```

To set the secrets with GitHub CLI after the repository remote is configured:

```bash
gh secret set SUPABASE_URL --body "https://kedjrbwnznvfqlzszawa.supabase.co"
gh secret set SUPABASE_ANON_KEY --body "<anon API key>"
```

Release options:

- Push a tag like `v0.1.0` to build and publish that release.
- Run the workflow manually and provide `release_tag`.
- Run the workflow manually without `release_tag` to publish a prerelease named
  `apk-<run>-<sha>`.

The workflow runs `flutter analyze`, `flutter test`, then:

```bash
flutter build apk --release \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  --dart-define=APP_ENVIRONMENT=production \
  --dart-define=AUTH_CALLBACK_SCHEME=worktracker \
  --dart-define=AUTH_CALLBACK_HOST=auth-callback
```
