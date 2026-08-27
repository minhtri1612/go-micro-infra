#!/usr/bin/env bash
# Phân loại range commit: service | env-only | none
#   service   — có thay đổi *-service/, client/, go.mod trong range
#   env-only  — chỉ env/* (test tag GitOps, không build image)
#   none      — không thuộc hai loại trên (Jenkinsfile, scripts/ci/, …)
#
# Ưu tiên GIT_PREVIOUS_COMMIT (Jenkins SCM) để không bỏ sót commit bị chôn dưới HEAD.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

HEAD="${HEAD_REF:-${GIT_COMMIT:-HEAD}}"
# BASE: Jenkins set GIT_PREVIOUS_COMMIT khi push SCM; fallback HEAD~1.
BASE="${BASE_REF:-${GIT_PREVIOUS_COMMIT:-HEAD~1}}"

has_service=0
has_env=0

add_path() {
  local p="$1"
  [[ -z "$p" ]] && return
  case "$p" in
    product-service/*|inventory-service/*|order-service/*|payment-service/*|notification-service/*|client/*|go.mod|go.sum)
      has_service=1 ;;
    env/*)
      has_env=1 ;;
  esac
}

# Tất cả file thay đổi trong range BASE..HEAD (bao gồm mọi commit push lần này)
if git rev-parse --verify "${BASE}^{commit}" >/dev/null 2>&1; then
  while IFS= read -r p; do
    add_path "$p"
  done < <(git diff --name-only "$BASE" "$HEAD" 2>/dev/null || true)
else
  # Fallback: chỉ commit HEAD
  while IFS= read -r p; do
    add_path "$p"
  done < <(git show -1 --name-only --pretty=format: "$HEAD" 2>/dev/null || true)
fi

if [[ "$has_service" -eq 1 ]]; then
  echo service
elif [[ "$has_env" -eq 1 ]]; then
  echo env-only
else
  echo none
fi
