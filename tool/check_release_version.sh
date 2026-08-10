#!/usr/bin/env bash
set -euo pipefail

base_ref="${1:-origin/dev}"
mode="${2:-report}"
change_text="${3:-}"

if [[ "${mode}" != "report" && "${mode}" != "check" && "${mode}" != "promote" ]]; then
  echo "Usage: $0 [base-ref] [report|check|promote] [change-text]" >&2
  exit 2
fi

read_version() {
  sed -n 's/^version: \([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)+\([0-9][0-9]*\)$/\1 \2/p'
}

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

base_weight="$(version_weight "${base_version}")"
head_weight="$(version_weight "${head_version}")"
actual_declared="${head_version}+${head_build}"

if [[ "${mode}" == "promote" ]]; then
  echo "Promotion baseline: ${base_version}+${base_build} (${base_ref})"
  echo "Promoted version: ${actual_declared}"

  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    {
      echo "impact=promotion"
      echo "expected=>${base_version}+${base_build}"
      echo "actual=${actual_declared}"
    } >> "${GITHUB_OUTPUT}"
  fi

  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    {
      echo "### Version promotion"
      echo
      echo "- Target baseline: \`${base_version}+${base_build}\`"
      echo "- Promoted version: \`${actual_declared}\`"
    } >> "${GITHUB_STEP_SUMMARY}"
  fi

  if (( head_weight < base_weight || head_build < base_build )); then
    echo "Promotion must not decrease semantic version or build number below ${base_version}+${base_build}." >&2
    exit 1
  fi

  if (( head_weight == base_weight && head_build == base_build )); then
    echo "Promotion carries no new app version; allowing operational-only changes."
    exit 0
  fi

  if (( head_weight == base_weight || head_build == base_build )); then
    echo "A versioned promotion must increase both semantic version and build number beyond ${base_version}+${base_build}." >&2
    exit 1
  fi
  exit 0
fi

if [[ -z "${change_text}" ]]; then
  change_text="$(git log --format='%s%n%b' "${base_ref}..HEAD")"
fi

impact="none"
if grep -Eq '^[a-z]+(\([^)]*\))?!:|^BREAKING CHANGE:' <<< "${change_text}"; then
  impact="major"
elif grep -Eq '^feat(\([^)]*\))?:' <<< "${change_text}"; then
  impact="minor"
elif grep -Eq '^(fix|perf|refactor)(\([^)]*\))?:' <<< "${change_text}"; then
  impact="patch"
elif git diff --name-only "${base_ref}...HEAD" | grep -Eq \
    '^(android|assets|ios|lib|supabase/functions|supabase/migrations)/|^pubspec\.lock$'; then
  # Protect non-Conventional local commits: shipped application/database
  # changes must still advance at least the patch version.
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
