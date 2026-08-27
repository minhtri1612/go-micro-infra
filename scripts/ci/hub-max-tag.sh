#!/usr/bin/env bash
# Usage: hub-max-tag.sh <tag-prefix>
# In ra tag semver LỚN NHẤT trên Docker Hub có dạng <prefix>MAJOR.MINOR.PATCH
# (vd prefix payment-service-v → payment-service-v1.0.4). Không in gì nếu không tìm thấy.
set -euo pipefail

prefix="${1:?tag prefix, e.g. payment-service-v}"
repo="${IMAGE_REPO:-minhtri1612/go-microservice}"
repo_ns="${repo%%/*}"
repo_name="${repo#*/}"
hub_latest=""
best_maj=-1
best_min=-1
best_pat=-1

consider_tag() {
  local t="$1"
  if [[ "$t" =~ ^${prefix}([0-9]+)\.([0-9]+)\.([0-9]+)(-[a-f0-9]+)?$ ]]; then
    local maj="${BASH_REMATCH[1]}" min="${BASH_REMATCH[2]}" pat="${BASH_REMATCH[3]}"
    if (( maj > best_maj )) ||
      { (( maj == best_maj )) && (( min > best_min )); } ||
      { (( maj == best_maj )) && (( min == best_min )) && (( pat > best_pat )); }; then
      best_maj=$maj
      best_min=$min
      best_pat=$pat
      hub_latest="${prefix}${maj}.${min}.${pat}"
    fi
  fi
}

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
    consider_tag "$t"
  done < <(printf '%s' "$body" | grep -oE '"name":"[^"]+"' | sed 's/"name":"//;s/"$//')

  url=""
  if printf '%s' "$body" | grep -q '"next":[^n]'; then
    url="$(printf '%s' "$body" | sed -n 's/.*"next"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
    url="${url//\\//}"
  fi
done

if [[ -n "$hub_latest" ]]; then
  printf '%s\n' "$hub_latest"
fi
