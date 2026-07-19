# Google Play delivery

Finance Suit uses the permanent Android application ID
`com.buildingsuit.finance`. Google Play delivery has two repository stages:

| Source | GitHub environment | Play track | Approval |
| --- | --- | --- | --- |
| Push to `test` | `play-test` | Internal testing | Automatic |
| Manual run for a `v*` tag on `main` | `play-production` | Production | Manual dispatch |

Both stages use the production Supabase project. The mobile bundle contains
only the public Supabase URL and anon key; never add a Supabase `service_role`
key to GitHub Actions.

The workflow stays disabled until `PLAY_SIGNING_READY=true`. Play API uploads
stay disabled separately until `PLAY_DELIVERY_ENABLED=true`. This allows the
first signed bundle to be created and uploaded manually before automation is
given Play Console access.

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

Add these repository variables before producing a signed Play build:

- `LEGAL_DEVELOPER_NAME`: the public publisher/developer identity
- `PRIVACY_CONTACT_EMAIL`: the monitored public privacy/support address

The in-app policy and terms use these values. Public legal-page sources and
account-deletion deployment instructions are documented in
`docs/PRIVACY_AND_ACCOUNT_DELETION.md`.

## 2. Build the first signed app bundle

After all four signing secrets exist, set the repository variable
`PLAY_SIGNING_READY` to `true`. Leave `PLAY_DELIVERY_ENABLED` set to `false`.
Run **Finance Suit Google Play Delivery** manually from the `test` branch with
stage `test`, then download the signed `.aab` artifact from that workflow run.

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
   - View app information and download bulk reports (read-only)
   - Release apps to testing tracks
   - Release to production, exclude devices, and use Play App Signing
6. Save the complete JSON key as the repository secret
   `PLAY_SERVICE_ACCOUNT_JSON`.
7. Set repository variable `PLAY_DELIVERY_ENABLED` to `true`.

Do not put the service-account JSON in the app bundle, repository, workflow
artifacts, issue comments, or chat messages.

## 5. Personal-account production access

New Personal Play Console accounts must complete a Closed Test with at least
12 testers continuously opted in for 14 days, then apply for production
access. Internal Testing remains the regular fast test stage, but it does not
satisfy that one-time production eligibility requirement. Complete the Closed
Test in Play Console before pushing the first production tag.

## Versioning and releases

- Every run uses the workflow-wide run number as Android `versionCode`, so a
  later production build is newer than earlier Internal Testing builds.
- Test builds use `<pubspec-version>-test.<run-number>` as `versionName`.
- A production tag such as `v1.0.0` uses `1.0.0` as `versionName`.
- Production tags must point to a commit contained in `main`.
- Production can only run through an explicit manual workflow dispatch for an
  existing `v*` tag whose commit is contained in `main`.
- A production tag also publishes the AAB and checksum to GitHub Releases.

## Rollout commands

Merge changes to `test` for an Internal Testing build:

```bash
git switch test
git merge --ff-only main
git push origin test
```

Publish production after Play Console grants production access:

```bash
git switch main
git tag -a v1.0.0 -m "Finance Suit v1.0.0"
git push origin v1.0.0
gh workflow run android-play-release.yml \
  --ref main \
  -f stage=production \
  -f release_tag=v1.0.0
```
