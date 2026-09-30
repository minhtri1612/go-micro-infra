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

locals {
  ami_id = var.ami_id != null ? var.ami_id : data.aws_ami.ubuntu[0].id
}

resource "aws_instance" "master" {
  count                       = var.master_count
  ami                         = local.ami_id
  instance_type               = var.master_instance_type
  subnet_id                   = var.private_subnet_ids[0]
  vpc_security_group_ids      = [var.node_common_sg_id, var.master_sg_id]
  iam_instance_profile        = var.iam_instance_profile
  associate_public_ip_address = false

  user_data = templatefile("${path.module}/userdata_master.sh", {
    rke2_version = var.rke2_version
    rke2_token   = var.rke2_token
    api_dns_name = var.api_dns_name
  })
  user_data_replace_on_change = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  dynamic "instance_market_options" {
    for_each = var.use_spot ? [1] : []
    content {
      market_type = "spot"
      spot_options {
        spot_instance_type             = "persistent"
        instance_interruption_behavior = "stop"
      }
    }
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_size
    encrypted   = true
  }

  tags = {
    Name = "${var.project_name}-master-${count.index + 1}-${var.environment}"
    Role = "rke2-master"
  }
}

resource "aws_instance" "worker" {
  count                       = var.worker_count
  ami                         = local.ami_id
  instance_type               = var.worker_instance_type
  subnet_id                   = var.private_subnet_ids[count.index % length(var.private_subnet_ids)]
  vpc_security_group_ids      = [var.node_common_sg_id, var.worker_sg_id]
  iam_instance_profile        = var.iam_instance_profile
  associate_public_ip_address = false

  user_data = templatefile("${path.module}/userdata_worker.sh", {
    rke2_version = var.rke2_version
    rke2_token   = var.rke2_token
    master_ip    = aws_instance.master[0].private_ip
  })
  user_data_replace_on_change = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  dynamic "instance_market_options" {
    for_each = var.use_spot ? [1] : []
    content {
      market_type = "spot"
      spot_options {
        spot_instance_type             = "persistent"
        instance_interruption_behavior = "stop"
      }
    }
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_size
    encrypted   = true
  }

  tags = {
    Name = "${var.project_name}-worker-${count.index + 1}-${var.environment}"
    Role = "rke2-worker"
  }
}

resource "aws_lb_target_group_attachment" "api" {
  count            = var.master_count
  target_group_arn = var.api_target_group_arn
  target_id        = aws_instance.master[count.index].id
  port             = 6443
}

resource "aws_lb_target_group_attachment" "web_http_master" {
  count            = var.master_count
  target_group_arn = var.web_http_target_group_arn
  target_id        = aws_instance.master[count.index].id
  port             = var.http_node_port
}

resource "aws_lb_target_group_attachment" "web_http_worker" {
  count            = var.worker_count
  target_group_arn = var.web_http_target_group_arn
  target_id        = aws_instance.worker[count.index].id
  port             = var.http_node_port
}

resource "aws_lb_target_group_attachment" "web_https_master" {
  count            = var.master_count
  target_group_arn = var.web_https_target_group_arn
  target_id        = aws_instance.master[count.index].id
  port             = var.https_node_port
}

resource "aws_lb_target_group_attachment" "web_https_worker" {
  count            = var.worker_count
  target_group_arn = var.web_https_target_group_arn
  target_id        = aws_instance.worker[count.index].id
  port             = var.https_node_port
}
