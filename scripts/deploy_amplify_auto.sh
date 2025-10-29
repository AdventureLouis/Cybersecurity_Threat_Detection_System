#!/bin/bash

# Automated Amplify Deployment Script
set -e

echo "🚀 Automated Amplify Deployment"
echo "==============================="

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

# Get Amplify app ID from Terraform
print_status "Getting Amplify app ID..."
APP_ID=$(terraform output -raw amplify_app_id 2>/dev/null || echo "")

if [ -z "$APP_ID" ]; then
    echo "Error: Could not get Amplify app ID. Run terraform apply first."
    exit 1
fi

print_status "Amplify App ID: $APP_ID"

# Create deployment package
print_status "Creating deployment package..."
mkdir -p amplify_deploy

# Get API endpoint and inject into HTML
API_ENDPOINT=$(terraform output -raw api_gateway_url)/predict

# Process index.html with API endpoint
sed "s|\${api_endpoint}|$API_ENDPOINT|g" amplify_package/index.html > amplify_deploy/index.html

# Copy result.html
cp amplify_package/result.html amplify_deploy/result.html

# Create ZIP file
cd amplify_deploy
zip -r ../threat-detection-app.zip .
cd ..

print_success "Deployment package created!"

# Upload ZIP to S3 first
print_status "Uploading deployment package to S3..."
S3_BUCKET=$(terraform output -raw s3_model_artifacts_bucket)
S3_KEY="amplify-deployments/threat-detection-$(date +%s).zip"

aws s3 cp threat-detection-app.zip "s3://$S3_BUCKET/$S3_KEY"
S3_URL="s3://$S3_BUCKET/$S3_KEY"

# Deploy to Amplify from S3
print_status "Deploying to Amplify from S3..."
DEPLOYMENT_ID=$(aws amplify start-deployment \
    --app-id "$APP_ID" \
    --branch-name main \
    --source-url "$S3_URL" \
    --query 'jobSummary.jobId' \
    --output text)

print_status "Deployment started with ID: $DEPLOYMENT_ID"

# Wait for deployment to complete
print_status "Waiting for deployment to complete..."
while true; do
    STATUS=$(aws amplify get-job \
        --app-id "$APP_ID" \
        --branch-name main \
        --job-id "$DEPLOYMENT_ID" \
        --query 'job.summary.status' \
        --output text)
    
    case $STATUS in
        "SUCCEED")
            print_success "Deployment completed successfully!"
            break
            ;;
        "FAILED")
            echo "Deployment failed!"
            exit 1
            ;;
        *)
            echo "Status: $STATUS - waiting..."
            sleep 10
            ;;
    esac
done

# Get final URL
AMPLIFY_URL="https://main.$APP_ID.amplifyapp.com"
# Cleanup S3 deployment file
aws s3 rm "$S3_URL" || true

print_success "Threat Detection System deployed!"
echo ""
echo "🌐 Access your application at: $AMPLIFY_URL"
echo ""