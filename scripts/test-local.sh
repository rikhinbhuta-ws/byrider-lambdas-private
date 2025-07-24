#!/bin/bash

set -e

# Configuration
LOCALSTACK_ENDPOINT="http://localhost:4566"
LAMBDA_NAME="data-producer"
SQS_QUEUE_1="processing-queue-1"
SQS_QUEUE_2="processing-queue-2"
REGION="us-east-1"

if [ -f .env.localstack ]; then
  export $(grep -v '^#' .env.localstack | xargs)
fi

echo "🧪 Testing the fanout pattern..."

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

# Wait a moment for message propagation
echo "⏳ Waiting for message propagation..."
sleep 3

# Check messages in both queues
echo "📥 Checking Queue 1 ($SQS_QUEUE_1)..."
QUEUE_1_URL=$(aws --endpoint-url=$LOCALSTACK_ENDPOINT sqs get-queue-url \
    --queue-name $SQS_QUEUE_1 \
    --region $REGION \
    --query 'QueueUrl' \
    --output text)

MESSAGES_1=$(aws --endpoint-url=$LOCALSTACK_ENDPOINT sqs receive-message \
    --queue-url $QUEUE_1_URL \
    --max-number-of-messages 10 \
    --region $REGION)

if echo "$MESSAGES_1" | jq -e '.Messages' > /dev/null; then
    echo "✅ Found messages in Queue 1:"
    echo "$MESSAGES_1" | jq '.Messages[] | {MessageId, Body}' | head -20
else
    echo "❌ No messages found in Queue 1"
fi

echo ""
echo "📥 Checking Queue 2 ($SQS_QUEUE_2)..."
QUEUE_2_URL=$(aws --endpoint-url=$LOCALSTACK_ENDPOINT sqs get-queue-url \
    --queue-name $SQS_QUEUE_2 \
    --region $REGION \
    --query 'QueueUrl' \
    --output text)

MESSAGES_2=$(aws --endpoint-url=$LOCALSTACK_ENDPOINT sqs receive-message \
    --queue-url $QUEUE_2_URL \
    --max-number-of-messages 10 \
    --region $REGION)

if echo "$MESSAGES_2" | jq -e '.Messages' > /dev/null; then
    echo "✅ Found messages in Queue 2:"
    echo "$MESSAGES_2" | jq '.Messages[] | {MessageId, Body}' | head -20
else
    echo "❌ No messages found in Queue 2"
fi

# Clean up
rm -f response.json

echo ""
echo "🎉 Test complete! Check the output above to verify the fanout pattern is working."