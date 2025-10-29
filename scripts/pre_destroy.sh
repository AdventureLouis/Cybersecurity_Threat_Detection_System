#!/bin/bash

# Pre-destroy script to handle SageMaker notebook cleanup
set -e

echo "🧹 Pre-destroy cleanup..."

# Stop SageMaker notebook instances if running
NOTEBOOKS=$(aws sagemaker list-notebook-instances --status-equals InService --region eu-west-1 --query 'NotebookInstances[?contains(NotebookInstanceName, `Threat-detection`)].NotebookInstanceName' --output text)

for notebook in $NOTEBOOKS; do
    if [ -n "$notebook" ]; then
        echo "Stopping SageMaker notebook: $notebook"
        aws sagemaker stop-notebook-instance --notebook-instance-name "$notebook" --region eu-west-1 || true
        aws sagemaker wait notebook-instance-stopped --notebook-instance-name "$notebook" --region eu-west-1 || true
    fi
done

echo "✅ Pre-destroy cleanup completed"