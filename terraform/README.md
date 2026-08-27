# terraform - minimal EC2 host for Kind lab

This stack creates the smallest AWS base infrastructure for the `go-micro` Kind lab:

- 1 VPC
- 1 public subnet
- 1 Internet Gateway
- 1 route table for Internet access
- 1 security group
- 1 Ubuntu EC2 instance (`m7i.xlarge` by default — 16 GiB RAM; đủ cho 3 Kind cluster lab, lúc chạy ~10 GiB used)

It is intentionally simple. It does **not** create EKS, NAT, private subnets, ALB, or EBS CSI.

## What user_data installs

At first boot, the EC2 host installs:

- Docker Engine
- `kubectl`
- `helm`
- `kind`
- `argocd`
- `cilium`
- `git`, `jq`, `curl`, `unzip`

It also:

- enables Docker on boot
- adds user `ubuntu` to the `docker` group
- installs helper command `go-micro-check-tools`

## SSH key

This stack uses an **existing** EC2 key pair in the region (created in AWS console).

- Set `ssh_key_name` to the exact key pair name in AWS (e.g. `minhtri`)
- Keep the downloaded private key locally (e.g. `../minhtri.pem`) for SSH
- Terraform does **not** create/import a key pair and does **not** need a `.pub` file

## What gets opened

From your current public IP only (auto-detected at `terraform apply` unless you set `ssh_ingress_cidr`):

- `22` for SSH
- `18080` for Argo CD port-forward on the host
- `18081` for Jenkins port-forward on the host

Edit `allowed_tcp_ports` or set `ssh_ingress_cidr` to pin a fixed CIDR if needed.

When you change WiFi/location, run `terraform apply` again — it will refresh the security group with your new IP.

## Run

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# set ssh_key_name to the exact existing AWS key pair name
terraform init
terraform plan
terraform apply -auto-approve
```

## Outputs

After apply:

```bash
terraform output ssh_command
terraform output argo_url
terraform output jenkins_url
```

Then SSH in and run:

```bash
ssh -i ../minhtri.pem ubuntu@<public-ip>
go-micro-check-tools
```

If you want the repo cloned automatically into your home directory workflow, run:

```bash
git clone https://github.com/minhtri1612/go-micro.git ~/go-micro
cd ~/go-micro
bash scripts/bootstrap-ubuntu-ec2-kind.sh
```

## Notes

- Default AMI: Ubuntu 24.04 LTS
- Root disk: `gp3` 100 GiB
- Region default: `ap-southeast-2`
- Default SSH: existing key pair `minhtri` + private key `../minhtri.pem`
- `kind/README.md` is still the source of truth for the Kubernetes lab steps
