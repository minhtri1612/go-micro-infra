#!/usr/bin/env bash
# Usage: hub-find-tag-by-semver.sh <semver-prefix>
# Tìm tag trên Docker Hub khớp đúng semver prefix, với hoặc không có SHA suffix.
# Ưu tiên: tag CÓ SHA (nhiều thông tin hơn) → fallback tag KHÔNG SHA.
#
# Ví dụ:
#   hub-find-tag-by-semver.sh payment-service-v1.0.3
#   → Output: payment-service-v1.0.3-def5678   (nếu tìm thấy bản có SHA)
#   → Output: payment-service-v1.0.3            (fallback nếu chỉ có bản cũ không SHA)
#   → Output: (rỗng)                            nếu không tìm thấy gì
set -euo pipefail

semver_prefix="${1:?semver prefix, vd: payment-service-v1.0.3}"
repo="${IMAGE_REPO:-minhtri1612/go-microservice}"
repo_ns="${repo%%/*}"
repo_name="${repo#*/}"

found_with_sha=""
found_no_sha=""

# Escape dots cho bash regex (vd: "v1.0.3" → "v1\.0\.3")
escaped_prefix="${semver_prefix//./\\.}"

fetch_hub_tags_page() {
  local url="$1"
  local curl_args=(-fsSL)
  if [[ -n "${DOCKER_USER:-}" && -n "${DOCKER_PASS:-}" ]]; then
    curl_args+=(-u "${DOCKER_USER}:${DOCKER_PASS}")
  fi
  curl "${curl_args[@]}" "$url" 2>/dev/null || true
}

url="https://hub.docker.com/v2/repositories/${repo_ns}/${repo_name}/tags/?page_size=100"
while [[ -n "$url" ]]; do
  body="$(fetch_hub_tags_page "$url")"
  if [[ -z "$body" ]]; then
    break
  fi

  while IFS= read -r t; do
    [[ -z "$t" ]] && continue
    if [[ "$t" == "${semver_prefix}" ]]; then
      # Exact match không SHA
      found_no_sha="$t"
    elif [[ "$t" =~ ^${escaped_prefix}-([a-f0-9]+)$ ]]; then
      # Match có SHA suffix
      found_with_sha="$t"
    fi
  done < <(printf '%s' "$body" | grep -oE '"name":"[^"]+"' | sed 's/"name":"//;s/"$//')

  # Early exit: đã tìm thấy bản có SHA rồi (kết quả tốt nhất)
  if [[ -n "$found_with_sha" ]]; then
    break
  fi

  url=""
  if printf '%s' "$body" | grep -q '"next":[^n]'; then
    url="$(printf '%s' "$body" | sed -n 's/.*"next"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
    url="${url//\\//}"
  fi
done

# Ưu tiên tag có SHA, fallback không SHA
if [[ -n "$found_with_sha" ]]; then
  printf '%s\n' "$found_with_sha"
elif [[ -n "$found_no_sha" ]]; then
  printf '%s\n' "$found_no_sha"
fi
# Nếu không tìm thấy gì → output rỗng, caller tự xử lý
