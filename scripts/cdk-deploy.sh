#!/bin/bash
set -e

TARGET=${1:-aws}  # default to real AWS
STACK_NAME="FanoutStack"

if [ "$TARGET" == "local" ]; then
  echo "🚀 Deploying CDK to LocalStack..."

  # Check if cdklocal is installed
  if ! command -v cdklocal &> /dev/null; then
    echo "❌ cdklocal is not installed. Installing..."
    npm install -g aws-cdk-local aws-cdk
  fi

  # Load LocalStack environment variables if they exist
  if [ -f .env.localstack ]; then
    export $(grep -v '^#' .env.localstack | xargs)
  fi

  # Set CDK-specific environment variables for LocalStack
  export CDK_DEFAULT_ACCOUNT=000000000000
  export CDK_DEFAULT_REGION=us-east-1
  export AWS_ENDPOINT_URL_S3=http://localhost:4566
  export AWS_ENDPOINT_URL_CLOUDFORMATION=http://localhost:4566
  export AWS_ENDPOINT_URL_STS=http://localhost:4566
  export AWS_ENDPOINT_URL_IAM=http://localhost:4566
  export AWS_ENDPOINT_URL_LAMBDA=http://localhost:4566
  export AWS_ENDPOINT_URL_SNS=http://localhost:4566
  export AWS_ENDPOINT_URL_SQS=http://localhost:4566
  
  # Wait for LocalStack to be ready
  echo "⏳ Waiting for LocalStack to be ready..."
  max_attempts=30
  attempt=0
  
  while [ $attempt -lt $max_attempts ]; do
      if curl -s http://localhost:4566/_localstack/health | grep -q "\"cloudformation\": \"available\""; then
          echo "✅ LocalStack is ready!"
          break
      fi
      echo "Waiting for LocalStack services... (attempt $((attempt + 1))/$max_attempts)"
      sleep 3
      attempt=$((attempt + 1))
  done
  
  if [ $attempt -eq $max_attempts ]; then
      echo "❌ LocalStack failed to start properly"
      exit 1
  fi

  # Apply DNS fix for CDK assets
  echo "🔧 Applying DNS fix for CDK assets..."
  
  # Check if DNS entries exist, add if missing
  ASSETS_HOST="cdk-hnb659fds-assets-000000000000-us-east-1.localhost"
  if ! grep -q "$ASSETS_HOST" /etc/hosts 2>/dev/null; then
    echo "Adding DNS entry for CDK assets bucket..."
    echo "127.0.0.1 $ASSETS_HOST" | sudo tee -a /etc/hosts > /dev/null || {
      echo "⚠️ Could not add DNS entry to /etc/hosts. You may need to run:"
      echo "sudo echo '127.0.0.1 $ASSETS_HOST' >> /etc/hosts"
    }
  fi

  # Use LocalStack-specific CDK configuration
  if [ -f cdk.json ]; then
    cp cdk.json cdk.json.aws.backup
  fi
  cp cdk.localstack.json cdk.json

  # Clean up any previous deployments
  echo "🧹 Cleaning up previous deployments..."
  cdklocal destroy $STACK_NAME --force 2>/dev/null || true
  sleep 5

  # Bootstrap with retry logic
  echo "🔧 Bootstrapping CDK for LocalStack..."
  max_bootstrap_attempts=3
  bootstrap_attempt=0
  
  while [ $bootstrap_attempt -lt $max_bootstrap_attempts ]; do
    if cdklocal bootstrap --require-approval never; then
      echo "✅ Bootstrap successful"
      break
    else
      bootstrap_attempt=$((bootstrap_attempt + 1))
      echo "⚠️ Bootstrap attempt $bootstrap_attempt failed, retrying..."
      sleep 10
    fi
  done
  
  if [ $bootstrap_attempt -eq $max_bootstrap_attempts ]; then
    echo "❌ Bootstrap failed after $max_bootstrap_attempts attempts"
    echo "💡 Try running: ./scripts/fix-cdk-dns.sh"
    exit 1
  fi
  
  echo "🚀 Deploying stack to LocalStack..."
  if cdklocal deploy $STACK_NAME --require-approval never --outputs-file cdk-outputs-local.json; then
    echo "✅ LocalStack deployment complete!"
    echo "📋 Stack outputs saved to: cdk-outputs-local.json"
  else
    echo "❌ Deployment failed"
    echo "💡 Try running: ./scripts/fix-cdk-dns.sh"
    exit 1
  fi

  # Restore original cdk.json
  if [ -f cdk.json.aws.backup ]; then
    mv cdk.json.aws.backup cdk.json
  fi

else
  echo "🚀 Deploying CDK to real AWS..."

  # Ensure we're using the AWS cdk.json
  if [ -f cdk.json.aws.backup ]; then
    cp cdk.json.aws.backup cdk.json
  fi

  AWS_PROFILE=${AWS_PROFILE:-default}
  echo "Using AWS profile: $AWS_PROFILE"

  # Check if AWS CLI is configured
  if ! aws sts get-caller-identity --profile "$AWS_PROFILE" &> /dev/null; then
    echo "❌ AWS CLI not configured or invalid profile. Run 'aws configure --profile $AWS_PROFILE'"
    exit 1
  fi

  echo "🔧 Bootstrapping CDK for AWS..."
  cdk bootstrap --profile "$AWS_PROFILE" --require-approval never
  
  echo "🚀 Deploying stack to AWS..."
  cdk deploy $STACK_NAME --profile "$AWS_PROFILE" --require-approval never --outputs-file cdk-outputs-aws.json

  echo "✅ AWS deployment complete!"
  echo "📋 Stack outputs saved to: cdk-outputs-aws.json"
fi

echo ""
echo "🧪 To test the deployment:"
if [ "$TARGET" == "local" ]; then
  echo "   ./scripts/test-cdk-local.sh"
else
  echo "   ./scripts/test-cdk-aws.sh"
fi