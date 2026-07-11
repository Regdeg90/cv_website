import json
import os
import re

import boto3

sns = boto3.client("sns")

TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]

EMAIL_PATTERN = re.compile(
    r"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@"
    r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$"
)


def create_response(status_code: int, body: dict) -> dict:
    return {
        "statusCode": status_code,
        "headers": {
            "Access-Control-Allow-Origin": "https://cv.regdeg90.com",
            "Access-Control-Allow-Methods": "POST,OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type",
            "Content-Type": "application/json",
        },
        "body": json.dumps(body),
    }


def lambda_handler(event, context):
    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return create_response(400, {"message": "Invalid request body"})

    email = str(body.get("email", "")).strip().lower()

    if len(email) > 254 or not EMAIL_PATTERN.fullmatch(email):
        return create_response(400, {"message": "Enter a valid email address"})

    sns.subscribe(
        TopicArn=TOPIC_ARN,
        Protocol="email",
        Endpoint=email,
        ReturnSubscriptionArn=True,
    )

    return create_response(
        202,
        {
            "message": (
                "Check your inbox and confirm your subscription "
                "to receive website updates."
            )
        },
    )