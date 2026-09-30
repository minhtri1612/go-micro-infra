#!/usr/bin/env bash
# Usage: export-kubeconfig.sh <rke2-management|rke2-dev|rke2-prod>
# Lấy kubeconfig từ RKE2 master qua SSH (jump = OpenVPN host), trỏ server về
# internal NLB, rồi lưu Secrets Manager để Jenkins / Argo CD dùng qua peering.
set -euo pipefail

stack="${1:?stack: rke2-management|rke2-dev|rke2-prod}"
env_name="${stack#rke2-}"
project="${PROJECT_NAME:-go-micro}"
region="${AWS_DEFAULT_REGION:-ap-southeast-2}"
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
chdir="${repo_root}/terraform/environments/${stack}"
mgmt_chdir="${repo_root}/terraform/environments/rke2-management"

master_ip="$(terraform -chdir="$chdir" output -json master_private_ips | python3 -c 'import json,sys; print(json.load(sys.stdin)[0])')"
api_dns="$(terraform -chdir="$chdir" output -raw api_dns_name)"
node_key="$(terraform -chdir="$chdir" output -raw ssh_private_key_path)"
jump_ip="$(terraform -chdir="$mgmt_chdir" output -raw openvpn_public_ip)"
jump_key="$(terraform -chdir="$mgmt_chdir" output -raw ssh_private_key_path)"

ssh_opts="-o StrictHostKeyChecking=no -o IdentitiesOnly=yes -o ConnectTimeout=15"

kubeconfig="$(ssh $ssh_opts -i "$node_key" \
  -o ProxyCommand="ssh -W %h:%p -i ${jump_key} ${ssh_opts} ubuntu@${jump_ip}" \
  "ubuntu@${master_ip}" 'sudo cat /etc/rancher/rke2/rke2.yaml')"

if [[ -z "$kubeconfig" ]]; then
  echo "empty kubeconfig from ${master_ip}" >&2
  exit 1
fi

# Server phải là internal NLB: DNS này đã nằm trong tls-san của apiserver nên
# không cần insecure-skip-tls-verify.
kubeconfig="${kubeconfig//https:\/\/127.0.0.1:6443/https://${api_dns}:6443}"

secret_name="${project}/${env_name}/kubeconfig"
if aws secretsmanager describe-secret --region "$region" --secret-id "$secret_name" >/dev/null 2>&1; then
  aws secretsmanager put-secret-value --region "$region" \
    --secret-id "$secret_name" --secret-string "$kubeconfig" >/dev/null
else
  aws secretsmanager create-secret --region "$region" \
    --name "$secret_name" --secret-string "$kubeconfig" >/dev/null
fi

echo "kubeconfig → secret ${secret_name} (server https://${api_dns}:6443)"
