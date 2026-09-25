# Terraform + Jenkins: kiểm soát thay đổi (team ~10)

Tổng hợp trao đổi với CODEX. **Không** biến lab Kind/EC2 thành AWS enterprise (HA, EKS, chi phí lớn). Cái cần đạt chuẩn production là **quy trình**: ai được sửa gì, PR/review trước khi chạy, Terraform apply chỉ trên Jenkins — không trên laptop.

Kèm plan CI service/GitOps (repo `go-micro-gitops`): `docs/cicd-hardening-plan.md`. **Không** dùng Trivy/image scan trong phạm vi này.

**Không** thêm `ciTerraform`. Shared library `go-micro-ci` chỉ cho CI service. Terraform = đúng **hai** job DevOps-owned trên Jenkins chung; không nhét vào pipeline-lib.

---

## Mục tiêu một câu

Dev chỉ sửa code service. DevOps chỉ sửa Terraform. Một Jenkins controller: service thì `go-micro-ci` build/push; Terraform thì `platform/terraform-management-plan` trên PR rồi `platform/terraform-management-apply` trên `main`. Không ai apply từ laptop; không ai tự deploy prod.

---

## Ai được đụng gì

| | Developer | DevOps |
|---|---|---|
| Repo | `go-micro-product`, `order`, `payment`, … | `go-micro-infra` (terraform, jenkins), `go-micro-pipeline-lib`, GitOps platform |
| Việc | Sửa code service → PR → review → merge `main` | Sửa Terraform → PR → **plan Jenkins** → review/tự-kiểm → merge `main` → apply Jenkins |
| Jenkins | Job `services/*` (`go-micro-ci` / `ciGoMicroService`) | `platform/terraform-management-plan` (PR) + `platform/terraform-management-apply` (`main`) |
| Không | Repo Terraform, AWS credential, chạy job apply | Viết business logic trong service |

Dev **không** gọi Terraform. Không Jenkins riêng cho mỗi người.

---

## Hai luồng (đã chốt)

```
Developer
  → chỉ sửa service: order, payment, product, …
  → tạo PR
  → review
  → merge main
  → Jenkins chung + go-micro-ci: build/push image
  → cập nhật GitOps
  → Argo CD deploy
```

```
DevOps
  → sửa go-micro-infra/terraform
  → PR Terraform (chỉ DevOps)
  → platform/terraform-management-plan
       fmt → validate → tflint → terraform plan
       comment add/change/destroy vào PR
  → tự-kiểm (1 DevOps) hoặc review (khi ≥2)
  → merge main
  → platform/terraform-management-apply
       init → plan -out=tfplan → approval → apply tfplan
```

GitOps prod: PR promote **cùng digest**, CODEOWNERS — không rebuild, không push thẳng.

---

## Lab vs “production-IaC”

Terraform hiện là **sườn lab tốt**, chưa production-IaC cho team. Vấn đề lớn không phải thiếu HA/EC2, mà **tính đúng đắn, secret, ai được apply**.

**Ổn sẵn**

- Remote state S3 (versioning, encryption, public-access block) + S3 native lock (`use_lockfile`)
- Module vừa đủ: VPC, ubuntu-host, SSM, app-credentials, eso-iam
- Không SSH/key pair; SSM role
- Root volume mã hóa; AMI Canonical

**Lỗi chức năng (đã vá trên code, chờ apply)**

- `environments/management` gọi VPC, SSM, 2 EC2, **`app-credentials` (foreach env)**, **`eso-iam`**
- Apply tạo Secrets Manager + ESO access key; outputs `app_credentials_secret_names`, `eso_*`
- `environments` + `app_credentials_name_suffix_by_env` đã dùng; `secret_recovery_window_in_days` mặc định 7

**Nâng khi làm IaC “đúng” (sau apply lần đầu, không phải làm hết trước CI)**

- Secret nằm trong Terraform state; `sensitive = true` chỉ che CLI. Backend IAM hẹp; cân nhắc KMS CMK thay AES256
- `recovery_window_in_days` mặc định 7 (còn option `0` trong tfvars khi destroy lab gấp)
- ESO IAM key tĩnh, đọc cả prefix `go-micro/*`, chưa rotation; lab Kind chấp nhận, nên tách principal dev/prod theo ARN exact
- AMI `most_recent` + `ignore_changes = [ami]`, `user_data_replace_on_change = false` — cloud-init/AMI mới không lên host cũ; cần runbook patch/rebuild
- Provider pin `~> 5.0`; lockfile đã commit theo root; apply chỉ từ Jenkins + người DevOps

**Thứ tự IaC:** wire secret/ESO + outputs/README khớp → GitHub quyền Terraform + job plan/apply Jenkins → siết state/KMS/rotation → chốt drift/host update.

---

## Một Jenkins, library chỉ cho service

Một **controller** (Docker Compose trên EC2, CasC trong `go-micro-infra/jenkins`). Không có Jenkins riêng cho mỗi dev.

Repo `go-micro-pipeline-lib` đăng ký tên **`go-micro-ci`**. Chỉ CI service:

```
services/product      → ciGoMicroService
services/order        → ciGoMicroService
services/payment      → …
```

DevOps sở hữu library + Job DSL. Dev không viết docker/gitops/terraform trong Jenkinsfile service — Jenkinsfile service chỉ identity.

**Không** `ciTerraform`. Terraform không đi qua `go-micro-ci`. Đủ hai job Job DSL/JCasC:

- `platform/terraform-management-plan` — PR
- `platform/terraform-management-apply` — `main`

Nếu chỉ DevOps được tạo PR/sửa `go-micro-infra`, Jenkinsfile trên PR repo này **không** còn đường leo thang từ developer service. **Nhưng** job apply vẫn chỉ chạy pipeline từ `main` đã merge — không chạy Jenkinsfile từ PR branch.

---

## Terraform: hai job, không `ciTerraform`

Terraform **chỉ** plan/apply trên Jenkins chung **sau lần dựng đầu**. Laptop không phải cổng apply hàng ngày. Dev không access Terraform. Không mỗi dev một Jenkins.

**Lần đầu (con gà–quả trứng):** `bootstrap/` luôn local (chưa có S3). `management/` lần đầu cũng local — stack này tạo EC2 Jenkins, nên job apply chưa tồn tại. Cài compose Jenkins trên EC2 xong mới dùng hai job dưới. Không tách `jenkins-host/` khỏi `management/` (cùng VPC). Plan nào đụng `module.jenkins_host` / SG :8080: review kỹ; apply hỏng Jenkins → sửa bằng apply **local** (cùng `backend.hcl`). Chi tiết: `terraform/README.md`.

### 1. PR vẫn có plan visibility — `platform/terraform-management-plan`

Diff `.tf` đúng cú pháp không đồng nghĩa plan ra đúng resource (module sai, var mặc định lệch, data source đổi). Trước merge, job checkout **PR** `go-micro-infra`, chạy:

`fmt` → `validate` → `tflint` → `terraform plan`

Comment summary add/change/destroy vào PR. Không shared library mới.

Gọi credential là **plan-only**, không phải “read-only tuyệt đối”. `terraform plan` vẫn cần:

- đọc S3 state
- tạo/xóa object lock `.tflock` trên cùng bucket (S3 native lock, Terraform ≥ 1.10)
- gọi API AWS **read** để refresh state

Role này **không** được tạo/sửa/xóa resource AWS thật. **Không apply.**

### 2. Apply đúng plan vừa tính — `platform/terraform-management-apply`

Không `init` rồi `apply` thẳng. Cùng workspace, cùng commit `main`, cùng lần chạy Jenkins:

```
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

Giữa `plan -out` và `apply tfplan` (cùng build): apply đúng file đó — không tính lại. Lab 1 DevOps: **không** `input` step; “approval” = quy trình (đọc log rồi mới bấm Build). Không phải gate kỹ thuật. ≥2 DevOps mới thêm `input` chờ Proceed.

Trigger: sau merge `main`, hoặc DevOps chạy tay. **Chỉ checkout `main`.** Credential AWS **write**. Pipeline **không** lấy Jenkinsfile từ PR branch.

Plan lúc review PR và plan lúc apply là **hai lần plan riêng**. Cố ý: apply re-plan để tránh plan stale. Nếu AWS state đổi giữa merge và apply, plan 2 có thể khác plan 1.

So sánh **count add / change / destroy** (và danh sách resource nếu có). Management stack nhỏ (vài EC2 + IAM): **mọi lệch, kể cả 1 resource, đều fail cứng** — không ngưỡng %, không warning rồi tiếp. `error()` trong pipeline; **không** override, **không** resume. DevOps đọc log, tự quyết re-run (plan lại từ đầu trên `main`).

### JCasC / Job DSL apply khi nào

Cùng nguyên tắc job apply: **chỉ từ `main`**, không từ PR.

Lab hiện tại: `CASC_JENKINS_CONFIG` bind-mount `jenkins/casc/` — CasC + Job DSL (`jobs.groovy`) load lúc **Jenkins start / restart**. Đổi YAML trên PR **không** reload controller.

Sau merge `main`: DevOps `git pull` trên host Jenkins rồi restart (hoặc CasC reload thủ công từ checkout `main`).

Nếu sau này thêm seed job auto-reload: trigger **chỉ** push `main` (path `jenkins/casc/**`); checkout `main`; PR `jenkins/casc` không được seed.

### CODEOWNERS khi 1 DevOps

Không tạo kiểm soát hai người. Giữ branch protection + check Jenkins: chống push nhầm, có audit trail. “Review DevOps” = **checklist tự-kiểm trước apply** (đọc plan PR + plan lúc apply). ≥2 DevOps mới bật required approval/CODEOWNERS cho dual-control thật.

Dev không quyền repo Terraform, không thấy AWS write, không chạy job apply.

Bootstrap (S3 + `use_lockfile`) lần đầu: DevOps làm theo runbook. Sau đó hai job trên Jenkins.

Hiện chưa có các job này; `loggedInUsersCanDoAnything` nên chưa siết được quyền.

---

## Layout Terraform (đã chốt)

`bootstrap/` **không** phải environment — chỉ tạo remote backend (local state lần đầu).

```
terraform/
├── bootstrap/                 # local state — S3 + use_lockfile
├── environments/
│   └── management/            # remote state key: management/terraform.tfstate
└── modules/
```

- Mỗi root `provider.tf` **thật** (không symlink)
- Bootstrap **không** khai báo provider `http`; chỉ management (lấy IP public cho SG)
- Key cũ `live/terraform.tfstate`. Lab đã destroy bucket → lần apply tới là **greenfield**. Nếu bucket còn state `live/` thì `terraform init -migrate-state` + `terraform state list` **trước** mọi apply

---

## Checklist việc (không Trivy)

Làm **1 → 6** (kể cả **5.5**) trước, rồi **7 → 9**. Bước 10 xuyên suốt.

### 1. GitHub: quyền + branch protection

- Bảo vệ `main`: `go-micro-infra`, `go-micro-gitops`, `go-micro-pipeline-lib`, repo service
- Cấm push thẳng; mọi thay đổi qua PR
- `go-micro-infra`: chỉ DevOps mở PR Terraform; Dev không write
- CODEOWNERS `terraform/**`, `jenkins/**` → DevOps — **cấm Dev**, không giả dual-approval khi chỉ 1 DevOps
- GitOps prod / Argo / secret config → DevOps/tech lead
- Lab 1 DevOps: không required second reviewer; checklist tự-kiểm trước apply + job plan; CODEOWNERS/protection để chống push nhầm + audit

### 2. Jenkins theo vai trò

- Bỏ `loggedInUsersCanDoAnything`
- Folder `services/` vs `platform/` — Matrix Authorization (hoặc Folder Authorization) **trong JCasC**, không dựa mô tả job
- Developer: đọc/chạy `services/*`; **không** Job/Read `platform/*` (kể cả log, artifact `tfplan`)
- DevOps: CasC, credentials, `platform/terraform-management-plan` + `platform/terraform-management-apply`, prod
- Dev không xem AWS credential, GitOps write token, Jenkins admin

### 3. Tách credential

- AWS **plan-only** (`platform/terraform-management-plan`) ≠ AWS **write** (`platform/terraform-management-apply`)
- Plan-only: đọc S3 state, ghi/xóa `.tflock`, API read refresh — **không** tạo/sửa/xóa resource lab
- GitHub read-only checkout source (service + infra)
- Bot chỉ write `go-micro-gitops`
- Registry chỉ push đúng image repo
- Job service **không** có AWS
- Job plan **không** bind credential apply
- Job apply **không** chạy Jenkinsfile từ PR branch

### 4. Hoàn thiện Terraform root trước khi cắm job

- Đã wire `app-credentials` (foreach env) + `eso-iam` vào `environments/management`; outputs khớp README
- Giữ S3 versioning + `use_lockfile` (không DynamoDB)
- `secret_recovery_window_in_days` mặc định 7
- Commit `.terraform.lock.hcl` (đã có theo root)
- Pin version Terraform/provider trên Jenkins
- Runbook: bootstrap + **lần đầu management** = local; sau đó mọi đổi `management/` qua Jenkins; Jenkins chết thì apply local lại

### 5. PR Terraform (nội bộ DevOps, GitHub)

- Chỉ DevOps sửa `go-micro-infra/terraform`
- PR → job plan → tự-kiểm / review → merge `main`
- **Không** `ciTerraform`
- 1 DevOps: checklist tự-kiểm trước apply; không giả reviewer thứ hai
- Merge xong (hoặc DevOps chạy tay trên `main`) mới apply

### 5.5. `platform/terraform-management-plan`

- Job DevOps-owned (Job DSL/JCasC). Không shared library mới
- Trigger PR `go-micro-infra`; checkout **PR**
- **Commit mới trên cùng PR** → job chạy lại; comment plan **cập nhật/thay** (không để summary stale trên PR)
- Credential **plan-only** (S3 state + `.tflock` + API read; không CRUD resource lab)
- `-chdir=terraform/environments/management`
- `fmt` → `validate` → `tflint` → `terraform plan`
- Comment PR: add/change/destroy; **không** in secret
- Artifact plan text/summary nếu lưu: chỉ người có Job/Read `platform/` (DevOps)
- **Không apply**

### 6. `platform/terraform-management-apply`

- Job DevOps-owned; pipeline từ **`main` đã merge**, không Jenkinsfile PR branch
- Trigger: sau merge `main`, hoặc DevOps chạy tay
- Chỉ checkout `main`; cùng workspace / cùng commit / cùng lần chạy
- `-chdir=terraform/environments/management`
- `terraform init` → `terraform plan -out=tfplan` → so sánh count add/change/destroy với plan PR (**mọi lệch, kể cả 1 resource** → `error()`, job fail cứng, không override/resume) → `terraform apply tfplan`
- Apply đúng file `tfplan` vừa tạo trong **cùng build** — không reuse artifact từ job PR
- Fail lệch plan: DevOps đọc log rồi tự trigger lại (re-plan trên `main`) — khớp “quy trình, không gate kỹ thuật”
- Lab 1 DevOps: không `input` Proceed trong pipeline; tự-kiểm log rồi mới trigger/continue — **quy trình**, không gate kỹ thuật. ≥2 người: `input` step
- Jenkins lock theo state
- Chỉ DevOps trigger
- Chỉ job này AWS write
- `tfplan` binary: Jenkins artifact của job `platform/terraform-management-apply`; TTL ngắn; **không** public. Quyền xem = quyền Job/Read folder `platform/` (JCasC bước 2) — Dev không đọc được. Không commit `tfplan` lên git

### 7. Job service PR-aware

- PR service: test/lint — **không** build/push nếu chưa merge (hoặc không credential deploy)
- Merge `main` mới `ciGoMicroService` build/push image immutable
- Library pin tag; `allowVersionOverride: false`
- Jenkinsfile chỉ identity service; không `envFile` / `gitBranch` / `gitopsRepo` tùy ý

### 8. GitOps qua PR, không push thẳng

- Sau image: bot **mở PR** GitOps (digest/tag)
- PR GitOps: Helm template, kubeconform/schema, policy, tag tồn tại trên registry
- Merge rồi Argo sync **dev**
- Prod: PR promote digest đã qua dev; không rebuild

### 9. Concurrent (10 dev, **service**)

- Ưu tiên `env/dev/product.yaml`, `env/dev/order.yaml`, …
- Hoặc lock + fetch/rebase/retry nếu còn file chung
- File riêng → diff nhỏ, ownership rõ

### 10. Audit / vận hành

- Jenkins báo plan PR + apply Terraform lên GitHub
- Gắn SHA, PR URL, build URL; log **plan** (PR + lúc apply) — không chỉ “build xanh”
- Hai plan là hai lần chạy: PR = visibility; apply = nguồn apply. Mọi lệch add/change/destroy (kể cả 1 resource) → `error()`, fail cứng; không resume
- JCasC/Job DSL: load lúc Jenkins start/restart từ checkout **`main`**; không reload từ PR. Seed job (nếu có) chỉ push `main`
- Rollback Terraform: revert PR DevOps → plan PR → merge → apply `tfplan` trên Jenkins
- Rollback GitOps: PR restore digest → merge → Argo
- Drift: job/plan định kỳ `-detailed-exitcode`, **chỉ báo**, không tự apply

---

## Khi xong 1–6 (kể cả 5.5)

Bản này **đủ nguyên tắc** để implement. Chi tiết so sánh count / `error()` / CasC restart — làm lúc viết job thật; không còn chọn threshold tùy hứng.

Dev PR service → review → merge → Jenkins `ciGoMicroService`. DevOps PR Terraform → `platform/terraform-management-plan` → tự-kiểm (quy trình) → merge → `platform/terraform-management-apply` (`init` / `plan -out` / so sánh count / lệch thì fail / `apply tfplan`). CasC chỉ từ `main`. Một controller, không HA AWS.

---

## Cố ý không làm ở đây

- `ciTerraform` / Terraform trong `go-micro-ci`
- Trivy / image CVE scan
- EKS, IRSA, Multi-AZ, NAT đắt
- Mỗi dev một Jenkins
- Dev đụng `go-micro-infra/terraform`
- Giả dual-control CODEOWNERS khi chỉ 1 DevOps
