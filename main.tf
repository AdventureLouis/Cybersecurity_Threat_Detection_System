# Random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# S3 Buckets
resource "aws_s3_bucket" "raw_data" {
  bucket        = "cybersec-raw-data-${random_string.suffix.result}"
  force_destroy = true
}

resource "aws_s3_bucket" "processed_data" {
  bucket        = "cybersec-processed-data-${random_string.suffix.result}"
  force_destroy = true
}

resource "aws_s3_bucket" "model_artifacts" {
  bucket        = "cybersec-model-artifacts-${random_string.suffix.result}"
  force_destroy = true
}

# S3 bucket policy for Amplify access
resource "aws_s3_bucket_policy" "model_artifacts_amplify" {
  bucket = aws_s3_bucket.model_artifacts.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "amplify.amazonaws.com"
        }
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion"
        ]
        Resource = "${aws_s3_bucket.model_artifacts.arn}/*"
      },
      {
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.amplify_role.arn
        }
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion"
        ]
        Resource = "${aws_s3_bucket.model_artifacts.arn}/*"
      }
    ]
  })
}

resource "aws_s3_bucket" "frontend_assets" {
  bucket        = "cybersec-frontend-${random_string.suffix.result}"
  force_destroy = true
}

# S3 Bucket versioning
resource "aws_s3_bucket_versioning" "raw_data" {
  bucket = aws_s3_bucket.raw_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "processed_data" {
  bucket = aws_s3_bucket.processed_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket public access block
resource "aws_s3_bucket_public_access_block" "raw_data" {
  bucket = aws_s3_bucket.raw_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "processed_data" {
  bucket = aws_s3_bucket.processed_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Frontend bucket for static website
resource "aws_s3_bucket_website_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend_assets.id

  index_document {
    suffix = "index.html"
  }
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend_assets.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "frontend" {
  depends_on = [aws_s3_bucket_public_access_block.frontend]
  
  bucket = aws_s3_bucket.frontend_assets.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.frontend_assets.arn}/*"
      },
    ]
  })
}

# IAM Role for SageMaker
resource "aws_iam_role" "sagemaker_role" {
  name = "SageMakerThreatDetectionRole-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "sagemaker.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "sagemaker_execution" {
  role       = aws_iam_role.sagemaker_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
}

resource "aws_iam_role_policy" "sagemaker_s3_access" {
  name = "SageMakerS3Access"
  role = aws_iam_role.sagemaker_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.raw_data.arn,
          "${aws_s3_bucket.raw_data.arn}/*",
          aws_s3_bucket.processed_data.arn,
          "${aws_s3_bucket.processed_data.arn}/*",
          aws_s3_bucket.model_artifacts.arn,
          "${aws_s3_bucket.model_artifacts.arn}/*"
        ]
      }
    ]
  })
}

# SageMaker Notebook Instance
resource "aws_sagemaker_notebook_instance" "threat_detection" {
  name          = "Threat-detection-${random_string.suffix.result}"
  role_arn      = aws_iam_role.sagemaker_role.arn
  instance_type = "ml.t3.medium"

  tags = {
    Name = "ThreatDetectionNotebook"
  }
}

# Lambda function for API
resource "aws_iam_role" "lambda_role" {
  name = "ThreatDetectionLambdaRole-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_sagemaker" {
  name = "LambdaSageMakerAccess"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sagemaker:InvokeEndpoint"
        ]
        Resource = "*"
      }
    ]
  })
}

# Lambda function
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/predict.py"
  output_path = "${path.module}/lambda/predict.zip"
}

resource "aws_lambda_function" "predict" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "threat-detection-predict-${random_string.suffix.result}"
  role            = aws_iam_role.lambda_role.arn
  handler         = "predict.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime         = "python3.9"
  timeout         = 30

  environment {
    variables = {
      ENDPOINT_NAME = "threat-detection-endpoint"
    }
  }
}



# CloudWatch Log Groups (created automatically by Lambda)
# resource "aws_cloudwatch_log_group" "lambda_logs" {
#   name              = "/aws/lambda/${aws_lambda_function.predict.function_name}"
#   retention_in_days = 14
# }

resource "aws_cloudwatch_log_group" "sagemaker_logs" {
  name              = "/aws/sagemaker/NotebookInstances/${aws_sagemaker_notebook_instance.threat_detection.name}"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  name              = "API-Gateway-Execution-Logs_${aws_api_gateway_rest_api.threat_detection_api.id}/prod"
  retention_in_days = 14
}

# Frontend files are handled by Amplify deployment
# No need to upload to S3 separately