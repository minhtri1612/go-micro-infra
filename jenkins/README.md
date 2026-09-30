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

Dev không SSH Jenkins trừ khi xem log job của mình. Secret **không** nằm Git, **không** nằm `.env` committed.

## Secret (production)

Nguồn sự thật: **AWS Secrets Manager** `go-micro/jenkins/runtime` (Terraform tạo secret rỗng; JSON seed trên console, không vào tfstate).

Máy Jenkins có IAM role riêng (`go-micro-jenkins-ec2`): đọc **đúng** secret đó + SSM sang Kind. Role Kind (`go-micro-ec2-ssm`) **không** đọc secret Jenkins.

User login: **GitHub OAuth**. Jenkins không lưu password admin/dest. SM chỉ giữ **OAuth App** `GITHUB_OAUTH_CLIENT_ID` / `CLIENT_SECRET` + PAT/Docker/AWS job keys.

GitHub → Settings → Developer settings → OAuth Apps → New:

- Homepage: `http://32.237.61.14:8080/`
- Authorization callback: `http://32.237.61.14:8080/securityRealm/finishLogin`

`JENKINS_ADMIN_ID` / `JENKINS_DEST_ID` trong secret = **GitHub username** (Role Strategy `entries.user`). Tạo OAuth App + ghi 2 key vào SM **trước** khi `compose up` (sai callback = lockout).

```bash
cd ~/go-micro-infra/jenkins
chmod +x scripts/load-runtime-env.sh
./scripts/load-runtime-env.sh
docker compose up -d --build
```

Shape JSON: `jenkins/secrets.example.json`. File `.env.runtime` sinh ra trên disk (`chmod 600`), gitignore.

## Chạy (cũ, đừng dùng)

`cp .env.example .env` đã bỏ. Đừng commit password.

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

Webhook tokens và AWS plan/apply keys nằm trong secret `go-micro/jenkins/runtime`.

```bash
cd ~/go-micro-infra && git pull
cd jenkins
./scripts/load-runtime-env.sh
docker compose up -d --build --force-recreate
set -a && source .env.runtime && set +a
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
