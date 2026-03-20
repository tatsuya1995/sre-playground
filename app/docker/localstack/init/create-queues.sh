#!/bin/bash
# localstack起動時にSQSキューを自動作成

awslocal sqs create-queue --queue-name articles
awslocal sqs create-queue --queue-name articles-dlq

echo "SQS queues created."
