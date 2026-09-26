data "aws_caller_identity" "ci" {}

locals {
  tf_state_bucket = "${var.project_name}-tfstate-${data.aws_caller_identity.ci.account_id}"
  tf_state_lock_resources = [
    "arn:aws:s3:::${local.tf_state_bucket}/management/terraform.tfstate",
    "arn:aws:s3:::${local.tf_state_bucket}/management/terraform.tfstate.tflock",
  ]
}

data "aws_iam_policy_document" "tf_state_lock" {
  statement {
    sid       = "ListStateBucket"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${local.tf_state_bucket}"]
  }

  statement {
    sid       = "StateAndLockfile"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = local.tf_state_lock_resources
  }
}

resource "aws_iam_user" "tf_plan" {
  name = "${var.project_name}-tf-plan"
}

resource "aws_iam_user" "tf_apply" {
  name = "${var.project_name}-tf-apply"
}

resource "aws_iam_user_policy_attachment" "tf_plan_readonly" {
  user       = aws_iam_user.tf_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_user_policy" "tf_plan_lock" {
  name   = "${var.project_name}-tf-plan-state-lock"
  user   = aws_iam_user.tf_plan.name
  policy = data.aws_iam_policy_document.tf_state_lock.json
}

resource "aws_iam_user_policy_attachment" "tf_apply_poweruser" {
  user       = aws_iam_user.tf_apply.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

resource "aws_iam_user_policy_attachment" "tf_apply_iam" {
  user       = aws_iam_user.tf_apply.name
  policy_arn = "arn:aws:iam::aws:policy/IAMFullAccess"
}

resource "aws_iam_user_policy" "tf_apply_lock" {
  name   = "${var.project_name}-tf-apply-state-lock"
  user   = aws_iam_user.tf_apply.name
  policy = data.aws_iam_policy_document.tf_state_lock.json
}

resource "aws_iam_access_key" "tf_plan" {
  user = aws_iam_user.tf_plan.name
}

resource "aws_iam_access_key" "tf_apply" {
  user = aws_iam_user.tf_apply.name
}
