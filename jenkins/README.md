# Jenkins CI (ngoài cluster)

Jenkins **không** chạy trong RKE2, không do Helm/Argo quản. Đây là server CI (`docker compose`) trên EC2 **private subnet** VPC management. UI chỉ qua VPN, không EIP.

## Vận hành

```
Dev  →  git push service repo
          Jenkins job  services/<name>     (Jenkinsfile trong repo — chỉ Test)
          Jenkins job  release/<name>      (Jenkinsfile trong repo này)
            1. checkout allowlist repo
            2. test
            3. docker build/push
            4. bump go-micro-gitops/env/dev/<service>.yaml
          Argo CD (RKE2 management)  →  dev/prod cluster
```

Dev không SSH Jenkins trừ khi xem log job của mình. Secret **không** nằm Git, **không** nằm `.env` committed.

## Secret (production)

Nguồn sự thật: **AWS Secrets Manager** `go-micro/jenkins/runtime` (Terraform tạo secret rỗng; JSON seed trên console, không vào tfstate).

Máy Jenkins có IAM role riêng (`go-micro-rke2-jenkins`): đọc **đúng** secret đó. kubectl đi kubeconfig (peering), không SSM sang cluster.

User login: **GitHub OAuth**. Jenkins không lưu password. SM chỉ giữ **OAuth App** `GITHUB_OAUTH_CLIENT_ID` / `CLIENT_SECRET` + PAT/Docker/AWS job keys.

GitHub → Settings → Developer settings → OAuth Apps → New:

- Homepage: `http://<jenkins-private-ip>:8080/`
- Authorization callback: `http://<jenkins-private-ip>:8080/securityRealm/finishLogin`

Browser phải đang nối OpenVPN; GitHub chỉ redirect về URL đó.

`JENKINS_ADMIN_ID` / `JENKINS_DEVELOPER_ID` trong secret = **hai GitHub username khác nhau** (Role Strategy `entries.user`). Môi trường CI là `dev` (`env/dev.yaml`), không phải role Jenkins. Tạo OAuth App + ghi 2 key vào SM **trước** khi `compose up` (sai callback = lockout).

```bash
cd ~/go-micro-infra/jenkins
chmod +x scripts/load-runtime-env.sh
./scripts/load-runtime-env.sh
docker compose up -d --build
```

Shape JSON: `jenkins/secrets.example.json`. File `.env.runtime` sinh ra trên disk (`chmod 600`), gitignore.

## Chạy (cũ, đừng dùng)

`cp .env.example .env` đã bỏ. Đừng commit password.

GitHub **không** webhook được Jenkins private. Job `services/*` scan repo mỗi 2 phút (`periodicFolderTrigger`). Terraform plan cron mỗi ~2 phút (open PR), apply poll `main`.

Job: `services/<name>` (test), `release/<name>` (deploy; pipeline `jenkins/release/Jenkinsfile`), và `platform/terraform-management-plan`, `platform/terraform-management-apply`.

Library `go-micro-ci` pin tag `v1.1.5`, `allowVersionOverride: false`. Docker Hub + GitOps write PAT nằm folder `release/`, không GLOBAL. `github-go-micro-pat` GLOBAL chỉ để clone — nên đổi sang PAT read-only và để `GITHUB_PAT_WRITE` cho folder.

## Terraform trên Jenkins (PR → plan → merge → apply)

Không `ciTerraform`. Job DSL folder `platform/`. Jenkinsfile **luôn từ `main`**.

1. PR đụng `terraform/**` → job **plan** poll GitHub (check `terraform-plan`, comment summary). PR không đụng terraform → check xanh, skip plan.
2. Merge `main` → job **apply** poll SCM (re-plan, so sánh `<!-- tf-plan-summary -->`, `apply tfplan`).
3. CODEOWNERS ghi owner; lab 1 DevOps **không** bật required reviews.

`TF_STACK` mặc định `rke2-management` (allowlist: `rke2-management` `rke2-dev` `rke2-prod` `networking`).

### Trên EC2 Jenkins

AWS plan/apply keys nằm trong secret `go-micro/jenkins/runtime`.

```bash
cd ~/go-micro-infra && git pull
cd jenkins
./scripts/load-runtime-env.sh
docker compose up -d --build --force-recreate
set -a && source .env.runtime && set +a
chmod +x github/configure-repo.sh
./github/configure-repo.sh
```

Không tạo GitHub webhook. `configure-repo.sh` chỉ bật branch protection (`terraform-plan`).

### Manual / emergency

- Plan tay: `GIT_REF` + `GH_PR_NUMBER`
- Apply tay: ACTION=`apply`, `SKIP_PR_COMPARE=true` chỉ khi không có PR plan

Laptop không apply `rke2-*` trừ khi Jenkins chết.

## Trách nhiệm

| DevOps (repo này + pipeline-lib) | Dev (repo service) |
|---|---|
| docker compose, JCasC, credentials | `Jenkinsfile` một dòng, không `@main` |
| Job DSL `services/*` + `release/*` | code + test |
| Shared library `go-micro-ci` (pin tag) | không viết docker/gitops trong Jenkinsfile |
