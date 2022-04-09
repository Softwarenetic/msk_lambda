resource "aws_lambda_function" "msk_to_s3" {
  filename         = "msk_to_s3.zip"
  function_name    = "lambda-msk-test-terraform"
  role             = aws_iam_role.lambda.arn
  handler          = "msk_to_s3.lambda_handler"
  source_code_hash = data.archive_file.lambda.output_base64sha256
  runtime          = "python3.9"
  timeout          = 15

  environment {
    variables = {
      BUCKET = module.s3_bucket.bucket_id
    }
  }
}

data "archive_file" "lambda" {
  type        = "zip"
  output_path = "msk_to_s3.zip"
  source_file = "msk_to_s3.py"
}

resource "aws_lambda_event_source_mapping" "example" {
  event_source_arn  = module.kafka.cluster_arn
  function_name     = aws_lambda_function.msk_to_s3.arn
  topics            = ["Example"]
  starting_position = "TRIM_HORIZON"
}
