#!/bin/bash

set -e

LOCALSTACK_ENDPOINT="http://localhost:4566"
REGION="us-east-1"

echo "🧪 Testing CDK LocalStack deployment..."

# Check if outputs file exists
if [ ! -f "cdk-outputs-local.json" ]; then
    echo "❌ CDK outputs file not found. Deploy first with: ./scripts/cdk-deploy.sh local"
    exit 1
fi

# Extract values from CDK outputs
LAMBDA_NAME=$(jq -r '.FanoutStack.LambdaFunctionName' cdk-outputs-local.json)
TOPIC_ARN=$(jq -r '.FanoutStack.TopicArn' cdk-outputs-local.json)
QUEUE_1_URL=$(jq -r '.FanoutStack.Queue1Url' cdk-outputs-local.json)
QUEUE_2_URL=$(jq -r '.FanoutStack.Queue2Url' cdk-outputs-local.json)

echo "📋 Using CDK deployment:"
echo "   Lambda Function: $LAMBDA_NAME"
echo "   Topic ARN: $TOPIC_ARN"
echo "   Queue 1 URL: $QUEUE_1_URL"
echo "   Queue 2 URL: $QUEUE_2_URL"
echo ""

# Invoke the lambda function
echo "🚀 Invoking producer lambda..."
aws --endpoint-url=$LOCALSTACK_ENDPOINT lambda invoke \
    --function-name $LAMBDA_NAME \
    --payload '{}' \
    --region $REGION \
    response.json

echo "📄 Lambda response:"
cat response.json | jq '.'
echo ""

# Wait for message propagation
echo "⏳ Waiting for message propagation..."
sleep 5

# Check messages in both queues
echo "📥 Checking Queue 1..."
MESSAGES_1=$(aws --endpoint-url=$LOCALSTACK_ENDPOINT sqs receive-message \
    --queue-url $QUEUE_1_URL \
    --max-number-of-messages 10 \
    --region $REGION 2>/dev/null || echo '{}')

if echo "$MESSAGES_1" | jq -e '.Messages' > /dev/null 2>&1; then
    echo "✅ Found messages in Queue 1:"
    echo "$MESSAGES_1" | jq '.Messages[] | {MessageId, Body}' | head -20
else
    echo "❌ No messages found in Queue 1"
fi

echo ""
echo "📥 Checking Queue 2..."
MESSAGES_2=$(aws --endpoint-url=$LOCALSTACK_ENDPOINT sqs receive-message \
    --queue-url $QUEUE_2_URL \
    --max-number-of-messages 10 \
    --region $REGION 2>/dev/null || echo '{}')

if echo "$MESSAGES_2" | jq -e '.Messages' > /dev/null 2>&1; then
    echo "✅ Found messages in Queue 2:"
    echo "$MESSAGES_2" | jq '.Messages[] | {MessageId, Body}' | head -20
else
    echo "❌ No messages found in Queue 2"
fi

# Clean up
rm -f response.json

echo ""
echo "🎉 CDK LocalStack test complete!"

# Additional verification
echo ""
echo "🔍 Stack verification:"
echo "   Checking if all resources exist..."

# Check Lambda function
if aws --endpoint-url=$LOCALSTACK_ENDPOINT lambda get-function --function-name $LAMBDA_NAME --region $REGION > /dev/null 2>&1; then
    echo "   ✅ Lambda function exists and is accessible"
else
    echo "   ❌ Lambda function not found or not accessible"
fi

# Check SNS topic
if aws --endpoint-url=$LOCALSTACK_ENDPOINT sns get-topic-attributes --topic-arn $TOPIC_ARN --region $REGION > /dev/null 2>&1; then
    echo "   ✅ SNS topic exists and is accessible"
else
    echo "   ❌ SNS topic not found or not accessible"
fi

# Check SQS queues
if aws --endpoint-url=$LOCALSTACK_ENDPOINT sqs get-queue-attributes --queue-url $QUEUE_1_URL --region $REGION > /dev/null 2>&1; then
    echo "   ✅ SQS Queue 1 exists and is accessible"
else
    echo "   ❌ SQS Queue 1 not found or not accessible"
fi

if aws --endpoint-url=$LOCALSTACK_ENDPOINT sqs get-queue-attributes --queue-url $QUEUE_2_URL --region $REGION > /dev/null 2>&1; then
    echo "   ✅ SQS Queue 2 exists and is accessible"
else
    echo "   ❌ SQS Queue 2 not found or not accessible"
fi