# SummitLabs Helm Chart

A Helm chart for deploying tool-server and langconnect services to Kubernetes with ArgoCD support.

## Overview

This chart deploys four services:

- **web**: Frontend web application on port 80, exposed via nginx ingress (main user interface)
- **tool-server**: API backend service on port 8000, exposed via nginx ingress
- **langconnect**: Internal RAG/FastAPI service on port 8080, accessible only within the cluster
- **postgres**: PostgreSQL database with pgvector extension (required by langconnect)

### Architecture

```
Internet → Nginx Ingress → web:80 (frontend)
                         ↓
                         → tool-server:8000 (API backend) → langconnect:8080 (internal)
                                                                    ↓
                                                            postgres:5432 (pgvector)
```

## Features

- ✅ Separate deployments for web, tool-server, langconnect, and postgres
- ✅ Environment-specific configurations (prod/staging)
- ✅ Internal service communication via Kubernetes DNS
- ✅ Nginx ingress for external access
- ✅ Horizontal Pod Autoscaling support
- ✅ Health probes (liveness/readiness)
- ✅ Security contexts and pod security
- ✅ ArgoCD GitOps deployment support
- ✅ Local image support for development

## Quick Start

See [QUICKSTART.md](QUICKSTART.md) for a 5-minute setup guide.

## Documentation

- **[QUICKSTART.md](QUICKSTART.md)** - Get up and running quickly (local development)
- **[DEPLOYMENT.md](DEPLOYMENT.md)** - Complete deployment guide with troubleshooting
- **[AWS-DEPLOYMENT.md](AWS-DEPLOYMENT.md)** - AWS EKS deployment with ECR
- **[LOCAL-DEVELOPMENT.md](LOCAL-DEVELOPMENT.md)** - Docker Desktop local dev workarounds

## Prerequisites

### Local Development
- Kubernetes 1.19+ (kind/minikube/Docker Desktop)
- Helm 3.x
- nginx-ingress-controller installed
- Docker images: `tool-server:latest` and `langconnect:latest` (built locally)

### AWS EKS Deployment
- AWS EKS cluster
- AWS CLI configured
- ECR repositories created
- kubectl configured for EKS cluster
- Images pushed to ECR (see [AWS-DEPLOYMENT.md](AWS-DEPLOYMENT.md))

## Installation

### Staging Environment

```bash
helm install summitlabs-staging . \
  --namespace summitlabs-staging \
  --create-namespace \
  --values values-staging.yaml
```

### Production Environment

```bash
helm install summitlabs-prod . \
  --namespace summitlabs-prod \
  --create-namespace \
  --values values-prod.yaml
```

## Configuration

### Values Files

- `values.yaml` - Default values
- `values-staging.yaml` - Staging environment overrides
- `values-prod.yaml` - Production environment overrides

### Key Configuration Options

#### Tool Server

```yaml
toolServer:
  replicaCount: 3
  image:
    repository: tool-server
    tag: "latest"
    pullPolicy: Never
  service:
    port: 8000
  ingress:
    enabled: true
    className: nginx
    hosts:
      - host: tool-server.prod.local
  resources:
    limits:
      cpu: 1000m
      memory: 1Gi
```

#### LangConnect

```yaml
langconnect:
  replicaCount: 2
  image:
    repository: langconnect
    tag: "latest"
    pullPolicy: Never
  service:
    type: ClusterIP  # Internal only
    port: 8080
  resources:
    limits:
      cpu: 500m
      memory: 512Mi
```

## Service Communication

**tool-server → langconnect:**
- Environment variable: `LANGCONNECT_URL=http://summitlabs-langconnect:8080`
- Configured in `templates/tool-server-deployment.yaml:43-44`

**langconnect → postgres:**
- Connection via environment variables:
  - `POSTGRES_HOST=summitlabs-postgres`
  - `POSTGRES_PORT=5432`
  - `POSTGRES_USER=postgres`
  - `POSTGRES_PASSWORD` (from secret)
  - `POSTGRES_DB=postgres`
- Configured in `templates/langconnect-deployment.yaml:43-59`

## ArgoCD Deployment

ArgoCD application manifests are available in the `argocd/` directory:

- `argocd/application-staging.yaml` - Staging environment
- `argocd/application-prod.yaml` - Production environment

### Deploy with ArgoCD

```bash
# Update repoURL in application manifests
# Then apply
kubectl apply -f argocd/application-staging.yaml
kubectl apply -f argocd/application-prod.yaml
```

See [DEPLOYMENT.md](DEPLOYMENT.md#deploying-with-argocd) for complete ArgoCD setup.

## Local Development

### Load Images into Cluster

**kind:**
```bash
kind load docker-image tool-server:latest
kind load docker-image langconnect:latest
```

**minikube:**
```bash
eval $(minikube docker-env)
docker build -t tool-server:latest ./path/to/tool-server
docker build -t langconnect:latest ./path/to/langconnect
```

### Configure /etc/hosts

```bash
echo "127.0.0.1 tool-server.staging.local tool-server.prod.local" | sudo tee -a /etc/hosts
```

### Test Deployment

```bash
# Check pods
kubectl get pods -n summitlabs-staging

# Test external access
curl http://tool-server.staging.local/

# Test internal communication
kubectl exec -n summitlabs-staging \
  deployment/summitlabs-staging-tool-server -- \
  curl http://summitlabs-staging-langconnect:8080/
```

## Upgrading

```bash
# Staging
helm upgrade summitlabs-staging . \
  --namespace summitlabs-staging \
  --values values-staging.yaml

# Production
helm upgrade summitlabs-prod . \
  --namespace summitlabs-prod \
  --values values-prod.yaml
```

## Uninstalling

```bash
helm uninstall summitlabs-staging -n summitlabs-staging
helm uninstall summitlabs-prod -n summitlabs-prod
```

## Template Files

```
templates/
├── tool-server-deployment.yaml    # tool-server deployment
├── tool-server-service.yaml       # tool-server ClusterIP service
├── tool-server-ingress.yaml       # nginx ingress for external access
├── langconnect-deployment.yaml    # langconnect deployment
├── langconnect-service.yaml       # langconnect ClusterIP service (internal)
├── postgres-deployment.yaml       # postgres deployment (pgvector)
├── postgres-service.yaml          # postgres ClusterIP service (internal)
├── postgres-secret.yaml           # postgres password secret
├── postgres-pvc.yaml              # postgres persistent volume claim
├── serviceaccount.yaml            # shared service account
├── _helpers.tpl                   # template helpers
└── NOTES.txt                      # post-install notes
```

## Environment Differences

| Feature | Staging | Production |
|---------|---------|------------|
| tool-server replicas | 2 | 3 |
| langconnect replicas | 1 | 2 |
| HPA enabled | No | Yes |
| Resource limits | Lower | Higher |
| Hostname | tool-server.staging.local | tool-server.prod.local |

## Troubleshooting

See [DEPLOYMENT.md](DEPLOYMENT.md#troubleshooting) for detailed troubleshooting guide.

### Common Issues

**ImagePullBackOff:**
- Ensure images are loaded into cluster
- Verify `imagePullPolicy: Never` for local images

**Ingress not working:**
- Check nginx-ingress-controller is installed
- Verify /etc/hosts configuration
- Check ingress resource: `kubectl get ingress -n <namespace>`

**Service connection failures:**
- Test DNS: `kubectl exec -it <pod> -- nslookup <service-name>`
- Check environment variable: `kubectl exec -it <pod> -- env | grep LANGCONNECT`

## Contributing

1. Make changes to templates or values files
2. Test with `helm template` to validate:
   ```bash
   helm template summitlabs . --values values-staging.yaml
   ```
3. Deploy to staging first
4. Test thoroughly before production deployment

## License

[Your License Here]

## Support

For issues or questions, see [DEPLOYMENT.md](DEPLOYMENT.md) or open an issue.
