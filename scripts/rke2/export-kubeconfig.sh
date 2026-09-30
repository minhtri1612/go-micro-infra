#!/usr/bin/env bash
# Usage: export-kubeconfig.sh <rke2-management|rke2-dev|rke2-prod>
# Đọc kubeconfig từ RKE2 master qua SSM (không SSH), trỏ server về internal NLB,
# rồi lưu vào Secrets Manager để Jenkins / Argo CD dùng qua VPC peering.
set -euo pipefail

stack="${1:?stack: rke2-management|rke2-dev|rke2-prod}"
env_name="${stack#rke2-}"
project="${PROJECT_NAME:-go-micro}"
region="${AWS_DEFAULT_REGION:-ap-southeast-2}"
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
chdir="${repo_root}/terraform/environments/${stack}"

master_id="$(terraform -chdir="$chdir" output -json master_instance_ids | python3 -c 'import json,sys; print(json.load(sys.stdin)[0])')"
api_dns="$(terraform -chdir="$chdir" output -raw api_dns_name)"

cmd_id="$(aws ssm send-command \
  --region "$region" \
  --instance-ids "$master_id" \
  --document-name AWS-RunShellScript \
  --parameters 'commands=["cat /etc/rancher/rke2/rke2.yaml"]' \
  --query 'Command.CommandId' --output text)"

for _ in $(seq 1 60); do
  status="$(aws ssm get-command-invocation --region "$region" \
    --command-id "$cmd_id" --instance-id "$master_id" \
    --query Status --output text 2>/dev/null || echo Pending)"
  [[ "$status" == "Success" || "$status" == "Failed" ]] && break
  sleep 3
done

if [[ "$status" != "Success" ]]; then
  echo "SSM command ${cmd_id} ended as ${status}" >&2
  exit 1
fi

kubeconfig="$(aws ssm get-command-invocation --region "$region" \
  --command-id "$cmd_id" --instance-id "$master_id" \
  --query StandardOutputContent --output text)"

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
