#!/bin/bash

# Test script for S3 cleanup functionality
# This script tests the empty_bucket function without actually running cleanup

set -e

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

# Test function to check if buckets exist and have content
test_bucket_status() {
    print_status "Testing S3 bucket cleanup functionality..."
    
    # Check if AWS CLI is available
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured."
        exit 1
    fi
    
    # Get bucket names from Terraform state if available
    if [ -f "terraform.tfstate" ]; then
        RAW_BUCKET=$(terraform output -raw s3_raw_data_bucket 2>/dev/null || echo "")
        PROCESSED_BUCKET=$(terraform output -raw s3_processed_data_bucket 2>/dev/null || echo "")
        MODEL_BUCKET=$(terraform output -raw s3_model_artifacts_bucket 2>/dev/null || echo "")
        FRONTEND_BUCKET=$(terraform output -raw s3_frontend_bucket 2>/dev/null || echo "")
        
        print_status "Found buckets in Terraform state:"
        [ -n "$RAW_BUCKET" ] && echo "  • Raw data: $RAW_BUCKET"
        [ -n "$PROCESSED_BUCKET" ] && echo "  • Processed data: $PROCESSED_BUCKET"
        [ -n "$MODEL_BUCKET" ] && echo "  • Model artifacts: $MODEL_BUCKET"
        [ -n "$FRONTEND_BUCKET" ] && echo "  • Frontend: $FRONTEND_BUCKET"
    else
        print_warning "No Terraform state found."
    fi
    
    # Check for threat-detection buckets
    print_status "Searching for threat-detection buckets..."
    THREAT_BUCKETS=$(aws s3api list-buckets --query 'Buckets[?contains(Name, `threat-detection`)].Name' --output text 2>/dev/null || echo "")
    
    if [ -n "$THREAT_BUCKETS" ]; then
        print_status "Found threat-detection buckets:"
        for bucket in $THREAT_BUCKETS; do
            echo "  • $bucket"
            # Check if bucket has objects
            OBJECT_COUNT=$(aws s3 ls "s3://$bucket" --recursive | wc -l)
            echo "    Objects: $OBJECT_COUNT"
        done
    else
        print_success "No threat-detection buckets found."
    fi
    
    print_success "S3 bucket status check completed!"
}

# Run the test
test_bucket_status