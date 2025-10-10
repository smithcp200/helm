#!/bin/bash
# Fix EKS add-ons to use pod identity associations

set -e

CLUSTER_NAME="summitlabs-prod"

echo "🔧 Updating EKS add-ons with pod identity associations..."

# Update vpc-cni addon
echo "Updating vpc-cni addon..."
eksctl update addon \
  --name vpc-cni \
  --cluster ${CLUSTER_NAME} \
  --force

# Update aws-ebs-csi-driver addon
echo "Updating aws-ebs-csi-driver addon..."
eksctl update addon \
  --name aws-ebs-csi-driver \
  --cluster ${CLUSTER_NAME} \
  --force

echo "✅ Add-ons updated successfully!"
echo ""
echo "Verify with:"
echo "  eksctl get addon --cluster ${CLUSTER_NAME} --region ${REGION}"
