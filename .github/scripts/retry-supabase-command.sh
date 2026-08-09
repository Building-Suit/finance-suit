#!/usr/bin/env bash

set -euo pipefail

if (( $# < 3 )); then
  echo "Usage: $0 <output-file|-> <description> <command> [args...]" >&2
  exit 64
fi

output_path="$1"
description="$2"
shift 2

max_attempts="${SUPABASE_RETRY_ATTEMPTS:-3}"
retry_delay_seconds="${SUPABASE_RETRY_DELAY_SECONDS:-60}"

if ! [[ "${max_attempts}" =~ ^[1-9][0-9]*$ ]]; then
  echo "SUPABASE_RETRY_ATTEMPTS must be a positive integer." >&2
  exit 64
fi
if ! [[ "${retry_delay_seconds}" =~ ^[0-9]+$ ]]; then
  echo "SUPABASE_RETRY_DELAY_SECONDS must be a non-negative integer." >&2
  exit 64
fi

stdout_file="$(mktemp "${RUNNER_TEMP:-/tmp}/supabase-retry-stdout.XXXXXX")"
stderr_file="$(mktemp "${RUNNER_TEMP:-/tmp}/supabase-retry-stderr.XXXXXX")"

cleanup() {
  rm -f "${stdout_file}" "${stderr_file}"
}
trap cleanup EXIT

is_transient_failure() {
  local combined_file="$1"

  grep -Eiq \
    '"retryable"[[:space:]]*:[[:space:]]*true|status[[:space:]]+(429|5[0-9]{2})|"status"[[:space:]]*:[[:space:]]*(429|5[0-9]{2})|HTTP[^0-9]*(429|5[0-9]{2})|ECONNRESET|ETIMEDOUT|EAI_AGAIN|i/o timeout|timed? out|connection (reset|refused)|temporary failure|could not resolve host|network request failed|fetch failed|TLS handshake timeout|unexpected EOF' \
    "${combined_file}"
}

for (( attempt = 1; attempt <= max_attempts; attempt++ )); do
  : > "${stdout_file}"
  : > "${stderr_file}"

  if "$@" > "${stdout_file}" 2> "${stderr_file}"; then
    cat "${stderr_file}" >&2
    if [[ "${output_path}" == "-" ]]; then
      cat "${stdout_file}"
    else
      cp "${stdout_file}" "${output_path}"
    fi
    exit 0
  else
    status=$?
  fi

  cat "${stdout_file}"
  cat "${stderr_file}" >&2

  combined_file="$(mktemp "${RUNNER_TEMP:-/tmp}/supabase-retry-combined.XXXXXX")"
  cat "${stdout_file}" "${stderr_file}" > "${combined_file}"
  if ! is_transient_failure "${combined_file}"; then
    rm -f "${combined_file}"
    echo "${description} failed with a non-transient error; not retrying." >&2
    exit "${status}"
  fi
  rm -f "${combined_file}"

  if (( attempt == max_attempts )); then
    echo "${description} failed after ${max_attempts} transient-error attempts." >&2
    exit "${status}"
  fi

  echo "::warning::${description} hit a transient Supabase API error on attempt ${attempt}/${max_attempts}; retrying in ${retry_delay_seconds} seconds."
  sleep "${retry_delay_seconds}"
done
