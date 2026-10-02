data "aws_ami" "ubuntu" {
  count       = var.ami_id == null ? 1 : 0
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "this" {
  ami                         = var.ami_id != null ? var.ami_id : data.aws_ami.ubuntu[0].id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [var.security_group_id]
  iam_instance_profile        = var.iam_instance_profile
  key_name                    = var.key_name
  associate_public_ip_address = true

  # This host routes VPN client traffic into the VPCs, so it must be allowed to
  # send and receive packets for addresses other than its own.
  source_dest_check = false

  user_data = <<-EOF
    #!/bin/bash
    set -eux
    apt-get update
    apt-get install -y openvpn easy-rsa iptables-persistent
    # SSM agent stays installed as break-glass for when the VPN itself is down.
    snap list amazon-ssm-agent >/dev/null 2>&1 || snap install amazon-ssm-agent --classic
    snap start amazon-ssm-agent || true
  EOF

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_size
    encrypted   = true
  }

  tags = {
    Name = "${var.project_name}-openvpn-${var.environment}"
    Role = "openvpn"
  }
}

resource "aws_eip" "this" {
  instance = aws_instance.this.id
  domain   = "vpc"

  tags = {
    Name = "${var.project_name}-openvpn-eip-${var.environment}"
  }
}
