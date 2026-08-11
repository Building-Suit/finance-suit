#!/usr/bin/env bash
set -euo pipefail

policy_script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check_release_version.sh"
fixture_root="$(mktemp -d)"
trap 'rm -rf "${fixture_root}"' EXIT

fail() {
  echo "Version policy test failed: $*" >&2
  exit 1
}

run_case() {
  local name="$1"
  local title="$2"
  local declared="$3"
  local expected_status="$4"
  local expected_message="$5"
  local mode="${6:-check}"
  local changes_app="${7:-true}"
  local case_dir="${fixture_root}/${name}"

  mkdir -p "${case_dir}/lib"
  (
    cd "${case_dir}"
    git init -q
    git config user.name version-policy-test
    git config user.email version-policy@example.invalid
    printf 'name: fixture\nversion: 0.6.0+11\n' > pubspec.yaml
    mkdir -p docs
    printf 'base\n' > lib/app.dart
    printf 'base\n' > docs/readme.md
    git add pubspec.yaml lib/app.dart docs/readme.md
    git commit -qm base
    base_commit="$(git rev-parse HEAD)"

    printf 'name: fixture\nversion: %s\n' "${declared}" > pubspec.yaml
    if [[ "${changes_app}" == "true" ]]; then
      printf 'changed\n' > lib/app.dart
    else
      printf 'changed\n' > docs/readme.md
    fi
    git add pubspec.yaml lib/app.dart docs/readme.md
    git commit -qm change

    set +e
    output="$("${policy_script}" "${base_commit}" "${mode}" "${title}" 2>&1)"
    status=$?
    set -e

    [[ "${status}" == "${expected_status}" ]] || {
      echo "${output}" >&2
      fail "${name}: expected status ${expected_status}, got ${status}"
    }
    grep -Fq "${expected_message}" <<< "${output}" || {
      echo "${output}" >&2
      fail "${name}: missing '${expected_message}'"
    }
  )
}

run_case feat 'feat(finance): add catalog lookup' 0.7.0+12 0 \
  'Calculated impact: minor'
run_case fix 'fix(finance): correct catalog lookup' 0.6.1+12 0 \
  'Calculated impact: patch'
run_case breaking 'feat(finance)!: replace catalog contract' 1.0.0+12 0 \
  'Calculated impact: major'
run_case docs 'docs: explain catalog lookup' 0.6.0+11 0 \
  'Calculated impact: none' check false
run_case mislabeled-docs 'docs: explain catalog lookup' 0.6.1+12 0 \
  'Calculated impact: patch'
run_case wrong-feat 'feat: add catalog lookup' 0.6.1+12 1 \
  'Set pubspec.yaml version to 0.7.0+12.'
run_case promotion 'promotion' 0.7.0+12 0 \
  'Promoted version: 0.7.0+12' promote
run_case operational-promotion 'promotion' 0.6.0+11 0 \
  'allowing operational-only changes' promote false
run_case stale-promotion 'promotion' 0.5.9+10 1 \
  'Promotion must not decrease semantic version or build number' promote false
run_case incomplete-promotion 'promotion' 0.7.0+11 1 \
  'A versioned promotion must increase both semantic version and build number' promote

# Feature PRs are validated before merging. Two independently prepared
# features may therefore carry the same release version when merged into dev.
# The post-merge dev check must only enforce monotonicity, not demand a second
# version bump from the later squash commit.
workflow_file="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.github/workflows/branch-version-policy.yml"
dev_push_block="$(sed -n '/elif \[\[ "${CURRENT_BRANCH}" == "dev" \]\]; then/,/else/p' "${workflow_file}")"
grep -Fq './tool/check_release_version.sh "${BEFORE_SHA}" promote' <<< "${dev_push_block}" ||
  fail 'dev push must perform the monotonic promotion check for parallel feature merges'

echo "Version policy tests passed."
