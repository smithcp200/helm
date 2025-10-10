#!/bin/bash

# Test script for verifying SummitLabs Helm deployment
# Usage: ./test-deployment.sh [staging|prod]

set -e

ENVIRONMENT=${1:-staging}
NAMESPACE="summitlabs-${ENVIRONMENT}"

echo "========================================="
echo "Testing SummitLabs Deployment"
echo "Environment: ${ENVIRONMENT}"
echo "Namespace: ${NAMESPACE}"
echo "========================================="
echo

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

function check_command() {
    if command -v $1 &> /dev/null; then
        echo -e "${GREEN}✓${NC} $1 is installed"
    else
        echo -e "${RED}✗${NC} $1 is not installed"
        exit 1
    fi
}

function test_step() {
    echo -e "${YELLOW}Testing:${NC} $1"
}

function success() {
    echo -e "${GREEN}✓${NC} $1"
}

function failure() {
    echo -e "${RED}✗${NC} $1"
}

# Check prerequisites
echo "Checking prerequisites..."
check_command kubectl
check_command helm
echo

# Check namespace exists
test_step "Namespace exists"
if kubectl get namespace ${NAMESPACE} &> /dev/null; then
    success "Namespace ${NAMESPACE} exists"
else
    failure "Namespace ${NAMESPACE} does not exist"
    echo "Run: kubectl create namespace ${NAMESPACE}"
    exit 1
fi
echo

# Check deployments
test_step "Deployments are ready"
TOOL_SERVER_DEPLOY="${NAMESPACE}-tool-server"
LANGCONNECT_DEPLOY="${NAMESPACE}-langconnect"

if kubectl rollout status deployment/${TOOL_SERVER_DEPLOY} -n ${NAMESPACE} --timeout=60s &> /dev/null; then
    success "tool-server deployment is ready"
else
    failure "tool-server deployment is not ready"
fi

if kubectl rollout status deployment/${LANGCONNECT_DEPLOY} -n ${NAMESPACE} --timeout=60s &> /dev/null; then
    success "langconnect deployment is ready"
else
    failure "langconnect deployment is not ready"
fi
echo

# Check services
test_step "Services are available"
if kubectl get service ${TOOL_SERVER_DEPLOY} -n ${NAMESPACE} &> /dev/null; then
    success "tool-server service exists"
else
    failure "tool-server service does not exist"
fi

if kubectl get service ${LANGCONNECT_DEPLOY} -n ${NAMESPACE} &> /dev/null; then
    success "langconnect service exists"
else
    failure "langconnect service does not exist"
fi
echo

# Check ingress
test_step "Ingress is configured"
if kubectl get ingress ${TOOL_SERVER_DEPLOY} -n ${NAMESPACE} &> /dev/null; then
    success "tool-server ingress exists"
    INGRESS_HOST=$(kubectl get ingress ${TOOL_SERVER_DEPLOY} -n ${NAMESPACE} -o jsonpath='{.spec.rules[0].host}')
    echo "  Ingress host: ${INGRESS_HOST}"
else
    failure "tool-server ingress does not exist"
fi
echo

# Test DNS resolution inside cluster
test_step "Internal DNS resolution"
POD=$(kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/component=tool-server -o jsonpath='{.items[0].metadata.name}')

if [ -n "$POD" ]; then
    if kubectl exec -n ${NAMESPACE} ${POD} -- nslookup ${LANGCONNECT_DEPLOY} &> /dev/null; then
        success "langconnect service is resolvable from tool-server"
    else
        failure "langconnect service is NOT resolvable from tool-server"
    fi
else
    failure "No tool-server pod found"
fi
echo

# Test environment variable
test_step "Environment variables"
if [ -n "$POD" ]; then
    LANGCONNECT_URL=$(kubectl exec -n ${NAMESPACE} ${POD} -- env | grep LANGCONNECT_URL | cut -d'=' -f2)
    if [ -n "$LANGCONNECT_URL" ]; then
        success "LANGCONNECT_URL is set: ${LANGCONNECT_URL}"
    else
        failure "LANGCONNECT_URL is not set"
    fi
else
    failure "No tool-server pod found"
fi
echo

# Test internal connectivity
test_step "Internal service connectivity"
if [ -n "$POD" ]; then
    if kubectl exec -n ${NAMESPACE} ${POD} -- wget -q -O- ${LANGCONNECT_DEPLOY}:8080 --timeout=5 &> /dev/null; then
        success "tool-server can connect to langconnect"
    else
        failure "tool-server CANNOT connect to langconnect"
    fi
else
    failure "No tool-server pod found"
fi
echo

# Test external access (if ingress is configured)
test_step "External access via ingress"
if [ -n "$INGRESS_HOST" ]; then
    if curl -s -o /dev/null -w "%{http_code}" http://${INGRESS_HOST}/ --max-time 10 &> /dev/null; then
        success "Ingress is accessible at http://${INGRESS_HOST}/"
    else
        failure "Ingress is NOT accessible at http://${INGRESS_HOST}/"
        echo "  Make sure ${INGRESS_HOST} is in /etc/hosts"
    fi
fi
echo

# Pod resource usage
test_step "Pod resource usage"
echo "Tool Server pods:"
kubectl top pods -n ${NAMESPACE} -l app.kubernetes.io/component=tool-server 2>/dev/null || echo "  Metrics not available (metrics-server may not be installed)"
echo
echo "LangConnect pods:"
kubectl top pods -n ${NAMESPACE} -l app.kubernetes.io/component=langconnect 2>/dev/null || echo "  Metrics not available (metrics-server may not be installed)"
echo

# Summary
echo "========================================="
echo "Test Summary"
echo "========================================="
echo "Namespace: ${NAMESPACE}"
echo

kubectl get pods -n ${NAMESPACE}
echo

kubectl get svc -n ${NAMESPACE}
echo

kubectl get ingress -n ${NAMESPACE}
echo

echo "========================================="
echo "Testing complete!"
echo "========================================="
echo
echo "To view logs:"
echo "  kubectl logs -n ${NAMESPACE} -l app.kubernetes.io/component=tool-server"
echo "  kubectl logs -n ${NAMESPACE} -l app.kubernetes.io/component=langconnect"
echo
echo "To test external access:"
echo "  curl http://${INGRESS_HOST}/"
echo
echo "To exec into pod:"
echo "  kubectl exec -it -n ${NAMESPACE} ${POD} -- sh"
