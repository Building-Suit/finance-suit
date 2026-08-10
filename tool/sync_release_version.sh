#!/usr/bin/env bash
set -euo pipefail

base_ref="${1:-origin/dev}"
change_text="${2:-}"
root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
policy_script="${root_dir}/tool/check_release_version.sh"

expected="$(${policy_script} "${base_ref}" report "${change_text}" | sed -n 's/^Expected version: //p')"
current="$(sed -n 's/^version: //p' "${root_dir}/pubspec.yaml")"

if [[ -z "${expected}" || -z "${current}" ]]; then
  echo "Unable to calculate or read the application version." >&2
  exit 1
fi

if [[ "${current}" == "${expected}" ]]; then
  echo "Release version already matches ${expected}."
  exit 0
fi

sed -i "s/^version: .*/version: ${expected}/" "${root_dir}/pubspec.yaml"
echo "Synchronized application version: ${current} -> ${expected}."
