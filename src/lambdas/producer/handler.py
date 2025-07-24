import json
import boto3
import requests
from datetime import datetime
import os
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Producer lambda that fetches data from external APIs and publishes to SNS
    """
    
    # Initialize SNS client
    sns_client = boto3.client(
        'sns',
        endpoint_url=os.environ.get('SNS_ENDPOINT_URL', None),
        region_name=os.environ.get('AWS_REGION', 'us-east-1')
    )
    
    topic_arn = os.environ.get('SNS_TOPIC_ARN')
    
    try:
        # Fetch data from external APIs
        data_sources = fetch_data_from_sources()
        
        messages_sent = 0
        
        for source_name, data in data_sources.items():
            # Process and create messages for each data source
            messages = process_data_source(source_name, data)
            
            for message in messages:
                # Publish to SNS topic
                response = sns_client.publish(
                    TopicArn=topic_arn,
                    Message=json.dumps(message),
                    Subject=f'Data from {source_name}',
                    MessageAttributes={
                        'source': {
                            'DataType': 'String',
                            'StringValue': source_name
                        },
                        'timestamp': {
                            'DataType': 'String',
                            'StringValue': datetime.utcnow().isoformat()
                        }
                    }
                )
                
                logger.info(f"Published message to SNS: {response['MessageId']}")
                messages_sent += 1
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Successfully processed and sent {messages_sent} messages',
                'sources_processed': list(data_sources.keys())
            })
        }
        
    except Exception as e:
        logger.error(f"Error in lambda execution: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }

def fetch_data_from_sources():
    """
    Fetch data from various external sources
    For demo purposes, using public APIs
    """
    data_sources = {}
    
    try:
        # Example: JSONPlaceholder API (REST)
        rest_response = requests.get(
            'https://jsonplaceholder.typicode.com/posts',
            timeout=10
        )
        if rest_response.status_code == 200:
            data_sources['jsonplaceholder'] = rest_response.json()[:5]  # Limit for demo
    
    except requests.RequestException as e:
        logger.warning(f"Failed to fetch from REST API: {e}")
    
    try:
        # Example: Another public API
        weather_response = requests.get(
            'https://api.openweathermap.org/data/2.5/weather?q=London&appid=demo',
            timeout=10
        )
        # Note: This will likely fail without API key, but shows the pattern
        if weather_response.status_code == 200:
            data_sources['weather'] = weather_response.json()
    
    except requests.RequestException as e:
        logger.warning(f"Failed to fetch from weather API: {e}")
    
    # Fallback demo data if external APIs fail
    if not data_sources:
        data_sources['demo'] = [
            {'id': 1, 'title': 'Demo Post 1', 'body': 'This is demo content'},
            {'id': 2, 'title': 'Demo Post 2', 'body': 'More demo content'}
        ]
    
    return data_sources

def process_data_source(source_name, data):
    """
    Process raw data and create structured messages
    """
    messages = []
    
    if source_name == 'jsonplaceholder':
        for item in data:
            message = {
                'source': source_name,
                'type': 'blog_post',
                'data': {
                    'id': item.get('id'),
                    'title': item.get('title'),
                    'content': item.get('body'),
                    'user_id': item.get('userId')
                },
                'processed_at': datetime.utcnow().isoformat()
            }
            messages.append(message)
    
    elif source_name == 'weather':
        message = {
            'source': source_name,
            'type': 'weather_data',
            'data': {
                'location': data.get('name'),
                'temperature': data.get('main', {}).get('temp'),
                'description': data.get('weather', [{}])[0].get('description')
            },
            'processed_at': datetime.utcnow().isoformat()
        }
        messages.append(message)
    
    elif source_name == 'demo':
        for item in data:
            message = {
                'source': source_name,
                'type': 'demo_data',
                'data': item,
                'processed_at': datetime.utcnow().isoformat()
            }
            messages.append(message)
    
    return messages