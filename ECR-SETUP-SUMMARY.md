# ECR Setup Summary

## Changes Made for AWS EKS Deployment

### 1. Updated Image Repositories

All values files now use ECR repositories:

**ECR Repository URLs:**
- `283174975792.dkr.ecr.us-west-2.amazonaws.com/summitlabs/tool-server`
- `283174975792.dkr.ecr.us-west-2.amazonaws.com/summitlabs/langconnect`
- `283174975792.dkr.ecr.us-west-2.amazonaws.com/summitlabs/web` (reserved for future use)

**Files Updated:**
- ✅ `values.yaml` - Base configuration with ECR URLs
- ✅ `values-staging.yaml` - Staging with `pullPolicy: Always`
- ✅ `values-prod.yaml` - Production with `pullPolicy: Always`

### 2. AWS-Specific Values Files Created

Two new environment-specific files for AWS EKS:

- **`values-aws-staging.yaml`** - Staging configuration for AWS
  - ECR image pull secret configured
  - EBS gp3 storage class for PostgreSQL
  - LoadBalancer ingress configuration
  - Domain: `tool-server.staging.summitlabs.io` (update as needed)

- **`values-aws-prod.yaml`** - Production configuration for AWS
  - ECR image pull secret configured
  - Secrets from Kubernetes secrets (not hardcoded)
  - HPA enabled
  - EBS gp3 storage with 20Gi
  - Domain: `tool-server.summitlabs.io` (update as needed)

### 3. Documentation Created

- **`AWS-DEPLOYMENT.md`** - Complete AWS EKS deployment guide
  - ECR authentication setup
  - Image push instructions
  - Kubernetes secret creation
  - Ingress and DNS configuration
  - TLS/SSL setup with cert-manager
  - Troubleshooting guide

- **`ECR-SETUP-SUMMARY.md`** - This file

### 4. Helper Scripts Created

- **`push-to-ecr.sh`** - Build and push images to ECR
  ```bash
  ./push-to-ecr.sh langconnect latest
  ./push-to-ecr.sh tool-server v1.2.3
  ./push-to-ecr.sh all latest
  ```

- **`refresh-ecr-secret.sh`** - Refresh ECR pull secret (tokens expire after 12 hours)
  ```bash
  ./refresh-ecr-secret.sh summitlabs-staging
  ./refresh-ecr-secret.sh summitlabs-prod
  ```

## Quick Deployment Steps

### 1. Push Images to ECR

```bash
# Authenticate
aws ecr get-login-password --region us-west-2 | \
  docker login --username AWS --password-stdin 283174975792.dkr.ecr.us-west-2.amazonaws.com

# Build and push langconnect
cd /Users/clintsmith/Development/langconnect/langconnect
docker build -t 283174975792.dkr.ecr.us-west-2.amazonaws.com/summitlabs/langconnect:latest .
docker push 283174975792.dkr.ecr.us-west-2.amazonaws.com/summitlabs/langconnect:latest

# Build and push tool-server (update path)
cd /path/to/tool-server
docker build -t 283174975792.dkr.ecr.us-west-2.amazonaws.com/summitlabs/tool-server:latest .
docker push 283174975792.dkr.ecr.us-west-2.amazonaws.com/summitlabs/tool-server:latest
```

### 2. Create Namespace and ECR Pull Secret

```bash
# Create namespace
kubectl create namespace summitlabs-staging

# Create ECR pull secret
kubectl create secret docker-registry ecr-pull-secret \
  --docker-server=283174975792.dkr.ecr.us-west-2.amazonaws.com \
  --docker-username=AWS \
  --docker-password=$(aws ecr get-login-password --region us-west-2) \
  -n summitlabs-staging
```

### 3. Deploy with Helm

```bash
helm install summitlabs-staging . \
  -f values-aws-staging.yaml \
  -n summitlabs-staging
```

### 4. Verify Deployment

```bash
kubectl get pods -n summitlabs-staging
kubectl get svc -n summitlabs-staging
kubectl get ingress -n summitlabs-staging
```

## Important Notes

### ECR Token Expiration

ECR authentication tokens expire after 12 hours. For production:

1. **Use IRSA (Recommended)**: IAM Roles for Service Accounts
   - No token expiration issues
   - Automatic authentication
   - See AWS-DEPLOYMENT.md for setup

2. **Use Cron Job**: Run `refresh-ecr-secret.sh` every 10 hours
   ```bash
   # Crontab example
   0 */10 * * * /path/to/refresh-ecr-secret.sh summitlabs-prod
   ```

3. **Use External Secrets Operator**: Sync from AWS Secrets Manager

### Storage Classes

The chart uses `gp3` storage class for PostgreSQL on AWS. Verify it exists:

```bash
kubectl get storageclass
```

If not available, update `values-aws-*.yaml` to use `gp2` or create gp3 storage class.

### Domain Names

Update the domain names in values files:
- `values-aws-staging.yaml`: Line 31, 42
- `values-aws-prod.yaml`: Line 25, 33

Current placeholders:
- Staging: `tool-server.staging.summitlabs.io`
- Production: `tool-server.summitlabs.io`

### Secrets Management

Production uses Kubernetes secrets for sensitive data. Create them before deploying:

```bash
kubectl create secret generic tool-server-secrets \
  --from-literal=tavily-api-key=YOUR_KEY \
  -n summitlabs-prod

kubectl create secret generic langconnect-secrets \
  --from-literal=openai-api-key=YOUR_KEY \
  --from-literal=supabase-url=YOUR_URL \
  --from-literal=supabase-key=YOUR_KEY \
  -n summitlabs-prod
```

## Web Service (Future)

The ECR repository for `summitlabs/web` is created but not yet used. When ready:

1. Create deployment and service templates
2. Add to values files
3. Update `push-to-ecr.sh` with correct path
4. Build and push image

## Rollback

If you need to rollback to local images (Docker Desktop):

```bash
helm upgrade summitlabs-staging . \
  -f values-staging.yaml \
  -n summitlabs-staging
```

Note: `values-staging.yaml` still references ECR. For truly local images, you'd need to:
1. Change `pullPolicy` back to `Never`
2. Change repository back to just `tool-server` and `langconnect`

## Next Steps

1. ✅ Push Docker images to ECR
2. ✅ Create ECR pull secret in EKS cluster
3. ✅ Deploy using `values-aws-staging.yaml`
4. ✅ Configure DNS for ingress LoadBalancer
5. ✅ Setup TLS certificates (cert-manager or manual)
6. ✅ Configure production secrets
7. ✅ Deploy production using `values-aws-prod.yaml`
8. ✅ Setup monitoring and logging (optional)
9. ✅ Configure IRSA for ECR authentication (recommended)
