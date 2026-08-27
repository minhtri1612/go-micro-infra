#!/usr/bin/env bash
# Sync CA bundle cho ClusterMesh mTLS giữa 4 cluster Kind (management + dev/staging/prod).
# Dùng khi recreate cluster / rotate cert làm KVStoreMesh chưa bắt tay đủ.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HUB_CTX="${HUB_CTX:-kind-management}"
HUB_NS="${HUB_NS:-kube-system}"
# Lab default: management + dev + prod (no staging). Override with SPOKE_CTXS="kind-dev kind-prod".
SPOKE_CTXS=(${SPOKE_CTXS:-kind-dev kind-prod})
ALL_CTXS=("${HUB_CTX}" "${SPOKE_CTXS[@]}")
PEER_SCRIPT="${ROOT}/scripts/kind-clustermesh-peer-ip.sh"

has_ctx() {
  kubectl config get-contexts -o name 2>/dev/null | grep -Fxq "$1"
}

if [[ ! -f "${PEER_SCRIPT}" ]]; then
  echo "Missing ${PEER_SCRIPT}" >&2
  exit 1
fi

echo "==> Update management peer endpoint file"
bash "${PEER_SCRIPT}"

echo "==> Gather cilium-ca from all contexts"
CA_ALL="$(mktemp)"
trap 'rm -f "${CA_ALL}"' EXIT
for ctx in "${ALL_CTXS[@]}"; do
  if ! has_ctx "${ctx}"; then
    echo "Skip ${ctx} (missing context)"
    continue
  fi
  kubectl --context "${ctx}" -n "${HUB_NS}" get secret cilium-ca -o jsonpath='{.data.ca\.crt}' | base64 -d >> "${CA_ALL}"
  echo >> "${CA_ALL}"
done
CA_B64="$(base64 -w0 "${CA_ALL}")"

echo "==> Patch remote-cert + server-cert on all contexts"
for ctx in "${ALL_CTXS[@]}"; do
  has_ctx "${ctx}" || continue
  kubectl --context "${ctx}" -n "${HUB_NS}" patch secret clustermesh-apiserver-remote-cert \
    --type=merge -p "{\"data\":{\"ca.crt\":\"${CA_B64}\"}}"
  kubectl --context "${ctx}" -n "${HUB_NS}" patch secret clustermesh-apiserver-server-cert \
    --type=merge -p "{\"data\":{\"ca.crt\":\"${CA_B64}\"}}"
done

echo "==> Restart clustermesh-apiserver + cilium on all contexts"
for ctx in "${ALL_CTXS[@]}"; do
  has_ctx "${ctx}" || continue
  kubectl --context "${ctx}" -n "${HUB_NS}" rollout restart deploy/clustermesh-apiserver ds/cilium
done

echo "==> Wait for cilium daemonset rollout"
for ctx in "${ALL_CTXS[@]}"; do
  has_ctx "${ctx}" || continue
  kubectl --context "${ctx}" -n "${HUB_NS}" rollout status ds/cilium --timeout=180s
done

echo "Done."
echo "Next: argocd app sync cilium-management cilium-dev cilium-prod"
echo "Verify: for ctx in kind-management kind-dev kind-prod; do cilium clustermesh status --context \$ctx; done"
