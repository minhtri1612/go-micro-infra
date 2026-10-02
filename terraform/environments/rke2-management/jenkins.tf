# Jenkins is a private VM (docker.sock). Not a pod: RKE2 runs containerd.
# UI and SSH only from the management VPC and the OpenVPN pool.
# IAM name is prefixed rke2- so it does not clash with leftover IAM names.

data "aws_iam_policy_document" "jenkins_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# Recreated here after environments/management was destroyed.
resource "aws_secretsmanager_secret" "jenkins_runtime" {
  name                    = var.jenkins_runtime_secret_name
  description             = "Jenkins compose/CasC runtime. Seed JSON in the AWS console."
  recovery_window_in_days = 0
}

resource "aws_iam_role" "jenkins" {
  name               = "${var.project_name}-rke2-jenkins"
  assume_role_policy = data.aws_iam_policy_document.jenkins_assume.json
}

resource "aws_iam_role_policy_attachment" "jenkins_ssm" {
  role       = aws_iam_role.jenkins.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "jenkins_runtime" {
  name = "${var.project_name}-rke2-jenkins-runtime"
  role = aws_iam_role.jenkins.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadJenkinsRuntimeSecret"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [aws_secretsmanager_secret.jenkins_runtime.arn]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "jenkins" {
  name = "${var.project_name}-rke2-jenkins"
  role = aws_iam_role.jenkins.name
}

module "jenkins" {
  source = "../../modules/ubuntu-host"

  name                        = "rke2-jenkins"
  project_name                = var.project_name
  instance_type               = var.jenkins_instance_type
  ami_arch                    = "amd64"
  use_spot                    = false
  subnet_id                   = module.network.private_subnet_ids[0]
  vpc_id                      = module.network.vpc_id
  iam_instance_profile        = aws_iam_instance_profile.jenkins.name
  key_name                    = module.keys.key_name
  associate_public_ip_address = false
  allocate_eip                = false
  ingress_cidrs               = [var.vpc_cidr, "10.8.0.0/24"]
  allowed_tcp_ports           = [22, 8080]
  root_volume_size            = 30
  user_data                   = file("${path.module}/cloud-init-jenkins.sh")
}
