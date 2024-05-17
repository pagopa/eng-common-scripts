#!/usr/bin/env bash
AWS_PROFILE=$1
REGION="eu-south-1"
RANDOM_STRING=$(date +%s)
S3_BUCKET_NAME="terraform-state-${RANDOM_STRING}"
DYNAMO_TABLE_NAME="terraform-lock"

if [ -z "${AWS_PROFILE}" ]; then
    printf "\e[1;31mYou must provide a profile as first argument.\n"
    exit 1
fi

if [ "$(aws s3api list-buckets --region "${REGION}" --query "Buckets[].Name")" == *"terraform-state"* ]; then
   echo "[INFO] s3 bucket: ${S3_BUCKET_NAME} already exists"
else
   aws s3api create-bucket --bucket "${S3_BUCKET_NAME}" --acl  "private" --create-bucket-configuration LocationConstraint="${REGION}"
   aws s3api put-bucket-versioning --bucket "${S3_BUCKET_NAME}" --versioning-configuration Status=Enabled 
   aws s3api put-bucket-lifecycle --bucket  "${S3_BUCKET_NAME}" --lifecycle-configuration file://lifecycle.json
fi

if [ "$(aws dynamodb list-tables --query "TableNames[].Name")" = "terraform-lock" ];then
 echo "[INFO] DynamoDB table named ${DYNAMO_TABLE_NAME} already created. \n"
else
 aws dynamodb create-table \
    --table-name "${DYNAMO_TABLE_NAME}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S AttributeName=Digest,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH AttributeName=Digest,KeyType=RANGE \
    --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5   
fi


