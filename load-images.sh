#!/bin/bash

# Script to load local Docker images into Kubernetes cluster
# Supports: kind, minikube, Docker Desktop

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

TOOL_SERVER_IMAGE="tool-server:latest"
LANGCONNECT_IMAGE="langconnect:latest"

echo "========================================="
echo "Load Local Images into Kubernetes"
echo "========================================="
echo

# Detect cluster type
function detect_cluster() {
    if kubectl config current-context | grep -q "kind"; then
        echo "kind"
    elif kubectl config current-context | grep -q "minikube"; then
        echo "minikube"
    elif kubectl config current-context | grep -q "docker-desktop"; then
        echo "docker-desktop"
    else
        echo "unknown"
    fi
}

CLUSTER_TYPE=$(detect_cluster)
echo -e "Detected cluster type: ${YELLOW}${CLUSTER_TYPE}${NC}"
echo

# Check if images exist locally
function check_image() {
    if docker image inspect $1 &> /dev/null; then
        echo -e "${GREEN}✓${NC} Image $1 exists locally"
        return 0
    else
        echo -e "${RED}✗${NC} Image $1 does not exist locally"
        return 1
    fi
}

echo "Checking local images..."
check_image ${TOOL_SERVER_IMAGE} || exit 1
check_image ${LANGCONNECT_IMAGE} || exit 1
echo

# Load images based on cluster type
case ${CLUSTER_TYPE} in
    kind)
        echo "Loading images into kind cluster..."
        kind load docker-image ${TOOL_SERVER_IMAGE}
        kind load docker-image ${LANGCONNECT_IMAGE}

        echo
        echo "Verifying images in kind..."
        docker exec -it kind-control-plane crictl images | grep -E 'tool-server|langconnect' || true
        ;;

    minikube)
        echo "Loading images into minikube..."
        minikube image load ${TOOL_SERVER_IMAGE}
        minikube image load ${LANGCONNECT_IMAGE}

        echo
        echo "Verifying images in minikube..."
        minikube image list | grep -E 'tool-server|langconnect' || true
        ;;

    docker-desktop)
        echo "Docker Desktop detected - images are already available!"
        echo "No need to load images explicitly for Docker Desktop."
        echo
        echo "Verifying images are accessible..."
        kubectl run test-image --image=${TOOL_SERVER_IMAGE} --image-pull-policy=Never --dry-run=client -o yaml > /dev/null && \
            echo -e "${GREEN}✓${NC} ${TOOL_SERVER_IMAGE} is accessible" || \
            echo -e "${RED}✗${NC} ${TOOL_SERVER_IMAGE} is NOT accessible"

        kubectl run test-image --image=${LANGCONNECT_IMAGE} --image-pull-policy=Never --dry-run=client -o yaml > /dev/null && \
            echo -e "${GREEN}✓${NC} ${LANGCONNECT_IMAGE} is accessible" || \
            echo -e "${RED}✗${NC} ${LANGCONNECT_IMAGE} is NOT accessible"
        ;;

    unknown)
        echo -e "${RED}Unable to detect cluster type!${NC}"
        echo "Current context: $(kubectl config current-context)"
        echo
        echo "Please load images manually:"
        echo "  - For kind: kind load docker-image <image>"
        echo "  - For minikube: minikube image load <image>"
        echo "  - For Docker Desktop: Images should be automatically available"
        exit 1
        ;;
esac

echo
echo "========================================="
echo -e "${GREEN}Images loaded successfully!${NC}"
echo "========================================="
echo
echo "You can now deploy with:"
echo "  helm install summitlabs-staging . \\"
echo "    --namespace summitlabs-staging \\"
echo "    --create-namespace \\"
echo "    --values values-staging.yaml"
