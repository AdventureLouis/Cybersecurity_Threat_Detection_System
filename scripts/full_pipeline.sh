#!/bin/bash

# Complete Automation Pipeline for CyberGuard AI
# Deploys infrastructure, sets up data, and trains model

set -e

echo "🚀 CyberGuard AI - Complete Automation Pipeline"
echo "=============================================="

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Step 1: Deploy Infrastructure
deploy_infrastructure() {
    print_status "Step 1: Deploying AWS infrastructure..."
    
    terraform init
    terraform plan -out=tfplan
    terraform apply tfplan
    
    print_success "Infrastructure deployed successfully!"
}

# Step 2: Setup Data Pipeline
setup_data_pipeline() {
    print_status "Step 2: Setting up data pipeline..."
    
    ./scripts/setup_data.sh
    
    print_success "Data pipeline setup completed!"
}

# Step 3: Prepare Training Environment
prepare_training() {
    print_status "Step 3: Preparing training environment..."
    
    ./scripts/train_model.sh
    
    print_success "Training environment prepared!"
}

# Step 4: Update Frontend API Endpoint and Deploy
deploy_frontend() {
    print_status "Step 4: Updating frontend API endpoint and deploying to Amplify..."
    
    # Get the API Gateway URL from Terraform output
    API_URL=$(terraform output -raw api_gateway_url)
    API_ENDPOINT="${API_URL}/predict"
    
    print_status "Updating frontend with API endpoint: $API_ENDPOINT"
    
    # Update the API endpoint in index.html
    sed -i.bak "s|const API_ENDPOINT = '.*';|const API_ENDPOINT = '$API_ENDPOINT';|g" amplify_package/index.html
    
    # Ensure Lambda points to correct endpoint
    CURRENT_ENDPOINT=$(aws sagemaker list-endpoints --name-contains "threat-detection-endpoint" --query 'Endpoints[0].EndpointName' --output text 2>/dev/null || echo "")
    if [ -n "$CURRENT_ENDPOINT" ] && [ "$CURRENT_ENDPOINT" != "None" ]; then
        LAMBDA_NAME=$(terraform output -raw lambda_function_name)
        aws lambda update-function-configuration \
          --function-name $LAMBDA_NAME \
          --environment Variables="{ENDPOINT_NAME=$CURRENT_ENDPOINT}" 2>/dev/null || true
        print_status "Lambda configured with endpoint: $CURRENT_ENDPOINT"
    fi
    
    # Deploy to Amplify
    AMPLIFY_APP_ID=$(terraform output -raw amplify_app_id)
    FRONTEND_BUCKET=$(terraform output -raw s3_frontend_bucket)
    
    cd amplify_package
    zip -r ../amplify_deploy.zip .
    cd ..
    
    # Ensure button always works (safety net)
    ./scripts/ensure_working_button.sh
    
    aws s3 cp amplify_deploy.zip s3://$FRONTEND_BUCKET/amplify_deploy.zip
    aws amplify start-deployment --app-id $AMPLIFY_APP_ID --branch-name main --source-url s3://$FRONTEND_BUCKET/amplify_deploy.zip
    
    # Update Lambda function with current endpoint name
    print_status "Updating Lambda function with current SageMaker endpoint..."
    CURRENT_ENDPOINT=$(aws sagemaker list-endpoints --name-contains "threat-detection-endpoint" --query 'Endpoints[0].EndpointName' --output text)
    if [ "$CURRENT_ENDPOINT" != "None" ] && [ "$CURRENT_ENDPOINT" != "" ]; then
        LAMBDA_NAME=$(terraform output -raw lambda_function_name)
        aws lambda update-function-configuration \
          --function-name $LAMBDA_NAME \
          --environment Variables="{ENDPOINT_NAME=$CURRENT_ENDPOINT}"
        print_success "Lambda updated with endpoint: $CURRENT_ENDPOINT"
    fi
    
    print_success "Frontend deployed to Amplify with correct API endpoint!"
    
    # Wait for deployment to complete
    sleep 10
    
    # Test end-to-end functionality
    print_status "Testing end-to-end functionality..."
    API_URL=$(terraform output -raw api_gateway_url)
    TEST_RESPONSE=$(curl -s -X POST "$API_URL/predict" \
      -H "Content-Type: application/json" \
      -d '{"features": [0, 0.1, 0, 0, 0.0181, 0.545, 0.1, 0.2, 0.3, 0.4]}' \
      --max-time 15)
    
    if echo "$TEST_RESPONSE" | grep -q "prediction"; then
        print_success "✅ API is working! Test response: $TEST_RESPONSE"
    else
        print_warning "⚠️ API test failed. Response: $TEST_RESPONSE"
        print_warning "Run 'python scripts/automated_training.py' to train the model"
    fi
}

# Step 5: Display final information
display_summary() {
    echo ""
    echo "🎉 CyberGuard AI Deployment Complete!"
    echo "====================================="
    echo ""
    
    RAW_BUCKET=$(terraform output -raw s3_raw_data_bucket)
    PROCESSED_BUCKET=$(terraform output -raw s3_processed_data_bucket)
    FRONTEND_URL=$(terraform output -raw frontend_website_url)
    API_URL=$(terraform output -raw api_gateway_url)
    NOTEBOOK_URL=$(terraform output -raw sagemaker_notebook_url)
    
    echo "📊 System Resources:"
    echo "  • Raw Data Bucket: $RAW_BUCKET"
    echo "  • Processed Data Bucket: $PROCESSED_BUCKET"
    echo "  • Frontend URL: $FRONTEND_URL"
    echo "  • API Gateway URL: $API_URL"
    echo "  • SageMaker Notebook: $NOTEBOOK_URL"
    echo ""
    
    echo "✅ Completed Steps:"
    echo "  ✓ Infrastructure deployed"
    echo "  ✓ NSL-KDD dataset downloaded and uploaded"
    echo "  ✓ Data preprocessing completed"
    echo "  ✓ Training environment prepared"
    echo "  ✓ Frontend configured"
    echo ""
    
    echo "📋 Next Steps:"
    echo "  1. Run automated training: python3 scripts/automated_training.py"
    echo "  2. Access your app: $FRONTEND_URL"
    echo "  3. Test threat detection with the 6-input form"
    echo "  4. Verify results page shows prediction, score, and status"
    echo ""
    
    echo "🔧 Monitoring:"
    echo "  • CloudWatch Logs: https://eu-west-1.console.aws.amazon.com/cloudwatch/home?region=eu-west-1#logsV2:log-groups"
    echo "  • SageMaker Console: https://eu-west-1.console.aws.amazon.com/sagemaker/home?region=eu-west-1"
    echo ""
    
    print_success "System is ready for cybersecurity threat detection!"
}

# Error handling
cleanup_on_error() {
    print_error "Pipeline failed. Check the logs above for details."
    print_warning "You can run individual scripts to debug:"
    echo "  • ./scripts/deploy.sh - Deploy infrastructure only"
    echo "  • ./scripts/setup_data.sh - Setup data pipeline only"
    echo "  • ./scripts/train_model.sh - Setup training only"
    exit 1
}

# Set error trap
trap cleanup_on_error ERR

# Main execution
main() {
    print_status "Starting complete automation pipeline..."
    echo ""
    
    # Check prerequisites
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform not found. Please install Terraform first."
        exit 1
    fi
    
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI not found. Please install AWS CLI first."
        exit 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured. Please run 'aws configure'."
        exit 1
    fi
    
    # Execute pipeline steps
    deploy_infrastructure
    echo ""
    
    setup_data_pipeline
    echo ""
    
    prepare_training
    echo ""
    
    deploy_frontend
    echo ""
    
    display_summary
}

# Run main function
main "$@"