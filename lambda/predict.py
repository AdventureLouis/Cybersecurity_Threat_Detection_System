import json
import boto3
import os

def lambda_handler(event, context):
    try:
        # Parse the request body
        body = json.loads(event['body'])
        features = body['features']
        
        # Initialize SageMaker clients
        sagemaker_runtime = boto3.client('sagemaker-runtime')
        sagemaker = boto3.client('sagemaker')
        
        # Get endpoint name from environment variable with fallback
        endpoint_name = os.environ.get('ENDPOINT_NAME', 'threat-detection-endpoint-1761182339')
        
        # Prepare the input data (convert to CSV format for XGBoost)
        csv_input = ','.join(map(str, features))
        
        # Invoke the SageMaker endpoint
        response = sagemaker_runtime.invoke_endpoint(
            EndpointName=endpoint_name,
            ContentType='text/csv',
            Body=csv_input
        )
        
        # Parse the prediction result
        result = response['Body'].read().decode().strip()
        
        # Handle different response formats
        if result.startswith('[') and result.endswith(']'):
            # Remove brackets and get the number
            prediction = float(result.strip('[]'))
        else:
            prediction = float(result)
        
        # Convert to binary classification (0: normal, 1: attack)
        threat_detected = 1 if prediction > 0.5 else 0
        confidence = prediction if threat_detected else 1 - prediction
        
        return {
            'statusCode': 200,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type',
                'Access-Control-Allow-Methods': 'POST, OPTIONS'
            },
            'body': json.dumps({
                'prediction': threat_detected,
                'confidence': round(confidence, 4),
                'status': 'Attack Detected' if threat_detected else 'Normal Traffic',
                'raw_score': round(prediction, 4)
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type',
                'Access-Control-Allow-Methods': 'POST, OPTIONS'
            },
            'body': json.dumps({
                'error': str(e),
                'message': 'Error processing prediction request'
            })
        }