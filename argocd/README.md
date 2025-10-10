# ArgoCD Application Deployment

This directory contains ArgoCD Application manifests for deploying SummitLabs to Kubernetes.

## Prerequisites

1. **ArgoCD installed and accessible**: https://argocd.agentstudioapp.com
2. **Git repository** with Helm charts pushed
3. **ACM certificates validated** (check with `aws acm list-certificates --region us-west-2`)
4. **ECR pull secrets created** in namespaces

## Setup Steps

### 1. Create ECR Pull Secrets

Create the ECR pull secret in both staging and production namespaces:

```bash
# Staging namespace
kubectl create namespace summitlabs-staging
kubectl create secret docker-registry ecr-pull-secret \
  --docker-server=283174975792.dkr.ecr.us-west-2.amazonaws.com \
  --docker-username=AWS \
  --docker-password=$(aws ecr get-login-password --region us-west-2) \
  -n summitlabs-staging

# Production namespace
kubectl create namespace summitlabs-prod
kubectl create secret docker-registry ecr-pull-secret \
  --docker-server=283174975792.dkr.ecr.us-west-2.amazonaws.com \
  --docker-username=AWS \
  --docker-password=$(aws ecr get-login-password --region us-west-2) \
  -n summitlabs-prod
```

**Note**: ECR tokens expire after 12 hours. For production, consider using:
- [k8s-ecr-login-renew](https://github.com/nabsul/k8s-ecr-login-renew) to auto-renew tokens
- Or configure IRSA (IAM Roles for Service Accounts) to pull from ECR without secrets

### 2. Update Git Repository URL

Edit `staging-app.yaml` and `prod-app.yaml` to update the `repoURL` field with your Git repository:

```yaml
source:
  repoURL: https://github.com/yourusername/summitlabs-gitops.git  # UPDATE THIS
```

### 3. Push Helm Charts to Git

```bash
cd /Users/clintsmith/Development/summitlabs/gitops/summitlabs
git add .
git commit -m "Add Helm charts and ArgoCD manifests"
git push origin main
```

### 4. Deploy Applications via ArgoCD

```bash
# Deploy staging environment
kubectl apply -f argocd/staging-app.yaml

# Deploy production environment (when ready)
kubectl apply -f argocd/prod-app.yaml
```

### 5. Monitor Deployment

```bash
# Via kubectl
kubectl get applications -n argocd

# Via ArgoCD CLI
argocd app list
argocd app get summitlabs-staging
argocd app get summitlabs-prod

# Via ArgoCD UI
open https://argocd.agentstudioapp.com
```

## Certificate ARNs

Once ACM certificates are validated, they will be automatically used by the ALB ingress controller.

Check certificate status:
```bash
aws acm list-certificates --region us-west-2 --query 'CertificateSummaryList[?DomainName==`agentstudioapp.com` || DomainName==`staging.agentstudioapp.com` || DomainName==`api.agentstudioapp.com` || DomainName==`api-staging.agentstudioapp.com`].[DomainName,Status]' --output table
```

See `cluster/acm-certificates.md` for full certificate ARN list.

## Application URLs

### Staging
- Web Frontend: https://staging.agentstudioapp.com
- API (tool-server): https://api-staging.agentstudioapp.com

### Production
- Web Frontend: https://agentstudioapp.com
- API (tool-server): https://api.agentstudioapp.com

## Troubleshooting

### Application won't sync
```bash
# Check ArgoCD application status
argocd app get summitlabs-staging

# View sync errors
kubectl describe application summitlabs-staging -n argocd

# Manual sync
argocd app sync summitlabs-staging
```

### Pods won't start
```bash
# Check pods
kubectl get pods -n summitlabs-staging

# Check pod logs
kubectl logs -n summitlabs-staging <pod-name>

# Check events
kubectl get events -n summitlabs-staging --sort-by='.lastTimestamp'
```

### Image pull errors
```bash
# Verify ECR secret exists
kubectl get secret ecr-pull-secret -n summitlabs-staging

# Recreate ECR secret (tokens expire after 12 hours)
kubectl delete secret ecr-pull-secret -n summitlabs-staging
kubectl create secret docker-registry ecr-pull-secret \
  --docker-server=283174975792.dkr.ecr.us-west-2.amazonaws.com \
  --docker-username=AWS \
  --docker-password=$(aws ecr get-login-password --region us-west-2) \
  -n summitlabs-staging
```

### Ingress not working
```bash
# Check ingress
kubectl get ingress -n summitlabs-staging

# Check ALB controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Check external-dns logs
kubectl logs -n kube-system -l app.kubernetes.io/name=external-dns
```

## Auto-Sync Policy

Both applications are configured with automated sync:
- **prune: true** - Delete resources that are removed from Git
- **selfHeal: true** - Auto-revert manual changes
- **CreateNamespace: true** - Auto-create namespace if missing

To disable auto-sync temporarily:
```bash
argocd app set summitlabs-staging --sync-policy none
```

To re-enable:
```bash
argocd app set summitlabs-staging --sync-policy automated --auto-prune --self-heal
```
