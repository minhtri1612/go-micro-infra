# Jenkins CI (ngoài cluster)

Jenkins **không** chạy trong Kind, không do Helm/Argo quản. Đây là server CI dựng đầu tiên (`docker compose`) trên EC2/VPS riêng.

## Vận hành

```
Dev  →  git push service repo
          Jenkins job  services/<name>
            1. docker build/push
            2. bump go-micro-gitops/env/dev.yaml
          Argo CD (máy Kind)  →  cluster
```

Dev không SSH Jenkins trừ khi xem log job của mình. DevOps giữ `.env`, library, Job DSL.

## Chạy

Máy này chỉ cần Docker (không cần Kind).

```bash
cd jenkins
cp .env.example .env
# điền password + Docker Hub token + GitHub PAT (repo + contents:write trên go-micro-gitops)
docker compose up -d --build
```

UI: `http://<ip-máy-jenkins>:8080` (user/pass trong `.env`).

Webhook GitHub từng service repo:

`http://<ip-máy-jenkins>:8080/github-webhook/`

event: `push`.

Job: `services/product`, `services/order`, … và `platform/terraform-management-plan`, `platform/terraform-management-apply`.

## Terraform trên Jenkins (PR → plan → merge → apply)

Không `ciTerraform`. Job DSL folder `platform/`. Jenkinsfile **luôn từ `main`**.

1. PR đụng `terraform/**` → GitHub `pull_request` → job **plan** (check `terraform-plan`, comment summary). PR không đụng terraform → check xanh, skip plan.
2. Merge `main` → GitHub `push` → job **apply** (re-plan, so sánh `<!-- tf-plan-summary -->`, `apply tfplan`).
3. CODEOWNERS ghi owner; lab 1 DevOps **không** bật required reviews.

### Trên EC2 Jenkins

Thêm vào `.env` (xem `.env.example`):

```
TF_PLAN_WEBHOOK_TOKEN=<openssl rand -hex 24>
TF_APPLY_WEBHOOK_TOKEN=<openssl rand -hex 24>
```

`AWS_PLAN_*` / `AWS_APPLY_*` tạm bằng `AWS_*` cho đến khi apply tạo user `go-micro-tf-plan` / `go-micro-tf-apply`.

```bash
cd ~/go-micro-infra && git pull
cd jenkins
docker compose up -d --build --force-recreate
# đợi "Jenkins is fully up and running"
set -a && source .env && set +a
chmod +x github/configure-repo.sh
./github/configure-repo.sh
```

Webhook GitHub **service** vẫn `http://<jenkins>:8080/github-webhook/` event `push`.

Terraform:

- plan: `http://<jenkins>:8080/generic-webhook-trigger/invoke?token=<TF_PLAN_WEBHOOK_TOKEN>` event `pull_request`
- apply: `...?token=<TF_APPLY_WEBHOOK_TOKEN>` event `push`

### Manual / emergency

- Plan tay: `GIT_REF` + `GH_PR_NUMBER`
- Apply tay: ACTION=`apply`, `SKIP_PR_COMPARE=true` chỉ khi không có PR plan
- Destroy Kind: ACTION=`destroy-target`, TARGET=`module.kind_host`

Laptop không apply management trừ khi Jenkins chết.

## Trách nhiệm

| DevOps (repo này + pipeline-lib) | Dev (repo service) |
|---|---|
| docker compose, JCasC, credentials | `Jenkinsfile` 5 dòng |
| Job DSL một job / service | code + test |
| Shared library `go-micro-ci` | không viết docker/gitops trong Jenkinsfile |
