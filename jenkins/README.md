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

## Terraform trên Jenkins

Không `ciTerraform`. Job DSL tạo folder `platform/`. Pipeline lấy **Jenkinsfile từ `main`**.

Trên EC2 Jenkins, `.env` thêm AWS + `TF_*` (xem `.env.example`). IAM user phải plan/apply được stack management (S3 state, EC2, SM). **Không** destroy cả stack từ job (chết Jenkins).

```bash
cd ~/go-micro-infra/jenkins
# sửa .env: JENKINS_URL=http://32.237.61.14:8080/ + AWS + TF_*
git pull
docker compose up -d --build
```

CasC load lúc start. UI: http://32.237.61.14:8080

- **Plan:** `platform/terraform-management-plan` — `GIT_REF=origin/main`, không apply.
- **Tạo lại Kind (sau destroy-target):** `platform/terraform-management-apply` — ACTION=`apply`, SKIP_PR_COMPARE=true.
- **Destroy Kind qua Jenkins:** ACTION=`destroy-target`, TARGET=`module.kind_host`.

Laptop không apply/destroy management nữa, trừ khi Jenkins chết.

## Trách nhiệm

| DevOps (repo này + pipeline-lib) | Dev (repo service) |
|---|---|
| docker compose, JCasC, credentials | `Jenkinsfile` 5 dòng |
| Job DSL một job / service | code + test |
| Shared library `go-micro-ci` | không viết docker/gitops trong Jenkinsfile |
