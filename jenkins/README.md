# Jenkins CI (ngoài cluster)

Jenkins **không** chạy trong RKE2, không do Helm/Argo quản. Đây là server CI (`docker compose`) trên EC2 trong VPC management.

## Vận hành

```
Dev  →  git push service repo
          Jenkins job  services/<name>
            1. docker build/push
            2. bump go-micro-gitops/env/dev.yaml
          Argo CD (RKE2 management)  →  dest/prod cluster
```

Dev không SSH Jenkins trừ khi xem log job của mình. Secret **không** nằm Git, **không** nằm `.env` committed.

## Secret (production)

Nguồn sự thật: **AWS Secrets Manager** `go-micro/jenkins/runtime` (Terraform tạo secret rỗng; JSON seed trên console, không vào tfstate).

Máy Jenkins có IAM role riêng (`go-micro-rke2-jenkins`): đọc **đúng** secret đó. kubectl đi kubeconfig (peering), không SSM sang cluster.

User login: **GitHub OAuth**. Jenkins không lưu password. SM chỉ giữ **OAuth App** `GITHUB_OAUTH_CLIENT_ID` / `CLIENT_SECRET` + PAT/Docker/AWS job keys.

GitHub → Settings → Developer settings → OAuth Apps → New:

- Homepage: `http://<jenkins-eip>:8080/`
- Authorization callback: `http://<jenkins-eip>:8080/securityRealm/finishLogin`

`JENKINS_ADMIN_ID` / `JENKINS_DEVELOPER_ID` trong secret = **hai GitHub username khác nhau** (Role Strategy `entries.user`). `dest` là môi trường (`env/dev.yaml`), không phải role Jenkins. Tạo OAuth App + ghi 2 key vào SM **trước** khi `compose up` (sai callback = lockout).

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

`TF_STACK` mặc định `rke2-management` (allowlist: `rke2-management` `rke2-dev` `rke2-prod` `networking`).

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

Laptop không apply `rke2-*` trừ khi Jenkins chết.

## Trách nhiệm

| DevOps (repo này + pipeline-lib) | Dev (repo service) |
|---|---|
| docker compose, JCasC, credentials | `Jenkinsfile` 5 dòng |
| Job DSL một job / service | code + test |
| Shared library `go-micro-ci` | không viết docker/gitops trong Jenkinsfile |
