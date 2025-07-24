#!/bin/bash

set -e

# Configuration
LOCALSTACK_ENDPOINT="http://localhost:4566"
LOCALSTACK_INTERNAL_ENDPOINT="http://host.docker.internal:4566"
BUCKET_NAME="lambda-deployment-bucket"
LAMBDA_NAME="data-producer"
SNS_TOPIC_NAME="data-fanout-topic"
SQS_QUEUE_1="processing-queue-1"
SQS_QUEUE_2="processing-queue-2"
REGION="us-east-1"

if [ -f .env.localstack ]; then
  export $(grep -v '^#' .env.localstack | xargs)
fi

echo "🚀 Starting LocalStack deployment..."

# Wait for LocalStack to be ready
echo "⏳ Waiting for LocalStack to be ready..."
max_attempts=30
attempt=0

while [ $attempt -lt $max_attempts ]; do
    if curl -s $LOCALSTACK_ENDPOINT/_localstack/health | grep -q "\"sns\": \"available\""; then
        break
    fi
    echo "Waiting for LocalStack services... (attempt $((attempt + 1))/$max_attempts)"
    sleep 3
    attempt=$((attempt + 1))
done

if [ $attempt -eq $max_attempts ]; then
    echo "❌ LocalStack failed to start properly. Check docker logs:"
    echo "   docker-compose logs localstack"
    exit 1
fi

echo "✅ LocalStack is ready!"

# Create S3 bucket for lambda deployment
echo "📦 Creating S3 bucket for lambda deployments..."
aws --endpoint-url=$LOCALSTACK_ENDPOINT s3 mb s3://$BUCKET_NAME --region $REGION || true

# Package lambda function
echo "📦 Packaging lambda function..."

# Create a temporary directory for packaging
TEMP_DIR=$(mktemp -d)
echo "Using temporary directory: $TEMP_DIR"

# Copy lambda source files
cp -r src/lambdas/producer/* $TEMP_DIR/

# Install dependencies in the temporary directory
cd $TEMP_DIR
pip install -r requirements.txt -t . --quiet

# Create deployment package
zip -r lambda-deployment.zip . -x "*.pyc" "__pycache__/*" "*.git*" > /dev/null

# Move the zip file to project root
mv lambda-deployment.zip $OLDPWD/

# Return to project root and clean up
cd $OLDPWD
rm -rf $TEMP_DIR

# Upload lambda package to S3
echo "⬆️ Uploading lambda package..."
aws --endpoint-url=$LOCALSTACK_ENDPOINT s3 cp lambda-deployment.zip s3://$BUCKET_NAME/

# Create SNS Topic
echo "📢 Creating SNS topic..."
TOPIC_ARN=$(aws --endpoint-url=$LOCALSTACK_ENDPOINT sns create-topic \
    --name $SNS_TOPIC_NAME \
    --region $REGION \
    --query 'TopicArn' \
    --output text)

echo "📢 SNS Topic ARN: $TOPIC_ARN"

# Create SQS Queues
echo "📥 Creating SQS queues..."
QUEUE_1_URL=$(aws --endpoint-url=$LOCALSTACK_ENDPOINT sqs create-queue \
    --queue-name $SQS_QUEUE_1 \
    --region $REGION \
    --query 'QueueUrl' \
    --output text)

QUEUE_2_URL=$(aws --endpoint-url=$LOCALSTACK_ENDPOINT sqs create-queue \
    --queue-name $SQS_QUEUE_2 \
    --region $REGION \
    --query 'QueueUrl' \
    --output text)

echo "📥 Queue 1 URL: $QUEUE_1_URL"
echo "📥 Queue 2 URL: $QUEUE_2_URL"

# Get queue ARNs
QUEUE_1_ARN=$(aws --endpoint-url=$LOCALSTACK_ENDPOINT sqs get-queue-attributes \
    --queue-url $QUEUE_1_URL \
    --attribute-names QueueArn \
    --query 'Attributes.QueueArn' \
    --output text)

QUEUE_2_ARN=$(aws --endpoint-url=$LOCALSTACK_ENDPOINT sqs get-queue-attributes \
    --queue-url $QUEUE_2_URL \
    --attribute-names QueueArn \
    --query 'Attributes.QueueArn' \
    --output text)

# Subscribe queues to SNS topic
echo "🔗 Subscribing queues to SNS topic..."

# Add permissions for SNS to write to SQS
aws --endpoint-url=$LOCALSTACK_ENDPOINT sqs set-queue-attributes \
    --queue-url $QUEUE_1_URL \
    --attributes '{
        "Policy": "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":\"*\",\"Action\":\"sqs:SendMessage\",\"Resource\":\"'$QUEUE_1_ARN'\",\"Condition\":{\"ArnEquals\":{\"aws:SourceArn\":\"'$TOPIC_ARN'\"}}}]}"
    }'

aws --endpoint-url=$LOCALSTACK_ENDPOINT sqs set-queue-attributes \
    --queue-url $QUEUE_2_URL \
    --attributes '{
        "Policy": "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":\"*\",\"Action\":\"sqs:SendMessage\",\"Resource\":\"'$QUEUE_2_ARN'\",\"Condition\":{\"ArnEquals\":{\"aws:SourceArn\":\"'$TOPIC_ARN'\"}}}]}"
    }'

aws --endpoint-url=$LOCALSTACK_ENDPOINT sns subscribe \
    --topic-arn $TOPIC_ARN \
    --protocol sqs \
    --notification-endpoint $QUEUE_1_ARN

aws --endpoint-url=$LOCALSTACK_ENDPOINT sns subscribe \
    --topic-arn $TOPIC_ARN \
    --protocol sqs \
    --notification-endpoint $QUEUE_2_ARN

# Create IAM role for lambda (simplified for LocalStack)
echo "🔐 Creating IAM role..."
ROLE_ARN="arn:aws:iam::000000000000:role/lambda-execution-role"
aws --endpoint-url=$LOCALSTACK_ENDPOINT iam create-role \
    --role-name lambda-execution-role \
    --assume-role-policy-document '{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": {
                    "Service": "lambda.amazonaws.com"
                },
                "Action": "sts:AssumeRole"
            }
        ]
    }' || true

# Attach policies to role
aws --endpoint-url=$LOCALSTACK_ENDPOINT iam attach-role-policy \
    --role-name lambda-execution-role \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole || true

aws --endpoint-url=$LOCALSTACK_ENDPOINT iam put-role-policy \
    --role-name lambda-execution-role \
    --policy-name SNSPublishPolicy \
    --policy-document '{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": [
                    "sns:Publish"
                ],
                "Resource": "*"
            }
        ]
    }' || true

# Create Lambda function
echo "🔧 Creating Lambda function..."

# Give role a moment to propagate
sleep 2

aws --endpoint-url=$LOCALSTACK_ENDPOINT lambda create-function \
    --function-name $LAMBDA_NAME \
    --runtime python3.9 \
    --role $ROLE_ARN \
    --handler handler.lambda_handler \
    --code S3Bucket=$BUCKET_NAME,S3Key=lambda-deployment.zip \
    --timeout 30 \
    --environment Variables="{SNS_TOPIC_ARN=$TOPIC_ARN,SNS_ENDPOINT_URL=$LOCALSTACK_INTERNAL_ENDPOINT,AWS_REGION=$REGION}" \
    --region $REGION 2>/dev/null || {
        echo "🔄 Function exists, updating..."
        aws --endpoint-url=$LOCALSTACK_ENDPOINT lambda update-function-code \
            --function-name $LAMBDA_NAME \
            --s3-bucket $BUCKET_NAME \
            --s3-key lambda-deployment.zip \
            --region $REGION
        
        aws --endpoint-url=$LOCALSTACK_ENDPOINT lambda update-function-configuration \
            --function-name $LAMBDA_NAME \
            --environment Variables="{SNS_TOPIC_ARN=$TOPIC_ARN,SNS_ENDPOINT_URL=$LOCALSTACK_INTERNAL_ENDPOINT,AWS_REGION=$REGION}" \
            --region $REGION
    }

echo "⏳ Waiting for Lambda function to become active..."
aws --endpoint-url=$LOCALSTACK_ENDPOINT lambda wait function-active-v2 \
    --function-name $LAMBDA_NAME \
    --region $REGION
echo "✅ Lambda function is active!"

# Verify lambda function was created
echo "🔍 Verifying lambda function..."
aws --endpoint-url=$LOCALSTACK_ENDPOINT lambda get-function \
    --function-name $LAMBDA_NAME \
    --region $REGION > /dev/null

if [ $? -eq 0 ]; then
    echo "✅ Lambda function verified successfully"
else
    echo "❌ Lambda function verification failed"
    exit 1
fi

# Clean up
rm -f lambda-deployment.zip

echo "✅ Deployment complete!"
echo ""
echo "📋 Summary:"
echo "   Lambda Function: $LAMBDA_NAME"
echo "   SNS Topic ARN: $TOPIC_ARN"
echo "   Queue 1 URL: $QUEUE_1_URL"
echo "   Queue 2 URL: $QUEUE_2_URL"
echo ""
echo "🧪 To test the function, run:"
echo "   ./scripts/test-local.sh"
