#!/usr/bin/env bash
# In ra service (product, order, …) có tag đổi trong commit HEAD cho env/<file>.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
ENV_FILE="${1:-env/dev.yaml}"
HEAD="${HEAD_REF:-HEAD}"
BASE="${BASE_REF:-HEAD~1}"

if ! git show -1 --name-only --pretty=format: "$HEAD" 2>/dev/null | grep -qx "$ENV_FILE"; then
  exit 0
fi

declare -A ch=()
cur=""
while IFS= read -r line; do
  case "$line" in
    product:|inventory:|order:|payment:|noti:|client:)
      cur="${line%:}"
      ;;
    +*tag:*)
      if [[ -n "$cur" ]]; then
        ch["$cur"]=1
      fi
      ;;
  esac
done < <(git diff "$BASE" "$HEAD" -- "$ENV_FILE" 2>/dev/null || true)

if [[ ${#ch[@]} -eq 0 ]] && git diff "$BASE" "$HEAD" -- "$ENV_FILE" 2>/dev/null | grep -qE '^[+-][[:space:]]+tag:'; then
  for s in product inventory order payment noti client; do
    ch[$s]=1
  done
fi

for k in "${!ch[@]}"; do echo "$k"; done | sort
