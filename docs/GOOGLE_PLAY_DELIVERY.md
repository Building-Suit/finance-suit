# Google Play delivery

Finance Suit uses the permanent Android application ID
`com.buildingsuit.finance`. Google Play delivery has two repository stages:

| Source | GitHub environment | Play track | Approval |
| --- | --- | --- | --- |
| Merge a feature into `test` | `play-test` | Internal testing | Automatic |
| Promote `test` into `main` | `play-production` | Production | Automatic after the production environment gate |

Both stages use the production Supabase project. The mobile bundle contains
only the public Supabase URL and anon key; never add a Supabase `service_role`
key to GitHub Actions.

The workflow stays disabled until `PLAY_SIGNING_READY=true`. Test and
production delivery are controlled independently by
`PLAY_TEST_DELIVERY_ENABLED` and `PLAY_PRODUCTION_DELIVERY_ENABLED`. Keep the
production variable `false` until Play Console grants production access and
the `play-production` environment has its own service-account credential.

## 1. Create and retain the upload key

Generate this key on a trusted machine with a JDK installed. It is not the app
signing key managed by Google Play; it authorizes future uploads.

```bash
keytool -genkeypair -v \
  -keystore finance-suit-upload.jks \
  -storetype JKS \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -alias finance-suit-upload

keytool -export -rfc \
  -keystore finance-suit-upload.jks \
  -alias finance-suit-upload \
  -file finance-suit-upload-certificate.pem
```

Keep an offline backup of the JKS file, its passwords, alias, and exported
certificate. Do not commit any of them.

Add these repository secrets under **Settings > Secrets and variables >
Actions**:

- `PLAY_UPLOAD_KEYSTORE_BASE64`: the single-line Base64 encoding of the JKS
- `PLAY_UPLOAD_KEYSTORE_PASSWORD`
- `PLAY_UPLOAD_KEY_ALIAS`: normally `finance-suit-upload`
- `PLAY_UPLOAD_KEY_PASSWORD`

Create the Base64 value without line wrapping:

```bash
# Linux
base64 -w 0 finance-suit-upload.jks

# macOS
base64 < finance-suit-upload.jks | tr -d '\n'
```

The existing repository secrets `SUPABASE_URL` and `SUPABASE_ANON_KEY` are
used for both stages.

These repository variables are configured for the approved publisher:

- `LEGAL_DEVELOPER_NAME`: `Tareq Abdelwhap`
- `PRIVACY_CONTACT_EMAIL`: `tarekian99@gmail.com`

The in-app policy and terms use these values. The public pages are:

- Privacy: `https://tareq-abdelwhap.github.io/finance-suit-legal/privacy-policy.html`
- Terms: `https://tareq-abdelwhap.github.io/finance-suit-legal/terms.html`
- Account deletion: `https://tareq-abdelwhap.github.io/finance-suit-legal/delete-account.html`

Account-deletion deployment instructions are documented in
`docs/PRIVACY_AND_ACCOUNT_DELETION.md`.

## 2. Build the first signed app bundle

After all four signing secrets exist, set the repository variable
`PLAY_SIGNING_READY` to `true`. Set `PLAY_TEST_DELIVERY_ENABLED` to `true`
after the first signed bundle has been uploaded manually. A push to `test`
then builds, signs, and publishes the next bundle to Internal testing.

The workflow builds an Android App Bundle rather than a universal APK. Google
Play generates device-specific APKs from it, avoiding the download of unused
CPU architectures and screen-density resources. Release builds also use R8,
Dart obfuscation, tree shaking, and split Dart debug information. Retain the
symbols artifact from each build for crash symbolication.

## 3. Create the Play Console app

In Play Console, choose **Home > Create app** and use:

- App name: `Finance Suit`
- Type: App
- Pricing: Free, unless the product decision changes before the first release
- Default language: the intended store-listing language
- Application ID after upload: `com.buildingsuit.finance`

Accept the Play App Signing terms and let Google generate and manage the app
signing key. Upload the first signed AAB manually to **Testing > Internal
testing**. If Android developer verification asks for package registration,
use `com.buildingsuit.finance` and the exported upload certificate.

## 4. Enable API delivery

1. Create a Google Cloud project.
2. Enable **Google Play Android Developer API**.
3. Create a dedicated service account and JSON key.
4. In Play Console **Users and permissions**, invite the service-account email.
5. Grant app access to Finance Suit and only these permissions:
   - View app information (read-only)
   - Release apps to testing tracks
6. Save the complete JSON key as the `PLAY_SERVICE_ACCOUNT_JSON` secret in the
   `play-test` GitHub environment.
7. Set repository variable `PLAY_TEST_DELIVERY_ENABLED` to `true`.

For production, create a separate service account with Finance Suit app access,
**View app information (read-only)**, and **Release to production, exclude
devices, and use Play App Signing**. Save its JSON key as
`PLAY_SERVICE_ACCOUNT_JSON` in the `play-production` environment. Restrict that
environment to the `main` branch and set
`PLAY_PRODUCTION_DELIVERY_ENABLED=true` only after Play grants production
access.

Do not put the service-account JSON in the app bundle, repository, workflow
artifacts, issue comments, or chat messages.

## 5. Personal-account production access

New Personal Play Console accounts must complete a Closed Test with at least
12 testers continuously opted in for 14 days, then apply for production
access. Internal Testing remains the regular fast test stage, but it does not
satisfy that one-time production eligibility requirement. Complete the Closed
Test in Play Console before enabling production delivery or promoting a
release to `main`.

## Versioning and releases

- Every run uses the workflow-wide run number as Android `versionCode`, so a
  later production build is newer than earlier Internal Testing builds.
- Test builds use `<pubspec-version>-test.<run-number>` as `versionName`.
- Production uses the base `pubspec.yaml` version as `versionName`.
- Before promoting `test` to `main`, bump `pubspec.yaml` to a version that has
  never been released. The workflow rejects a tag already used by another
  commit.
- After Google Play accepts the production bundle, the workflow creates the
  matching `v<pubspec-version>` tag and publishes the AAB and checksum to a
  GitHub Release.

## Rollout commands

Create feature branches from `test` and merge them back through a pull request.
Each merge publishes a new Internal Testing build:

```bash
git switch test
git pull --ff-only origin test
git switch -c feature/my-change
# Commit and push, then open a pull request targeting test.
```

After QA approves the Internal Testing build, bump the version on `test` if
needed and open a promotion pull request from `test` to `main`. Merging that
pull request publishes the exact `main` commit to Production:

```bash
gh pr create --base main --head test \
  --title "release: promote Finance Suit v1.0.0"
```

The workflow can also be dispatched manually on either `test` or `main`; the
selected branch still determines the Play track and cannot be overridden.
