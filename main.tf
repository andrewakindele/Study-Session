data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "lambda_s3" {
  statement {

    sid     = "S3FullAccess"
    effect  = "Allow"
    actions = ["s3:*"]

    resources = ["*"]
  }
}

data "archive_file" "lambda_zip_file" {
  type        = "zip"
  source_file = "index.py"
  output_path = "index.zip"
}

resource "aws_s3_bucket" "gets3apilambda" {
  bucket = "gets3apilambda-terraform"
  
  tags = {
    Name        = "terraform project"
    Environment = "Dev"
  }
}

resource "aws_iam_role" "iam_role_lambda" {
  name               = "lambda-api-s3-role-terraform"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_policy" "lambda_policy_s3" {
  name        = "lambda-api-s3-policy-terraform"
  description = "Contains S3 full access permission for lambda"
  policy      = data.aws_iam_policy_document.lambda_s3.json
}

resource "aws_iam_role_policy_attachment" "lambda_exec_role_attachment" {
  policy_arn = aws_iam_policy.lambda_policy_s3.arn
  role       = aws_iam_role.iam_role_lambda.name
}

resource "aws_lambda_function" "lambda_function" {
  filename         = "index.zip"
  function_name    = "gets3-api-terraform"
  role             = aws_iam_role.iam_role_lambda.arn
  handler          = "index.lambda_handler"
  runtime          = "python3.12"
  timeout          = 120
  source_code_hash = data.archive_file.lambda_zip_file.output_base64sha256
}

resource "aws_api_gateway_rest_api" "rest_api" {
  name = "lamda-restapi-terraform"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "rest_api_resource" {
  parent_id   = aws_api_gateway_rest_api.rest_api.root_resource_id
  rest_api_id = aws_api_gateway_rest_api.rest_api.id
  path_part   = "demo-path"
}

resource "aws_api_gateway_method" "rest_api_method" {
  authorization = "NONE"
  http_method   = "GET"
  rest_api_id   = aws_api_gateway_rest_api.rest_api.id
  resource_id   = aws_api_gateway_resource.rest_api_resource.id
}

resource "aws_api_gateway_integration" "lambda_integration" {
  http_method             = aws_api_gateway_method.rest_api_method.http_method
  rest_api_id             = aws_api_gateway_rest_api.rest_api.id
  resource_id             = aws_api_gateway_resource.rest_api_resource.id
  type                    = "AWS_PROXY"
  integration_http_method = "GET"
  uri                     = aws_lambda_function.lambda_function.invoke_arn
}

resource "aws_api_gateway_deployment" "api-deployment" {
  rest_api_id = aws_api_gateway_rest_api.rest_api.id
  stage_name  = "dev-terraform"

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.rest_api_resource.id,
      aws_api_gateway_method.rest_api_method.id,
      aws_api_gateway_integration.lambda_integration.id
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lambda_permission" "lambda-api-permission-terraform" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_function.function_name
  principal     = "apigateway.amazonaws.com"
  statement_id  = "AllowExecutionFromAPIGateway"
  source_arn    = "${aws_api_gateway_rest_api.rest_api.execution_arn}/*/*/*"
}

output "invoke_url" {
  value = aws_api_gateway_deployment.api-deployment.invoke_url
}
