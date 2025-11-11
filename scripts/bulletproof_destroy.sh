#!/bin/bash

# Bulletproof Destroy Script
# Ensures ALL resources are deleted without errors

set -e

echo "🛡️ CyberGuard AI - Bulletproof Destroy"
echo "======================================"

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

# Function to run pre-destroy cleanup
run_pre_destroy() {
    print_status "🧹 Running comprehensive pre-destroy cleanup..."
    
    if [ -f "scripts/pre_destroy.sh" ]; then
        chmod +x scripts/pre_destroy.sh
        ./scripts/pre_destroy.sh
    else
        print_warning "Pre-destroy script not found, continuing..."
    fi
}

# Function to run terraform destroy with retries
run_terraform_destroy() {
    print_status "🗑️ Running Terraform destroy..."
    
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        print_status "Attempt $attempt of $max_attempts..."
        
        if terraform destroy --auto-approve; then
            print_success "✅ Terraform destroy completed successfully!"
            return 0
        else
            print_warning "⚠️ Terraform destroy attempt $attempt failed"
            
            if [ $attempt -lt $max_attempts ]; then
                print_status "Waiting 30 seconds before retry..."
                sleep 30
                
                # Run pre-destroy again in case some resources were recreated
                print_status "Running pre-destroy cleanup again..."
                run_pre_destroy
            fi
        fi
        
        ((attempt++))
    done
    
    print_error "❌ Terraform destroy failed after $max_attempts attempts"
    return 1
}

# Function to verify all resources are deleted
verify_cleanup() {
    print_status "🔍 Verifying all resources are deleted..."
    
    local region=$(aws configure get region 2>/dev/null || echo "eu-west-1")
    
    # Check SageMaker endpoints
    local endpoints=$(aws sagemaker list-endpoints --region $region --query 'Endpoints[?contains(EndpointName, `threat-detection`)].EndpointName' --output text 2>/dev/null || echo "")
    if [ -n "$endpoints" ]; then
        print_warning "⚠️ SageMaker endpoints still exist: $endpoints"
        return 1
    fi
    
    # Check S3 buckets
    local buckets=$(aws s3 ls | grep -E "(cybersec|threat)" | awk '{print $3}' || echo "")
    if [ -n "$buckets" ]; then
        print_warning "⚠️ S3 buckets still exist: $buckets"
        return 1
    fi
    
    # Check Lambda functions
    local functions=$(aws lambda list-functions --query 'Functions[?contains(FunctionName, `threat-detection`)].FunctionName' --output text 2>/dev/null || echo "")
    if [ -n "$functions" ]; then
        print_warning "⚠️ Lambda functions still exist: $functions"
        return 1
    fi
    
    print_success "✅ All resources verified as deleted!"
    return 0
}

# Function to clean local files
clean_local_files() {
    print_status "🧹 Cleaning local files..."
    
    rm -rf .terraform* terraform.tfstate* tfplan *.zip *.bak 2>/dev/null || true
    rm -rf notebooks/automated/ 2>/dev/null || true
    
    print_success "✅ Local files cleaned"
}

# Main execution
main() {
    echo ""
    print_status "Starting bulletproof destroy process..."
    echo ""
    
    # Step 1: Pre-destroy cleanup
    run_pre_destroy
    echo ""
    
    # Step 2: Terraform destroy with retries
    if run_terraform_destroy; then
        echo ""
        
        # Step 3: Verify cleanup
        if verify_cleanup; then
            # Step 4: Clean local files
            clean_local_files
            
            echo ""
            print_success "🎉 BULLETPROOF DESTROY COMPLETED SUCCESSFULLY!"
            print_success "All AWS resources have been deleted"
            print_success "All local files have been cleaned"
            echo ""
            print_status "You can now safely redeploy with:"
            echo "  terraform init"
            echo "  terraform apply -auto-approve"
            echo ""
        else
            print_warning "⚠️ Some resources may still exist. Check AWS console."
        fi
    else
        print_error "❌ Terraform destroy failed. Manual cleanup may be required."
        echo ""
        print_status "You can try manual cleanup with:"
        echo "  ./scripts/force_cleanup.sh"
        exit 1
    fi
}

# Confirmation prompt
echo ""
print_warning "⚠️  This will DELETE ALL threat detection resources!"
print_warning "⚠️  This action cannot be undone!"
echo ""
read -p "Are you sure you want to continue? (yes/no): " confirm

if [ "$confirm" = "yes" ] || [ "$confirm" = "y" ]; then
    main
else
    print_status "Destroy cancelled by user"
    exit 0
fi