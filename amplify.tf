# Local files for Amplify deployment
resource "local_file" "amplify_index" {
  content = file("${path.module}/amplify_package/index.html")
  filename = "${path.module}/amplify_deploy/index.html"
}

resource "local_file" "amplify_result" {
  content  = file("${path.module}/amplify_package/result.html")
  filename = "${path.module}/amplify_deploy/result.html"
}

# Create zip file for Amplify deployment
data "archive_file" "amplify_zip" {
  type        = "zip"
  source_dir  = "${path.module}/amplify_deploy"
  output_path = "${path.module}/threat-detection-app.zip"
  
  depends_on = [
    local_file.amplify_index,
    local_file.amplify_result
  ]
}

# AWS Amplify App
resource "aws_amplify_app" "threat_detection_app" {
  name        = "threat-detection-${random_string.suffix.result}"
  description = "AI-Powered Threat Detection System"
  
  platform = "WEB"
  iam_service_role_arn = aws_iam_role.amplify_role.arn
  
  # Custom rules for SPA routing
  custom_rule {
    source = "/<*>"
    status = "404"
    target = "/index.html"
  }

  tags = {
    Name        = "ThreatDetectionApp"
    Environment = "Production"
  }
}

# Amplify branch for deployment
resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.threat_detection_app.id
  branch_name = "main"
  
  framework = "Web"
  stage     = "PRODUCTION"
}

# Deployment handled by separate script after Terraform completes

# IAM Role for Amplify
resource "aws_iam_role" "amplify_role" {
  name = "AmplifyRole-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "amplify.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy for Amplify
resource "aws_iam_role_policy" "amplify_policy" {
  name = "AmplifyPolicy-${random_string.suffix.result}"
  role = aws_iam_role.amplify_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "s3:GetObject",
          "s3:GetObjectVersion"
        ]
        Resource = [
          "arn:aws:logs:*:*:*",
          "${aws_s3_bucket.model_artifacts.arn}/*"
        ]
      }
    ]
  })
}

