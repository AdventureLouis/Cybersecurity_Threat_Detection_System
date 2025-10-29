output "s3_raw_data_bucket" {
  description = "Name of the S3 bucket for raw data"
  value       = aws_s3_bucket.raw_data.id
}

output "s3_processed_data_bucket" {
  description = "Name of the S3 bucket for processed data"
  value       = aws_s3_bucket.processed_data.id
}

output "s3_model_artifacts_bucket" {
  description = "Name of the S3 bucket for model artifacts"
  value       = aws_s3_bucket.model_artifacts.id
}

output "s3_frontend_bucket" {
  description = "Name of the S3 bucket for frontend assets"
  value       = aws_s3_bucket.frontend_assets.id
}

output "frontend_website_url" {
  description = "URL of the frontend website"
  value       = "http://${aws_s3_bucket.frontend_assets.bucket}.s3-website-${var.region}.amazonaws.com"
}

output "sagemaker_notebook_instance_name" {
  description = "Name of the SageMaker notebook instance"
  value       = aws_sagemaker_notebook_instance.threat_detection.name
}

output "sagemaker_role_arn" {
  description = "ARN of the SageMaker execution role"
  value       = aws_iam_role.sagemaker_role.arn
}

output "sagemaker_notebook_url" {
  description = "URL of the SageMaker notebook instance"
  value       = "https://${aws_sagemaker_notebook_instance.threat_detection.name}.notebook.${var.region}.sagemaker.aws"
}

output "api_gateway_url" {
  description = "URL of the API Gateway"
  value       = "https://${aws_api_gateway_rest_api.threat_detection_api.id}.execute-api.${var.region}.amazonaws.com/prod"
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.predict.function_name
}

output "amplify_app_id" {
  description = "Amplify app ID"
  value       = aws_amplify_app.threat_detection_app.id
}

output "amplify_app_url" {
  description = "URL of the Amplify app"
  value       = "https://main.${aws_amplify_app.threat_detection_app.id}.amplifyapp.com"
}

output "amplify_console_url" {
  description = "Amplify console URL"
  value       = "https://console.aws.amazon.com/amplify/home#/${aws_amplify_app.threat_detection_app.id}"
}

output "cloudwatch_logs_url" {
  description = "URL of the CloudWatch logs"
  value       = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#logsV2:log-groups"
}

output "setup_instructions" {
  description = "Setup instructions for the threat detection system"
  value = <<-EOT
    
    🚀 Cybersecurity Threat Detection System Deployed Successfully!
    
    📋 Next Steps:
    
    1. Upload NSL-KDD Dataset:
       - Download NSL-KDD dataset from: https://www.kaggle.com/code/eneskosar19/intrusion-detection-system-nsl-kdd
       - Upload KDDTrain+.txt to: s3://${aws_s3_bucket.raw_data.id}/
       - Upload KDDTest+.txt to: s3://${aws_s3_bucket.raw_data.id}/
    
    2. Access SageMaker Notebook:
       - URL: https://${aws_sagemaker_notebook_instance.threat_detection.name}.notebook.${var.region}.sagemaker.aws
       - Upload notebooks from ./notebooks/ directory
       - Run data_preprocessing.ipynb first
       - Then run model_training.ipynb
    
    3. Update Frontend API URL:
       - Edit frontend/script.js
       - Replace API_ENDPOINT with: https://${aws_api_gateway_rest_api.threat_detection_api.id}.execute-api.${var.region}.amazonaws.com/prod/predict
       - Re-upload to S3 or access directly at: http://${aws_s3_bucket.frontend_assets.bucket}.s3-website-${var.region}.amazonaws.com
    
    4. Monitor System:
       - CloudWatch Logs: https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#logsV2:log-groups
       - Lambda Logs: /aws/lambda/${aws_lambda_function.predict.function_name}
       - SageMaker Logs: /aws/sagemaker/NotebookInstances/${aws_sagemaker_notebook_instance.threat_detection.name}
    
    🔐 Security Features:
    - IAM roles with minimal required permissions
    - S3 buckets with appropriate access controls
    - CloudWatch logging for all components
    - API Gateway with CORS enabled
    
    💡 Usage:
    - Access the web interface to analyze network traffic
    - Upload CSV files or enter features manually
    - Get real-time threat detection results
    - Export analysis reports
    
    EOT
}