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

Job: `services/product`, `services/order`, …

## Trách nhiệm

| DevOps (repo này + pipeline-lib) | Dev (repo service) |
|---|---|
| docker compose, JCasC, credentials | `Jenkinsfile` 5 dòng |
| Job DSL một job / service | code + test |
| Shared library `go-micro-ci` | không viết docker/gitops trong Jenkinsfile |
