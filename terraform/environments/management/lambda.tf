data "archive_file" "hello" {
  type        = "zip"
  source_file = "${path.module}/lambda/hello/index.js"
  output_path = "${path.module}/lambda/hello.zip"
}

data "aws_iam_policy_document" "hello_lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "hello_lambda" {
  name               = "${var.project_name}-hello-lambda"
  assume_role_policy = data.aws_iam_policy_document.hello_lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "hello_lambda_logs" {
  role       = aws_iam_role.hello_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "hello" {
  function_name    = "${var.project_name}-hello"
  filename         = data.archive_file.hello.output_path
  source_code_hash = data.archive_file.hello.output_base64sha256
  role             = aws_iam_role.hello_lambda.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  architectures    = ["arm64"]
  memory_size      = 128
  timeout          = 10
}

data "archive_file" "hello_java" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/hello_java"
  output_path = "${path.module}/lambda/hello-java.zip"
  excludes    = ["**/*.java"]
}

resource "aws_lambda_function" "hello_java" {
  function_name    = "${var.project_name}-hello-java"
  filename         = data.archive_file.hello_java.output_path
  source_code_hash = data.archive_file.hello_java.output_base64sha256
  role             = aws_iam_role.hello_lambda.arn
  handler          = "example.Handler::handleRequest"
  runtime          = "java21"
  architectures    = ["arm64"]
  memory_size      = 256
  timeout          = 10
}
