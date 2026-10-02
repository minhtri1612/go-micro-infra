#!/usr/bin/env bash
# Pull Jenkins runtime env from AWS Secrets Manager using the instance role.
# Source of truth: secret go-micro/jenkins/runtime. Writes .env.runtime (chmod 600), not git.
set -euo pipefail

SECRET_ID="${JENKINS_RUNTIME_SECRET:-go-micro/jenkins/runtime}"
OUT="${1:-.env.runtime}"
REGION="${AWS_DEFAULT_REGION:-ap-southeast-2}"

python3 - "$SECRET_ID" "$OUT" "$REGION" <<'PY'
import json, os, subprocess, sys

secret_id, out, region = sys.argv[1], sys.argv[2], sys.argv[3]
required = [
    "JENKINS_ADMIN_ID",
    "JENKINS_DEVELOPER_ID",
    "JENKINS_URL",
    "GITHUB_OAUTH_CLIENT_ID",
    "GITHUB_OAUTH_CLIENT_SECRET",
    "DOCKERHUB_USER",
    "DOCKERHUB_TOKEN",
    "GITHUB_USER",
    "GITHUB_PAT",
    "TF_STATE_BUCKET",
    "TF_ADMIN_INGRESS_CIDR",
    "TF_DB_PASSWORD",
    "TF_STRIPE_SECRET_KEY",
    "TF_PLAN_WEBHOOK_TOKEN",
    "TF_APPLY_WEBHOOK_TOKEN",
    "AWS_PLAN_ACCESS_KEY_ID",
    "AWS_PLAN_SECRET_ACCESS_KEY",
    "AWS_APPLY_ACCESS_KEY_ID",
    "AWS_APPLY_SECRET_ACCESS_KEY",
]
raw = subprocess.check_output(
    [
        "aws", "secretsmanager", "get-secret-value",
        "--secret-id", secret_id,
        "--region", region,
        "--query", "SecretString",
        "--output", "text",
    ],
    text=True,
)
data = json.loads(raw)
if not str(data.get("JENKINS_DEVELOPER_ID", "")).strip():
    data["JENKINS_DEVELOPER_ID"] = str(data.get("JENKINS_DEST_ID", "")).strip()
missing = [k for k in required if not str(data.get(k, "")).strip()]
if missing:
    sys.exit("secret %s missing keys: %s" % (secret_id, ", ".join(missing)))
data.setdefault("AWS_DEFAULT_REGION", region)
data.setdefault("JENKINS_DEST_ID", data.get("JENKINS_DEVELOPER_ID", ""))
with open(out, "w", encoding="utf-8") as fh:
    for key, val in data.items():
        if val is None:
            continue
        fh.write("%s=%s\n" % (key, str(val).replace("\n", "").replace("\r", "")))
os.chmod(out, 0o600)
print("wrote", out)
PY
