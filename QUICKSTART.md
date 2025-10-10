# Quick Start Guide

## TL;DR - Get Running in 5 Minutes

**Note:** This chart deploys 3 services: tool-server, langconnect (RAG/FastAPI), and PostgreSQL with pgvector.

### 1. Load Local Images

**For kind:**
```bash
kind load docker-image tool-server:latest
kind load docker-image langconnect:latest
```

**For minikube:**
```bash
eval $(minikube docker-env)
docker build -t tool-server:latest ./path/to/tool-server
docker build -t langconnect:latest ./path/to/langconnect
```

**For Docker Desktop:**
```bash
# Images are already available - just build them
docker build -t tool-server:latest ./path/to/tool-server
docker build -t langconnect:latest ./path/to/langconnect

# Note: PostgreSQL image (pgvector/pgvector:pg16) will be pulled automatically
```

### 2. Install nginx-ingress

```bash
# For kind
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

# For minikube
minikube addons enable ingress

# For Docker Desktop
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml
```

### 3. Update /etc/hosts

```bash
echo "127.0.0.1 tool-server.staging.local tool-server.prod.local" | sudo tee -a /etc/hosts
```

### 4. Deploy Staging

```bash
helm install summitlabs-staging . \
  --namespace summitlabs-staging \
  --create-namespace \
  --values values-staging.yaml
```

### 5. Test It

```bash
# Wait for pods to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=tool-server -n summitlabs-staging --timeout=120s

# Test external access
curl http://tool-server.staging.local/

# Test internal communication
kubectl exec -n summitlabs-staging deployment/summitlabs-staging-tool-server -- curl http://summitlabs-staging-langconnect:8080/
```

## Deploy Production

```bash
helm install summitlabs-prod . \
  --namespace summitlabs-prod \
  --create-namespace \
  --values values-prod.yaml

# Test
curl http://tool-server.prod.local/
```

## Update/Upgrade

```bash
# Staging
helm upgrade summitlabs-staging . -n summitlabs-staging --values values-staging.yaml

# Production
helm upgrade summitlabs-prod . -n summitlabs-prod --values values-prod.yaml
```

## Cleanup

```bash
helm uninstall summitlabs-staging -n summitlabs-staging
helm uninstall summitlabs-prod -n summitlabs-prod
kubectl delete namespace summitlabs-staging summitlabs-prod
```

## ArgoCD Deployment

See [DEPLOYMENT.md](DEPLOYMENT.md) for full ArgoCD setup instructions.

Quick version:
```bash
# Install ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Update Git repo URL in argocd/application-*.yaml files
# Then apply
kubectl apply -f argocd/application-staging.yaml
kubectl apply -f argocd/application-prod.yaml
```

## Troubleshooting

**Pods not starting?**
```bash
kubectl describe pod <pod-name> -n <namespace>
```

**Ingress not working?**
```bash
kubectl get ingress -n <namespace>
kubectl describe ingress -n <namespace>
```

**Can't connect between services?**
```bash
kubectl exec -it -n <namespace> deployment/<deployment-name> -- nslookup <service-name>
```

For detailed troubleshooting, see [DEPLOYMENT.md](DEPLOYMENT.md).
