# terraform — AWS lab (Kind + Jenkins EC2)

Không EKS. `bootstrap/` không phải environment: chỉ tạo remote backend (local state). Stack máy nằm ở `environments/management`.

```
terraform/
├── bootstrap/                 # local state — S3 bucket (lock = use_lockfile)
├── environments/
│   └── management/            # remote state key: management/terraform.tfstate
└── modules/                   # vpc, ubuntu-host, app-credentials, eso-iam, ec2-ssm
```

Mỗi root có `provider.tf` thật (không symlink) để Jenkins `terraform -chdir=...` chạy được.

Jenkins **không** nằm trên Kind. Hai EC2, một VPC. Cả hai Spot. **Không** tách `jenkins-host/` thành stack riêng: VPC + Kind + Jenkins + secrets cùng `management/`.

## Con gà–quả trứng (ai apply lúc nào)

Jenkins CI sau này apply **chính** stack `management/` — kể cả EC2 đang chạy Jenkins. Lần đầu Jenkins chưa tồn tại nên **không** apply qua CI được.

```
Lần đầu (1 lần, DevOps laptop):
  bootstrap/      local state  →  S3 (versioning + S3 lockfile)
  management/     remote S3    →  VPC, Kind EC2, Jenkins EC2, SM, ESO IAM
                  →  cài Jenkins (compose) trên EC2 vừa tạo

Từ lần 2:
  đổi management/  →  PR  →  platform/terraform-management-plan
                   →  merge →  platform/terraform-management-apply
                   (chạy trên Jenkins EC2 của cùng stack)
```

`bootstrap/` **luôn** local — không có remote backend, không job Jenkins.

Job Jenkins **không** apply `bootstrap/` (allowlist chỉ `management` khi có CI).

### Cảnh báo: Jenkins apply hạ tầng đang host nó

Apply sau này có thể đụng `module.jenkins_host` (AMI, SG :8080, Spot, instance type). Nếu apply fail giữa chừng làm chết Jenkins thì **không còn job** để sửa — quay lại **apply local** trên laptop (cùng `backend.hcl`).

Review kỹ plan nào có change/destroy trên `module.jenkins_host`. AMI đã `ignore_changes`; `user_data_replace_on_change = false`. Đổi SG chặn IP của bạn / port 8080 = mất UI + webhook.

## State key

Remote state **mới** dùng `management/terraform.tfstate`. Key cũ `live/terraform.tfstate` đã bỏ.

**Không apply** management nếu bucket còn object `live/terraform.tfstate` mà chưa migrate. Kiểm tra:

```bash
cd terraform/environments/management
terraform init -backend-config=backend.hcl -migrate-state
terraform state list
```

Phải thấy VPC/EC2 cũ trước khi `apply`. Hiện lab đã destroy backend S3 (`go-micro-tfstate-*` không còn) — lần apply tới là **greenfield**, không có state để migrate.

## 1) Bootstrap remote state (local, một lần)

Bucket chưa có thì chưa đẩy state vào S3. Root này giữ **local state**.

```bash
cd terraform/bootstrap
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply
terraform output backend_hcl
```

Copy output vào `terraform/environments/management/backend.hcl` (gitignore).

Bucket: `{project}-tfstate-{account_id}`. Lock: object `.tflock` cạnh state (`use_lockfile = true`). Không DynamoDB.

## 2) Management — lần đầu cũng local

Jenkins chưa có. DevOps apply trên laptop:

```bash
cd terraform/environments/management
cp backend.hcl.example backend.hcl
# dán bucket / table từ bước 1
cp terraform.tfvars.example terraform.tfvars
# db_password, stripe_secret_key (no .pem / ssh_key_name)

terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

Sau này đổi `.tf` → PR + Jenkins, **không** apply laptop trừ khi Jenkins chết (fallback ở trên).

Outputs:

```bash
terraform output kind_ssm_command
terraform output jenkins_ssm_command
terraform output argo_url
terraform output jenkins_url
terraform output app_credentials_secret_names
```

SG mặc định chỉ IP public lúc `apply` (Jenkins :8080, Argo :18080). Đổi WiFi thì `apply` lại (lần đầu: local; sau: Jenkins hoặc local nếu mất UI). **Không mở port 22** — vào máy bằng SSM.

EIP gắn từng máy — stop/start không đổi IP.

Laptop cần AWS CLI + [Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html). IAM user/role của bạn phải có `ssm:StartSession`.

## 3) Sau khi SSM — cài Jenkins trên EC2 vừa tạo

```bash
terraform output -raw jenkins_ssm_command
# aws ssm start-session --target i-... --region ap-southeast-2
```

**Jenkins trước** (CI):

```bash
git clone https://github.com/minhtri1612/go-micro-infra.git ~/go-micro-infra
cd ~/go-micro-infra/jenkins
cp .env.example .env
docker compose up -d --build
```

**Kind** (cluster + Argo): `kind/README.md`. Clone `go-micro-infra` + `go-micro-gitops`.

## Secrets / ESO

`environments/management` gọi `app-credentials` (foreach `environments`, mặc định `dev` + `prod`) và `eso-iam`. Tên secret: `go-micro/{env}/app-credentials`.

```bash
cd terraform/environments/management
kubectl -n external-secrets create secret generic aws-credentials \
  --from-literal=access-key-id="$(terraform output -raw eso_access_key_id)" \
  --from-literal=secret-access-key="$(terraform output -raw eso_secret_access_key)"
```

`secret_recovery_window_in_days` mặc định `7` (không xóa SM ngay khi destroy). Lab cần xóa gấp: set `0` trong tfvars.

## Defaults

| | Kind | Jenkins |
|---|---|---|
| Type | t3.xlarge (amd64, Spot persistent / stop) | t4g.small (arm64, Spot persistent / stop) |
| Disk | 40 GiB | 20 GiB |
| Ports | 18080 | 8080 |
| Login | SSM (no .pem) | SSM (no .pem) |
| user_data | Docker, kind, kubectl 1.28, helm, argocd, SSM agent | Docker + compose + SSM agent |

Region mặc định `ap-southeast-2`. Không cần EC2 key pair.

Jenkins jobs (`-chdir`) — **sau** lần đầu local:

```bash
terraform -chdir=terraform/environments/management ...
```

Bootstrap không đi qua Jenkins:

```bash
terraform -chdir=terraform/bootstrap ...
```
