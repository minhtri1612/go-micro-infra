#!/usr/bin/env bash
# In ra các service app có image.tag trong env file (không gồm *-db).
set -euo pipefail
env_file="${1:-env/dev.yaml}"
for s in product inventory order payment noti client; do
  if grep -q "^${s}:" "$env_file" 2>/dev/null; then
    echo "$s"
  fi
done
