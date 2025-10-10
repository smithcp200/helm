#!/bin/bash
# Script to refresh ECR pull secret (ECR tokens expire after 12 hours)
# Run this as a cron job or use IRSA for automatic authentication

set -e

AWS_REGION="us-west-2"
AWS_ACCOUNT_ID="283174975792"
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

NAMESPACE=${1:-summitlabs-staging}

echo "🔄 Refreshing ECR pull secret in namespace: ${NAMESPACE}"

# Delete existing secret if it exists
kubectl delete secret ecr-pull-secret -n ${NAMESPACE} --ignore-not-found=true

# Create new secret with fresh token
kubectl create secret docker-registry ecr-pull-secret \
  --docker-server=${ECR_REGISTRY} \
  --docker-username=AWS \
  --docker-password=$(aws ecr get-login-password --region ${AWS_REGION}) \
  -n ${NAMESPACE}

echo "✅ ECR pull secret refreshed successfully in ${NAMESPACE}"

# Optional: Restart deployments to pick up new secret
read -p "Restart deployments to use new secret? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]
then
    echo "🔄 Restarting deployments..."
    kubectl rollout restart deployment -n ${NAMESPACE}
    echo "✅ Deployments restarted"
fi
