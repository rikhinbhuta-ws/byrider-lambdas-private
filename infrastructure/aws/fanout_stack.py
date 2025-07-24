import os
from aws_cdk import (
    Stack,
    Duration,
    CfnOutput,
    aws_lambda as lambda_,
    aws_sns as sns,
    aws_sqs as sqs,
    aws_sns_subscriptions as subs,
    aws_iam as iam,
)
from constructs import Construct

class FanoutStack(Stack):
    def __init__(self, scope: Construct, construct_id: str, **kwargs):
        super().__init__(scope, construct_id, **kwargs)

        # Check if we're deploying to LocalStack
        is_local = self.node.try_get_context('localstack') == True

        # SNS topic
        topic = sns.Topic(
            self, "DataFanoutTopic",
            display_name="Data Fanout Topic for Demo"
        )

        # SQS queues with better configuration
        queue1 = sqs.Queue(
            self, "ProcessingQueue1",
            queue_name="processing-queue-1" if is_local else None,
            visibility_timeout=Duration.seconds(300),
            retention_period=Duration.days(14)
        )
        
        queue2 = sqs.Queue(
            self, "ProcessingQueue2", 
            queue_name="processing-queue-2" if is_local else None,
            visibility_timeout=Duration.seconds(300),
            retention_period=Duration.days(14)
        )

        # Subscribe queues to topic
        topic.add_subscription(subs.SqsSubscription(queue1))
        topic.add_subscription(subs.SqsSubscription(queue2))

        # IAM role for Lambda
        role = iam.Role(
            self, "LambdaExecutionRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            role_name="fanout-lambda-role" if is_local else None
        )
        
        role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole")
        )
        
        # Allow Lambda to publish to SNS topic
        topic.grant_publish(role)

        # Lambda function
        lambda_path = os.path.join(os.path.dirname(__file__), '../../src/lambdas/producer')

        # Environment variables - different for LocalStack vs AWS
        environment_vars = {
            "SNS_TOPIC_ARN": topic.topic_arn,
        }
        
        if is_local:
            environment_vars["SNS_ENDPOINT_URL"] = "http://host.docker.internal:4566"

        producer_fn = lambda_.Function(
            self, "ProducerFunction",
            function_name="data-producer" if is_local else None,
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="handler.lambda_handler",
            code=lambda_.Code.from_asset(lambda_path),
            role=role,
            environment=environment_vars,
            timeout=Duration.seconds(30),
            memory_size=256
        )

        # Outputs for easy reference
        CfnOutput(self, "TopicArn", value=topic.topic_arn)
        CfnOutput(self, "Queue1Url", value=queue1.queue_url)
        CfnOutput(self, "Queue2Url", value=queue2.queue_url)
        CfnOutput(self, "LambdaFunctionName", value=producer_fn.function_name)