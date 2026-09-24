# terraform — một chỗ cho AWS lab

Không còn `terraform_secret/`. Không EKS.

```
bootstrap/   S3 + DynamoDB (state + lock). Local state lần đầu.
live/        VPC + EC2 Jenkins (t4g.small Spot) + EC2 Kind (t3.large Spot). Secrets not created.
modules/     vpc, ubuntu-host, app-credentials, eso-iam, ec2-ssm
```

Jenkins **không** nằm trên Kind. Hai EC2, một VPC. Cả hai Spot.

## 1) Bootstrap remote state (làm một lần)

Chicken-egg: bucket state chưa có thì chưa đẩy state vào S3. Root này giữ **local state**.

```bash
cd terraform/bootstrap
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply
terraform output backend_hcl
```

Copy output vào `terraform/live/backend.hcl` (file này gitignore).

Bucket: `{project}-tfstate-{account_id}`. Table: `{project}-tf-locks`.

## 2) Live (máy + secret)

```bash
cd terraform/live
cp backend.hcl.example backend.hcl
# dán bucket / table từ bước 1
cp terraform.tfvars.example terraform.tfvars
# db_password, stripe_secret_key (no .pem / ssh_key_name)

terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

Outputs:

```bash
terraform output kind_ssm_command
terraform output jenkins_ssm_command
terraform output argo_url
terraform output jenkins_url
terraform output -raw eso_access_key_id
terraform output -raw eso_secret_access_key
```

SG mặc định chỉ IP public lúc `apply` (Jenkins :8080, Argo :18080). Đổi WiFi thì `apply` lại. **Không mở port 22** — vào máy bằng SSM.

EIP gắn từng máy — stop/start không đổi IP.

Laptop cần AWS CLI + [Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html). IAM user/role của bạn phải có `ssm:StartSession`.

## 3) Sau khi SSM

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

`go-micro/{dev,prod}/app-credentials` — JSON DB + Stripe.

IAM user ESO: `GetSecretValue` trên prefix `go-micro/*`. Tạo secret K8s sau khi cluster lên:

```bash
kubectl -n external-secrets create secret generic aws-credentials \
  --from-literal=access-key-id="$(terraform output -raw eso_access_key_id)" \
  --from-literal=secret-access-key="$(terraform output -raw eso_secret_access_key)"
```

Chạy `output` từ `terraform/live`.

## Defaults

| | Kind | Jenkins |
|---|---|---|
| Type | t3.large (amd64, Spot persistent / stop) | t4g.small (arm64, Spot persistent / stop) |
| Disk | 40 GiB | 20 GiB |
| Ports | 18080 | 8080 |
| Login | SSM (no .pem) | SSM (no .pem) |
| user_data | Docker, kind, kubectl 1.28, helm, argocd, SSM agent | Docker + compose + SSM agent |

Region mặc định `ap-southeast-2`. Không cần EC2 key pair.
