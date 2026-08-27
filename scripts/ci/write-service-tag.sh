#!/usr/bin/env bash
# Usage: write-service-tag.sh <env-file> <service> <new-tag>
set -euo pipefail

env_file="${1:?env file}"
service="${2:?service}"
new_tag="${3:?new tag}"
key="${service}:"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
in_block=false
patched=false

while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ "$line" == "${key}" ]]; then
    in_block=true
    printf '%s\n' "$line" >>"$tmp"
    continue
  fi
  if [[ "$in_block" == true ]] && [[ "$line" =~ ^[a-zA-Z0-9_-]+:[[:space:]]*$ ]]; then
    in_block=false
  fi
  if [[ "$in_block" == true ]] && [[ "$patched" == false ]] &&
    [[ "$line" =~ ^([[:space:]]+tag:[[:space:]]+\")[^\"]+(\".*)$ ]]; then
    printf '%s%s%s\n' "${BASH_REMATCH[1]}" "$new_tag" "${BASH_REMATCH[2]}" >>"$tmp"
    patched=true
    continue
  fi
  printf '%s\n' "$line" >>"$tmp"
done <"$env_file"

if [[ "$patched" != true ]]; then
  echo "Failed to write tag under ${key}" >&2
  exit 1
fi

mv "$tmp" "$env_file"
trap - EXIT
