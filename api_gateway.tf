# API Gateway for Threat Detection
resource "aws_api_gateway_rest_api" "threat_detection_api" {
  name        = "threat-detection-api-${random_string.suffix.result}"
  description = "API for Threat Detection ML predictions"
  
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# API Gateway Resource
resource "aws_api_gateway_resource" "predict_resource" {
  rest_api_id = aws_api_gateway_rest_api.threat_detection_api.id
  parent_id   = aws_api_gateway_rest_api.threat_detection_api.root_resource_id
  path_part   = "predict"
}

# POST Method
resource "aws_api_gateway_method" "predict_post" {
  rest_api_id   = aws_api_gateway_rest_api.threat_detection_api.id
  resource_id   = aws_api_gateway_resource.predict_resource.id
  http_method   = "POST"
  authorization = "NONE"
}

# OPTIONS Method for CORS
resource "aws_api_gateway_method" "predict_options" {
  rest_api_id   = aws_api_gateway_rest_api.threat_detection_api.id
  resource_id   = aws_api_gateway_resource.predict_resource.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

# Lambda Integration for POST
resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id = aws_api_gateway_rest_api.threat_detection_api.id
  resource_id = aws_api_gateway_resource.predict_resource.id
  http_method = aws_api_gateway_method.predict_post.http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.predict.invoke_arn
}

# CORS Integration for OPTIONS
resource "aws_api_gateway_integration" "cors_integration" {
  rest_api_id = aws_api_gateway_rest_api.threat_detection_api.id
  resource_id = aws_api_gateway_resource.predict_resource.id
  http_method = aws_api_gateway_method.predict_options.http_method

  type = "MOCK"
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

# Method Response for POST
resource "aws_api_gateway_method_response" "predict_post_response" {
  rest_api_id = aws_api_gateway_rest_api.threat_detection_api.id
  resource_id = aws_api_gateway_resource.predict_resource.id
  http_method = aws_api_gateway_method.predict_post.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = true
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
  }
}

# Method Response for OPTIONS (CORS)
resource "aws_api_gateway_method_response" "predict_options_response" {
  rest_api_id = aws_api_gateway_rest_api.threat_detection_api.id
  resource_id = aws_api_gateway_resource.predict_resource.id
  http_method = aws_api_gateway_method.predict_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = true
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
  }
}

# Integration Response for POST
resource "aws_api_gateway_integration_response" "predict_post_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.threat_detection_api.id
  resource_id = aws_api_gateway_resource.predict_resource.id
  http_method = aws_api_gateway_method.predict_post.http_method
  status_code = aws_api_gateway_method_response.predict_post_response.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'"
  }

  depends_on = [aws_api_gateway_integration.lambda_integration]
}

# Integration Response for OPTIONS (CORS)
resource "aws_api_gateway_integration_response" "predict_options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.threat_detection_api.id
  resource_id = aws_api_gateway_resource.predict_resource.id
  http_method = aws_api_gateway_method.predict_options.http_method
  status_code = aws_api_gateway_method_response.predict_options_response.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'"
  }

  depends_on = [aws_api_gateway_integration.cors_integration]
}

# API Gateway Deployment
resource "aws_api_gateway_deployment" "threat_detection_deployment" {
  rest_api_id = aws_api_gateway_rest_api.threat_detection_api.id

  depends_on = [
    aws_api_gateway_method.predict_post,
    aws_api_gateway_method.predict_options,
    aws_api_gateway_integration.lambda_integration,
    aws_api_gateway_integration.cors_integration,
    aws_api_gateway_integration_response.predict_post_integration_response,
    aws_api_gateway_integration_response.predict_options_integration_response
  ]
}

# API Gateway Stage
resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.threat_detection_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.threat_detection_api.id
  stage_name    = "prod"
}

# Lambda Permission for API Gateway
resource "aws_lambda_permission" "api_gateway_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.predict.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.threat_detection_api.execution_arn}/*/*"
}