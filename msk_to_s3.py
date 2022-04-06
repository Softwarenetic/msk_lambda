import json
import boto3
import os


client = boto3.client('s3')

def lambda_handler(event, context):
    print("Lambda invoked")
    print(event)

    client.put_object(Body=b'Some test data', Bucket=os.getenv('BUCKET'), Key='{}'.format(context.aws_request_id))

    return {
        "statusCode": 200,
        "body": json.dumps('End run')
    }
