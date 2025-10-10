# PostgreSQL Configuration for LangConnect

This document explains the PostgreSQL setup required for the langconnect service.

## Overview

LangConnect is a RAG (Retrieval-Augmented Generation) service built with FastAPI and LangChain. It **requires** PostgreSQL with the pgvector extension to store document embeddings and perform vector similarity searches.

## Architecture

```
langconnect (FastAPI + LangChain)
    ↓
postgres:5432 (PostgreSQL 16 + pgvector)
    ↓
PersistentVolume (production only)
```

## Docker Compose Reference

The langconnect application was originally designed with Docker Compose using:

```yaml
services:
  postgres:
    image: pgvector/pgvector:pg16
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: postgres
    volumes:
      - postgres_data:/var/lib/postgresql/data

  api:
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      POSTGRES_HOST: postgres
      POSTGRES_PORT: 5432
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: postgres
```

## Kubernetes Implementation

The Helm chart recreates this setup in Kubernetes with the following components:

### 1. PostgreSQL Deployment

**File:** `templates/postgres-deployment.yaml`

- Image: `pgvector/pgvector:pg16`
- Strategy: `Recreate` (important for databases with persistent volumes)
- Single replica (PostgreSQL is not horizontally scalable without replication setup)
- Health checks: `pg_isready` command
- Persistent storage support (enabled in production)

### 2. PostgreSQL Service

**File:** `templates/postgres-service.yaml`

- Type: `ClusterIP` (internal only - not exposed externally)
- Port: 5432
- Service name pattern: `<release-name>-postgres`

### 3. PostgreSQL Secret

**File:** `templates/postgres-secret.yaml`

- Stores the PostgreSQL password
- Base64 encoded
- Referenced by both postgres and langconnect deployments

### 4. Persistent Volume Claim

**File:** `templates/postgres-pvc.yaml`

- Only created if `postgres.persistence.enabled: true`
- Default size: 8Gi (staging), 20Gi (production)
- Access mode: ReadWriteOnce
- Storage class: Uses cluster default (configurable)

## Environment Variables

### PostgreSQL Container

```yaml
- POSTGRES_USER: postgres
- POSTGRES_PASSWORD: <from secret>
- POSTGRES_DB: postgres
- PGDATA: /var/lib/postgresql/data/pgdata
```

### LangConnect Container

```yaml
- POSTGRES_HOST: <release-name>-postgres
- POSTGRES_PORT: "5432"
- POSTGRES_USER: postgres
- POSTGRES_PASSWORD: <from secret>
- POSTGRES_DB: postgres
```

## Configuration Options

### Staging Environment (`values-staging.yaml`)

```yaml
postgres:
  image:
    repository: pgvector/pgvector
    tag: pg16
    pullPolicy: IfNotPresent

  auth:
    username: postgres
    password: postgres-staging
    database: postgres

  persistence:
    enabled: false  # Uses emptyDir - data lost on restart

  resources:
    limits:
      cpu: 500m
      memory: 512Mi
    requests:
      cpu: 250m
      memory: 256Mi
```

**Key Points:**
- Persistence disabled (data is ephemeral)
- Lower resource allocation
- Suitable for testing and development

### Production Environment (`values-prod.yaml`)

```yaml
postgres:
  image:
    repository: pgvector/pgvector
    tag: pg16
    pullPolicy: IfNotPresent

  auth:
    username: postgres
    password: CHANGE_ME_IN_PRODUCTION  # ⚠️ MUST CHANGE!
    database: postgres

  persistence:
    enabled: true  # Uses PersistentVolumeClaim
    size: 20Gi
    storageClass: ""  # Uses default
    accessMode: ReadWriteOnce

  resources:
    limits:
      cpu: 1000m
      memory: 1Gi
    requests:
      cpu: 500m
      memory: 512Mi
```

**Key Points:**
- Persistence enabled with 20Gi storage
- Higher resource allocation
- **CRITICAL:** Change the default password!

## Security Considerations

### 🔒 Change Default Password

The default password is `postgres` which is **NOT SECURE** for production!

**Option 1: Update values file**
```yaml
postgres:
  auth:
    password: your-strong-password-here
```

**Option 2: Use Kubernetes Secret**

Create a secret manually:
```bash
kubectl create secret generic postgres-credentials \
  --from-literal=postgres-password=your-strong-password \
  -n <namespace>
```

Then update the templates to reference this secret instead.

**Option 3: Use External Secrets Operator**

For production, consider using:
- [External Secrets Operator](https://external-secrets.io/)
- [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets)
- Cloud provider secret managers (AWS Secrets Manager, GCP Secret Manager, etc.)

### Pod Security

The PostgreSQL deployment includes:

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 999  # postgres user
  fsGroup: 999
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - ALL
```

## Storage Persistence

### Staging (Ephemeral)

Uses `emptyDir`:
- ✅ Fast
- ✅ No storage provisioning needed
- ❌ Data lost when pod restarts
- ❌ Data lost when pod is deleted

**Use case:** Development, testing, CI/CD

### Production (Persistent)

Uses `PersistentVolumeClaim`:
- ✅ Data survives pod restarts
- ✅ Data survives pod deletion
- ✅ Can be backed up
- ❌ Requires storage provisioner
- ❌ Tied to availability zone (ReadWriteOnce)

**Important:** Ensure your cluster has a default storage class:
```bash
kubectl get storageclass
```

If not, specify one in values:
```yaml
postgres:
  persistence:
    storageClass: "your-storage-class"
```

## Health Checks

### Liveness Probe

Checks if PostgreSQL is running:
```bash
pg_isready -U postgres
```

- Initial delay: 30s
- Period: 10s
- Failure threshold: 6 (60s before restart)

### Readiness Probe

Checks if PostgreSQL is ready to accept connections:
```bash
pg_isready -U postgres
```

- Initial delay: 5s
- Period: 5s
- Failure threshold: 3

## Backup and Recovery

### Manual Backup

```bash
# Get postgres pod name
POSTGRES_POD=$(kubectl get pod -n <namespace> -l app.kubernetes.io/component=postgres -o jsonpath='{.items[0].metadata.name}')

# Create backup
kubectl exec -n <namespace> $POSTGRES_POD -- pg_dump -U postgres postgres > backup.sql

# Restore from backup
kubectl exec -i -n <namespace> $POSTGRES_POD -- psql -U postgres postgres < backup.sql
```

### Automated Backups

For production, consider:
- [Velero](https://velero.io/) for cluster-level backups
- [pg_dump with CronJob](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/)
- Cloud provider managed databases (RDS, Cloud SQL, etc.)

## Monitoring

### Connect to PostgreSQL

```bash
# Port forward
kubectl port-forward -n <namespace> svc/<release-name>-postgres 5432:5432

# Connect with psql
psql -h localhost -U postgres -d postgres
```

### Check Database Size

```sql
SELECT pg_size_pretty(pg_database_size('postgres'));
```

### Check pgvector Extension

```sql
SELECT * FROM pg_extension WHERE extname = 'vector';
```

### View Tables

```sql
\dt
```

## Troubleshooting

### Pod Not Starting

Check logs:
```bash
kubectl logs -n <namespace> -l app.kubernetes.io/component=postgres
```

Common issues:
- PVC not binding (check storage class)
- Permission issues (check fsGroup)
- Resource limits too low

### Connection Refused

Check service:
```bash
kubectl get svc -n <namespace> | grep postgres
```

Test from another pod:
```bash
kubectl run -it --rm debug --image=postgres:16 --restart=Never -n <namespace> -- \
  psql -h <release-name>-postgres -U postgres -d postgres
```

### Data Loss

If using emptyDir (staging):
- Expected behavior - data is ephemeral

If using PVC (production):
- Check PV status: `kubectl get pv`
- Check PVC status: `kubectl get pvc -n <namespace>`
- Check reclaim policy (should be `Retain` for production)

### langconnect Can't Connect

Check environment variables:
```bash
kubectl exec -n <namespace> deployment/<release-name>-langconnect -- env | grep POSTGRES
```

Expected output:
```
POSTGRES_HOST=<release-name>-postgres
POSTGRES_PORT=5432
POSTGRES_USER=postgres
POSTGRES_DB=postgres
POSTGRES_PASSWORD=<password>
```

Test connectivity:
```bash
kubectl exec -n <namespace> deployment/<release-name>-langconnect -- \
  nc -zv <release-name>-postgres 5432
```

## Migration from Docker Compose

If migrating existing data from Docker Compose:

1. **Export data from Docker Compose:**
   ```bash
   docker-compose exec postgres pg_dump -U postgres postgres > backup.sql
   ```

2. **Import to Kubernetes:**
   ```bash
   kubectl exec -i -n <namespace> <postgres-pod> -- psql -U postgres postgres < backup.sql
   ```

## Scaling Considerations

### Single Instance

Current setup runs a single PostgreSQL instance:
- ✅ Simple
- ✅ No replication complexity
- ❌ Single point of failure
- ❌ No read scaling

### Future Scaling Options

For production at scale, consider:

1. **Managed Services:**
   - AWS RDS PostgreSQL
   - Google Cloud SQL
   - Azure Database for PostgreSQL

2. **PostgreSQL Operators:**
   - [Zalando Postgres Operator](https://github.com/zalando/postgres-operator)
   - [Crunchy Data PGO](https://github.com/CrunchyData/postgres-operator)
   - [CloudNativePG](https://cloudnative-pg.io/)

3. **External PostgreSQL:**
   - Update langconnect to point to external instance
   - Remove postgres deployment from chart

## References

- [pgvector Documentation](https://github.com/pgvector/pgvector)
- [PostgreSQL on Kubernetes](https://www.postgresql.org/docs/current/)
- [LangChain PGVector Integration](https://python.langchain.com/docs/integrations/vectorstores/pgvector)
- [Kubernetes StatefulSets](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/) (alternative to Deployment)
