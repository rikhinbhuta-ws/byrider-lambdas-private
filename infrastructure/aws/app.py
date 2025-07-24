#!/usr/bin/env python3
from aws_cdk import App, Environment
from fanout_stack import FanoutStack  # your stack

app = App()

# Check context if deploying to LocalStack
is_local = app.node.try_get_context('localstack') == "true"

env = Environment(
    account="000000000000" if is_local else None,  # dummy account for LocalStack
    region="us-east-1"
)

FanoutStack(app, "FanoutStack", env=env)

app.synth()
