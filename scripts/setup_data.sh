#!/bin/bash

# Data Setup Script for CyberGuard AI
# Automates NSL-KDD dataset download, upload, and processing

set -e

echo "🔄 CyberGuard AI - Data Setup Automation"
echo "========================================"

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

# Get bucket names from Terraform outputs
get_bucket_names() {
    print_status "Getting S3 bucket names from Terraform..."
    
    RAW_BUCKET=$(terraform output -raw s3_raw_data_bucket 2>/dev/null)
    PROCESSED_BUCKET=$(terraform output -raw s3_processed_data_bucket 2>/dev/null)
    
    if [ -z "$RAW_BUCKET" ] || [ -z "$PROCESSED_BUCKET" ]; then
        print_error "Could not get bucket names. Ensure Terraform has been applied."
        exit 1
    fi
    
    print_success "Raw data bucket: $RAW_BUCKET"
    print_success "Processed data bucket: $PROCESSED_BUCKET"
}

# Download NSL-KDD dataset
download_dataset() {
    print_status "Downloading NSL-KDD dataset..."
    
    mkdir -p data/raw
    cd data/raw
    
    # Download NSL-KDD dataset files
    if [ ! -f "KDDTrain+.txt" ]; then
        print_status "Downloading KDDTrain+.txt..."
        curl -L -o "KDDTrain+.txt" "https://raw.githubusercontent.com/defcom17/NSL_KDD/master/KDDTrain%2B.txt"
    fi
    
    if [ ! -f "KDDTest+.txt" ]; then
        print_status "Downloading KDDTest+.txt..."
        curl -L -o "KDDTest+.txt" "https://raw.githubusercontent.com/defcom17/NSL_KDD/master/KDDTest%2B.txt"
    fi
    
    cd ../..
    print_success "Dataset downloaded successfully!"
}

# Upload raw data to S3 with retry logic
upload_raw_data() {
    print_status "Uploading raw dataset to S3..."
    
    # Function to upload with retry
    upload_with_retry() {
        local file=$1
        local s3_path=$2
        local max_attempts=3
        local attempt=1
        
        while [ $attempt -le $max_attempts ]; do
            print_status "Upload attempt $attempt/$max_attempts for $file"
            
            if aws s3 cp "$file" "$s3_path" --cli-read-timeout 300 --cli-connect-timeout 60; then
                print_success "Successfully uploaded $file"
                return 0
            else
                print_warning "Upload attempt $attempt failed for $file"
                attempt=$((attempt + 1))
                [ $attempt -le $max_attempts ] && sleep 5
            fi
        done
        
        print_error "Failed to upload $file after $max_attempts attempts"
        return 1
    }
    
    upload_with_retry "data/raw/KDDTrain+.txt" "s3://$RAW_BUCKET/KDDTrain+.txt"
    upload_with_retry "data/raw/KDDTest+.txt" "s3://$RAW_BUCKET/KDDTest+.txt"
    
    print_success "Raw data uploaded to s3://$RAW_BUCKET/"
}

# Create and upload preprocessing script
create_preprocessing_script() {
    print_status "Creating automated preprocessing script..."
    
    mkdir -p data/scripts
    
    cat > data/scripts/preprocess_data.py << 'EOF'
import pandas as pd
import numpy as np
import boto3
from sklearn.preprocessing import LabelEncoder, StandardScaler
from sklearn.model_selection import train_test_split
import io
import sys

def main():
    # S3 client
    s3 = boto3.client('s3')
    
    # Get bucket names from command line
    raw_bucket = sys.argv[1]
    processed_bucket = sys.argv[2]
    
    print("Starting data preprocessing...")
    
    # Column names for NSL-KDD dataset
    columns = [
        'duration', 'protocol_type', 'service', 'flag', 'src_bytes', 'dst_bytes',
        'land', 'wrong_fragment', 'urgent', 'hot', 'num_failed_logins', 'logged_in',
        'num_compromised', 'root_shell', 'su_attempted', 'num_root', 'num_file_creations',
        'num_shells', 'num_access_files', 'num_outbound_cmds', 'is_host_login',
        'is_guest_login', 'count', 'srv_count', 'serror_rate', 'srv_serror_rate',
        'rerror_rate', 'srv_rerror_rate', 'same_srv_rate', 'diff_srv_rate',
        'srv_diff_host_rate', 'dst_host_count', 'dst_host_srv_count',
        'dst_host_same_srv_rate', 'dst_host_diff_srv_rate', 'dst_host_same_src_port_rate',
        'dst_host_srv_diff_host_rate', 'dst_host_serror_rate', 'dst_host_srv_serror_rate',
        'dst_host_rerror_rate', 'dst_host_srv_rerror_rate', 'label', 'difficulty'
    ]
    
    # Download and load data from S3
    print("Loading training data...")
    train_obj = s3.get_object(Bucket=raw_bucket, Key='KDDTrain+.txt')
    train_data = pd.read_csv(io.BytesIO(train_obj['Body'].read()), names=columns)
    
    print("Loading test data...")
    test_obj = s3.get_object(Bucket=raw_bucket, Key='KDDTest+.txt')
    test_data = pd.read_csv(io.BytesIO(test_obj['Body'].read()), names=columns)
    
    print(f"Training data shape: {train_data.shape}")
    print(f"Test data shape: {test_data.shape}")
    
    # Preprocessing function
    def preprocess_data(df):
        df = df.copy()
        
        # Remove difficulty column
        if 'difficulty' in df.columns:
            df = df.drop('difficulty', axis=1)
        
        # Convert label to binary (0: normal, 1: attack)
        df['label'] = df['label'].apply(lambda x: 0 if x == 'normal' else 1)
        
        # Encode categorical features
        categorical_features = ['protocol_type', 'service', 'flag']
        
        for feature in categorical_features:
            le = LabelEncoder()
            df[feature] = le.fit_transform(df[feature])
        
        # Separate features and target
        X = df.drop('label', axis=1)
        y = df['label']
        
        # Normalize continuous features
        scaler = StandardScaler()
        X_scaled = pd.DataFrame(scaler.fit_transform(X), columns=X.columns)
        
        return X_scaled, y, scaler
    
    # Preprocess data
    print("Preprocessing training data...")
    X_train, y_train, scaler = preprocess_data(train_data)
    
    print("Preprocessing test data...")
    X_test, y_test, _ = preprocess_data(test_data)
    
    # Prepare data for XGBoost (target as first column)
    train_data_xgb = pd.concat([y_train, X_train], axis=1)
    test_data_xgb = pd.concat([y_test, X_test], axis=1)
    
    # Create validation split
    X_train_split, X_val, y_train_split, y_val = train_test_split(
        X_train, y_train, test_size=0.2, random_state=42, stratify=y_train
    )
    
    train_split_xgb = pd.concat([y_train_split, X_train_split], axis=1)
    val_data_xgb = pd.concat([y_val, X_val], axis=1)
    
    # Upload processed data to S3
    print("Uploading processed training data...")
    csv_buffer = io.StringIO()
    train_split_xgb.to_csv(csv_buffer, index=False, header=False)
    s3.put_object(Bucket=processed_bucket, Key='train/train.csv', Body=csv_buffer.getvalue())
    
    print("Uploading processed validation data...")
    csv_buffer = io.StringIO()
    val_data_xgb.to_csv(csv_buffer, index=False, header=False)
    s3.put_object(Bucket=processed_bucket, Key='validation/validation.csv', Body=csv_buffer.getvalue())
    
    print("Uploading processed test data...")
    csv_buffer = io.StringIO()
    test_data_xgb.to_csv(csv_buffer, index=False, header=False)
    s3.put_object(Bucket=processed_bucket, Key='test/test.csv', Body=csv_buffer.getvalue())
    
    # Save feature information
    feature_info = {
        'feature_names': X_train.columns.tolist(),
        'num_features': len(X_train.columns)
    }
    
    import json
    s3.put_object(
        Bucket=processed_bucket, 
        Key='feature_info.json', 
        Body=json.dumps(feature_info)
    )
    
    print("Data preprocessing completed successfully!")
    print(f"Training data: s3://{processed_bucket}/train/train.csv")
    print(f"Validation data: s3://{processed_bucket}/validation/validation.csv")
    print(f"Test data: s3://{processed_bucket}/test/test.csv")

if __name__ == "__main__":
    main()
EOF
    
    print_success "Preprocessing script created!"
}

# Run data preprocessing
run_preprocessing() {
    print_status "Running data preprocessing..."
    
    # Install required packages
    pip install pandas scikit-learn boto3 numpy
    
    # Run preprocessing script
    python data/scripts/preprocess_data.py $RAW_BUCKET $PROCESSED_BUCKET
    
    print_success "Data preprocessing completed!"
}

# Create SageMaker training job script
create_training_script() {
    print_status "Creating automated training script..."
    
    cat > data/scripts/train_model.py << 'EOF'
import boto3
import sagemaker
from sagemaker.xgboost.estimator import XGBoost
from sagemaker.inputs import TrainingInput
import sys

def main():
    processed_bucket = sys.argv[1]
    
    print("Starting model training...")
    
    # Initialize SageMaker session
    sess = sagemaker.Session()
    role = sagemaker.get_execution_role()
    region = boto3.Session().region_name
    
    # Define S3 paths
    train_path = f's3://{processed_bucket}/train/'
    validation_path = f's3://{processed_bucket}/validation/'
    output_path = f's3://{processed_bucket}/model-output/'
    
    print(f"Training data: {train_path}")
    print(f"Validation data: {validation_path}")
    print(f"Model output: {output_path}")
    
    # Get XGBoost container
    container = sagemaker.image_uris.retrieve('xgboost', region, version='1.5-1')
    
    # Create XGBoost estimator
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
            'num_round': 100,
            'max_depth': 6,
            'eta': 0.1,
            'subsample': 0.8,
            'colsample_bytree': 0.8,
            'min_child_weight': 3,
            'gamma': 0.1,
            'reg_alpha': 0.1,
            'reg_lambda': 1,
            'scale_pos_weight': 1,
            'early_stopping_rounds': 10,
            'verbosity': 1
        }
    )
    
    # Define training inputs
    train_input = TrainingInput(train_path, content_type='text/csv')
    validation_input = TrainingInput(validation_path, content_type='text/csv')
    
    # Start training
    print("Starting model training job...")
    xgb_estimator.fit({
        'train': train_input,
        'validation': validation_input
    })
    
    # Deploy model
    print("Deploying model to endpoint...")
    predictor = xgb_estimator.deploy(
        initial_instance_count=1,
        instance_type='ml.t2.medium',
        endpoint_name='threat-detection-endpoint'
    )
    
    print(f"Model deployed to endpoint: {predictor.endpoint_name}")
    print("Training and deployment completed successfully!")

if __name__ == "__main__":
    main()
EOF
    
    print_success "Training script created!"
}

# Main execution
main() {
    print_status "Starting automated data setup..."
    
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
    
    # Execute pipeline
    get_bucket_names
    download_dataset
    upload_raw_data
    create_preprocessing_script
    run_preprocessing
    create_training_script
    
    echo ""
    print_success "🎉 Data setup completed successfully!"
    echo ""
    echo "📋 Next Steps:"
    echo "  1. Access SageMaker notebook: $(terraform output -raw sagemaker_notebook_url)"
    echo "  2. Run training script: python data/scripts/train_model.py $PROCESSED_BUCKET"
    echo "  3. Monitor training in SageMaker console"
    echo ""
}

# Run main function
main "$@"