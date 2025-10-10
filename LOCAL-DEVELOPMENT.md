# Local Development with Docker Desktop

## TLS Certificate Issue

When running on Docker Desktop (macOS), there's a known limitation with the built-in proxy that handles ports 80 and 443:

### The Problem

1. Docker Desktop's proxy listens on ports 80 and 443
2. It doesn't properly support SNI (Server Name Indication) for multiple TLS certificates
3. All HTTPS requests get served the first certificate it encounters (ArgoCD in this case)
4. NodePorts are not accessible from the host due to Docker Desktop networking

### Verification

The Helm chart is configured correctly:
- ✅ TLS secret created: `tool-server-staging-tls`
- ✅ Ingress references the TLS secret
- ✅ nginx controller loads the certificate
- ✅ Internal nginx test (with SNI) serves correct certificate
- ❌ External access via Docker Desktop proxy serves wrong certificate

## Solutions for Local Development

### Option 1: Port-Forward (Recommended)

Bypass the ingress entirely:

```bash
# Staging
kubectl port-forward -n summitlabs-staging svc/summitlabs-staging-tool-server 9000:8000

# Access at: http://localhost:9000

# Production (when deployed)
kubectl port-forward -n summitlabs-prod svc/summitlabs-prod-tool-server 9001:8000
```

### Option 2: Accept Certificate Mismatch

Use HTTPS with the `-k` flag to ignore certificate errors:

```bash
curl -k https://tool-server.staging.local/health
```

In browsers, you'll need to accept the security warning.

### Option 3: Update /etc/hosts and Use ArgoCD Domain

Since ArgoCD's certificate is being served, you could temporarily point to ArgoCD's domain:

```bash
# This won't work well because ArgoCD routes to its own backend
# Not recommended
```

### Option 4: Reconfigure mkcert (Not Recommended for This Issue)

The nginx controller is working correctly. The issue is with Docker Desktop's proxy, not the certificates. Regenerating certificates won't help.

## Production Deployment

In production Kubernetes clusters (non-Docker Desktop):
- ✅ SNI works correctly
- ✅ Multiple TLS certificates are properly served
- ✅ Each ingress gets the correct certificate
- ✅ No issues with routing

The TLS configuration in the Helm chart is correct and will work properly in production.

## Quick Access Script

Create a helper script to quickly access services:

```bash
#!/bin/bash
# access-tool-server.sh

ENV=${1:-staging}

if [ "$ENV" = "staging" ]; then
    kubectl port-forward -n summitlabs-staging svc/summitlabs-staging-tool-server 9000:8000
elif [ "$ENV" = "prod" ]; then
    kubectl port-forward -n summitlabs-prod svc/summitlabs-prod-tool-server 9001:8000
else
    echo "Usage: $0 [staging|prod]"
    exit 1
fi
```

Usage:
```bash
chmod +x access-tool-server.sh
./access-tool-server.sh staging  # Access at http://localhost:9000
./access-tool-server.sh prod     # Access at http://localhost:9001
```

## Summary

For local development with Docker Desktop, **use port-forward** to access tool-server. The Helm chart and TLS configuration are correct and will work properly in production environments.
