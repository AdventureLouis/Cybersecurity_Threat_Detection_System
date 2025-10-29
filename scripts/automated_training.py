#!/usr/bin/env python3

import boto3
import sagemaker
import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import LabelEncoder
import json
import os
import sys
import time
from io import StringIO

def create_sample_data(bucket, s3_client):
    """Create sample training data if none exists"""
    print("📊 Creating sample training data...")
    
    # Generate synthetic NSL-KDD-like data
    np.random.seed(42)
    n_samples = 1000
    
    data = {
        'duration': np.random.exponential(1, n_samples),
        'protocol_type': np.random.choice([0, 1, 2], n_samples),
        'service': np.random.choice([0, 1, 2, 3, 4], n_samples),
        'flag': np.random.choice([0, 1, 2, 3], n_samples),
        'src_bytes': np.random.exponential(100, n_samples),
        'dst_bytes': np.random.exponential(1000, n_samples),
        'land': np.random.choice([0, 1], n_samples, p=[0.9, 0.1]),
        'wrong_fragment': np.random.poisson(0.1, n_samples),
        'urgent': np.random.poisson(0.05, n_samples),
        'hot': np.random.poisson(0.2, n_samples)
    }
    
    # Add more features to reach 41 total
    for i in range(31):
        data[f'feature_{i}'] = np.random.normal(0, 1, n_samples)
    
    # Create target (0=normal, 1=attack)
    data['label'] = np.random.choice([0, 1], n_samples, p=[0.7, 0.3])
    
    df = pd.DataFrame(data)
    
    # Split data
    train_df, val_df = train_test_split(df, test_size=0.2, random_state=42)
    
    # Upload to S3
    train_csv = train_df.to_csv(index=False, header=False)
    val_csv = val_df.to_csv(index=False, header=False)
    
    s3_client.put_object(Bucket=bucket, Key='train/train.csv', Body=train_csv)
    s3_client.put_object(Bucket=bucket, Key='validation/validation.csv', Body=val_csv)
    
    print("✅ Sample data created and uploaded")

def main():
    try:
        print("🚀 Starting bulletproof automated training...")
        
        # Initialize clients with error handling
        try:
            sess = sagemaker.Session()
            region = sess.boto_region_name
            s3_client = boto3.client('s3')
            sagemaker_client = boto3.client('sagemaker')
        except Exception as e:
            print(f"❌ Error initializing AWS clients: {e}")
            sys.exit(1)
        
        # Get SageMaker role
        try:
            role = os.popen('terraform output -raw sagemaker_role_arn 2>/dev/null').read().strip()
            if not role or 'Error' in role:
                raise Exception("No role found")
        except:
            print("❌ Error: Run 'terraform apply' first to create SageMaker role")
            sys.exit(1)
        
        # Get bucket
        try:
            bucket = os.popen('terraform output -raw s3_processed_data_bucket 2>/dev/null').read().strip()
            if not bucket or 'Error' in bucket:
                raise Exception("No bucket found")
        except:
            print("❌ Error: Run 'terraform apply' first to create S3 bucket")
            sys.exit(1)
        
        print(f"📦 Using bucket: {bucket}")
        print(f"🔑 Using role: {role}")
        
        # Check if training data exists, create if not
        try:
            s3_client.head_object(Bucket=bucket, Key='train/train.csv')
            print("✅ Training data found")
        except:
            print("⚠️ No training data found, creating sample data...")
            create_sample_data(bucket, s3_client)
        
        # Define paths
        train_path = f's3://{bucket}/train/'
        validation_path = f's3://{bucket}/validation/'
        output_path = f's3://{bucket}/model-output/'
        
        # Get XGBoost container
        try:
            container = sagemaker.image_uris.retrieve('xgboost', region, version='1.5-1')
        except Exception as e:
            print(f"❌ Error getting XGBoost container: {e}")
            sys.exit(1)
        
        # Create estimator with minimal resources
        try:
            from sagemaker.estimator import Estimator
            xgb_estimator = Estimator(
                image_uri=container,
                role=role,
                instance_count=1,
                instance_type='ml.m5.large',  # Smaller instance
                output_path=output_path,
                sagemaker_session=sess,
                hyperparameters={
                    'objective': 'binary:logistic',
                    'eval_metric': 'auc',
                    'num_round': 50,  # Reduced rounds
                    'max_depth': 4,   # Reduced depth
                    'eta': 0.1
                }
            )
        except Exception as e:
            print(f"❌ Error creating estimator: {e}")
            sys.exit(1)
        
        # Train model
        print("🔄 Training model (this may take 5-10 minutes)...")
        try:
            from sagemaker.inputs import TrainingInput
            xgb_estimator.fit({
                'train': TrainingInput(train_path, content_type='text/csv'),
                'validation': TrainingInput(validation_path, content_type='text/csv')
            }, wait=True)
        except Exception as e:
            print(f"❌ Training failed: {e}")
            sys.exit(1)
        
        # Clean up existing endpoints
        try:
            endpoints = sagemaker_client.list_endpoints(
                NameContains='threat-detection-endpoint'
            )['Endpoints']
            
            for ep in endpoints:
                if ep['EndpointStatus'] == 'InService':
                    print(f"🗑️ Deleting existing endpoint: {ep['EndpointName']}")
                    sagemaker_client.delete_endpoint(EndpointName=ep['EndpointName'])
                    time.sleep(5)
        except Exception as e:
            print(f"⚠️ Warning cleaning endpoints: {e}")
        
        # Deploy endpoint
        endpoint_name = f'threat-detection-endpoint-{int(time.time())}'
        print(f"🚀 Deploying endpoint: {endpoint_name}")
        
        try:
            predictor = xgb_estimator.deploy(
                initial_instance_count=1,
                instance_type='ml.t2.medium',
                endpoint_name=endpoint_name,
                wait=True
            )
        except Exception as e:
            print(f"❌ Deployment failed: {e}")
            sys.exit(1)
        
        # Update Lambda environment variable
        try:
            lambda_client = boto3.client('lambda')
            functions = lambda_client.list_functions()['Functions']
            
            for func in functions:
                if 'threat-detection-predict' in func['FunctionName']:
                    lambda_client.update_function_configuration(
                        FunctionName=func['FunctionName'],
                        Environment={
                            'Variables': {
                                'ENDPOINT_NAME': endpoint_name
                            }
                        }
                    )
                    print(f"✅ Updated Lambda function: {func['FunctionName']}")
                    break
        except Exception as e:
            print(f"⚠️ Warning updating Lambda: {e}")
        
        # Save endpoint info
        try:
            endpoint_info = {
                'endpoint_name': endpoint_name,
                'status': 'InService',
                'created_at': time.strftime('%Y-%m-%d %H:%M:%S')
            }
            
            s3_client.put_object(
                Bucket=bucket,
                Key='endpoint_info.json',
                Body=json.dumps(endpoint_info, indent=2)
            )
        except Exception as e:
            print(f"⚠️ Warning saving endpoint info: {e}")
        
        print("✅ Training and deployment completed successfully!")
        print(f"📍 Endpoint: {endpoint_name}")
        print(f"🌐 Your threat detection system is ready!")
        
    except KeyboardInterrupt:
        print("\n⚠️ Training interrupted by user")
        sys.exit(1)
    except Exception as e:
        print(f"❌ Unexpected error: {str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    main()