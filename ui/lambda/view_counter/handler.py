import os
import json
import boto3

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["TABLE_NAME"])

def lambda_handler(event, context):
    print("DEPLOYED VERSION: id-key-v1")
    print("TABLE_NAME:", os.environ["TABLE_NAME"])
    print("KEY:", {"id": "VIEW_COUNT"})
    response = table.update_item(
        Key={
            "id": "VIEW_COUNT",
        },
        UpdateExpression="ADD view_count :inc",
        ExpressionAttributeValues={
            ":inc": 1
        },
        ReturnValues="UPDATED_NEW"
    )

    return {
        "statusCode": 200,
        "headers": {
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "POST,OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type"
        },
        "body": json.dumps({
            "view_count": int(response["Attributes"]["view_count"])
        })
    }