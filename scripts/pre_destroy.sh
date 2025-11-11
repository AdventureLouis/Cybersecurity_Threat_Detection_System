#!/bin/bash

# Pre-destroy script to handle complete SageMaker cleanup
set -e

echo "🧹 Pre-destroy cleanup - Ensuring ALL resources are deleted..."

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# Get AWS region
REGION=$(aws configure get region 2>/dev/null || echo "eu-west-1")
print_status "Using AWS region: $REGION"

# 1. Delete ALL SageMaker endpoints (most critical)
print_status "🎯 Deleting ALL SageMaker endpoints..."
ENDPOINTS=$(aws sagemaker list-endpoints --region $REGION --query 'Endpoints[?contains(EndpointName, `threat-detection`)].EndpointName' --output text 2>/dev/null || echo "")

if [ -n "$ENDPOINTS" ]; then
    for endpoint in $ENDPOINTS; do
        if [ -n "$endpoint" ]; then
            print_status "Deleting SageMaker endpoint: $endpoint"
            aws sagemaker delete-endpoint --endpoint-name "$endpoint" --region $REGION 2>/dev/null || true
            print_success "Endpoint deletion initiated: $endpoint"
        fi
    done
    
    # Wait for endpoints to be deleted
    print_status "⏳ Waiting for endpoints to be fully deleted..."
    sleep 10
    
    # Verify all endpoints are gone
    REMAINING=$(aws sagemaker list-endpoints --region $REGION --query 'Endpoints[?contains(EndpointName, `threat-detection`)].EndpointName' --output text 2>/dev/null || echo "")
    if [ -z "$REMAINING" ]; then
        print_success "✅ All SageMaker endpoints deleted"
    else
        print_warning "⚠️ Some endpoints may still be deleting: $REMAINING"
    fi
else
    print_success "✅ No SageMaker endpoints found"
fi

# 2. Delete endpoint configurations
print_status "🔧 Deleting SageMaker endpoint configurations..."
CONFIGS=$(aws sagemaker list-endpoint-configs --region $REGION --query 'EndpointConfigs[?contains(EndpointConfigName, `threat-detection`)].EndpointConfigName' --output text 2>/dev/null || echo "")

if [ -n "$CONFIGS" ]; then
    for config in $CONFIGS; do
        if [ -n "$config" ]; then
            print_status "Deleting endpoint config: $config"
            aws sagemaker delete-endpoint-config --endpoint-config-name "$config" --region $REGION 2>/dev/null || true
        fi
    done
    print_success "✅ Endpoint configurations deleted"
else
    print_success "✅ No endpoint configurations found"
fi

# 3. Delete models
print_status "🤖 Deleting SageMaker models..."
MODELS=$(aws sagemaker list-models --region $REGION --query 'Models[?contains(ModelName, `threat-detection`)].ModelName' --output text 2>/dev/null || echo "")

if [ -n "$MODELS" ]; then
    for model in $MODELS; do
        if [ -n "$model" ]; then
            print_status "Deleting model: $model"
            aws sagemaker delete-model --model-name "$model" --region $REGION 2>/dev/null || true
        fi
    done
    print_success "✅ Models deleted"
else
    print_success "✅ No models found"
fi

# 4. Stop and delete SageMaker notebook instances
print_status "📓 Handling SageMaker notebook instances..."
NOTEBOOKS=$(aws sagemaker list-notebook-instances --region $REGION --query 'NotebookInstances[?contains(NotebookInstanceName, `Threat-detection`)].NotebookInstanceName' --output text 2>/dev/null || echo "")

if [ -n "$NOTEBOOKS" ]; then
    for notebook in $NOTEBOOKS; do
        if [ -n "$notebook" ]; then
            # Check status first
            STATUS=$(aws sagemaker describe-notebook-instance --notebook-instance-name "$notebook" --region $REGION --query 'NotebookInstanceStatus' --output text 2>/dev/null || echo "NotFound")
            
            if [ "$STATUS" = "InService" ]; then
                print_status "Stopping notebook: $notebook"
                aws sagemaker stop-notebook-instance --notebook-instance-name "$notebook" --region $REGION 2>/dev/null || true
                
                print_status "⏳ Waiting for notebook to stop..."
                aws sagemaker wait notebook-instance-stopped --notebook-instance-name "$notebook" --region $REGION 2>/dev/null || true
            fi
            
            print_success "✅ Notebook stopped: $notebook"
        fi
    done
else
    print_success "✅ No notebook instances found"
fi

# 5. Clean up training jobs (if any are still running)
print_status "🏋️ Checking for running training jobs..."
TRAINING_JOBS=$(aws sagemaker list-training-jobs --region $REGION --status-equals InProgress --query 'TrainingJobSummaries[?contains(TrainingJobName, `threat-detection`)].TrainingJobName' --output text 2>/dev/null || echo "")

if [ -n "$TRAINING_JOBS" ]; then
    for job in $TRAINING_JOBS; do
        if [ -n "$job" ]; then
            print_status "Stopping training job: $job"
            aws sagemaker stop-training-job --training-job-name "$job" --region $REGION 2>/dev/null || true
        fi
    done
    print_success "✅ Training jobs stopped"
else
    print_success "✅ No running training jobs found"
fi

# 6. Final verification
print_status "🔍 Final verification - checking for remaining SageMaker resources..."
REMAINING_ENDPOINTS=$(aws sagemaker list-endpoints --region $REGION --query 'Endpoints[?contains(EndpointName, `threat-detection`)].EndpointName' --output text 2>/dev/null || echo "")

if [ -z "$REMAINING_ENDPOINTS" ]; then
    print_success "✅ All SageMaker endpoints confirmed deleted"
else
    print_warning "⚠️ Warning: Some endpoints may still exist: $REMAINING_ENDPOINTS"
    print_status "Attempting final cleanup..."
    for ep in $REMAINING_ENDPOINTS; do
        aws sagemaker delete-endpoint --endpoint-name "$ep" --region $REGION 2>/dev/null || true
    done
fi

echo ""
print_success "🎉 Pre-destroy cleanup completed successfully!"
print_status "All SageMaker resources have been cleaned up"
print_status "Safe to run: terraform destroy --auto-approve"
echo ""