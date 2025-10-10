# Deployment Guide for SummitLabs Helm Chart

This guide covers deploying the tool-server and langconnect services to Kubernetes using Helm and ArgoCD.

## Table of Contents
- [Prerequisites](#prerequisites)
- [Architecture Overview](#architecture-overview)
- [Local Development Setup](#local-development-setup)
- [Loading Local Images](#loading-local-images)
- [Deploying with Helm (Manual)](#deploying-with-helm-manual)
- [Deploying with ArgoCD](#deploying-with-argocd)
- [Testing the Deployment](#testing-the-deployment)
- [Troubleshooting](#troubleshooting)

## Prerequisites

- Kubernetes cluster (kind, minikube, or Docker Desktop)
- Helm 3.x installed
- ArgoCD installed (for GitOps deployment)
- kubectl configured to access your cluster
- Docker images built locally:
  - `tool-server:latest`
  - `langconnect:latest`

## Architecture Overview

### Services

1. **tool-server**
   - Port: 8000
   - Type: ClusterIP (exposed via Ingress)
   - External access via nginx ingress
   - Connects to langconnect internally

2. **langconnect**
   - Port: 8080
   - Type: ClusterIP (internal only)
   - Not exposed externally

### Communication Flow

```
External Request → Nginx Ingress → tool-server:8000 → langconnect:8080
```

The tool-server connects to langconnect using the internal Kubernetes DNS:
```
LANGCONNECT_URL=http://summitlabs-langconnect:8080
```

## Local Development Setup

### Install nginx-ingress-controller

If you don't have an nginx ingress controller installed:

```bash
# For kind
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

# For minikube
minikube addons enable ingress

# For Docker Desktop
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml
```

Wait for the ingress controller to be ready:
```bash
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=90s
```

### Configure /etc/hosts

Add the following to your `/etc/hosts` file:

```bash
# For kind or Docker Desktop
127.0.0.1 tool-server.prod.local
127.0.0.1 tool-server.staging.local

# For minikube
# Get minikube IP first: minikube ip
<MINIKUBE_IP> tool-server.prod.local
<MINIKUBE_IP> tool-server.staging.local
```

## Loading Local Images

### For kind

```bash
# Load images into kind cluster
kind load docker-image tool-server:latest
kind load docker-image langconnect:latest

# Verify images are loaded
docker exec -it kind-control-plane crictl images | grep -E 'tool-server|langconnect'
```

### For minikube

```bash
# Option 1: Use minikube's Docker daemon
eval $(minikube docker-env)
docker build -t tool-server:latest ./path/to/tool-server
docker build -t langconnect:latest ./path/to/langconnect

# Option 2: Load pre-built images
minikube image load tool-server:latest
minikube image load langconnect:latest

# Verify
minikube image list | grep -E 'tool-server|langconnect'
```

### For Docker Desktop

Images built locally are automatically available in Docker Desktop's Kubernetes cluster:

```bash
# Just build the images
docker build -t tool-server:latest ./path/to/tool-server
docker build -t langconnect:latest ./path/to/langconnect

# Verify
kubectl run test --image=tool-server:latest --image-pull-policy=Never --dry-run=client
```

## Deploying with Helm (Manual)

### Staging Environment

```bash
# Create namespace
kubectl create namespace summitlabs-staging

# Deploy using staging values
helm install summitlabs-staging . \
  --namespace summitlabs-staging \
  --values values-staging.yaml

# Check deployment status
kubectl get pods -n summitlabs-staging
kubectl get svc -n summitlabs-staging
kubectl get ingress -n summitlabs-staging
```

### Production Environment

```bash
# Create namespace
kubectl create namespace summitlabs-prod

# Deploy using production values
helm install summitlabs-prod . \
  --namespace summitlabs-prod \
  --values values-prod.yaml

# Check deployment status
kubectl get pods -n summitlabs-prod
kubectl get svc -n summitlabs-prod
kubectl get ingress -n summitlabs-prod
```

### Upgrade Existing Deployment

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

### Uninstall

```bash
helm uninstall summitlabs-staging -n summitlabs-staging
helm uninstall summitlabs-prod -n summitlabs-prod
```

## Deploying with ArgoCD

### 1. Install ArgoCD

```bash
# Create argocd namespace
kubectl create namespace argocd

# Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Port forward to access UI (optional)
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Access at: https://localhost:8080 (username: admin)
```

### 2. Configure Git Repository

**Option A: Using Local Git Repository**

If your Helm chart is in a local Git repository:

1. Push your chart to a Git repository:
   ```bash
   git init
   git add .
   git commit -m "Initial Helm chart"
   git remote add origin <your-git-repo-url>
   git push -u origin main
   ```

2. Update ArgoCD application manifests:
   - Edit `argocd/application-prod.yaml`
   - Edit `argocd/application-staging.yaml`
   - Replace `repoURL` with your Git repository URL

**Option B: Using Local Path (for testing)**

For local testing without Git, you can use a local path repository:

```bash
# Register local path with ArgoCD CLI
argocd repo add file:///path/to/your/chart --name local-chart
```

Then update the application YAML:
```yaml
source:
  repoURL: file:///path/to/summitlabs
  targetRevision: HEAD
  path: .
```

### 3. Deploy Applications with ArgoCD

```bash
# Apply staging application
kubectl apply -f argocd/application-staging.yaml

# Apply production application
kubectl apply -f argocd/application-prod.yaml

# Check application status
kubectl get applications -n argocd

# View details
kubectl describe application summitlabs-staging -n argocd
kubectl describe application summitlabs-prod -n argocd
```

### 4. Using ArgoCD CLI (Optional)

```bash
# Login to ArgoCD
argocd login localhost:8080

# List applications
argocd app list

# Get application details
argocd app get summitlabs-staging
argocd app get summitlabs-prod

# Manually sync
argocd app sync summitlabs-staging
argocd app sync summitlabs-prod

# View sync status
argocd app wait summitlabs-staging --health
argocd app wait summitlabs-prod --health
```

### 5. ArgoCD Auto-Sync

The applications are configured with auto-sync enabled:
- **prune: true** - Automatically delete resources removed from Git
- **selfHeal: true** - Automatically sync when cluster state differs from Git

To disable auto-sync, remove or modify the `syncPolicy.automated` section in the application YAML.

## Testing the Deployment

### 1. Check Pod Status

```bash
# Staging
kubectl get pods -n summitlabs-staging
kubectl logs -n summitlabs-staging -l app.kubernetes.io/component=tool-server
kubectl logs -n summitlabs-staging -l app.kubernetes.io/component=langconnect

# Production
kubectl get pods -n summitlabs-prod
kubectl logs -n summitlabs-prod -l app.kubernetes.io/component=tool-server
kubectl logs -n summitlabs-prod -l app.kubernetes.io/component=langconnect
```

### 2. Test External Access

```bash
# Staging
curl http://tool-server.staging.local/

# Production
curl http://tool-server.prod.local/
```

### 3. Test Internal Communication

Test that tool-server can reach langconnect:

```bash
# Exec into tool-server pod
kubectl exec -it -n summitlabs-staging deployment/summitlabs-staging-tool-server -- sh

# Inside the pod, test connection to langconnect
curl http://summitlabs-staging-langconnect:8080/health
# or
curl http://summitlabs-staging-langconnect:8080/

# Check environment variable
echo $LANGCONNECT_URL
```

### 4. Verify Service DNS Resolution

```bash
# Create a debug pod
kubectl run -it --rm debug --image=busybox --restart=Never -n summitlabs-staging -- sh

# Inside the pod
nslookup summitlabs-staging-langconnect
nslookup summitlabs-staging-tool-server
```

### 5. Check Ingress

```bash
# Get ingress details
kubectl get ingress -n summitlabs-staging
kubectl describe ingress summitlabs-staging-tool-server -n summitlabs-staging

kubectl get ingress -n summitlabs-prod
kubectl describe ingress summitlabs-prod-tool-server -n summitlabs-prod
```

### 6. Test with Port Forwarding (Alternative)

If ingress is not working, test directly via port forwarding:

```bash
# Forward tool-server port
kubectl port-forward -n summitlabs-staging svc/summitlabs-staging-tool-server 8000:8000

# In another terminal
curl http://localhost:8000/
```

## Troubleshooting

### Pods Not Starting

**Check ImagePullPolicy:**
```bash
kubectl describe pod <pod-name> -n <namespace>
```

Look for `ImagePullBackOff` errors. Ensure `imagePullPolicy: Never` is set for local images.

**Solution:**
```bash
# Update values file to set pullPolicy: Never
# Or update via Helm
helm upgrade summitlabs-staging . \
  --set toolServer.image.pullPolicy=Never \
  --set langconnect.image.pullPolicy=Never \
  -n summitlabs-staging
```

### Ingress Not Working

**Check ingress controller:**
```bash
kubectl get pods -n ingress-nginx
```

**Check ingress resource:**
```bash
kubectl get ingress -n summitlabs-staging
kubectl describe ingress summitlabs-staging-tool-server -n summitlabs-staging
```

**Check /etc/hosts:**
Ensure the hostname is mapped correctly.

### tool-server Can't Reach langconnect

**Check service:**
```bash
kubectl get svc -n summitlabs-staging
```

**Test DNS resolution:**
```bash
kubectl exec -it -n summitlabs-staging deployment/summitlabs-staging-tool-server -- nslookup summitlabs-staging-langconnect
```

**Check environment variable:**
```bash
kubectl exec -it -n summitlabs-staging deployment/summitlabs-staging-tool-server -- env | grep LANGCONNECT
```

### ArgoCD Application Not Syncing

**Check application status:**
```bash
kubectl get applications -n argocd
kubectl describe application summitlabs-staging -n argocd
```

**View ArgoCD logs:**
```bash
kubectl logs -n argocd deployment/argocd-application-controller
```

**Common issues:**
- Invalid Git repository URL
- Incorrect path to Helm chart
- Missing credentials for private repositories
- Helm values file not found

**Manual sync:**
```bash
argocd app sync summitlabs-staging --force
```

### Resource Limits Causing Crashes

**Check pod resources:**
```bash
kubectl top pods -n summitlabs-staging
kubectl describe pod <pod-name> -n summitlabs-staging
```

**Adjust resource limits:**
Edit `values-staging.yaml` or `values-prod.yaml` and increase limits:
```yaml
toolServer:
  resources:
    limits:
      cpu: 1000m
      memory: 1Gi
    requests:
      cpu: 500m
      memory: 512Mi
```

### Health Checks Failing

**Check probe configuration:**
```bash
kubectl describe pod <pod-name> -n <namespace>
```

**Disable probes temporarily:**
```yaml
toolServer:
  livenessProbe:
    enabled: false
  readinessProbe:
    enabled: false
```

**Update probe paths:**
Ensure the paths match your application's health endpoints:
```yaml
toolServer:
  livenessProbe:
    enabled: true
    path: /health  # or /healthz, /api/health, etc.
```

## Helm Commands Reference

```bash
# Validate template rendering
helm template summitlabs . --values values-staging.yaml

# Dry run
helm install summitlabs-staging . --dry-run --debug --values values-staging.yaml

# List releases
helm list -A

# Get release values
helm get values summitlabs-staging -n summitlabs-staging

# Rollback
helm rollback summitlabs-staging -n summitlabs-staging

# History
helm history summitlabs-staging -n summitlabs-staging
```

## Next Steps

1. **Enable TLS/HTTPS:**
   - Install cert-manager
   - Configure TLS in ingress
   - Update values files with TLS configuration

2. **Add Secrets Management:**
   - Use Kubernetes Secrets or External Secrets Operator
   - Configure secrets for API keys, credentials

3. **Monitoring and Logging:**
   - Install Prometheus and Grafana
   - Set up log aggregation (ELK, Loki)

4. **CI/CD Pipeline:**
   - Automate image builds
   - Push to container registry
   - Update image tags in ArgoCD

5. **Production Hardening:**
   - Network policies
   - Pod security policies
   - Resource quotas
   - RBAC configuration
