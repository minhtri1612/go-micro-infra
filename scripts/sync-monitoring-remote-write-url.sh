#!/usr/bin/env bash
# Đồng bộ remote_write URL (Prometheus Agent workload → Prometheus management) — không hardcode IP trong Git.
#
# Cách dùng:
#   MGMT_PROMETHEUS_REMOTE_WRITE_URL='http://x:32090/api/v1/write' ./scripts/sync-monitoring-remote-write-url.sh
#   ./scripts/sync-monitoring-remote-write-url.sh --print-only # chỉ in URL write
#   ./scripts/sync-monitoring-remote-write-url.sh --print-ready-url
#   ./scripts/sync-monitoring-remote-write-url.sh --check        # GET /-/ready từ máy host
#   ./scripts/sync-monitoring-remote-write-url.sh --commit-push  # sau khi ghi file: git add/commit (nếu có diff) + push
#   ./scripts/sync-monitoring-remote-write-url.sh --help
#
# Biến môi trường:
#   MGMT_PROMETHEUS_REMOTE_WRITE_URL  — bắt buộc. ClusterIP/NLB management Prometheus
#   MGMT_PROMETHEUS_NODEPORT            — mặc định: 32090 (chỉ dùng nếu URL thiếu port)
#   MONITORING_WORKLOAD_VALUES          — mặc định: monitoring/monitoring-workload.yaml (đường dẫn tương đối repo)
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${ROOT}/${MONITORING_WORKLOAD_VALUES:-monitoring/monitoring-workload.yaml}"
CHECK_RETRIES="${MGMT_READY_CHECK_RETRIES:-12}"
CHECK_SLEEP_SECONDS="${MGMT_READY_CHECK_SLEEP_SECONDS:-5}"

COMMIT_PUSH=false
argv=()
for arg in "$@"; do
  if [[ "$arg" == --commit-push ]]; then
    COMMIT_PUSH=true
    continue
  fi
  argv+=("$arg")
done
set -- "${argv[@]}"

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

resolve_url() {
  if [[ -z "${MGMT_PROMETHEUS_REMOTE_WRITE_URL:-}" ]]; then
    echo "Set MGMT_PROMETHEUS_REMOTE_WRITE_URL (management Prometheus, e.g. http://<ip>:32090/api/v1/write)." >&2
    exit 1
  fi
  echo "${MGMT_PROMETHEUS_REMOTE_WRITE_URL}"
}

write_ready_url() {
  local w="$1"
  echo "${w%/api/v1/write}/-/ready"
}

git_commit_push_values() {
  local rel="${TARGET#$ROOT/}"
  if [[ "$rel" == "$TARGET" ]] || [[ "$rel" == /* ]]; then
    echo "Không suy ra đường dẫn tương đối cho git add (TARGET ngoài ROOT?)." >&2
    exit 1
  fi
  cd "$ROOT"
  if ! git rev-parse --git-dir &>/dev/null; then
    echo "Thư mục không phải git repo: $ROOT" >&2
    exit 1
  fi
  git add -- "$rel"
  if git diff --cached --quiet; then
    echo "Git: không có thay đổi để commit (URL đã trùng hoặc file không đổi)."
  else
    git commit -m "chore(monitoring): sync remote_write URL"
  fi
  git push
  echo "Git: đã push (hoặc remote đã up to date)."
}

case "${1:-}" in
  --help|-h) usage ;;
esac

PRINT_ONLY=false
PRINT_READY=false
CHECK=false
[[ "${1:-}" == "--print-only" ]] && PRINT_ONLY=true
[[ "${1:-}" == "--print-ready-url" ]] && PRINT_READY=true
[[ "${1:-}" == "--check" ]] && CHECK=true

URL="$(resolve_url)"

if $PRINT_ONLY; then
  echo "$URL"
  exit 0
fi

if $PRINT_READY; then
  write_ready_url "$URL"
  exit 0
fi

if $CHECK; then
  ready="$(write_ready_url "$URL")"
  code=""
  for i in $(seq 1 "$CHECK_RETRIES"); do
    code="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 5 "$ready" || true)"
    echo "[$i/$CHECK_RETRIES] GET $ready → HTTP $code"
    if [[ "$code" == "200" ]]; then
      exit 0
    fi
    sleep "$CHECK_SLEEP_SECONDS"
  done
  echo "Prometheus management chưa sẵn sàng sau $CHECK_RETRIES lần thử." >&2
  if command -v kubectl &>/dev/null; then
    echo "Gợi ý chẩn đoán:" >&2
    echo "  kubectl -n monitoring get pods" >&2
    echo "  kubectl -n monitoring get svc monitoring-management-kube-prometheus -o wide" >&2
  fi
  exit 1
fi

if [[ ! -f "$TARGET" ]]; then
  echo "Không thấy file: $TARGET" >&2
  exit 1
fi

if command -v yq &>/dev/null; then
  yq -i ".prometheus.prometheusSpec.remoteWrite[0].url = \"${URL}\"" "$TARGET"
else
  if ! grep -q 'api/v1/write' "$TARGET"; then
    echo "Không tìm thấy dòng remote_write trong $TARGET" >&2
    exit 1
  fi
  # URL chuẩn http://IP:port/api/v1/write không chứa ký tự đặc biệt của sed khi dùng | làm delimiter
  sed -i "s|^[[:space:]]*- url: http://[^[:space:]]*api/v1/write|      - url: ${URL}|" "$TARGET"
fi

echo "Đã ghi remote_write URL: $URL"
echo "File: $TARGET"
echo "Kiểm tra: $0 --check"

if $COMMIT_PUSH; then
  git_commit_push_values
fi
