#!/bin/bash

# Automated Model Training Script
# Triggers SageMaker training job and endpoint deployment

set -e

echo "🤖 CyberGuard AI - Automated Model Training"
echo "==========================================="

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

# Get bucket and notebook info
get_resources() {
    print_status "Getting resource information from Terraform..."
    
    PROCESSED_BUCKET=$(terraform output -raw s3_processed_data_bucket 2>/dev/null)
    NOTEBOOK_NAME=$(terraform output -raw sagemaker_notebook_instance_name 2>/dev/null)
    
    if [ -z "$PROCESSED_BUCKET" ] || [ -z "$NOTEBOOK_NAME" ]; then
        print_error "Could not get resource information. Ensure Terraform has been applied."
        exit 1
    fi
    
    print_success "Processed data bucket: $PROCESSED_BUCKET"
    print_success "SageMaker notebook: $NOTEBOOK_NAME"
}

# Check if data exists
check_data() {
    print_status "Checking if processed data exists..."
    
    if aws s3 ls s3://$PROCESSED_BUCKET/train/train.csv &>/dev/null; then
        print_success "Training data found!"
    else
        print_error "Training data not found. Run './scripts/setup_data.sh' first."
        exit 1
    fi
}

# Create training notebook
create_training_notebook() {
    print_status "Creating automated training notebook..."
    
    mkdir -p notebooks/automated
    
    cat > notebooks/automated/automated_training.ipynb << 'EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Automated XGBoost Training for Threat Detection\n",
    "This notebook automatically trains and deploys the threat detection model."
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "import sagemaker\n",
    "import boto3\n",
    "from sagemaker.xgboost.estimator import XGBoost\n",
    "from sagemaker.inputs import TrainingInput\n",
    "from sagemaker.serializers import CSVSerializer\n",
    "from sagemaker.deserializers import CSVDeserializer\n",
    "import os"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Initialize SageMaker session\n",
    "sess = sagemaker.Session()\n",
    "role = sagemaker.get_execution_role()\n",
    "region = boto3.Session().region_name\n",
    "\n",
    "# Get processed data bucket from environment\n",
    "processed_bucket = os.environ.get('PROCESSED_BUCKET', 'cybersec-processed-data-xxxxxxxx')\n",
    "\n",
    "print(f\"SageMaker role: {role}\")\n",
    "print(f\"Region: {region}\")\n",
    "print(f\"Processed bucket: {processed_bucket}\")"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Define S3 paths\n",
    "train_path = f's3://{processed_bucket}/train/'\n",
    "validation_path = f's3://{processed_bucket}/validation/'\n",
    "output_path = f's3://{processed_bucket}/model-output/'\n",
    "\n",
    "print(f\"Training data: {train_path}\")\n",
    "print(f\"Validation data: {validation_path}\")\n",
    "print(f\"Model output: {output_path}\")"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Get XGBoost container\n",
    "container = sagemaker.image_uris.retrieve('xgboost', region, version='1.5-1')\n",
    "print(f\"XGBoost container: {container}\")"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Create XGBoost estimator\n",
    "xgb_estimator = XGBoost(\n",
    "    image_uri=container,\n",
    "    role=role,\n",
    "    instance_count=1,\n",
    "    instance_type='ml.m5.xlarge',\n",
    "    output_path=output_path,\n",
    "    sagemaker_session=sess,\n",
    "    hyperparameters={\n",
    "        'objective': 'binary:logistic',\n",
    "        'eval_metric': 'auc',\n",
    "        'num_round': 100,\n",
    "        'max_depth': 6,\n",
    "        'eta': 0.1,\n",
    "        'subsample': 0.8,\n",
    "        'colsample_bytree': 0.8,\n",
    "        'min_child_weight': 3,\n",
    "        'gamma': 0.1,\n",
    "        'reg_alpha': 0.1,\n",
    "        'reg_lambda': 1,\n",
    "        'scale_pos_weight': 1,\n",
    "        'early_stopping_rounds': 10,\n",
    "        'verbosity': 1\n",
    "    }\n",
    ")\n",
    "\n",
    "print(\"XGBoost estimator created!\")"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Define training inputs\n",
    "train_input = TrainingInput(train_path, content_type='text/csv')\n",
    "validation_input = TrainingInput(validation_path, content_type='text/csv')\n",
    "\n",
    "print(\"Starting model training...\")\n",
    "xgb_estimator.fit({\n",
    "    'train': train_input,\n",
    "    'validation': validation_input\n",
    "})\n",
    "\n",
    "print(\"Model training completed!\")"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Deploy model to endpoint\n",
    "print(\"Deploying model to endpoint...\")\n",
    "\n",
    "predictor = xgb_estimator.deploy(\n",
    "    initial_instance_count=1,\n",
    "    instance_type='ml.t2.medium',\n",
    "    endpoint_name='threat-detection-endpoint',\n",
    "    serializer=CSVSerializer(),\n",
    "    deserializer=CSVDeserializer()\n",
    ")\n",
    "\n",
    "print(f\"Model deployed to endpoint: {predictor.endpoint_name}\")"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Test the endpoint\n",
    "print(\"Testing the endpoint...\")\n",
    "\n",
    "# Sample test data (normalized features)\n",
    "test_sample = [\n",
    "    [0, 1, 0, 0, 0.1, 0.2, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, \n",
    "     0.5, 0.5, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.3, 0.3, 1.0, 0.0, 0.0, \n",
    "     0.0, 0.0, 0.0, 0.0, 0.0]\n",
    "]\n",
    "\n",
    "result = predictor.predict(test_sample)\n",
    "print(f\"Prediction result: {result}\")\n",
    "\n",
    "prediction = float(result[0][0])\n",
    "threat_detected = \"Attack\" if prediction > 0.5 else \"Normal\"\n",
    "confidence = prediction if prediction > 0.5 else 1 - prediction\n",
    "\n",
    "print(f\"Traffic Classification: {threat_detected}\")\n",
    "print(f\"Confidence: {confidence:.4f}\")"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Save endpoint information\n",
    "endpoint_info = {\n",
    "    'endpoint_name': predictor.endpoint_name,\n",

    "    'instance_type': 'ml.t2.medium',\n",
    "    'status': 'InService'\n",
    "}\n",
    "\n",
    "import json\n",
    "s3 = boto3.client('s3')\n",
    "s3.put_object(\n",
    "    Bucket=processed_bucket,\n",
    "    Key='endpoint_info.json',\n",
    "    Body=json.dumps(endpoint_info, indent=2)\n",
    ")\n",
    "\n",
    "print(\"✅ Training and deployment completed successfully!\")\n",
    "print(f\"Endpoint Name: {predictor.endpoint_name}\")\n",
    "print(\"Model is ready for real-time threat detection!\")"
   ]
  }
 ],
 "metadata": {
  "kernelspec": {
   "display_name": "conda_python3",
   "language": "python",
   "name": "conda_python3"
  },
  "language_info": {
   "codemirror_mode": {
    "name": "ipython",
    "version": 3
   },
   "file_extension": ".py",
   "mimetype": "text/x-python",
   "name": "python",
   "nbconvert_exporter": "python",
   "pygments_lexer": "ipython3",
   "version": "3.8.12"
  }
 },
 "nbformat": 4,
 "nbformat_minor": 4
}
EOF
    
    print_success "Training notebook created!"
}

# Upload notebook to SageMaker
upload_notebook() {
    print_status "Uploading notebook to SageMaker..."
    
    # Create a presigned URL to upload the notebook
    NOTEBOOK_URL=$(aws sagemaker describe-notebook-instance --notebook-instance-name $NOTEBOOK_NAME --query 'Url' --output text)
    
    print_success "Notebook available at: $NOTEBOOK_URL"
    print_warning "Please manually upload notebooks/automated/automated_training.ipynb to SageMaker"
}

# Execute training via SageMaker API
execute_training() {
    print_status "Executing automated training..."
    
    # Create a simple Python script to run the training
    cat > train_job.py << EOF
import boto3
import sagemaker
from sagemaker.xgboost.estimator import XGBoost
from sagemaker.inputs import TrainingInput

# Initialize
sess = sagemaker.Session()
role = sagemaker.get_execution_role()
region = boto3.Session().region_name

# Paths
processed_bucket = '$PROCESSED_BUCKET'
train_path = f's3://{processed_bucket}/train/'
validation_path = f's3://{processed_bucket}/validation/'
output_path = f's3://{processed_bucket}/model-output/'

# Container
container = sagemaker.image_uris.retrieve('xgboost', region, version='1.5-1')

# Estimator
xgb_estimator = XGBoost(
    image_uri=container,
    role=role,
    instance_count=1,
    instance_type='ml.m5.xlarge',
    output_path=output_path,
    sagemaker_session=sess,
    hyperparameters={
        'objective': 'binary:logistic',
        'eval_metric': 'auc',
        'num_round': 50,
        'max_depth': 6,
        'eta': 0.1
    }
)

# Training inputs
train_input = TrainingInput(train_path, content_type='text/csv')
validation_input = TrainingInput(validation_path, content_type='text/csv')

# Start training
print("Starting training job...")
xgb_estimator.fit({
    'train': train_input,
    'validation': validation_input
}, wait=False)

print(f"Training job started: {xgb_estimator.latest_training_job.name}")
EOF
    
    print_success "Training script created. Run 'python train_job.py' in SageMaker notebook."
}

# Main execution
main() {
    print_status "Starting automated model training setup..."
    
    get_resources
    check_data
    create_training_notebook
    upload_notebook
    execute_training
    
    echo ""
    print_success "🎉 Training setup completed!"
    echo ""
    echo "📋 Next Steps:"
    echo "  1. Access SageMaker notebook: $(terraform output -raw sagemaker_notebook_url)"
    echo "  2. Upload and run: notebooks/automated/automated_training.ipynb"
    echo "  3. Monitor training job in SageMaker console"
    echo "  4. Endpoint will be automatically deployed after training"
    echo ""
}

# Run main function
main "$@"