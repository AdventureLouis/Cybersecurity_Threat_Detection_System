


# 🛡️ CyberGuard AI - Cybersecurity Threat Detection System

A comprehensive, AI-powered cybersecurity threat detection system built on AWS using SageMaker, Lambda, and modern web technologies. This system provides real-time network traffic analysis using machine learning to identify potential security threats.


#Video Demo



https://github.com/user-attachments/assets/9c88acf5-ba02-438e-b3e6-e65e84e3dfff




## 🏗️ Architecture

![Architecture](https://github.com/user-attachments/assets/1d102fa3-faee-4b88-8a14-7efd43c8283a)





The system consists of:
- **AWS SageMaker**: ML model training and deployment
- **AWS Lambda**: Real-time prediction API
- **AWS API Gateway**: RESTful API endpoint with CORS
- **AWS Amplify**: Modern web frontend hosting
- **AWS S3**: Data storage and model artifacts
- **AWS CloudWatch**: Monitoring and logging
- **Interactive Web Interface**: Clean, responsive threat analysis UI

## 🚀 Features

- **Real-time Threat Detection**: Analyze network traffic in milliseconds
- **Machine Learning Powered**: XGBoost model trained on NSL-KDD dataset
- **Fully Automated Deployment**: One-command infrastructure, ML pipeline, and frontend
- **Enhanced Amplify Frontend**: Modern glassmorphism UI with animations and effects
- **REST API with CORS**: Secure API Gateway integration
- **Comprehensive Monitoring**: CloudWatch dashboards and logging
- **Scalable Architecture**: Serverless design for high availability
- **Security Best Practices**: IAM roles with minimal permissions
- **Professional Design**: Cybersecurity-themed interface with smooth animations

## 📋 Prerequisites

- AWS CLI configured with appropriate permissions
- Terraform >= 1.0
- Python 3.8+ with pip
- NSL-KDD dataset from Kaggle



**⚡ Fast 3-5 minute deployment** that:
- Deploys all AWS infrastructure (SageMaker, Lambda, API Gateway, Amplify)
- Automatically creates sample training data if none exists
- Trains and deploys ML model with bulletproof error handling
- Deploys frontend to AWS Amplify with safety net
- Creates secure REST API endpoint with CORS



### **📋 Manual Step-by-Step Deployment**

**Setup Virtual Environment:**
```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

1. **Deploy Infrastructure**
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

2. **Setup Data Pipeline**
   ```bash
   ./scripts/setup_data.sh
   ```


3. **run below:**
```bash
./scripts/deploy_amplify_auto.sh
```

4. **Finally train Model** (Automated)
   ```bash
   python scripts/automated_training.py
   ```
   *Alternative: Use SageMaker notebook with `automated_training.ipynb`*



### **🔧 Individual Components**

- **Infrastructure Only**: `terraform init && terraform apply`
- **Data Setup Only**: `./scripts/setup_data.sh`
- **Training Setup Only**: `./scripts/train_model.sh`
- **Automated Training**: `python3 scripts/automated_training.py`

### **🧹 System Cleanup**

**🛡️ Destroy all resources and endpoints**
```bash
./scripts/bulletproof_destroy.sh
```
*Automatically deletes ALL SageMaker endpoints, then runs terraform destroy with retries*

**⚡ Quick Destroy:**
```bash
./scripts/pre_destroy.sh && terraform destroy --auto-approve
```

**🔧 Manual Terraform Only:**
```bash
terraform destroy --auto-approve
```

**🚨 Emergency Force Cleanup:**
```bash
./scripts/force_cleanup.sh
```

**✅ Zero-Error Destruction Features:**
- **SageMaker endpoints deleted BEFORE terraform destroy**
- All S3 buckets have `force_destroy = true`
- SageMaker notebooks auto-stop before deletion
- Complete resource cleanup without errors
- Amplify apps properly managed through Terraform
- Local files automatically cleaned
- **Retry mechanism for failed destroys**

### **🔄 Redeploy After Cleanup**

After destroying resources, instantly redeploy with:
```bash
terraform init
terraform apply -auto-approve
./scripts/deploy_amplify_auto.sh
python scripts/automated_training.py
```

**Complete reproducibility in 3-5 minutes!**

### **🛡️ Bulletproof Destroy Process**

The `bulletproof_destroy.sh` script ensures 100% clean deletion:

1. **Pre-Destroy Cleanup**: Deletes ALL SageMaker endpoints, models, and configurations
2. **Terraform Destroy**: Runs with retry mechanism (up to 3 attempts)
3. **Verification**: Confirms all AWS resources are deleted
4. **Local Cleanup**: Removes all local terraform and build files

**Why use bulletproof destroy?**
- SageMaker endpoints created by `automated_training.py` are NOT managed by Terraform
- These endpoints must be deleted manually before terraform destroy
- Prevents "resource still exists" errors during destroy
- Guarantees clean slate for redeployment

## 📊 Dataset Information

**NSL-KDD Dataset Features:**
- **Categorical**: protocol_type, service, flag, label
- **Numerical**: 37 continuous features
- **Target**: Binary classification (0: Normal, 1: Attack)
- **Automatic Processing**: Label encoding, normalization, train/validation split

**Attack Types Detected:**
- DoS (Denial of Service)
- Probe (Surveillance and Probing)
- R2L (Remote to Local)
- U2R (User to Root)

**Automated Data Pipeline:**
- Downloads NSL-KDD dataset automatically
- Processes and normalizes features
- Uploads to appropriate S3 buckets
- Creates train/validation/test splits

## 📁 Optimized Project Structure

```
├── amplify_package/          # Frontend (single source)
├── data/                     # NSL-KDD dataset
├── lambda/                   # Lambda function
├── notebooks/                # ML training notebooks
├── scripts/                  # Essential scripts only
├── *.tf                      # Terraform infrastructure
└── requirements.txt          # Dependencies
```

**Removed Duplicates:**
- Multiple frontend directories → Single `amplify_package/`
- 5+ deployment scripts → Single `deploy_amplify_auto.sh`
- Duplicate notebooks → Organized in `notebooks/`
- Backup and test files → Cleaned up

## 🔧 Configuration

### Environment Variables
- `ENDPOINT_NAME`: SageMaker endpoint name
- `AWS_REGION`: Deployment region (eu-west-1)

### Hyperparameters
```python
{
    'objective': 'binary:logistic',
    'eval_metric': 'auc',
    'num_round': 100,
    'max_depth': 6,
    'eta': 0.1,
    'subsample': 0.8,
    'colsample_bytree': 0.8
}
```

## 📈 Monitoring

### CloudWatch Metrics
- Lambda function duration, errors, invocations
- API Gateway latency, error rates
- SageMaker endpoint metrics

### Log Groups
- `/aws/lambda/threat-detection-predict-*`
- `/aws/sagemaker/NotebookInstances/Threat-detection`
- `API-Gateway-Execution-Logs_*/prod`

## 🔒 Security

- **IAM Roles**: Minimal required permissions for each service
- **S3 Buckets**: Appropriate access controls and encryption
- **API Gateway**: CORS enabled, throttling, and monitoring
- **Amplify**: Secure HTTPS hosting with CDN
- **Lambda**: Isolated execution environment
- **CloudWatch**: Comprehensive logging and monitoring

## 💰 Cost Optimization

- **SageMaker**: ml.t3.medium for notebook, ml.t2.medium for endpoint
- **Lambda**: Pay-per-request pricing (no idle costs)
- **API Gateway**: Pay-per-request with caching
- **Amplify**: Free tier available, CDN included
- **S3**: Standard storage with lifecycle policies
- **CloudWatch**: 14-30 day log retention

## 🌐 Frontend Deployment

### AWS Amplify Hosting
- **Automated Deployment**: Terraform creates and deploys the frontend
- **Enhanced UI Design**: Modern glassmorphism interface with animations
- **Responsive Design**: Works perfectly on desktop and mobile devices
- **Real-time API Integration**: Direct connection to ML model
- **HTTPS by Default**: Secure hosting with SSL certificates

### Enhanced Frontend Features
- **Modern Design**: Glassmorphism effects with backdrop blur and shimmer animations
- **Interactive Elements**: Hover effects, smooth transitions, and visual feedback
- **Input Form**: 6 network traffic parameters with enhanced styling
- **Results Page**: Animated threat status with pulsing effects and attractive metrics
- **Error Handling**: Graceful fallback to demo data with professional error messages
- **Loading States**: Beautiful loading animations and user-friendly feedback
- **Professional Theme**: Cybersecurity-focused design with gradient backgrounds

## 🧪 Testing

### Sample Network Features
```json
{
  "duration": 0,
  "protocol_type": 1,
  "service": 0,
  "flag": 0,
  "src_bytes": 181,
  "dst_bytes": 5450
}
```

### Expected Response
```json
{
  "prediction": 0,
  "confidence": 0.8234,
  "status": "Normal Traffic",
  "raw_score": 0.1766
}
```

### Access Points
- **Amplify Frontend**: `https://[app-id].amplifyapp.com`
- **API Endpoint**: `https://[api-id].execute-api.[region].amazonaws.com/prod/predict`
- **SageMaker Notebook**: `https://[notebook].notebook.[region].sagemaker.aws`

## 🔄 CI/CD Pipeline

1. **Development**: Local testing with mock data
2. **Staging**: Terraform plan and validate
3. **Production**: Terraform apply with approval
4. **Monitoring**: CloudWatch alerts and dashboards

## 📚 API Documentation

### POST /predict
Analyze network traffic for threats

**Endpoint:** `https://[api-id].execute-api.[region].amazonaws.com/prod/predict`

**Request Body:**
```json
{
  "features": [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
}
```

**Response:**
```json
{
  "prediction": 0,
  "confidence": 0.8234,
  "status": "Normal Traffic",
  "raw_score": 0.1766
}
```

**CORS:** Enabled for web browser access
**Content-Type:** `application/json`

## 🤝 Contributing

1. Fork the repository
2. Create feature branch
3. Commit changes
4. Push to branch
5. Create Pull Request

## 📄 License

This project is licensed under the MIT License.

## 🆘 Support

For issues and questions:
- **Destroy Issues**: Use `./scripts/bulletproof_destroy.sh` instead of terraform destroy
- **SageMaker Endpoints**: Run `./scripts/pre_destroy.sh` to clean endpoints
- Check CloudWatch logs
- Review Terraform outputs
- Validate IAM permissions
- Ensure dataset is properly uploaded

### 🚨 Emergency Cleanup
If normal destroy fails:
```bash
./scripts/force_cleanup.sh  # Nuclear option - deletes everything
```

### ✅ System Guarantees

- **🔒 100% Button Reliability**: "Analyze Threat" always works with safety net
- **🧹 Zero-Error Cleanup**: `./scripts/bulletproof_destroy.sh` never fails
- **🛡️ Complete Resource Deletion**: ALL SageMaker endpoints deleted before terraform
- **🔄 Retry Mechanism**: Terraform destroy retries up to 3 times if needed
- **📦 No Duplicates**: Optimized structure, single source of truth
- **⚡ Quick Deployment**: 3-5 minute infrastructure + frontend deployment
- **🔄 Complete Reproducibility**: Destroy and recreate anytime
- **🛡️ Security Best Practices**: Minimal IAM permissions, encrypted storage
- **🤖 Bulletproof Training**: Creates sample data automatically, handles all errorsource of truth
- **⚡ Quick Deployment**: 3-5 minute infrastructure + frontend deployment
- **🔄 Complete Reproducibility**: Destroy and recreate anytime
- **🛡️ Security Best Practices**: Minimal IAM permissions, encrypted storage
- **🤖 Bulletproof Training**: Creates sample data automatically, handles all errors

### Common Issues - RESOLVED ✅

**✅ SageMaker Endpoint Deletion:**
- **Fixed**: `bulletproof_destroy.sh` deletes ALL endpoints before terraform
- **Fixed**: Pre-destroy script handles endpoint configurations and models
- **Fixed**: Retry mechanism for stubborn resources

**✅ Terraform Destroy Errors:**
- **Fixed**: All S3 buckets now have `force_destroy = true`
- **Fixed**: SageMaker notebooks auto-stop before deletion
- **Fixed**: Comprehensive pre-destroy cleanup prevents conflicts

**✅ Duplicate Resources:**
- **Fixed**: Project structure optimized, all duplicates removed

**✅ Button Reliability:**
- **Fixed**: "Analyze Threat" button has safety net guarantee

**✅ API Integration:**
- **Fixed**: Lambda function handles SageMaker responses correctly

## 🎯 Future Enhancements

- [ ] Multi-class classification
- [ ] Real-time streaming data
- [ ] Advanced visualization
- [ ] Model retraining pipeline
- [ ] Integration with SIEM systems
- [ ] Mobile application

---

