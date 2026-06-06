#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${ROOT}/cilium/clustermesh-management-peer.yaml"
HUB_LB_IP="${HUB_LB_IP:-172.18.255.41}"

cat > "${OUT}" <<EOF
# AUTO — scripts/kind-clustermesh-peer-ip.sh — endpoint clustermesh-apiserver của management
clustermesh:
  config:
    clusters:
      - name: management
        port: 2379
        ips:
          - ${HUB_LB_IP}
EOF

echo "Wrote ${OUT} with management LB IP: ${HUB_LB_IP}"
