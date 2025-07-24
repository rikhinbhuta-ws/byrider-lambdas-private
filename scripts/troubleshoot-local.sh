#!/bin/bash

# LocalStack Troubleshooting Script

LOCALSTACK_ENDPOINT="http://localhost:4566"

echo "🔍 LocalStack Troubleshooting Guide"
echo "================================="

# Check if Docker is running
echo "1. Checking Docker status..."
if docker info > /dev/null 2>&1; then
    echo "   ✅ Docker is running"
else
    echo "   ❌ Docker is not running. Please start Docker first."
    exit 1
fi

# Check if LocalStack container is running
echo "2. Checking LocalStack container..."
if docker ps | grep -q localstack; then
    echo "   ✅ LocalStack container is running"
    CONTAINER_ID=$(docker ps | grep localstack | awk '{print $1}')
    echo "   Container ID: $CONTAINER_ID"
else
    echo "   ❌ LocalStack container is not running"
    echo "   Run: cd infrastructure/localstack && docker-compose up -d"
    exit 1
fi

# Check LocalStack health endpoint
echo "3. Checking LocalStack health..."
HEALTH_RESPONSE=$(curl -s $LOCALSTACK_ENDPOINT/_localstack/health 2>/dev/null)

if [ $? -eq 0 ]; then
    echo "   ✅ LocalStack health endpoint is accessible"
    echo "   Services status:"
    echo "$HEALTH_RESPONSE" | jq '.services' 2>/dev/null || echo "$HEALTH_RESPONSE"
else
    echo "   ❌ Cannot reach LocalStack health endpoint"
    echo "   Trying basic connectivity..."
    if curl -s $LOCALSTACK_ENDPOINT > /dev/null 2>&1; then
        echo "   ✅ Basic connectivity works"
    else
        echo "   ❌ No connectivity to LocalStack"
        echo "   Check if port 4566 is available: netstat -an | grep 4566"
    fi
fi

# Check specific services
echo "4. Testing specific AWS services..."

# Test S3
echo "   Testing S3..."
if aws --endpoint-url=$LOCALSTACK_ENDPOINT s3 ls > /dev/null 2>&1; then
    echo "   ✅ S3 service is working"
else
    echo "   ❌ S3 service is not responding"
fi

# Test SNS
echo "   Testing SNS..."
if aws --endpoint-url=$LOCALSTACK_ENDPOINT sns list-topics --region us-east-1 > /dev/null 2>&1; then
    echo "   ✅ SNS service is working"
else
    echo "   ❌ SNS service is not responding"
fi

# Test SQS
echo "   Testing SQS..."
if aws --endpoint-url=$LOCALSTACK_ENDPOINT sqs list-queues --region us-east-1 > /dev/null 2>&1; then
    echo "   ✅ SQS service is working"
else
    echo "   ❌ SQS service is not responding"
fi

# Test Lambda
echo "   Testing Lambda..."
if aws --endpoint-url=$LOCALSTACK_ENDPOINT lambda list-functions --region us-east-1 > /dev/null 2>&1; then
    echo "   ✅ Lambda service is working"
else
    echo "   ❌ Lambda service is not responding"
fi

# Show container logs if there are issues
echo "5. Recent LocalStack logs:"
echo "   (Last 20 lines)"
docker logs --tail 20 $CONTAINER_ID 2>/dev/null || echo "   Could not retrieve logs"

echo ""
echo "🛠️  Common Solutions:"
echo "   - Restart LocalStack: cd infrastructure/localstack && docker-compose restart"
echo "   - Reset LocalStack: cd infrastructure/localstack && docker-compose down && docker-compose up -d"
echo "   - Check Docker memory/CPU limits"
echo "   - Ensure no other services are using port 4566"
echo "   - Wait 30-60 seconds after starting LocalStack before running scripts"

echo ""
echo "📋 Environment Info:"
echo "   Docker version: $(docker --version)"
echo "   AWS CLI version: $(aws --version)"
echo "   Python version: $(python --version)"
echo "   Current directory: $(pwd)"