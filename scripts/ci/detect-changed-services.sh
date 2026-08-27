#!/usr/bin/env bash
# In ra tên service (product, order, …) cần build.
# Nhìn toàn bộ range BASE..HEAD (Jenkins: GIT_PREVIOUS_COMMIT..GIT_COMMIT)
# để không bỏ sót service-commit bị chôn dưới commit Jenkinsfile/scripts.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

if [[ -n "${FORCE_SERVICES:-}" ]]; then
  tr ',' '\n' <<< "${FORCE_SERVICES// /}"
  exit 0
fi

HEAD="${HEAD_REF:-${GIT_COMMIT:-HEAD}}"
BASE="${BASE_REF:-${GIT_PREVIOUS_COMMIT:-HEAD~1}}"

declare -A s=()
add_path() {
  local p="$1"
  case "$p" in
    product-service/*) s[product]=1 ;;
    inventory-service/*) s[inventory]=1 ;;
    order-service/*) s[order]=1 ;;
    payment-service/*) s[payment]=1 ;;
    notification-service/*) s[noti]=1 ;;
    client/*) s[client]=1 ;;
    go.mod|go.sum) for x in product inventory order payment noti; do s[$x]=1; done ;;
  esac
}

# Tất cả file trong range BASE..HEAD (bao phủ nhiều commit được push cùng lúc)
if git rev-parse --verify "${BASE}^{commit}" >/dev/null 2>&1; then
  while IFS= read -r p; do
    [[ -n "$p" ]] && add_path "$p"
  done < <(git diff --name-only "$BASE" "$HEAD" 2>/dev/null || true)
else
  # Fallback khi không có BASE hợp lệ: chỉ HEAD
  while IFS= read -r p; do
    [[ -n "$p" ]] && add_path "$p"
  done < <(git show -1 --name-only --pretty=format: "$HEAD" 2>/dev/null || true)
fi

if [[ ${#s[@]} -eq 0 ]]; then
  echo "DEBUG: range ${BASE}..${HEAD} — không có *-service/ hoặc client/ trong:" >&2
  git log --oneline "$BASE..$HEAD" 2>/dev/null | sed 's/^/  /' >&2
  exit 0
fi

for k in "${!s[@]}"; do echo "$k"; done | sort
