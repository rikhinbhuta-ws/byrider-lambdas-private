#!/bin/bash

set -e

echo "🔧 Setting up AWS Fanout Demo Environment"
echo "========================================"

# Check if virtual environment exists
if [ ! -d ".venv" ]; then
    echo "📦 Creating virtual environment..."
    python3 -m .venv venv
fi

# Activate virtual environment
echo "🔌 Activating virtual environment..."
source .venv/bin/activate

# Upgrade pip
echo "⬆️ Upgrading pip..."
pip install --upgrade pip

# Install Python dependencies
echo "📚 Installing Python dependencies..."
pip install -r requirements.txt

# Install Node.js dependencies for CDK
echo "🟢 Checking Node.js and npm..."
if ! command -v node &> /dev/null; then
    echo "❌ Node.js is not installed. Please install Node.js and npm first."
    echo "   Visit: https://nodejs.org/"
    exit 1
fi

if ! command -v npm &> /dev/null; then
    echo "❌ npm is not installed. Please install npm first."
    exit 1
fi

echo "🔧 Installing CDK CLI tools..."
npm install -g aws-cdk aws-cdk-local

# Configure AWS CLI with dummy credentials for LocalStack
echo "🔑 Configuring AWS CLI for LocalStack..."
aws configure set aws_access_key_id test
aws configure set aws_secret_access_key test
aws configure set region us-east-1

# Make scripts executable
echo "🛠️ Making scripts executable..."
chmod +x scripts/*.sh

# Create .env.localstack if it doesn't exist
if [ ! -f ".env.localstack" ]; then
    echo "⚙️ Creating .env.localstack..."
    cat > .env.localstack << EOF
# LocalStack Configuration
LOCALSTACK_ENDPOINT=http://localhost:4566
AWS_REGION=us-east-1
AWS_DEFAULT_REGION=us-east-1
AWS_ACCESS_KEY_ID=test
AWS_SECRET_ACCESS_KEY=test

# CDK Configuration
CDK_DEFAULT_ACCOUNT=000000000000
CDK_DEFAULT_REGION=us-east-1
EOF
fi

# Verify installations
echo ""
echo "✅ Environment setup complete!"
echo ""
echo "🔍 Verification:"
echo "   Python: $(python --version)"
echo "   pip: $(pip --version)"
echo "   AWS CLI: $(aws --version)"
echo "   CDK: $(cdk --version)"
echo "   CDK Local: $(cdklocal --version)"
echo "   Node.js: $(node --version)"
echo "   npm: $(npm --version)"

echo ""
echo "🚀 Next steps:"
echo "1. Start LocalStack:"
echo "   cd infrastructure/localstack && docker-compose up -d"
echo ""
echo "2. Choose your deployment method:"
echo "   Bash scripts: ./scripts/deploy-local.sh"
echo "   CDK: ./scripts/cdk-deploy.sh local"
echo ""
echo "3. Test your deployment:"
echo "   Bash: ./scripts/test-local.sh"
echo "   CDK: ./scripts/test-cdk-local.sh"