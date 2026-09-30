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

Jenkins **không** nằm trên Kind. Hai EC2, một VPC. Kind = Spot; Jenkins = On-Demand (`jenkins_use_spot = false`) vì Spot `t4g.small` bị AWS stop khi hết capacity. **Không** tách `jenkins-host/` thành stack riêng: VPC + Kind + Jenkins + secrets cùng `management/`.

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

Review kỹ plan nào có change/destroy trên `module.jenkins_host`. `user_data_replace_on_change = false`. Pin `jenkins_ami_id` / `kind_ami_id`. Đổi SG chặn IP của bạn / port 8080 = mất UI + webhook.

**Spot không đổi instance type tại chỗ** (Jenkins apply `t3.large`→`t3.xlarge` sẽ fail). Resize Kind: `create-image` instance đang chạy → set `kind_ami_id` + `kind_instance_type` → apply **replace** instance (disk Kind/Argo nằm trong AMI). Không dùng Ubuntu AMI mới. `kind_host` user_data để trống khi boot từ snapshot. Sau boot, Docker IP Kind có thể đổi → re-register Argo cluster secret.

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
| Ports | 18080 Argo, 32000 Grafana, 32090 Prometheus | 8080 |
| Login | SSM (no .pem) | SSM (no .pem) |
| user_data | snapshot AMI: empty (Kind already on disk). Fresh Ubuntu: Docker, kind, kubectl 1.28, helm, argocd, SSM agent | Docker + compose + SSM agent |

Region mặc định `ap-southeast-2`. Không cần EC2 key pair.

Jenkins jobs (`-chdir`) — **sau** lần đầu local:

```bash
terraform -chdir=terraform/environments/management ...
```

Bootstrap không đi qua Jenkins:

```bash
terraform -chdir=terraform/bootstrap ...
```

## RKE2 — 3 VPC peering (management / dev / prod)

Stack mới, **không** thay `management/` (Kind host + Jenkins vẫn chạy nguyên trong VPC `10.50.0.0/16`).

```
environments/rke2-management/   10.0.0.0/16   RKE2 + Argo CD + OpenVPN
environments/rke2-dev/          10.1.0.0/16   RKE2 (private only)
environments/rke2-prod/         10.2.0.0/16   RKE2 (private only)
environments/networking/        peering: mgmt↔dev, mgmt↔prod, jenkins↔dev, jenkins↔prod
```

`modules/`: `rke2-network`, `rke2-iam`, `keys`, `rke2-token`, `rke2-lb`, `rke2-nodes`, `openvpn`.

### Đường vào: OpenVPN + SSH (không phải SSM)

Node nằm **private subnet, không public IP**. Máy duy nhất hở internet là **OpenVPN host** ở public subnet của management; nó cũng là **jump host SSH** cho mọi node.

```
laptop --(.ovpn)--> OpenVPN host 10.0.1.x --peering--> dev 10.1.101.x / prod 10.2.101.x
                         ^ ProxyCommand cho ansible / ssh / export-kubeconfig
```

Vì sao SSH chứ không SSM: Ansible chạy **native SSH** (không cần `aws_ssm` + bucket S3 trung chuyển từng task), và VPN cho **tunnel layer-3 thật** — `kubectl` tới internal NLB, `ping`/`nc`/`psql`, Argo CD UI, Grafana đều đi được, không phải mở một session port-forward cho từng port. Mô hình này cũng mang nguyên sang GCP/Azure/on-prem. IAM `AmazonSSMManagedInstanceCore` vẫn attach để **break-glass** khi VPN sập.

Ranh giới sở hữu: **Terraform** = Security Group / route / peering / key pair. **Ansible** = `iptables` trên VPN host + user/`authorized_keys`/`sudoers` trên node. Không để Ansible sửa SG, nếu không `terraform apply` sau sẽ xoá mất.

Key pair do Terraform sinh (`modules/keys`), private key ghi ra `environments/<stack>/rke2-key-<env>.pem` (gitignored `*.pem`). `admin_ssh_cidr` nên set `/32` IP của mày; mặc định `0.0.0.0/0` chỉ để lab.

NAT gateway mỗi VPC cho registry / `get.rke2.io` / Secrets Manager.

CNI là **Canal** (default RKE2). `rke2-ingress-nginx` bị `disable` vì Traefik do Argo CD quản lý và dùng NodePort **32080/32443** — public NLB trỏ vào 2 port đó (thay `host-nodeport-proxy` của Kind).

Token cluster do Terraform sinh và lưu Secrets Manager `go-micro/{env}/rke2-token`, không qua tfvars.

### Thứ tự apply

`networking/` đọc VPC theo tag nên dev/prod là optional — apply được ngay sau management.

```bash
export TF_STACK=rke2-management   # rồi rke2-dev, rke2-prod, networking
terraform -chdir=terraform/environments/$TF_STACK init -backend-config=backend.hcl
terraform -chdir=terraform/environments/$TF_STACK apply
```

State key theo stack: `{stack}/terraform.tfstate`. Job Jenkins dùng `TF_STACK` (allowlist trong `jenkins/terraform/run.sh`).

### OpenVPN server (Ansible qua SSH)

```bash
cd ansible
cp inventory_openvpn.example.yml inventory_openvpn.yml   # điền openvpn_public_ip
cp group_vars/users.yml.example group_vars/users.yml     # ai được .ovpn + SSH key + role
ansible-playbook -i inventory_openvpn.yml openvpn-server.yml \
  -e openvpn_public_ip="$(terraform -chdir=../terraform/environments/rke2-management output -raw openvpn_public_ip)"
```

`.ovpn` (UDP 1194 + bản `-tcp` fallback 443) về `ansible/out/` — gitignored. **DevOps phát file này cho từng engineer**: nó cho quyền *mạng* vào VPC, không phải quyền login máy.

Firewall theo user trên gateway: `10.8.0.51` (devops) đi hết, `10.8.0.50` (developer) vào được `10.1.0.0/16` nhưng **DROP** sang `10.2.0.0/16`.

Chưa làm: `easyrsa revoke` + CRL (`crl-verify`) để thu hồi `.ovpn`.

### Cấp quyền SSH trên node

```bash
scripts/rke2/gen-ansible-inventory.sh rke2-dev     # inventory + ProxyCommand qua jump
cd ansible && ansible-playbook -i inventory_rke2-dev.yml nodes-access.yml
```

Tạo user theo `vpn_users`, đẩy `authorized_keys` (`exclusive: true`), và chỉ `role: devops` được `NOPASSWD` sudo. Thêm người = thêm entry vào `users.yml` rồi chạy lại playbook.

### kubeconfig cho Jenkins / Argo CD

```bash
scripts/rke2/export-kubeconfig.sh rke2-dev
```

SSH qua jump đọc `/etc/rancher/rke2/rke2.yaml`, đổi server thành internal NLB (đã có trong `tls-san`), lưu `go-micro/{env}/kubeconfig`. Jenkins ở `10.50.0.0/16` gọi apiserver qua peering — SG master mở 6443 cho `10.0.0.0/16` + `10.50.0.0/16`.
