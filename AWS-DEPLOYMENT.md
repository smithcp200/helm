# AWS EKS Deployment Guide

This guide covers deploying the SummitLabs Helm chart to AWS EKS with ECR for container images.

## Prerequisites

1. **AWS CLI** configured with appropriate credentials
2. **kubectl** configured to connect to your EKS cluster
3. **helm** v3.x installed
4. **Docker images** built and pushed to ECR

## ECR Repositories

The following ECR repositories have been created:

- `283174975792.dkr.ecr.us-west-2.amazonaws.com/summitlabs/web` (frontend)
- `283174975792.dkr.ecr.us-west-2.amazonaws.com/summitlabs/tool-server` (API backend)
- `283174975792.dkr.ecr.us-west-2.amazonaws.com/summitlabs/langconnect` (RAG service)

## Step 1: Build and Push Docker Images

### Authenticate to ECR

```bash
aws ecr get-login-password --region us-west-2 | \
  docker login --username AWS --password-stdin 283174975792.dkr.ecr.us-west-2.amazonaws.com
```

### Web Frontend

```bash
cd /path/to/web
docker build -t 283174975792.dkr.ecr.us-west-2.amazonaws.com/summitlabs/web:latest .
docker push 283174975792.dkr.ecr.us-west-2.amazonaws.com/summitlabs/web:latest
```

### Tool Server

```bash
cd /path/to/tool-server
docker build -t 283174975792.dkr.ecr.us-west-2.amazonaws.com/summitlabs/tool-server:latest .
docker push 283174975792.dkr.ecr.us-west-2.amazonaws.com/summitlabs/tool-server:latest
```

### LangConnect

```bash
cd /Users/clintsmith/Development/langconnect/langconnect
docker build -t 283174975792.dkr.ecr.us-west-2.amazonaws.com/summitlabs/langconnect:latest .
docker push 283174975792.dkr.ecr.us-west-2.amazonaws.com/summitlabs/langconnect:latest
```

**Or use the helper script:**

```bash
./push-to-ecr.sh web latest
./push-to-ecr.sh tool-server latest
./push-to-ecr.sh langconnect latest
```

## Step 2: Create ECR Pull Secret

Kubernetes needs credentials to pull images from ECR. Create a docker-registry secret:

### For Staging

```bash
kubectl create namespace summitlabs-staging

kubectl create secret docker-registry ecr-pull-secret \
  --docker-server=283174975792.dkr.ecr.us-west-2.amazonaws.com \
  --docker-username=AWS \
  --docker-password=$(aws ecr get-login-password --region us-west-2) \
  -n summitlabs-staging
```

### For Production

```bash
kubectl create namespace summitlabs-prod

kubectl create secret docker-registry ecr-pull-secret \
  --docker-server=283174975792.dkr.ecr.us-west-2.amazonaws.com \
  --docker-username=AWS \
  --docker-password=$(aws ecr get-login-password --region us-west-2) \
  -n summitlabs-prod
```

**Note**: ECR tokens expire after 12 hours. For production, consider using:
- **IAM Roles for Service Accounts (IRSA)** - Recommended
- **AWS Secrets Manager** with External Secrets Operator
- **ECR credential helper** with a cron job to refresh tokens

## Step 3: Install NGINX Ingress Controller

If not already installed:

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer
```

Wait for the LoadBalancer to be provisioned:

```bash
kubectl get svc -n ingress-nginx ingress-nginx-controller --watch
```

## Step 4: Configure DNS

Get the LoadBalancer hostname:

```bash
kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

Create DNS records (in Route 53 or your DNS provider):

**Staging:**
- `web.staging.summitlabs.io` → CNAME to LoadBalancer hostname
- `tool-server.staging.summitlabs.io` → CNAME to LoadBalancer hostname

**Production:**
- `summitlabs.io` (or `www.summitlabs.io`) → CNAME to LoadBalancer hostname
- `tool-server.summitlabs.io` → CNAME to LoadBalancer hostname

## Step 5: Deploy with Helm

### Staging Deployment

```bash
helm install summitlabs-staging . \
  -f values-aws-staging.yaml \
  -n summitlabs-staging
```

Or if already installed:

```bash
helm upgrade summitlabs-staging . \
  -f values-aws-staging.yaml \
  -n summitlabs-staging
```

### Production Deployment

First, create secrets for production:

```bash
# Create API key secrets
kubectl create secret generic tool-server-secrets \
  --from-literal=tavily-api-key=YOUR_TAVILY_API_KEY \
  -n summitlabs-prod

kubectl create secret generic langconnect-secrets \
  --from-literal=openai-api-key=YOUR_OPENAI_API_KEY \
  --from-literal=supabase-url=YOUR_SUPABASE_URL \
  --from-literal=supabase-key=YOUR_SUPABASE_KEY \
  -n summitlabs-prod
```

Then deploy:

```bash
helm install summitlabs-prod . \
  -f values-aws-prod.yaml \
  -n summitlabs-prod
```

## Step 6: Configure TLS Certificates

### Option 1: cert-manager with Let's Encrypt (Recommended)

Install cert-manager:

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
```

Create ClusterIssuer:

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@summitlabs.io
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
```

The Ingress will automatically request certificates via annotations in the values files.

### Option 2: Manual Certificate

Upload your certificate to Kubernetes:

```bash
kubectl create secret tls tool-server-staging-tls \
  --cert=/path/to/cert.pem \
  --key=/path/to/key.pem \
  -n summitlabs-staging
```

## Step 7: Verify Deployment

```bash
# Check pods
kubectl get pods -n summitlabs-staging

# Check services
kubectl get svc -n summitlabs-staging

# Check ingress
kubectl get ingress -n summitlabs-staging

# Test health endpoint
curl https://tool-server.staging.summitlabs.io/health
```

## Storage Configuration

The Helm chart uses the `gp3` storage class for PostgreSQL persistence on AWS EKS. Ensure your cluster has this storage class:

```bash
kubectl get storageclass
```

If `gp3` doesn't exist, you can use `gp2` (default on EKS) or create a gp3 storage class:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  encrypted: "true"
volumeBindingMode: WaitForFirstConsumer
```

## IAM Roles for Service Accounts (IRSA)

For production, use IRSA instead of ECR pull secrets:

1. Create an IAM role with ECR pull permissions
2. Associate it with the service account
3. Update the service account annotation in values file:

```yaml
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::283174975792:role/summitlabs-role
```

## Updating Images

When you push new images to ECR:

```bash
# Build and push
docker build -t 283174975792.dkr.ecr.us-west-2.amazonaws.com/summitlabs/tool-server:v1.2.3 .
docker push 283174975792.dkr.ecr.us-west-2.amazonaws.com/summitlabs/tool-server:v1.2.3

# Update Helm release
helm upgrade summitlabs-staging . \
  -f values-aws-staging.yaml \
  --set toolServer.image.tag=v1.2.3 \
  -n summitlabs-staging
```

## Troubleshooting

### ImagePullBackOff errors

Check ECR authentication:

```bash
# Verify secret exists
kubectl get secret ecr-pull-secret -n summitlabs-staging

# Recreate if expired (tokens expire after 12 hours)
kubectl delete secret ecr-pull-secret -n summitlabs-staging
kubectl create secret docker-registry ecr-pull-secret \
  --docker-server=283174975792.dkr.ecr.us-west-2.amazonaws.com \
  --docker-username=AWS \
  --docker-password=$(aws ecr get-login-password --region us-west-2) \
  -n summitlabs-staging
```

### Pod CrashLoopBackOff

Check logs:

```bash
kubectl logs -n summitlabs-staging -l app.kubernetes.io/component=tool-server
kubectl logs -n summitlabs-staging -l app.kubernetes.io/component=langconnect
```

### Ingress not working

Check ingress controller:

```bash
kubectl get pods -n ingress-nginx
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller
```

## Cleanup

```bash
# Staging
helm uninstall summitlabs-staging -n summitlabs-staging
kubectl delete namespace summitlabs-staging

# Production
helm uninstall summitlabs-prod -n summitlabs-prod
kubectl delete namespace summitlabs-prod
```

## ArgoCD Deployment (GitOps)

For GitOps with ArgoCD, update the Application manifests:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: summitlabs-staging
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/gitops
    targetRevision: HEAD
    path: summitlabs
    helm:
      valueFiles:
        - values-aws-staging.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: summitlabs-staging
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

## Summary

- ✅ Images configured to pull from ECR
- ✅ Pull secrets documented
- ✅ AWS-specific values files created (values-aws-staging.yaml, values-aws-prod.yaml)
- ✅ Storage class configured for EBS gp3
- ✅ Ingress configured for AWS LoadBalancer
- ✅ Security best practices (IRSA, secrets management)
