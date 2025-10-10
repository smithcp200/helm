# Fixing "uv: executable file not found in $PATH" Error

## Problem

When deploying to Kubernetes, you get this error:
```
Error: failed to start container "tool-server": Error response from daemon:
failed to create task for container: failed to create shim task:
OCI runtime create failed: runc create failed: unable to start container process:
exec: "uv": executable file not found in $PATH: unknown
```

## Root Cause

The Helm chart configures pods to run as user `1000` (non-root) for security:

```yaml
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 1000
  fsGroup: 1000
```

However, the Dockerfile installs `uv` to `/root/.local/bin/` which is:
1. Only accessible to the root user
2. Not in the PATH when running as user 1000

## Solution 1: Fix the Dockerfile (Recommended)

### For tool-server

Update your tool-server Dockerfile to install `uv` system-wide:

```dockerfile
FROM python:3.12-slim-bookworm

# Install uv system-wide so it's available to all users
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl ca-certificates && \
    curl -LsSf https://astral.sh/uv/install.sh | sh && \
    mv /root/.local/bin/uv /usr/local/bin/uv && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

ENV UV_COMPILE_BYTECODE=1

# Copy the project into the image
ADD . /app
WORKDIR /app

# Sync the project - this creates a .venv directory
RUN uv sync --frozen

# Run the FastAPI application
CMD ["uv", "run", "uvicorn", "app.server:app", "--host", "0.0.0.0", "--port", "8000"]
```

**Key changes:**
- `mv /root/.local/bin/uv /usr/local/bin/uv` - Moves uv to a system-wide location
- `/usr/local/bin` is in the default PATH for all users

### For langconnect (if needed)

The langconnect Dockerfile uses `pip install` approach which works, but if you want to use `uv` there too:

```dockerfile
FROM python:3.11-slim

WORKDIR /app

# Install uv system-wide
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl ca-certificates gcc python3-dev libpq-dev && \
    curl -LsSf https://astral.sh/uv/install.sh | sh && \
    mv /root/.local/bin/uv /usr/local/bin/uv && \
    apt-get purge -y --auto-remove gcc python3-dev && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Copy requirements and code
COPY pyproject.toml uv.lock ./
COPY . .

# Install dependencies
RUN uv sync --frozen

# Expose port
EXPOSE 8080

# Run application
CMD ["uv", "run", "uvicorn", "langconnect.server:APP", "--host", "0.0.0.0", "--port", "8080"]
```

## Solution 2: Alternative Dockerfile Pattern

Use a multi-stage build that doesn't rely on `uv` in the final image:

```dockerfile
FROM python:3.12-slim-bookworm AS builder

# Install uv
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl ca-certificates && \
    curl -LsSf https://astral.sh/uv/install.sh | sh

ENV PATH="/root/.local/bin/:$PATH"

WORKDIR /app
COPY . .

# Build the application and create a virtualenv
RUN uv sync --frozen

# Runtime stage
FROM python:3.12-slim-bookworm

WORKDIR /app

# Copy the virtual environment from builder
COPY --from=builder /app/.venv /app/.venv
COPY --from=builder /app /app

# Use the virtual environment directly
ENV PATH="/app/.venv/bin:$PATH"

# Run without uv
CMD ["python", "-m", "uvicorn", "app.server:app", "--host", "0.0.0.0", "--port", "8000"]
```

**Advantages:**
- Smaller final image (no uv binary needed)
- Works with any user
- More secure

## Solution 3: Temporary Workaround (Testing Only)

If you need to test quickly, you can temporarily disable the security context:

### Update values-staging.yaml

```yaml
toolServer:
  podSecurityContext: {}  # Disable - runs as root
  securityContext: {}     # Disable
```

**⚠️ WARNING:** This runs the container as root. Only use for local testing!

## Rebuild and Deploy

After fixing the Dockerfile:

```bash
# 1. Navigate to tool-server directory
cd /path/to/tool-server

# 2. Rebuild the image
docker build -t tool-server:latest .

# 3. Load into cluster
cd /Users/clintsmith/Development/summitlabs/gitops/summitlabs
./load-images.sh

# 4. Delete existing deployment (if needed)
kubectl delete deployment -n summitlabs-staging summitlabs-staging-tool-server

# 5. Upgrade Helm release
helm upgrade summitlabs-staging . \
  --namespace summitlabs-staging \
  --values values-staging.yaml

# 6. Check logs
kubectl logs -n summitlabs-staging -l app.kubernetes.io/component=tool-server -f
```

## Verification

Check that the pod starts successfully:

```bash
# Get pod status
kubectl get pods -n summitlabs-staging -l app.kubernetes.io/component=tool-server

# Should show:
# NAME                                          READY   STATUS    RESTARTS   AGE
# summitlabs-staging-tool-server-xxxxx-xxxxx   1/1     Running   0          30s
```

Test that uv is accessible:

```bash
# Exec into the pod
kubectl exec -it -n summitlabs-staging deployment/summitlabs-staging-tool-server -- sh

# Inside the pod, check uv
which uv
# Should output: /usr/local/bin/uv

uv --version
# Should output version number
```

## Why This Happens

1. **Docker Build (as root):**
   - Dockerfile runs as root user
   - `uv` installed to `/root/.local/bin/`
   - Works fine in Docker because default user is root

2. **Kubernetes Deployment (as user 1000):**
   - Security context forces pod to run as user 1000
   - User 1000 cannot access `/root/` directory
   - `/root/.local/bin/uv` is not in PATH
   - Container fails to start

## Best Practice

**Always install system-wide tools in `/usr/local/bin`** when building Docker images that will run with security contexts in Kubernetes.

```dockerfile
# Good - system-wide installation
RUN curl ... | sh && mv /root/.local/bin/uv /usr/local/bin/uv

# Bad - only works for root user
RUN curl ... | sh  # Installs to /root/.local/bin/
```

## Related Security Settings

The Helm chart enforces these security best practices:

```yaml
podSecurityContext:
  runAsNonRoot: true    # Never run as root
  runAsUser: 1000       # Run as specific non-root user
  fsGroup: 1000         # File system group

securityContext:
  allowPrivilegeEscalation: false  # Prevent privilege escalation
  capabilities:
    drop:
      - ALL            # Drop all Linux capabilities
  readOnlyRootFilesystem: false    # Allow writes to container filesystem
```

These settings are recommended by:
- [Kubernetes Security Best Practices](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [OWASP Kubernetes Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Kubernetes_Security_Cheat_Sheet.html)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)

## Additional Resources

- [uv Installation Guide](https://github.com/astral-sh/uv#installation)
- [Kubernetes Security Context](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)
- [Docker Multi-stage Builds](https://docs.docker.com/build/building/multi-stage/)
