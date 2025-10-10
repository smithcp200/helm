# ACM Certificates for agentstudioapp.com

## Certificate ARNs

### Staging Environment
- **staging.agentstudioapp.com** (web frontend)
  - ARN: `arn:aws:acm:us-west-2:283174975792:certificate/e9438ffa-3d2d-4757-94b0-3c5d2d5cbe89`

- **api-staging.agentstudioapp.com** (tool-server API)
  - ARN: `arn:aws:acm:us-west-2:283174975792:certificate/eb84c55e-b5da-400c-a694-508dec57fa88`

### Production Environment
- **agentstudioapp.com** (web frontend)
  - ARN: `arn:aws:acm:us-west-2:283174975792:certificate/9bcd76de-f170-4074-ac33-af8e38ebb215`

- **api.agentstudioapp.com** (tool-server API)
  - ARN: `arn:aws:acm:us-west-2:283174975792:certificate/4bbed62a-de49-4a01-a248-26a369176fb7`

### ArgoCD
- **argocd.agentstudioapp.com**
  - ARN: `arn:aws:acm:us-west-2:283174975792:certificate/a2fa931e-3e18-433f-9e80-3bcdeda8cd66`
  - Status: ISSUED ✅

## DNS Validation

All DNS validation CNAME records have been created in Route 53 hosted zone `Z00966911O34MI57GT518`.

Certificates typically take 5-30 minutes to validate and reach ISSUED status.

## Adding Certificates to Ingress

Once certificates are ISSUED, add them to your Helm values files:

### Staging (values-aws-staging.yaml)
```yaml
toolServer:
  ingress:
    annotations:
      alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:us-west-2:283174975792:certificate/eb84c55e-b5da-400c-a694-508dec57fa88

web:
  ingress:
    annotations:
      alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:us-west-2:283174975792:certificate/e9438ffa-3d2d-4757-94b0-3c5d2d5cbe89
```

### Production (values-aws-prod.yaml)
```yaml
toolServer:
  ingress:
    annotations:
      alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:us-west-2:283174975792:certificate/4bbed62a-de49-4a01-a248-26a369176fb7

web:
  ingress:
    annotations:
      alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:us-west-2:283174975792:certificate/9bcd76de-f170-4074-ac33-af8e38ebb215
```

## Check Certificate Status

```bash
# Check all certificate statuses
aws acm list-certificates --region us-west-2 --query 'CertificateSummaryList[?DomainName==`agentstudioapp.com` || DomainName==`staging.agentstudioapp.com` || DomainName==`api.agentstudioapp.com` || DomainName==`api-staging.agentstudioapp.com` || DomainName==`argocd.agentstudioapp.com`].[DomainName,Status]' --output table

# Check specific certificate
aws acm describe-certificate --certificate-arn <ARN> --region us-west-2 --query 'Certificate.Status' --output text
```
