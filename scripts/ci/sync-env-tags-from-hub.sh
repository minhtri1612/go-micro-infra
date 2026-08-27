#!/usr/bin/env bash
# Ghi tag CHÍNH XÁC (max semver trên Hub) vào env file — không bump +1.
# Usage: sync-env-tags-from-hub.sh <env-file> [service ...]
# Không truyền service → tất cả app service trong env (product … client).
set -euo pipefail

env_file="${1:?env file}"
shift

if [[ $# -eq 0 ]]; then
  mapfile -t services < <(bash "$(dirname "$0")/list-env-app-services.sh" "$env_file")
else
  services=("$@")
fi

for svc in "${services[@]}"; do
  current="$(bash "$(dirname "$0")/read-env-tag.sh" "$env_file" "$svc")"
  if [[ ! "$current" =~ ^(.*-v)([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "Skip ${svc}: cannot parse semver tag: ${current}" >&2
    continue
  fi
  prefix="${BASH_REMATCH[1]}"
  hub_latest="$(bash "$(dirname "$0")/hub-max-tag.sh" "$prefix" || true)"
  if [[ -z "$hub_latest" ]]; then
    echo "[WARN] ${svc}: Hub không có tag prefix '${prefix}' — giữ yaml: ${current}" >&2
    continue
  fi
  if [[ "$hub_latest" == "$current" ]]; then
    echo "${svc}: đã khớp Hub (${hub_latest})"
    continue
  fi
  bash "$(dirname "$0")/write-service-tag.sh" "$env_file" "$svc" "$hub_latest"
  echo "${svc}: ${current} → ${hub_latest} (Hub)"
done
