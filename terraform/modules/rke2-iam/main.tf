data "aws_iam_policy_document" "assume_ec2" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${var.project_name}-rke2-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.assume_ec2.json
}

# Private nodes have no SSH: SSM Session Manager is the only shell.
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_iam_instance_profile" "this" {
  name = "${var.project_name}-rke2-${var.environment}"
  role = aws_iam_role.this.name
}
