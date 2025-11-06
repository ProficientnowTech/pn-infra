# PostgreSQL Certificate Synchronization

## Overview

The Infisical deployment requires SSL/TLS connections to PostgreSQL. To avoid manual certificate management, we use an automated Kubernetes Job that dynamically extracts and patches the certificate on every ArgoCD sync.

## How It Works

### 1. Certificate Source
The PostgreSQL cluster (platform-db-cluster) managed by Zalando's PostgreSQL Operator automatically generates SSL certificates at:
```
/run/certs/server.crt  (inside postgres container)
```

### 2. Automated Sync Job
**File**: `cert-sync-job.yaml`

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: postgres-cert-sync
  namespace: infisical
  annotations:
    argocd.argoproj.io/hook: Sync
    argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
    argocd.argoproj.io/sync-wave: "-1"
```

**Key Points**:
- **Hook Type**: `Sync` - Runs on every ArgoCD sync (not just first time)
- **Sync Wave**: `-1` - Executes BEFORE main application resources
- **Delete Policy**: `BeforeHookCreation` - Old job deleted before creating new one
- **Trigger**: Every ArgoCD sync (manual or automatic via git push)

### 3. Cross-Namespace Access
The job needs to access resources in two namespaces:

**infisical namespace**:
- Read/patch the `infisical-secrets` secret

**platform-db-pg namespace**:
- Execute commands in `platform-db-cluster-0` pod to extract certificate

**RBAC Configuration**:
```yaml
# Role in infisical namespace
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "patch"]

# Role in platform-db-pg namespace
- apiGroups: [""]
  resources: ["pods/exec"]
  verbs: ["create"]
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get"]
```

### 4. Job Execution Flow

```bash
#!/bin/bash
set -e

# Extract certificate from PostgreSQL pod
CERT=$(kubectl exec platform-db-cluster-0 -n platform-db-pg \
  -c postgres -- cat /run/certs/server.crt | base64 -w 0)

# Validate extraction
if [ -z "$CERT" ]; then
  echo "ERROR: Failed to extract certificate"
  exit 1
fi

# Check if secret exists (graceful handling)
if ! kubectl get secret infisical-secrets -n infisical >/dev/null 2>&1; then
  echo "Secret infisical-secrets does not exist yet, skipping patch"
  exit 0
fi

# Patch the secret with base64-encoded certificate
kubectl patch secret infisical-secrets -n infisical \
  --type='json' \
  -p="[{\"op\":\"add\",\"path\":\"/data/DB_ROOT_CERT\",\"value\":\"$CERT\"}]"

echo "Certificate synced successfully!"
```

### 5. ArgoCD Drift Prevention

**Problem**: ArgoCD would normally detect the DB_ROOT_CERT field being modified by the job as "drift" from Git state.

**Solution**: Add annotations to the SealedSecret to ignore runtime changes:

```yaml
metadata:
  annotations:
    # Ignore runtime changes to secret fields
    argocd.argoproj.io/compare-options: IgnoreExtraneous
    # Don't delete the secret even if not in Git
    argocd.argoproj.io/sync-options: Prune=false
```

**Effect**:
- ArgoCD ignores fields added at runtime (like DB_ROOT_CERT)
- No "OutOfSync" status for certificate updates
- Secret won't be pruned if removed from Git temporarily
- Only fields in Git are compared for drift detection

## When Certificate Updates

The certificate is automatically refreshed in these scenarios:

1. **Manual ArgoCD Sync**: Click "Sync" button in ArgoCD UI
2. **Git Push**: ArgoCD auto-sync triggered by commit to main branch
3. **Periodic Refresh**: If ArgoCD auto-sync enabled with interval
4. **Hard Refresh**: ArgoCD "Hard Refresh" operation

## Certificate Lifecycle

```
PostgreSQL Operator
└── Generates SSL cert → /run/certs/server.crt
                             │
    ┌────────────────────────┘
    │
    ▼
ArgoCD Sync Triggered
    │
    ▼
postgres-cert-sync Job (wave: -1)
    │
    ├─→ Extract certificate from pod
    ├─→ Base64 encode
    └─→ Patch infisical-secrets/DB_ROOT_CERT
            │
            ▼
    Infisical Backend Pods
    └── Read DB_ROOT_CERT env var
        └── Establish SSL connection to PostgreSQL
```

## Why This Approach?

### Alternatives Considered

1. **Manual Certificate Management**
   - ❌ Requires manual extraction and base64 encoding
   - ❌ Must re-seal secret every time cert rotates
   - ❌ Not GitOps-friendly

2. **Certificate as ConfigMap + Volume Mount**
   - ❌ Infisical expects DB_ROOT_CERT as environment variable
   - ❌ Would require code changes to read from file
   - ❌ Documentation specifies base64-encoded env var

3. **Disable SSL Validation (sslmode=require without cert)**
   - ❌ PostgreSQL pooler requires SSL
   - ❌ Self-signed cert causes `DEPTH_ZERO_SELF_SIGNED_CERT` error
   - ❌ Security best practice violation

### Chosen Solution Benefits

✅ **Fully Automated**: No manual steps required
✅ **GitOps Compatible**: Works with ArgoCD sync workflow
✅ **Self-Healing**: Updates on every sync automatically
✅ **Certificate Rotation Safe**: Handles cert updates seamlessly
✅ **No Drift Detection**: ArgoCD ignores runtime changes
✅ **Secure**: Uses RBAC for least-privilege access
✅ **Idempotent**: Safe to run multiple times

## Troubleshooting

### Job Fails with "Failed to extract certificate"

**Check PostgreSQL pod status**:
```bash
kubectl get pod platform-db-cluster-0 -n platform-db-pg
```

**Verify certificate exists**:
```bash
kubectl exec platform-db-cluster-0 -n platform-db-pg -c postgres -- ls -la /run/certs/
```

### Job Fails with "Forbidden" Error

**Check RBAC permissions**:
```bash
kubectl auth can-i create pods/exec \
  --as=system:serviceaccount:infisical:cert-sync-job \
  -n platform-db-pg
```

**Expected**: `yes`

### Secret Not Getting Patched

**Check if secret exists**:
```bash
kubectl get secret infisical-secrets -n infisical
```

**View job logs**:
```bash
kubectl logs -n infisical -l job-name=postgres-cert-sync
```

### ArgoCD Shows "OutOfSync" for Secret

**Check annotations on SealedSecret**:
```bash
kubectl get sealedsecret infisical-secrets -n infisical -o yaml | grep -A2 annotations
```

**Should see**:
```yaml
annotations:
  argocd.argoproj.io/compare-options: IgnoreExtraneous
  argocd.argoproj.io/sync-options: Prune=false
```

## Updating the Secret

When you need to update other secret values (not DB_ROOT_CERT):

1. Edit `secrets/infisical-secrets.secret` with new values
2. Re-seal the secret:
   ```bash
   kubeseal --controller-name=sealed-secrets \
     --controller-namespace=sealed-secrets \
     -f v0.2.0/platform/charts/infisical/secrets/infisical-secrets.secret \
     -o yaml > v0.2.0/platform/charts/infisical/secrets/infisical-secrets-sealed.yaml
   ```
3. Commit and push the sealed secret
4. ArgoCD will sync and the job will re-add DB_ROOT_CERT automatically

**Important**: The annotations in the template ensure they're preserved after sealing:
```yaml
metadata:
  annotations:
    argocd.argoproj.io/compare-options: IgnoreExtraneous
    argocd.argoproj.io/sync-options: Prune=false
```

## Security Considerations

1. **Least Privilege**: Job ServiceAccount has minimal required permissions
2. **Namespace Isolation**: RBAC scoped to specific namespaces only
3. **Resource Name Restriction**: pods/exec only allowed for `platform-db-cluster-0`
4. **Base64 Encoding**: Certificate stored in Kubernetes secret (base64 by default)
5. **No Credential Exposure**: Job doesn't log certificate contents
6. **Job Cleanup**: Old jobs deleted automatically (BeforeHookCreation)

## References

- Infisical Configuration: https://infisical.com/docs/self-hosting/configuration/envars
- ArgoCD Resource Hooks: https://argo-cd.readthedocs.io/en/stable/user-guide/resource_hooks/
- ArgoCD Sync Options: https://argo-cd.readthedocs.io/en/stable/user-guide/sync-options/
- Kubernetes Jobs: https://kubernetes.io/docs/concepts/workloads/controllers/job/
