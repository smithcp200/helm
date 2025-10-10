# EKS Cluster Setup Guide for agentstudioapp.com

This guide walks through setting up your EKS cluster with AWS Load Balancer, SSL certificates, and DNS configuration.

## Prerequisites

- AWS CLI configured with appropriate credentials
- eksctl installed (`brew install eksctl` on macOS)
- kubectl installed
- helm installed
- Domain: `agentstudioapp.com` configured in Route 53 (or your DNS provider)

## Part 1: Create EKS Cluster

### 1. Review and Customize cluster.yaml

Before creating the cluster, review `cluster/cluster.yaml` and customize:

**Key settings to verify:**
- **Region**: `us-west-2` (change if needed)
- **Cluster name**: `summitlabs-prod`
- **Kubernetes version**: `1.31`
- **Node instance type**: `t3.medium` (2 vCPU, 4GB RAM)
- **Node count**: 2-6 nodes (starts with 2)

**Important IAM Service Accounts pre-configured:**
- ✅ `aws-load-balancer-controller` - For ALB/NLB ingress
- ✅ `external-dns` - Automatic DNS record management
- ✅ `cert-manager` - SSL certificate automation
- ✅ `cluster-autoscaler` - Auto-scaling nodes

### 2. Create the Cluster

```bash
cd /Users/clintsmith/Development/summitlabs/gitops/summitlabs/cluster

# Dry run to validate config
eksctl create cluster -f cluster.yaml --dry-run

# Create the cluster (takes 15-20 minutes)
eksctl create cluster -f cluster.yaml
```

**What this creates:**
- EKS control plane (Kubernetes 1.31)
- New VPC with public/private subnets across 3 AZs
- Managed node group with 2 t3.medium instances
- OIDC provider for IRSA
- IAM roles for service accounts
- EKS add-ons (VPC-CNI, CoreDNS, kube-proxy, EBS CSI)
- CloudWatch logging for control plane

### 3. Verify Cluster

```bash
# Update kubeconfig
aws eks update-kubeconfig --region us-west-2 --name summitlabs-prod

# Verify nodes
kubectl get nodes

# Verify add-ons
eksctl get addon --cluster summitlabs-prod --region us-west-2

# Verify OIDC provider
eksctl utils associate-iam-oidc-provider --cluster summitlabs-prod --region us-west-2 --approve
```

## Part 2: Install AWS Load Balancer Controller

The AWS Load Balancer Controller manages ALB and NLB for Kubernetes Ingress resources.

### 1. Install AWS Load Balancer Controller

```bash
# Add EKS Helm repo
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Install AWS Load Balancer Controller
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=summitlabs-prod \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

### 2. Verify Installation

```bash
kubectl get deployment -n kube-system aws-load-balancer-controller
kubectl logs -n kube-system deployment/aws-load-balancer-controller
```

## Part 3: Install ArgoCD

### 1. Install ArgoCD

```bash
# Create namespace
kubectl create namespace argocd

# Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for pods to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s
```

### 2. Get Initial Admin Password

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo
```

### 3. Create Ingress for ArgoCD

Create `argocd-ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-ingress
  namespace: argocd
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/backend-protocol: HTTPS
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
    alb.ingress.kubernetes.io/ssl-redirect: '443'
    # Add after cert-manager is installed:
    # cert-manager.io/cluster-issuer: letsencrypt-prod
    # alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:us-west-2:ACCOUNT:certificate/CERT_ID
spec:
  ingressClassName: alb
  rules:
  - host: argocd.agentstudioapp.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 443
```

Apply it:
```bash
kubectl apply -f argocd-ingress.yaml
```

### 4. Get Load Balancer DNS

```bash
kubectl get ingress -n argocd argocd-server-ingress
```

Look for the ADDRESS column - this is your ALB DNS name (e.g., `k8s-argocd-argocdse-xxx.us-west-2.elb.amazonaws.com`)

## Part 4: Install External DNS

External DNS automatically creates Route 53 records for your Ingress resources.

### 1. Install External DNS

```bash
helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/
helm repo update

helm install external-dns external-dns/external-dns \
  -n kube-system \
  --set serviceAccount.create=false \
  --set serviceAccount.name=external-dns \
  --set provider=aws \
  --set policy=sync \
  --set registry=txt \
  --set txtOwnerId=summitlabs-prod \
  --set domainFilters[0]=agentstudioapp.com
```

### 2. Verify External DNS

```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=external-dns
```

External DNS will automatically create Route 53 records for any Ingress with a hostname.

## Part 5: Install cert-manager for SSL

### 1. Install cert-manager

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Wait for cert-manager to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=300s
```

### 2. Create Let's Encrypt ClusterIssuer

Create `letsencrypt-prod.yaml`:

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@agentstudioapp.com  # Change this
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: alb
```

Apply it:
```bash
kubectl apply -f letsencrypt-prod.yaml
```

### 3. Request Certificate for ArgoCD

Update the ArgoCD ingress to use cert-manager:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-ingress
  namespace: argocd
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/backend-protocol: HTTPS
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
    alb.ingress.kubernetes.io/ssl-redirect: '443'
    cert-manager.io/cluster-issuer: letsencrypt-prod  # Add this
spec:
  ingressClassName: alb
  tls:  # Add this section
  - hosts:
    - argocd.agentstudioapp.com
    secretName: argocd-tls
  rules:
  - host: argocd.agentstudioapp.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 443
```

### 4. Verify Certificate

```bash
kubectl get certificate -n argocd
kubectl describe certificate argocd-tls -n argocd
```

## Part 6: Configure DNS

### Option A: Automatic (with External DNS)

External DNS should automatically create Route 53 records. Verify:

```bash
# Check External DNS logs
kubectl logs -n kube-system -l app.kubernetes.io/name=external-dns

# Verify Route 53 record created
aws route53 list-resource-record-sets \
  --hosted-zone-id YOUR_HOSTED_ZONE_ID \
  --query "ResourceRecordSets[?Name=='argocd.agentstudioapp.com.']"
```

### Option B: Manual (if External DNS not used)

1. Get ALB DNS name:
   ```bash
   kubectl get ingress -n argocd argocd-server-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
   ```

2. Create Route 53 CNAME record:
   - Go to Route 53 console
   - Select hosted zone for `agentstudioapp.com`
   - Create record:
     - Name: `argocd`
     - Type: `CNAME`
     - Value: `[ALB DNS name from step 1]`

## Part 7: Access ArgoCD

Once DNS propagates (1-5 minutes):

```bash
# Open in browser
open https://argocd.agentstudioapp.com

# Login:
# Username: admin
# Password: [from step 3.2]
```

## Part 8: Deploy Your Applications

### Update Helm Values for Production

Update your Helm values files to use `agentstudioapp.com`:

**values-aws-staging.yaml:**
```yaml
web:
  ingress:
    hosts:
      - host: staging.agentstudioapp.com
    tls:
      - secretName: web-staging-tls
        hosts:
          - staging.agentstudioapp.com

toolServer:
  ingress:
    hosts:
      - host: api-staging.agentstudioapp.com
    tls:
      - secretName: api-staging-tls
        hosts:
          - api-staging.agentstudioapp.com
```

**values-aws-prod.yaml:**
```yaml
web:
  ingress:
    hosts:
      - host: agentstudioapp.com
    tls:
      - secretName: web-prod-tls
        hosts:
          - agentstudioapp.com

toolServer:
  ingress:
    hosts:
      - host: api.agentstudioapp.com
    tls:
      - secretName: api-prod-tls
        hosts:
          - api.agentstudioapp.com
```

### Create ArgoCD Application

Create `argocd/application-prod.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: summitlabs-prod
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/gitops  # Update this
    targetRevision: HEAD
    path: summitlabs
    helm:
      valueFiles:
        - values-aws-prod.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: summitlabs-prod
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

Apply:
```bash
kubectl apply -f argocd/application-prod.yaml
```

## Summary Checklist

- ✅ EKS cluster created with eksctl
- ✅ AWS Load Balancer Controller installed
- ✅ ArgoCD installed and accessible
- ✅ External DNS configured for automatic DNS updates
- ✅ cert-manager configured for SSL certificates
- ✅ DNS records pointing to ALB
- ✅ SSL certificates issued by Let's Encrypt
- ✅ Applications deployed via ArgoCD

## Useful Commands

```bash
# View all ingresses
kubectl get ingress -A

# Get ALB info
kubectl describe ingress -n argocd argocd-server-ingress

# View certificates
kubectl get certificate -A

# Check External DNS logs
kubectl logs -n kube-system -l app.kubernetes.io/name=external-dns -f

# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager -f

# Delete cluster (when done testing)
eksctl delete cluster -f cluster.yaml
```

## Estimated Costs

**Monthly costs (us-west-2):**
- EKS control plane: $73/month
- 2 x t3.medium nodes: ~$60/month
- NAT Gateway (HA): ~$65/month
- ALB: ~$20/month
- EBS volumes: ~$3/month
- **Total: ~$220-250/month**

**Cost optimization tips:**
- Use Spot instances for non-critical workloads
- Enable cluster autoscaler to scale down during low usage
- Use single NAT gateway instead of HA for non-production
- Consider Fargate for serverless option
