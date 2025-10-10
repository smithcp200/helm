# EKS Quick Start - agentstudioapp.com

## TL;DR - One Command at a Time

```bash
# 1. Create cluster (15-20 min)
eksctl create cluster -f cluster/cluster.yaml

# 2. Install AWS Load Balancer Controller
helm repo add eks https://aws.github.io/eks-charts && helm repo update
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=summitlabs-prod \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller

# 3. Install ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 4. Get ArgoCD password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo

# 5. Install External DNS
helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/
helm install external-dns external-dns/external-dns \
  -n kube-system \
  --set serviceAccount.create=false \
  --set serviceAccount.name=external-dns \
  --set provider=aws \
  --set policy=sync \
  --set domainFilters[0]=agentstudioapp.com

# 6. Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
```

## What cluster.yaml Includes

✅ **OIDC Provider** - For IRSA (IAM Roles for Service Accounts)
✅ **Pre-configured IAM Service Accounts:**
  - aws-load-balancer-controller
  - external-dns
  - cert-manager
  - cluster-autoscaler

✅ **Managed Node Group:**
  - 2-6 t3.medium instances
  - Auto-scaling enabled
  - Private networking
  - EBS CSI driver

✅ **EKS Add-ons:**
  - VPC-CNI with network policies
  - CoreDNS
  - kube-proxy
  - AWS EBS CSI Driver

✅ **CloudWatch Logging** - Control plane logs enabled

## Key Modifications Made

| Original | Updated | Why |
|----------|---------|-----|
| Basic config | Full production config | Production-ready setup |
| No region | us-west-2 | AWS region specified |
| No IAM OIDC | OIDC enabled | For IRSA (secure, no static keys) |
| No service accounts | 4 service accounts | ALB, DNS, certs, autoscaling |
| Basic nodes | Managed node group | Auto-scaling, private subnets |
| No add-ons | 4 EKS add-ons | EBS, networking, DNS |
| No logging | CloudWatch enabled | Cluster monitoring |

## Suggested Ingress Hostnames

**Production:**
- Main app: `agentstudioapp.com` or `www.agentstudioapp.com`
- API: `api.agentstudioapp.com`
- ArgoCD: `argocd.agentstudioapp.com`

**Staging:**
- Main app: `staging.agentstudioapp.com`
- API: `api-staging.agentstudioapp.com`

## After Cluster is Ready

1. **Configure ArgoCD Ingress** - See EKS-SETUP-GUIDE.md Part 3.3
2. **Install cert-manager ClusterIssuer** - See EKS-SETUP-GUIDE.md Part 5.2
3. **Update Helm values** with agentstudioapp.com domains
4. **Deploy via ArgoCD** - See EKS-SETUP-GUIDE.md Part 8

## Verification Commands

```bash
# Cluster ready?
kubectl get nodes

# ALB controller ready?
kubectl get deployment -n kube-system aws-load-balancer-controller

# External DNS working?
kubectl logs -n kube-system -l app.kubernetes.io/name=external-dns

# Cert-manager ready?
kubectl get pods -n cert-manager

# View all ingresses
kubectl get ingress -A

# View certificates
kubectl get certificate -A
```

## Estimated Setup Time

- Cluster creation: **15-20 minutes**
- Install controllers: **5 minutes**
- DNS propagation: **1-5 minutes**
- SSL certificate: **2-5 minutes**
- **Total: ~25-35 minutes**

## Cost Estimate

**~$220-250/month** for the full production setup:
- EKS: $73/mo
- Nodes (2x t3.medium): $60/mo
- NAT Gateway: $65/mo
- ALB: $20/mo
- Storage: $3/mo

## Next Steps

1. Run `eksctl create cluster -f cluster/cluster.yaml`
2. Wait for completion
3. Follow EKS-SETUP-GUIDE.md for detailed setup
4. When ready, ping me and we'll configure ALB, SSL, and DNS together!
