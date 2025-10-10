#!/bin/bash
# Helper script to build and push Docker images to ECR

set -e

# ECR Configuration
AWS_REGION="us-west-2"
AWS_ACCOUNT_ID="283174975792"
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to authenticate with ECR
ecr_login() {
    print_info "Authenticating with ECR..."
    aws ecr get-login-password --region ${AWS_REGION} | \
        docker login --username AWS --password-stdin ${ECR_REGISTRY}
}

# Function to build and push an image
build_and_push() {
    local service=$1
    local dockerfile_path=$2
    local tag=${3:-latest}

    local image_name="${ECR_REGISTRY}/summitlabs/${service}:${tag}"

    print_info "Building ${service} image..."
    docker build -t ${image_name} ${dockerfile_path}

    print_info "Pushing ${service} to ECR..."
    docker push ${image_name}

    print_info "✅ Successfully pushed ${image_name}"
}

# Main script
case "${1}" in
    tool-server)
        ecr_login
        # Update this path to your tool-server directory
        build_and_push "tool-server" "/path/to/tool-server" "${2:-latest}"
        ;;

    langconnect)
        ecr_login
        build_and_push "langconnect" "/Users/clintsmith/Development/langconnect/langconnect" "${2:-latest}"
        ;;

    web)
        ecr_login
        # Update this path to your web frontend directory
        print_warn "Update the web service path in this script before running"
        build_and_push "web" "/path/to/web" "${2:-latest}"
        ;;

    all)
        ecr_login
        print_warn "Building all images (update paths in script first)"
        # Uncomment when paths are correct:
        # build_and_push "tool-server" "/path/to/tool-server" "${2:-latest}"
        build_and_push "langconnect" "/Users/clintsmith/Development/langconnect/langconnect" "${2:-latest}"
        # build_and_push "web" "/path/to/web" "${2:-latest}"
        ;;

    *)
        echo "Usage: $0 {tool-server|langconnect|web|all} [tag]"
        echo ""
        echo "Examples:"
        echo "  $0 tool-server latest    # Build and push tool-server:latest"
        echo "  $0 langconnect v1.2.3    # Build and push langconnect:v1.2.3"
        echo "  $0 all latest            # Build and push all images"
        echo ""
        echo "ECR Repositories:"
        echo "  - ${ECR_REGISTRY}/summitlabs/tool-server"
        echo "  - ${ECR_REGISTRY}/summitlabs/langconnect"
        echo "  - ${ECR_REGISTRY}/summitlabs/web"
        exit 1
        ;;
esac

print_info "Done! 🚀"
