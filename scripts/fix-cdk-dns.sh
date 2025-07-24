#!/bin/bash

echo "🔧 Fixing CDK LocalStack DNS issues..."

# Option 1: Add entries to /etc/hosts (requires sudo)
echo "Adding LocalStack DNS entries to /etc/hosts..."

ENTRIES_TO_ADD=(
    "127.0.0.1 cdk-hnb659fds-assets-000000000000-us-east-1.localhost"
    "127.0.0.1 cdk-hnb659fds-assets-000000000000-us-east-1.s3.localhost"
    "127.0.0.1 localhost.localstack.cloud"
)

for entry in "${ENTRIES_TO_ADD[@]}"; do
    if ! grep -q "$entry" /etc/hosts 2>/dev/null; then
        echo "Adding: $entry"
        echo "$entry" | sudo tee -a /etc/hosts > /dev/null
    else
        echo "Already exists: $entry"
    fi
done

echo "✅ DNS entries added to /etc/hosts"

# Option 2: Set CDK environment variables
echo ""
echo "🔧 Setting CDK environment variables..."

export AWS_ENDPOINT_URL_S3=http://localhost:4566
export AWS_ENDPOINT_URL_CLOUDFORMATION=http://localhost:4566
export AWS_ENDPOINT_URL_STS=http://localhost:4566
export AWS_ENDPOINT_URL_IAM=http://localhost:4566
export AWS_ENDPOINT_URL_LAMBDA=http://localhost:4566

echo "✅ Environment variables set"

echo ""
echo "🔍 Current /etc/hosts entries for LocalStack:"
grep -i localstack /etc/hosts || echo "No LocalStack entries found"
grep "127.0.0.1.*cdk-" /etc/hosts || echo "No CDK entries found"

echo ""
echo "✅ DNS fix complete!"
echo "Now try running: ./scripts/cdk-deploy.sh local"