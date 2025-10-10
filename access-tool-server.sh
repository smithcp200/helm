#!/bin/bash
# Helper script to access tool-server locally via port-forward
# Bypasses Docker Desktop's TLS proxy issues

ENV=${1:-staging}

if [ "$ENV" = "staging" ]; then
    echo "🚀 Forwarding tool-server (staging) to http://localhost:9000"
    echo "Press Ctrl+C to stop"
    kubectl port-forward -n summitlabs-staging svc/summitlabs-staging-tool-server 9000:8000
elif [ "$ENV" = "prod" ]; then
    echo "🚀 Forwarding tool-server (prod) to http://localhost:9001"
    echo "Press Ctrl+C to stop"
    kubectl port-forward -n summitlabs-prod svc/summitlabs-prod-tool-server 9001:8000
else
    echo "Usage: $0 [staging|prod]"
    echo ""
    echo "Examples:"
    echo "  $0 staging  # Access at http://localhost:9000"
    echo "  $0 prod     # Access at http://localhost:9001"
    exit 1
fi
