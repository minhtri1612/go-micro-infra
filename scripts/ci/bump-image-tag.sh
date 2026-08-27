#!/usr/bin/env bash
# Usage: bump-image-tag.sh [--compute-only] <env-file> <service>
# Bump patch +1 từ tag semver LỚN NHẤT trên Docker Hub (cùng prefix với tag trong yaml).
# Mặc định: in tag mới ra stdout VÀ ghi vào env file.
# --compute-only: chỉ in tag mới (Jenkins ghi env sau khi build/push thành công).
set -euo pipefail

compute_only=false
if [[ "${1:-}" == "--compute-only" ]]; then
  compute_only=true
  shift
fi

env_file="${1:?env file}"
service="${2:?service name}"
script_dir="$(cd "$(dirname "$0")" && pwd)"

current_tag="$(bash "${script_dir}/read-env-tag.sh" "$env_file" "$service")"

# Tag từ yaml có thể CÓ SHA (lần build trước Jenkins ghi vào) hoặc KHÔNG.
if [[ ! "$current_tag" =~ ^(.*-v)([0-9]+)\.([0-9]+)\.([0-9]+)(-[a-f0-9]+)?$ ]]; then
  echo "Cannot parse semver tag: $current_tag" >&2
  exit 1
fi
prefix="${BASH_REMATCH[1]}"

hub_latest="$(bash "${script_dir}/hub-max-tag.sh" "$prefix" || true)"
base_tag="$current_tag"
if [[ -n "$hub_latest" ]]; then
  base_tag="$hub_latest"
  echo "Hub latest for ${service}: ${hub_latest} (yaml had ${current_tag})" >&2
else
  echo "[WARN] Không lấy được tag từ Hub cho prefix '${prefix}' — bump từ yaml: ${current_tag}" >&2
fi

if [[ ! "$base_tag" =~ ^(.*-v)([0-9]+)\.([0-9]+)\.([0-9]+)(-[a-f0-9]+)?$ ]]; then
  echo "Cannot parse base tag: $base_tag" >&2
  exit 1
fi
# new_tag: semver only — SHA sẽ do Jenkinsfile ghép vào sau khi build thành công
new_tag="${BASH_REMATCH[1]}${BASH_REMATCH[2]}.${BASH_REMATCH[3]}.$((${BASH_REMATCH[4]} + 1))"

if [[ "$compute_only" != true ]]; then
  bash "${script_dir}/write-service-tag.sh" "$env_file" "$service" "$new_tag"
fi

printf '%s\n' "$new_tag"
