#!/bin/bash

# Force cleanup - No confirmation required
# Automatically destroys ALL threat detection resources

set -e

echo "🧹 Force Cleanup - Destroying ALL Threat Detection Resources"
echo "============================================================"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

# Force cleanup all resources
force_cleanup() {
    # Run pre-destroy cleanup first
    if [ -f "scripts/pre_destroy.sh" ]; then
        print_status "Running pre-destroy cleanup..."
        ./scripts/pre_destroy.sh
    fi
    
    print_status "🗑️ Force deleting ALL threat detection resources..."
    
    # S3 Buckets
    aws s3 ls | grep -E "(cybersec|threat)" | awk '{print $3}' | while read bucket; do
        if [ -n "$bucket" ]; then
            print_status "Deleting S3 bucket: $bucket"
            aws s3 rm "s3://$bucket" --recursive --quiet 2>/dev/null || true
            aws s3api delete-bucket --bucket "$bucket" 2>/dev/null || true
        fi
    done
    
    # SageMaker Endpoints
    aws sagemaker list-endpoints --name-contains "threat" --query 'Endpoints[].EndpointName' --output text | tr '\t' '\n' | while read endpoint; do
        [ -n "$endpoint" ] && aws sagemaker delete-endpoint --endpoint-name "$endpoint" 2>/dev/null || true
    done
    
    # Lambda Functions
    aws lambda list-functions --query 'Functions[?contains(FunctionName, `threat`)].FunctionName' --output text | tr '\t' '\n' | while read func; do
        [ -n "$func" ] && aws lambda delete-function --function-name "$func" 2>/dev/null || true
    done
    
    # API Gateways
    aws apigateway get-rest-apis --query 'items[?contains(name, `threat`)].id' --output text | tr '\t' '\n' | while read api; do
        [ -n "$api" ] && aws apigateway delete-rest-api --rest-api-id "$api" 2>/dev/null || true
    done
    
    # Amplify Apps
    aws amplify list-apps --query 'apps[?contains(name, `threat`)].appId' --output text | tr '\t' '\n' | while read app; do
        [ -n "$app" ] && aws amplify delete-app --app-id "$app" 2>/dev/null || true
    done
    
    # Terraform destroy
    if [ -f "terraform.tfstate" ] || [ -f ".terraform/terraform.tfstate" ]; then
        terraform destroy -auto-approve 2>/dev/null || true
    fi
    
    # Clean local files
    rm -rf .terraform* terraform.tfstate* tfplan *.zip *.bak 2>/dev/null || true
    
    print_success "✅ Force cleanup completed!"
}

# Run cleanup
force_cleanup