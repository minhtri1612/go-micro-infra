# terraform — AWS lab (RKE2)

Không EKS. `bootstrap/` không phải environment: chỉ tạo remote backend (local state).

`environments/management` là lab Kind cũ (VPC `10.50.0.0/16`) — **đã destroy, không apply lại**. Cluster + Jenkins nằm ở `rke2-*`.

```
terraform/
├── bootstrap/                      # local state — S3 bucket (lock = use_lockfile)
├── environments/
│   ├── rke2-management/            # 10.0.0.0/16  RKE2 + Argo + OpenVPN + Jenkins EC2
│   ├── rke2-dev/                   # 10.1.0.0/16
│   ├── rke2-prod/                  # 10.2.0.0/16
│   └── networking/                 # peering mgmt↔dev, mgmt↔prod
└── modules/                        # rke2-*, keys, openvpn, ubuntu-host, app-credentials, eso-iam
```

Mỗi root có `provider.tf` thật (không symlink) để Jenkins `terraform -chdir=...` chạy được.

## Con gà–quả trứng (ai apply lúc nào)

Jenkins CI sau này apply stack `rke2-*` — kể cả EC2 đang chạy Jenkins. Lần đầu Jenkins chưa tồn tại nên **không** apply qua CI được.

```
Lần đầu (1 lần, DevOps laptop):
  bootstrap/           local state  →  S3 (versioning + S3 lockfile)
  rke2-management/     remote S3    →  VPC, RKE2, OpenVPN, Jenkins EC2
                       →  cài Jenkins (compose) trên EC2 vừa tạo

Từ lần 2:
  đổi terraform/  →  PR  →  platform/terraform-management-plan
                  →  merge →  platform/terraform-management-apply
                  (chạy trên Jenkins EC2, TF_STACK=rke2-management|rke2-dev|rke2-prod|networking)
```

`bootstrap/` **luôn** local — không có remote backend, không job Jenkins.

### Cảnh báo: Jenkins apply hạ tầng đang host nó

Apply sau này có thể đụng `module.jenkins` (AMI, SG :8080). Nếu apply fail giữa chừng làm chết Jenkins thì **không còn job** để sửa — quay lại **apply local** trên laptop (cùng `backend.hcl`).

`user_data_replace_on_change = false`. Đổi SG chặn IP / port 8080 = mất UI + webhook.

## State key

State theo stack: `{stack}/terraform.tfstate` (`rke2-management/`, `rke2-dev/`, …). Key cũ `live/` và lab Kind `management/` đã bỏ.

Bucket: `{project}-tfstate-{account_id}`. Lock: object `.tflock` cạnh state (`use_lockfile = true`). Không DynamoDB.

## 1) Bootstrap remote state (local, một lần)

```bash
cd terraform/bootstrap
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply
terraform output backend_hcl
```

Copy output vào `terraform/environments/<stack>/backend.hcl` (gitignore).

## 2) RKE2 — lần đầu cũng local

Jenkins chưa có. DevOps apply trên laptop. Chi tiết OpenVPN / Ansible / kubeconfig ở dưới.

```bash
export TF_STACK=rke2-management   # rồi rke2-dev, rke2-prod, networking
terraform -chdir=terraform/environments/$TF_STACK init -backend-config=backend.hcl
terraform -chdir=terraform/environments/$TF_STACK apply
```

Sau này đổi `.tf` → PR + Jenkins, **không** apply laptop trừ khi Jenkins chết.

Region mặc định `ap-southeast-2`.

Jenkins jobs (`-chdir`) — **sau** lần đầu local — allowlist trong `jenkins/terraform/run.sh`.

Bootstrap không đi qua Jenkins:

```bash
terraform -chdir=terraform/bootstrap ...
```

## RKE2 — 3 VPC peering (management / dev / prod)

```
environments/rke2-management/   10.0.0.0/16   RKE2 + Argo CD + OpenVPN + Jenkins EC2
environments/rke2-dev/          10.1.0.0/16   RKE2 (private only)
environments/rke2-prod/         10.2.0.0/16   RKE2 (private only)
environments/networking/        peering: mgmt↔dev, mgmt↔prod
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

CNI là **Canal** (default RKE2). `rke2-ingress-nginx` bị `disable` vì Traefik do Argo CD quản lý và dùng NodePort **32080/32443** — public NLB trỏ vào 2 port đó.

Token cluster do Terraform sinh và lưu Secrets Manager `go-micro/{env}/rke2-token`, không qua tfvars.

### Who lives on management

| Piece | Where | How it gets there |
|---|---|---|
| OpenVPN + jump SSH | EC2 public subnet, EIP | Terraform `module.openvpn` + Ansible `openvpn-server.yml` (laptop, lần đầu / thêm user) |
| Ansible playbooks | `ansible/` | laptop qua jump — Jenkins không SSH VPN |
| Argo CD | **RKE2 management** | Helm **1 lần** trên laptop (gà–quả trứng; Jenkins chưa có cluster) |
| Prometheus + Grafana | **same cluster** | Argo CD Application `05-monitoring-mgmt.yaml` |
| Jenkins | **EC2 cùng VPC**, compose | Terraform `module.jenkins` — không phải pod |

Không có `provision.py` / `configure.py`. Terraform sau lần đầu = Jenkins. App/monitoring = Argo. Script chỉ việc CI không làm được: `scripts/rke2/export-kubeconfig.sh`, `scripts/rke2/gen-ansible-inventory.sh`.

Lần đầu (Jenkins chưa có) — laptop:

```bash
terraform -chdir=terraform/environments/rke2-management apply
# rồi Ansible OpenVPN (mục dưới) + sudo openvpn --config ansible/out/devops.ovpn
scripts/rke2/export-kubeconfig.sh rke2-management
export KUBECONFIG=kube_config_rke2_management.yaml   # hoặc lấy từ SM go-micro/management/kubeconfig
helm upgrade --install argocd argo/argo-cd -n argocd --create-namespace -f argocd/argocd-values.yaml
kubectl apply -f ../go-micro-gitops/argocd/bootstrap/00-argocd-cm-health.yaml
kubectl apply -f ../go-micro-gitops/argocd/bootstrap/01-projects.yaml
kubectl apply -f ../go-micro-gitops/argocd/bootstrap/05-monitoring-mgmt.yaml
```

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

SSH qua jump đọc `/etc/rancher/rke2/rke2.yaml`, đổi server thành internal NLB (đã có trong `tls-san`), lưu `go-micro/{env}/kubeconfig`. Jenkins nằm trong VPC management (`10.0.0.0/16`) gọi apiserver qua peering — SG master mở 6443 cho `10.0.0.0/16`.
