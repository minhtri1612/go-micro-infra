#!/usr/bin/env bash
# Usage: find-prev-tag.sh <current-full-tag>
# Tìm tag TRƯỚC (patch - 1) của tag hiện tại trên Docker Hub.
# Thay thế decrement-tag.sh — thay vì trừ 1 theo chuỗi (mù quáng),
# script này query thật lên Hub và trả về tag cũ kèm SHA gốc.
#
# Support cả 2 format (backward compatible):
#   - Có SHA:    payment-service-v1.0.4-abc1234  → payment-service-v1.0.3-def5678
#   - Không SHA: payment-service-v1.0.4           → payment-service-v1.0.3 (hoặc v1.0.3-sha nếu có)
#
# Ví dụ:
#   bash find-prev-tag.sh payment-service-v1.0.4-abc1234
#   → payment-service-v1.0.3-def5678
set -euo pipefail

current_tag="${1:?current tag, vd: payment-service-v1.0.4-abc1234}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse tag: tách prefix, major, minor, patch (SHA là optional)
if [[ "$current_tag" =~ ^(.*-v)([0-9]+)\.([0-9]+)\.([0-9]+)(-[a-f0-9]+)?$ ]]; then
  prefix="${BASH_REMATCH[1]}"   # vd: "payment-service-v"
  major="${BASH_REMATCH[2]}"    # vd: "1"
  minor="${BASH_REMATCH[3]}"    # vd: "0"
  patch="${BASH_REMATCH[4]}"    # vd: "4"
  # BASH_REMATCH[5] = SHA suffix (có thể rỗng nếu tag cũ không có SHA)
else
  echo "ERROR: Cannot parse semver tag: '${current_tag}'" >&2
  echo "  Expected format: <prefix>-v<MAJOR>.<MINOR>.<PATCH>[-<sha>]" >&2
  exit 1
fi

# Không thể rollback nếu patch đang là 0
if (( patch <= 0 )); then
  echo "ERROR: Cannot decrement patch 0 for tag: ${current_tag}" >&2
  echo "  Đây là version đầu tiên — không có version nào trước đó để rollback." >&2
  exit 1
fi

prev_patch=$(( patch - 1 ))
target_semver="${prefix}${major}.${minor}.${prev_patch}"

echo "[find-prev-tag] current: ${current_tag}" >&2
echo "[find-prev-tag] looking for: ${target_semver}[-sha] on Docker Hub..." >&2

prev_tag="$(bash "${script_dir}/hub-find-tag-by-semver.sh" "${target_semver}")"

if [[ -z "$prev_tag" ]]; then
  echo "ERROR: Tag '${target_semver}' (hoặc '${target_semver}-<sha>') không tìm thấy trên Docker Hub." >&2
  echo "  Current:  ${current_tag}" >&2
  echo "  Looking:  ${target_semver}" >&2
  echo "  Kiểm tra lại: image có thực sự được build và push lên Hub chưa?" >&2
  exit 1
fi

echo "[find-prev-tag] found: ${prev_tag}" >&2
printf '%s\n' "$prev_tag"
