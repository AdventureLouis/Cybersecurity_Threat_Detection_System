#!/bin/bash

# CyberGuard AI Cleanup Script
# This script destroys all AWS resources created by the threat detection system

set -e

echo "🧹 CyberGuard AI - Cleanup Script"
echo "================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Warning message
show_warning() {
    echo ""
    print_warning "⚠️  WARNING: This will destroy ALL resources created by the threat detection system!"
    print_warning "This action cannot be undone and will result in data loss."
    echo ""
    echo "Resources that will be destroyed:"
    echo "  • SageMaker notebook instance and endpoints"
    echo "  • S3 buckets and ALL files (including versions and delete markers)"
    echo "  • Lambda functions"
    echo "  • API Gateway"
    echo "  • CloudWatch logs and dashboards"
    echo "  • IAM roles and policies"
    echo ""
}

# Empty S3 buckets before destruction
empty_s3_buckets() {
    print_status "Emptying S3 buckets..."
    
    # Get bucket names from Terraform state
    RAW_BUCKET=$(terraform output -raw s3_raw_data_bucket 2>/dev/null || echo "")
    PROCESSED_BUCKET=$(terraform output -raw s3_processed_data_bucket 2>/dev/null || echo "")
    MODEL_BUCKET=$(terraform output -raw s3_model_artifacts_bucket 2>/dev/null || echo "")
    FRONTEND_BUCKET=$(terraform output -raw s3_frontend_bucket 2>/dev/null || echo "")
    
    # Function to completely empty a bucket
    empty_bucket() {
        local bucket_name="$1"
        if [ -z "$bucket_name" ]; then
            return
        fi
        
        # Check if bucket exists
        if ! aws s3 ls "s3://$bucket_name" &>/dev/null; then
            print_warning "Bucket $bucket_name not found or not accessible"
            return
        fi
        
        print_status "Emptying bucket: $bucket_name"
        
        # Delete all objects (including versions if versioning is enabled)
        aws s3api list-object-versions --bucket "$bucket_name" --query 'Versions[].{Key:Key,VersionId:VersionId}' --output text 2>/dev/null | while read -r key version_id; do
            if [ -n "$key" ] && [ -n "$version_id" ] && [ "$version_id" != "null" ]; then
                aws s3api delete-object --bucket "$bucket_name" --key "$key" --version-id "$version_id" &>/dev/null
            fi
        done
        
        # Delete all delete markers
        aws s3api list-object-versions --bucket "$bucket_name" --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' --output text 2>/dev/null | while read -r key version_id; do
            if [ -n "$key" ] && [ -n "$version_id" ]; then
                aws s3api delete-object --bucket "$bucket_name" --key "$key" --version-id "$version_id" &>/dev/null
            fi
        done
        
        # Final cleanup with recursive delete
        aws s3 rm "s3://$bucket_name" --recursive &>/dev/null || true
        
        print_success "Bucket $bucket_name emptied"
    }
    
    # Empty each bucket
    empty_bucket "$RAW_BUCKET"
    empty_bucket "$PROCESSED_BUCKET"
    empty_bucket "$MODEL_BUCKET"
    empty_bucket "$FRONTEND_BUCKET"
    
    # Fallback: Find and empty any remaining threat-detection buckets
    print_status "Checking for any remaining threat-detection buckets..."
    REMAINING_BUCKETS=$(aws s3api list-buckets --query 'Buckets[?contains(Name, `threat-detection`)].Name' --output text 2>/dev/null || echo "")
    
    for bucket in $REMAINING_BUCKETS; do
        if [ -n "$bucket" ]; then
            print_warning "Found additional bucket: $bucket"
            empty_bucket "$bucket"
        fi
    done
    
    print_success "All S3 buckets emptied successfully!"
}

# Stop SageMaker notebook instance
stop_sagemaker() {
    print_status "Stopping SageMaker notebook instance..."
    
    NOTEBOOK_NAME=$(terraform output -raw sagemaker_notebook_instance_name 2>/dev/null || echo "")
    
    if [ -n "$NOTEBOOK_NAME" ]; then
        # Check if notebook exists and is running
        STATUS=$(aws sagemaker describe-notebook-instance --notebook-instance-name "$NOTEBOOK_NAME" --query 'NotebookInstanceStatus' --output text 2>/dev/null || echo "NotFound")
        
        if [ "$STATUS" = "InService" ]; then
            print_status "Stopping notebook instance: $NOTEBOOK_NAME"
            aws sagemaker stop-notebook-instance --notebook-instance-name "$NOTEBOOK_NAME"
            
            # Wait for it to stop
            print_status "Waiting for notebook to stop..."
            aws sagemaker wait notebook-instance-stopped --notebook-instance-name "$NOTEBOOK_NAME"
        fi
    fi
    
    print_success "SageMaker notebook stopped!"
}

# Delete SageMaker endpoints
delete_endpoints() {
    print_status "Deleting SageMaker endpoints..."
    
    # List and delete any endpoints with our naming pattern
    ENDPOINTS=$(aws sagemaker list-endpoints --name-contains "threat-detection" --query 'Endpoints[].EndpointName' --output text 2>/dev/null || echo "")
    
    for endpoint in $ENDPOINTS; do
        if [ -n "$endpoint" ]; then
            print_status "Deleting endpoint: $endpoint"
            aws sagemaker delete-endpoint --endpoint-name "$endpoint"
        fi
    done
    
    print_success "SageMaker endpoints deleted!"
}

# Delete Amplify apps
delete_amplify_apps() {
    print_status "Deleting Amplify apps..."
    
    # List all Amplify apps with threat-detection in the name
    AMPLIFY_APPS=$(aws amplify list-apps --query 'apps[?contains(name, `threat-detection`)].appId' --output text 2>/dev/null || echo "")
    
    for app_id in $AMPLIFY_APPS; do
        if [ -n "$app_id" ]; then
            print_status "Deleting Amplify app: $app_id"
            aws amplify delete-app --app-id "$app_id" 2>/dev/null || print_warning "Failed to delete app $app_id"
        fi
    done
    
    # Also check for apps that might not have been caught by the name filter
    print_status "Checking for any remaining Amplify apps..."
    ALL_APPS=$(aws amplify list-apps --query 'apps[].{id:appId,name:name}' --output text 2>/dev/null || echo "")
    
    while IFS=$'\t' read -r app_id app_name; do
        if [[ "$app_name" == *"threat"* ]] || [[ "$app_name" == *"detection"* ]] || [[ "$app_name" == *"cyber"* ]]; then
            print_warning "Found potential related app: $app_name ($app_id)"
            read -p "Delete this app? (y/n): " -r
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                aws amplify delete-app --app-id "$app_id" 2>/dev/null || print_warning "Failed to delete app $app_id"
            fi
        fi
    done <<< "$ALL_APPS"
    
    print_success "Amplify apps cleanup completed!"
}

# Terraform destroy
terraform_destroy() {
    print_status "Running Terraform destroy..."
    
    # Check if Terraform state exists
    if [ ! -f "terraform.tfstate" ] && [ ! -f ".terraform/terraform.tfstate" ]; then
        print_warning "No Terraform state found. Resources may need manual cleanup."
        return
    fi
    
    terraform destroy -auto-approve
    print_success "Terraform resources destroyed!"
}

# Clean up local files
cleanup_local() {
    print_status "Cleaning up local files..."
    
    # Remove Terraform files
    rm -f terraform.tfstate*
    rm -f tfplan
    rm -f .terraform.lock.hcl
    rm -rf .terraform/
    
    # Remove backup files
    rm -f frontend/script.js.bak
    rm -f lambda/predict.zip
    
    print_success "Local cleanup completed!"
}

# Automatic cleanup of all threat detection resources
auto_cleanup_all() {
    print_status "Finding and cleaning ALL threat detection resources..."
    
    # Clean up any S3 buckets with threat detection patterns
    print_status "Cleaning up ALL threat detection S3 buckets..."
    aws s3 ls | grep -E "(cybersec|threat)" | awk '{print $3}' | while read bucket; do
        if [ -n "$bucket" ]; then
            print_status "Force emptying bucket: $bucket"
            aws s3 rm "s3://$bucket" --recursive --quiet 2>/dev/null || true
            aws s3api delete-bucket --bucket "$bucket" 2>/dev/null || true
        fi
    done
    
    # Clean up SageMaker endpoints
    aws sagemaker list-endpoints --name-contains "threat" --query 'Endpoints[].EndpointName' --output text | tr '\t' '\n' | while read endpoint; do
        if [ -n "$endpoint" ]; then
            print_status "Deleting endpoint: $endpoint"
            aws sagemaker delete-endpoint --endpoint-name "$endpoint" 2>/dev/null || true
        fi
    done
    
    # Clean up Lambda functions
    aws lambda list-functions --query 'Functions[?contains(FunctionName, `threat`)].FunctionName' --output text | tr '\t' '\n' | while read func; do
        if [ -n "$func" ]; then
            print_status "Deleting Lambda: $func"
            aws lambda delete-function --function-name "$func" 2>/dev/null || true
        fi
    done
    
    # Clean up API Gateways
    aws apigateway get-rest-apis --query 'items[?contains(name, `threat`)].id' --output text | tr '\t' '\n' | while read api; do
        if [ -n "$api" ]; then
            print_status "Deleting API Gateway: $api"
            aws apigateway delete-rest-api --rest-api-id "$api" 2>/dev/null || true
        fi
    done
    
    # Clean up Amplify apps
    aws amplify list-apps --query 'apps[?contains(name, `threat`)].appId' --output text | tr '\t' '\n' | while read app; do
        if [ -n "$app" ]; then
            print_status "Deleting Amplify app: $app"
            aws amplify delete-app --app-id "$app" 2>/dev/null || true
        fi
    done
}

# Main cleanup function
main() {
    show_warning
    
    # Ask for confirmation
    read -p "Are you absolutely sure you want to destroy all resources? Type 'yes' to confirm: " -r
    echo ""
    
    if [ "$REPLY" = "yes" ]; then
        print_status "Starting cleanup process..."
        
        # Check if Terraform is available
        if ! command -v terraform &> /dev/null; then
            print_error "Terraform is not installed. Cannot proceed with cleanup."
            exit 1
        fi
        
        # Check AWS credentials
        if ! aws sts get-caller-identity &> /dev/null; then
            print_error "AWS credentials not configured. Please run 'aws configure'."
            exit 1
        fi
        
        # Perform cleanup steps
        empty_s3_buckets
        stop_sagemaker
        delete_endpoints
        delete_amplify_apps
        terraform_destroy
        auto_cleanup_all  # Additional cleanup for any missed resources
        cleanup_local
        
        echo ""
        print_success "🎉 Cleanup completed successfully!"
        print_status "All AWS resources have been destroyed."
        echo ""
        
    else
        print_warning "Cleanup cancelled by user."
        exit 0
    fi
}

# Run main function
main "$@"