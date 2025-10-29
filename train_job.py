import boto3
import sagemaker
from sagemaker.xgboost.estimator import XGBoost
from sagemaker.inputs import TrainingInput

# Initialize
sess = sagemaker.Session()
role = sagemaker.get_execution_role()
region = boto3.Session().region_name

# Paths
processed_bucket = 'cybersec-processed-data-3yqpqcnl'
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
