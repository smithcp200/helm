# Web Service Addition Summary

## Overview

A new **web frontend service** has been added to the SummitLabs Helm chart. The web service serves as the main user interface and is exposed via nginx ingress.

## What Was Added

### 1. Kubernetes Templates

- **`templates/web-deployment.yaml`** - Deployment manifest for the web frontend
  - Configurable replicas, resources, autoscaling
  - Security contexts (runs as user 1000, non-root)
  - Health probes (liveness and readiness)
  - Environment variable injection (including TOOL_SERVER_URL, LANGCONNECT_URL)

- **`templates/web-service.yaml`** - ClusterIP service on port 80
  - Routes traffic to web pods on container port 3000

- **`templates/web-ingress.yaml`** - Ingress for external access
  - Nginx ingress controller support
  - TLS/SSL configuration
  - Host-based routing

### 2. Configuration Added to Values Files

All values files now include web service configuration:

#### `values.yaml` (base)
```yaml
web:
  replicaCount: 1
  image:
    repository: 283174975792.dkr.ecr.us-west-2.amazonaws.com/summitlabs/web
    pullPolicy: IfNotPresent
    tag: "latest"
  containerPort: 3000
  service:
    type: ClusterIP
    port: 80
  ingress:
    enabled: false
  # ... plus resources, probes, security context, env vars
```

#### `values-staging.yaml`
- 2 replicas
- Ingress enabled: `web.staging.local`
- Environment: `NEXT_PUBLIC_API_URL=http://tool-server.staging.local`

#### `values-prod.yaml`
- 3 replicas
- Ingress enabled: `web.prod.local`
- HPA enabled (3-10 replicas)
- Production resources (1Gi memory limit)

#### `values-aws-staging.yaml`
- AWS ECR repository
- Domain: `web.staging.summitlabs.io`
- EKS-optimized configuration

#### `values-aws-prod.yaml`
- AWS ECR repository
- Domain: `summitlabs.io` (root domain)
- Production-grade settings

### 3. Documentation Updates

- **`README.md`** - Updated architecture diagram and service list
- **`AWS-DEPLOYMENT.md`** - Added web service deployment instructions
- **`templates/NOTES.txt`** - Updated to show web service access info
- **`push-to-ecr.sh`** - Added web service build/push support

## Architecture

The updated architecture is:

```
Internet → Nginx Ingress → web:80 (frontend)
                         ↓
                         → tool-server:8000 (API backend) → langconnect:8080 (internal)
                                                                    ↓
                                                            postgres:5432 (pgvector)
```

## Service Communication

The web service can communicate with backend services via:

1. **Tool Server** - Environment variable `TOOL_SERVER_URL` points to tool-server service
2. **LangConnect** - Environment variable `LANGCONNECT_URL` points to langconnect service (optional)

These are automatically configured in the deployment template.

## Container Port

The web service is configured to run on **port 3000** (common for Next.js, React, etc.) and is exposed via service on **port 80**.

If your web app runs on a different port, update `web.containerPort` in the values files.

## Environment Variables

Default environment variables configured for web service:

- **`TOOL_SERVER_URL`** - Automatically set to tool-server service URL
- **`LANGCONNECT_URL`** - Automatically set to langconnect service URL
- **`NEXT_PUBLIC_API_URL`** - Set to public tool-server URL (for client-side calls)
- **`NODE_ENV`** - Set to "development" (staging) or "production" (prod)

Additional env vars can be added via `web.env` in values files.

## Ingress Configuration

### Local Development (Docker Desktop)
- Host: `web.staging.local`
- Add to `/etc/hosts`: `127.0.0.1 web.staging.local`
- TLS: `web-staging-tls` secret (create with mkcert if needed)

### AWS EKS
- Staging: `web.staging.summitlabs.io`
- Production: `summitlabs.io`
- DNS: Create CNAME records pointing to LoadBalancer
- TLS: Auto-provision with cert-manager or manual upload

## Building and Deploying

### 1. Build Web Image

```bash
cd /path/to/web
docker build -t 283174975792.dkr.ecr.us-west-2.amazonaws.com/summitlabs/web:latest .
```

### 2. Push to ECR

```bash
# Using helper script
./push-to-ecr.sh web latest

# Or manually
aws ecr get-login-password --region us-west-2 | \
  docker login --username AWS --password-stdin 283174975792.dkr.ecr.us-west-2.amazonaws.com
docker push 283174975792.dkr.ecr.us-west-2.amazonaws.com/summitlabs/web:latest
```

### 3. Deploy with Helm

```bash
# Staging (AWS)
helm upgrade summitlabs-staging . \
  -f values-aws-staging.yaml \
  -n summitlabs-staging

# Production (AWS)
helm upgrade summitlabs-prod . \
  -f values-aws-prod.yaml \
  -n summitlabs-prod
```

### 4. Create TLS Certificate (if needed)

For AWS with cert-manager:
- Certificate will be auto-provisioned if `cert-manager.io/cluster-issuer` annotation is set
- See AWS-DEPLOYMENT.md for cert-manager setup

For manual TLS:
```bash
kubectl create secret tls web-staging-tls \
  --cert=/path/to/cert.pem \
  --key=/path/to/key.pem \
  -n summitlabs-staging
```

## Verifying Deployment

```bash
# Check pods
kubectl get pods -n summitlabs-staging -l app.kubernetes.io/component=web

# Check service
kubectl get svc -n summitlabs-staging | grep web

# Check ingress
kubectl get ingress -n summitlabs-staging | grep web

# View logs
kubectl logs -n summitlabs-staging -l app.kubernetes.io/component=web

# Test access
curl https://web.staging.summitlabs.io
```

## Customization

### Change Container Port

If your web app runs on a different port (e.g., 8080), update values:

```yaml
web:
  containerPort: 8080  # Change from 3000
```

### Add Custom Environment Variables

```yaml
web:
  env:
  - name: CUSTOM_VAR
    value: "custom-value"
  - name: SECRET_VAR
    valueFrom:
      secretKeyRef:
        name: web-secrets
        key: secret-key
```

### Enable Autoscaling

```yaml
web:
  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 10
    targetCPUUtilizationPercentage: 70
```

### Adjust Resources

```yaml
web:
  resources:
    limits:
      cpu: 2000m
      memory: 2Gi
    requests:
      cpu: 1000m
      memory: 1Gi
```

## Troubleshooting

### Pod Not Starting

Check logs:
```bash
kubectl logs -n summitlabs-staging -l app.kubernetes.io/component=web
```

Common issues:
- Port mismatch (containerPort vs actual app port)
- Missing environment variables
- Image pull errors (check ECR authentication)

### Ingress Not Working

Check ingress:
```bash
kubectl describe ingress -n summitlabs-staging | grep web
```

Verify:
- DNS is configured correctly
- TLS secret exists
- Nginx ingress controller is running

### Can't Connect to Backend Services

The web pod should be able to reach:
- `summitlabs-staging-tool-server:8000` (or whatever the service name is)
- `summitlabs-staging-langconnect:8080`

Test from inside pod:
```bash
kubectl exec -n summitlabs-staging deployment/summitlabs-staging-web -- \
  curl http://summitlabs-staging-tool-server:8000/health
```

## Summary

✅ Web service templates created
✅ All values files updated with web configuration
✅ Ingress configured for external access
✅ ECR repository ready (`summitlabs/web`)
✅ Documentation updated
✅ Helper scripts updated

The web service is fully integrated into the Helm chart and ready to deploy once the Docker image is built and pushed to ECR.
