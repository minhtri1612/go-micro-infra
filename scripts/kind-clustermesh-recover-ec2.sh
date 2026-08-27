#!/usr/bin/env bash
# Self-contained ClusterMesh recovery for EC2 Kind lab (management + dev + prod).
set -euo pipefail
cd ~/go-micro
NS=kube-system
CTXS=(kind-management kind-dev kind-prod)

has_ctx() { kubectl config get-contexts -o name 2>/dev/null | grep -Fxq "$1"; }

echo "==> LB IPs"
for ctx in "${CTXS[@]}"; do
  echo -n "$ctx: "
  kubectl --context "$ctx" -n "$NS" get svc clustermesh-apiserver -o jsonpath='{.status.loadBalancer.ingress[0].ip}{"\n"}'
done

echo "==> Merge cilium-ca from all clusters into remote/server certs"
CA_ALL=$(mktemp)
trap 'rm -f "$CA_ALL"' EXIT
for ctx in "${CTXS[@]}"; do
  has_ctx "$ctx" || continue
  kubectl --context "$ctx" -n "$NS" get secret cilium-ca -o jsonpath='{.data.ca\.crt}' | base64 -d >>"$CA_ALL"
  printf '\n' >>"$CA_ALL"
done
CA_B64=$(base64 -w0 "$CA_ALL")
for ctx in "${CTXS[@]}"; do
  has_ctx "$ctx" || continue
  kubectl --context "$ctx" -n "$NS" patch secret clustermesh-apiserver-remote-cert \
    --type=merge -p "{\"data\":{\"ca.crt\":\"${CA_B64}\"}}"
  kubectl --context "$ctx" -n "$NS" patch secret clustermesh-apiserver-server-cert \
    --type=merge -p "{\"data\":{\"ca.crt\":\"${CA_B64}\"}}"
  echo "  patched CA on $ctx"
done

echo "==> Remove staging peer keys from secrets (no staging cluster)"
for ctx in "${CTXS[@]}"; do
  for sec in cilium-clustermesh cilium-kvstoremesh; do
    if kubectl --context "$ctx" -n "$NS" get secret "$sec" -o jsonpath='{.data.staging}' 2>/dev/null | grep -q .; then
      kubectl --context "$ctx" -n "$NS" patch secret "$sec" --type=json -p='[{"op":"remove","path":"/data/staging"}]' || true
      echo "  removed staging from $sec ($ctx)"
    fi
  done
done

echo "==> Strip staging from values file + remote-users (skip helm: Argo-owned)"
if [[ -f cilium/cilium-values-management.yaml ]]; then
  python3 - <<'PY' || true
from pathlib import Path
import re
p = Path("cilium/cilium-values-management.yaml")
t = p.read_text()
t2 = re.sub(r"\n\s+- name: staging\n\s+ips:\n\s+- 172\.18\.255\.21\n\s+port: 2379","",t)
if t2 != t:
    p.write_text(t2)
    print("stripped staging from cilium-values-management.yaml")
else:
    print("cilium-values-management.yaml already without staging (or different format)")
PY
fi
if kubectl --context kind-management -n "$NS" get cm clustermesh-remote-users >/dev/null 2>&1; then
  kubectl --context kind-management -n "$NS" get cm clustermesh-remote-users -o json | python3 -c '
import json,sys
d=json.load(sys.stdin)
data=d.get("data") or {}
for k in list(data):
  if "staging" in k:
    del data[k]
  elif "staging" in data[k]:
    data[k]="\n".join(ln for ln in data[k].splitlines() if "staging" not in ln)+"\n"
d["data"]=data
json.dump(d, sys.stdout)
' | kubectl --context kind-management -n "$NS" replace -f - >/dev/null || true
  echo "  scrubbed clustermesh-remote-users"
fi

echo "==> Copy kvstoremesh -> cilium-clustermesh endpoints"
for ctx in "${CTXS[@]}"; do
  keys=$(kubectl --context "$ctx" -n "$NS" get secret cilium-kvstoremesh -o go-template='{{range $k,$v := .data}}{{printf "%s\n" $k}}{{end}}')
  while IFS= read -r k; do
    [[ -z "$k" || "$k" == "staging" ]] && continue
    v=$(kubectl --context "$ctx" -n "$NS" get secret cilium-kvstoremesh -o jsonpath="{.data.$k}")
    kubectl --context "$ctx" -n "$NS" patch secret cilium-clustermesh --type merge -p "{\"data\":{\"$k\":\"$v\"}}" >/dev/null
    echo "  $ctx: copied $k"
  done <<< "$keys"
done

echo "==> Restart agents"
for ctx in "${CTXS[@]}"; do
  kubectl --context "$ctx" -n "$NS" rollout restart deploy/clustermesh-apiserver ds/cilium
done
for ctx in "${CTXS[@]}"; do
  kubectl --context "$ctx" -n "$NS" rollout status ds/cilium --timeout=300s
  kubectl --context "$ctx" -n "$NS" rollout status deploy/clustermesh-apiserver --timeout=300s
done

connected_line() {
  # true if line for peer has not "0/1 connected" for agent part
  local out="$1" peer="$2"
  echo "$out" | grep -E "^[[:space:]]*- ${peer}:" | grep -vq 'configured, 0/1 connected'
}

echo "==> Poll until management↔dev and management↔prod connected"
ok=0
for i in $(seq 1 36); do
  echo
  echo "----- attempt $i/36 $(date -u +%H:%M:%S) -----"
  out_m=$(cilium clustermesh status --context kind-management 2>&1 || true)
  out_d=$(cilium clustermesh status --context kind-dev 2>&1 || true)
  out_p=$(cilium clustermesh status --context kind-prod 2>&1 || true)
  echo "$out_m" | grep -E 'Cluster Connections|dev:|prod:|staging:|Errors|connected to' | head -30
  echo "DEV: $(echo "$out_d" | grep -E 'management:' | head -1)"
  echo "PROD: $(echo "$out_p" | grep -E 'management:' | head -1)"

  m_ok=0
  echo "$out_m" | grep -E '^[[:space:]]*- dev: .*1/1 connected' >/dev/null && \
  echo "$out_m" | grep -E '^[[:space:]]*- prod: .*1/1 connected' >/dev/null && m_ok=1 || true
  # alternate format: "configured, 1/1 connected"
  echo "$out_m" | grep -E '^[[:space:]]*- dev:.*configured, 1/1 connected' >/dev/null && \
  echo "$out_m" | grep -E '^[[:space:]]*- prod:.*configured, 1/1 connected' >/dev/null && m_ok=1 || true

  s_ok=0
  echo "$out_d" | grep -E '^[[:space:]]*- management:.*configured, 1/1 connected' >/dev/null && \
  echo "$out_p" | grep -E '^[[:space:]]*- management:.*configured, 1/1 connected' >/dev/null && s_ok=1 || true

  if [[ "$m_ok" -eq 1 && "$s_ok" -eq 1 ]]; then
    echo "SUCCESS"
    ok=1
    break
  fi

  if (( i == 12 || i == 24 )); then
    echo "==> re-patch CA + endpoints mid-loop"
    for ctx in "${CTXS[@]}"; do
      kubectl --context "$ctx" -n "$NS" patch secret clustermesh-apiserver-remote-cert --type=merge -p "{\"data\":{\"ca.crt\":\"${CA_B64}\"}}" >/dev/null || true
      kubectl --context "$ctx" -n "$NS" patch secret clustermesh-apiserver-server-cert --type=merge -p "{\"data\":{\"ca.crt\":\"${CA_B64}\"}}" >/dev/null || true
      keys=$(kubectl --context "$ctx" -n "$NS" get secret cilium-kvstoremesh -o go-template='{{range $k,$v := .data}}{{printf "%s\n" $k}}{{end}}')
      while IFS= read -r k; do
        [[ -z "$k" || "$k" == "staging" ]] && continue
        v=$(kubectl --context "$ctx" -n "$NS" get secret cilium-kvstoremesh -o jsonpath="{.data.$k}")
        kubectl --context "$ctx" -n "$NS" patch secret cilium-clustermesh --type merge -p "{\"data\":{\"$k\":\"$v\"}}" >/dev/null || true
      done <<< "$keys"
      kubectl --context "$ctx" -n "$NS" rollout restart ds/cilium deploy/clustermesh-apiserver >/dev/null || true
    done
    sleep 25
  else
    sleep 15
  fi
done

echo
echo "===== FINAL ====="
for ctx in "${CTXS[@]}"; do
  echo "=== $ctx ==="
  cilium clustermesh status --context "$ctx" || true
done

# diagnostics if failed
if [[ "$ok" -ne 1 ]]; then
  echo "===== TROUBLESHOOT (dev from hub) =====" >&2
  kubectl --context kind-management -n "$NS" exec ds/cilium -c cilium-agent -- \
    cilium-dbg troubleshoot clustermesh dev 2>&1 | tail -60 || true
  exit 1
fi
exit 0
