# config/initializers/aws.rb
#
# AWS SDK configuration for IRSA (IAM Roles for Service Accounts).
#
# How credentials are resolved at runtime inside a pod:
#   1. K8s injects a projected service account token at:
#      /var/run/secrets/eks.amazonaws.com/serviceaccount/token
#   2. The pod has AWS_ROLE_ARN and AWS_WEB_IDENTITY_TOKEN_FILE set (see
#      k8s/06-application.yaml).
#   3. The AWS SDK WebIdentityCredentials provider (built into aws-sdk-core)
#      calls sts:AssumeRoleWithWebIdentity automatically — no hardcoded keys.
#
# Nothing here should ever contain access keys or secrets.

require "aws-sdk-s3"

Aws.config.update(
  region: ENV.fetch("AWS_REGION", "us-east-1")
)
