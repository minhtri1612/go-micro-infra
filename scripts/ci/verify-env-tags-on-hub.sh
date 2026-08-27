#!/usr/bin/env bash
# Usage: verify-env-tags-on-hub.sh <env-file> [service ...]
# Không truyền service → kiểm tra mọi app service trong file.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
env_file="${1:?env file}"
shift || true
if [[ $# -eq 0 ]]; then
  mapfile -t svcs < <(bash "$ROOT/scripts/ci/list-env-app-services.sh" "$env_file")
else
  svcs=("$@")
fi
missing=0
for svc in "${svcs[@]}"; do
  [[ -z "$svc" ]] && continue
  tag="$(bash "$ROOT/scripts/ci/read-env-tag.sh" "$env_file" "$svc")"
  if bash "$ROOT/scripts/ci/image-exists-on-hub.sh" "$tag"; then
    echo "Hub OK: $svc → $tag"
  else
    missing=1
  fi
done
exit "$missing"
