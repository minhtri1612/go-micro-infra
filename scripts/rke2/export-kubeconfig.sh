#!/usr/bin/env bash
# Usage: export-kubeconfig.sh <rke2-management|rke2-dev|rke2-prod>
# Lấy kubeconfig từ RKE2 master qua SSH (jump = OpenVPN host), trỏ server về
# internal NLB, rồi lưu Secrets Manager để Jenkins / Argo CD dùng qua peering.
set -euo pipefail

# Snap terraform + broken /etc/ld.so.preload → ERROR: ld.so on every exec.
# Unset so snap can map; still expect ~5s per `terraform` invocation.
unset LD_PRELOAD || true
export TF_IN_AUTOMATION=1

stack="${1:?stack: rke2-management|rke2-dev|rke2-prod}"
env_name="${stack#rke2-}"
project="${PROJECT_NAME:-go-micro}"
region="${AWS_DEFAULT_REGION:-ap-southeast-2}"
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
chdir="${repo_root}/terraform/environments/${stack}"
mgmt_chdir="${repo_root}/terraform/environments/rke2-management"

echo "export-kubeconfig ${stack} (snap terraform ~5s/call, do not Ctrl+C)" >&2

abs_key() {
  local dir="$1" key="$2"
  if [[ "$key" == /* ]]; then
    printf '%s\n' "$key"
  else
    printf '%s/%s\n' "$dir" "${key#./}"
  fi
}

tf_get() {
  python3 -c 'import json,sys; d=json.load(sys.stdin); k=sys.argv[1]; v=d[k]["value"]; print(v[0] if isinstance(v,list) else v)' "$1"
}

echo "terraform output ${stack} ..." >&2
stack_json="$(terraform -chdir="$chdir" output -json)"
master_ip="$(tf_get master_private_ips <<<"$stack_json")"
api_dns="$(tf_get api_dns_name <<<"$stack_json")"
node_key="$(abs_key "$chdir" "$(tf_get ssh_private_key_path <<<"$stack_json")")"

if [[ "$stack" == "rke2-management" ]]; then
  jump_ip="$(tf_get openvpn_public_ip <<<"$stack_json")"
  jump_key="$(abs_key "$chdir" "$(tf_get ssh_private_key_path <<<"$stack_json")")"
else
  echo "terraform output rke2-management (jump) ..." >&2
  mgmt_json="$(terraform -chdir="$mgmt_chdir" output -json)"
  jump_ip="$(tf_get openvpn_public_ip <<<"$mgmt_json")"
  jump_key="$(abs_key "$mgmt_chdir" "$(tf_get ssh_private_key_path <<<"$mgmt_json")")"
fi

echo "outputs: master=${master_ip} jump=${jump_ip} api=${api_dns}" >&2
echo "ssh ${master_ip} via ${jump_ip} ..." >&2

# -F /dev/null: ignore ~/.ssh/config (ControlMaster / Identities hang on some laptops).
ssh_base=(
  ssh -F /dev/null
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o GlobalKnownHostsFile=/dev/null
  -o IdentitiesOnly=yes
  -o BatchMode=yes
  -o PasswordAuthentication=no
  -o KbdInteractiveAuthentication=no
  -o PreferredAuthentications=publickey
  -o ConnectTimeout=10
  -o ServerAliveInterval=5
  -o ServerAliveCountMax=3
)

kubeconfig="$(timeout 25 "${ssh_base[@]}" -i "$node_key" \
  -o ProxyCommand="${ssh_base[*]} -W %h:%p -i ${jump_key} ubuntu@${jump_ip}" \
  "ubuntu@${master_ip}" 'sudo -n cat /etc/rancher/rke2/rke2.yaml')"

if [[ -z "$kubeconfig" ]]; then
  echo "empty kubeconfig from ${master_ip}" >&2
  exit 1
fi

# Server phải là internal NLB: DNS này đã nằm trong tls-san của apiserver nên
# không cần insecure-skip-tls-verify.
kubeconfig="${kubeconfig//https:\/\/127.0.0.1:6443/https://${api_dns}:6443}"

out="${repo_root}/kube_config_rke2_${env_name}.yaml"
umask 077
printf '%s\n' "$kubeconfig" >"$out"

echo "secrets manager ${project}/${env_name}/kubeconfig ..." >&2
secret_name="${project}/${env_name}/kubeconfig"
if aws secretsmanager describe-secret --region "$region" --secret-id "$secret_name" >/dev/null 2>&1; then
  aws secretsmanager put-secret-value --region "$region" \
    --secret-id "$secret_name" --secret-string "$kubeconfig" >/dev/null
else
  aws secretsmanager create-secret --region "$region" \
    --name "$secret_name" --secret-string "$kubeconfig" >/dev/null
fi

echo "kubeconfig → ${out} and secret ${secret_name} (server https://${api_dns}:6443)"
