#!/usr/bin/env bash
# Usage: read-env-tag.sh <env-file> <service>
# service: product | inventory | order | payment | noti | client
set -euo pipefail
env_file="${1:?env file}"
svc="${2:?service}"
key="${svc}:"
tag=""
in_block=0
while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ "$line" == "${key}" ]]; then
    in_block=1
    continue
  fi
  if [[ "$in_block" -eq 1 ]] && [[ "$line" =~ ^[a-zA-Z0-9_-]+:[[:space:]]*$ ]]; then
    break
  fi
  if [[ "$in_block" -eq 1 ]] && [[ "$line" =~ ^[[:space:]]+tag:[[:space:]]+\"([^\"]+)\" ]]; then
    tag="${BASH_REMATCH[1]}"
    break
  fi
done <"$env_file"
if [[ -z "$tag" ]]; then
  echo "No tag for ${svc} in ${env_file}" >&2
  exit 1
fi
printf '%s\n' "$tag"
