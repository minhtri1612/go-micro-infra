#!/usr/bin/env bash
# Usage: decrement-tag.sh <tag>
# payment-service-v1.0.4 → payment-service-v1.0.3
set -euo pipefail
tag="${1:?tag}"
if [[ "$tag" =~ ^(.*-v)([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  patch="${BASH_REMATCH[4]}"
  if (( patch <= 0 )); then
    echo "Cannot decrement patch 0: $tag" >&2
    exit 1
  fi
  printf '%s%s.%s.%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" "$((patch - 1))"
  exit 0
fi
echo "Cannot parse semver tag: $tag" >&2
exit 1
