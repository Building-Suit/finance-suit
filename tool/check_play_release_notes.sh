#!/usr/bin/env bash
set -euo pipefail

base_ref="${1:-}"
mode="${2:-validate}"
notes_dir="distribution/whatsnew"
english_file="${notes_dir}/whatsnew-en-US"
arabic_file="${notes_dir}/whatsnew-ar"

if [[ "${mode}" != "validate" && "${mode}" != "check" ]]; then
  echo "Usage: $0 [base-ref] [validate|check]" >&2
  exit 2
fi
if [[ "${mode}" == "check" && -z "${base_ref}" ]]; then
  echo "A base ref is required in check mode." >&2
  exit 2
fi

validate_note() {
  local locale="$1"
  local file="$2"
  local length

  [[ -s "${file}" ]] || {
    echo "Missing ${locale} Play release notes: ${file}" >&2
    exit 1
  }

  length="$(wc -m < "${file}" | tr -d ' ')"
  if (( length < 40 || length > 500 )); then
    echo "${locale} release notes must contain 40-500 characters; found ${length}." >&2
    exit 1
  fi

  if grep -Eq '</?[A-Za-z-]+>' "${file}"; then
    echo "Do not put Play language tags inside ${file}; its filename selects the locale." >&2
    exit 1
  fi
}

validate_note "English" "${english_file}"
validate_note "Arabic" "${arabic_file}"

grep -Eq '[A-Za-z]{3}' "${english_file}" || {
  echo "English release notes do not contain recognizable English text." >&2
  exit 1
}
grep -Pq '\p{Arabic}' "${arabic_file}" || {
  echo "Arabic release notes do not contain recognizable Arabic text." >&2
  exit 1
}

if [[ "${mode}" == "check" ]]; then
  base_version="$(git show "${base_ref}:pubspec.yaml" | sed -n 's/^version: //p')"
  head_version="$(sed -n 's/^version: //p' pubspec.yaml)"

  if [[ -z "${base_version}" || -z "${head_version}" ]]; then
    echo "Unable to read the base or current app version." >&2
    exit 1
  fi

  if [[ "${base_version}" != "${head_version}" ]]; then
    changed_files="$(git diff --name-only "${base_ref}...HEAD")"
    for file in "${english_file}" "${arabic_file}"; do
      if ! grep -Fxq "${file}" <<< "${changed_files}"; then
        echo "App version changed from ${base_version} to ${head_version}." >&2
        echo "Update both English and Arabic Play release notes; ${file} is unchanged." >&2
        exit 1
      fi
    done
  fi
fi

echo "English Play release notes: $(wc -m < "${english_file}" | tr -d ' ') characters"
echo "Arabic Play release notes: $(wc -m < "${arabic_file}" | tr -d ' ') characters"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "### Google Play release notes"
    echo
    echo "#### English (United States)"
    echo
    cat "${english_file}"
    echo
    echo "#### العربية"
    echo
    cat "${arabic_file}"
    echo
  } >> "${GITHUB_STEP_SUMMARY}"
fi
