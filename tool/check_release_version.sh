#!/usr/bin/env bash
set -euo pipefail

requested_base_ref="${1:-origin/main}"
mode="${2:-report}"

if [[ "${mode}" != "report" && "${mode}" != "check" ]]; then
  echo "Usage: $0 [base-ref] [report|check]" >&2
  exit 2
fi

read_version() {
  sed -n 's/^version: \([0-9][0-9.]*\)+\([0-9][0-9]*\)$/\1 \2/p'
}

base_ref="${requested_base_ref}"
base_version_line="$(git show "${base_ref}:pubspec.yaml" | read_version)"
head_version_line="$(read_version < pubspec.yaml)"

if [[ -z "${base_version_line}" || -z "${head_version_line}" ]]; then
  echo "pubspec.yaml must contain version: MAJOR.MINOR.PATCH+BUILD." >&2
  exit 1
fi

read -r base_version base_build <<< "${base_version_line}"
read -r head_version head_build <<< "${head_version_line}"

version_weight() {
  local version="$1"
  local major minor patch
  IFS=. read -r major minor patch <<< "${version}"
  printf '%d' "$((major * 100000000 + minor * 10000 + patch))"
}

# 0.5.0 was staged before the current main branch caught up. Treat it as the
# minimum baseline, then automatically prefer main after production advances.
source tool/release_baseline.env
if (( $(version_weight "${RELEASE_BASE_VERSION}") > $(version_weight "${base_version}") )); then
  base_ref="${RELEASE_BASE_COMMIT}"
  base_version="${RELEASE_BASE_VERSION}"
  base_build="${RELEASE_BASE_BUILD}"
fi

commit_text="$(git log --format='%s%n%b' "${base_ref}..HEAD")"
impact="none"

if grep -Eq '^[a-z]+(\([^)]*\))?!:|^BREAKING CHANGE:' <<< "${commit_text}"; then
  impact="major"
elif grep -Eq '^feat(\([^)]*\))?:' <<< "${commit_text}"; then
  impact="minor"
elif grep -Eq '^(fix|perf|refactor)(\([^)]*\))?:' <<< "${commit_text}"; then
  impact="patch"
elif git diff --name-only "${base_ref}...HEAD" | grep -Eq \
    '^(android|assets|ios|lib|supabase/migrations)/|^pubspec\.lock$'; then
  impact="patch"
fi

IFS=. read -r major minor patch <<< "${base_version}"
case "${impact}" in
  major) expected_version="$((major + 1)).0.0" ;;
  minor) expected_version="${major}.$((minor + 1)).0" ;;
  patch) expected_version="${major}.${minor}.$((patch + 1))" ;;
  none) expected_version="${base_version}" ;;
esac

expected_build="${base_build}"
if [[ "${impact}" != "none" ]]; then
  expected_build="$((base_build + 1))"
fi
expected_declared="${expected_version}+${expected_build}"
actual_declared="${head_version}+${head_build}"

echo "Release baseline: ${base_version}+${base_build} (${base_ref})"
echo "Calculated impact: ${impact}"
echo "Expected version: ${expected_declared}"
echo "Declared version: ${actual_declared}"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "impact=${impact}"
    echo "expected=${expected_declared}"
    echo "actual=${actual_declared}"
  } >> "${GITHUB_OUTPUT}"
fi

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "### Version impact"
    echo
    echo "- Baseline: \`${base_version}+${base_build}\`"
    echo "- Impact: \`${impact}\`"
    echo "- Expected: \`${expected_declared}\`"
    echo "- Declared: \`${actual_declared}\`"
  } >> "${GITHUB_STEP_SUMMARY}"
fi

if [[ "${mode}" == "check" && "${actual_declared}" != "${expected_declared}" ]]; then
  echo "Set pubspec.yaml version to ${expected_declared}." >&2
  exit 1
fi
