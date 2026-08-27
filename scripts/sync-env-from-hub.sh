#!/usr/bin/env bash
# Đồng bộ env/*.yaml với tag CHÍNH XÁC trên Docker Hub (không sửa tay từng dòng).
# Usage:
#   ./scripts/sync-env-from-hub.sh                    # env/dev.yaml, mọi app service
#   ./scripts/sync-env-from-hub.sh env/dev.yaml payment order
# Có DOCKER_USER/DOCKER_PASS (hoặc source scripts/jenkins-ci.env) nếu repo private.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
env_file="env/dev.yaml"
if [[ $# -ge 1 && -f "$1" && "$1" == *.yaml ]]; then
  env_file="$1"
  shift
fi
bash scripts/ci/sync-env-tags-from-hub.sh "$env_file" "$@"
