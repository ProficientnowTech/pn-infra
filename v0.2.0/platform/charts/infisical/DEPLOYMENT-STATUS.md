# Infisical Deployment Status

## Overview
Infisical secret management platform configured for deployment with external PostgreSQL (platform-db) and Redis (platform-kv) integration.

## Completed Configuration

### 1. Chart Structure
- **Chart**: Infisical v0.4.2 (official Helm chart)
- **Namespace**: infisical
- **URL**: https://secrets.pnats.cloud
- **Backend replicas**: 2
- **Sync Wave**: 300 (after databases and Redis)

### 2. External Dependencies
- **PostgreSQL**: platform-db-cluster (Zalando operator managed)
  - Connection: Via PGBouncer pooler (platform-db-cluster-pooler)
  - SSL: Enabled with certificate auto-sync
  - Database: infisical
  - User: infisical_user

- **Redis**: platform-kv-sentinel (Redis Sentinel)
  - Connection: Sentinel mode for HA
  - Master: platform-kv-master
  - Service: platform-kv-sentinel-sentinel.platform-kv-redis-cluster.svc.cluster.local:26379

### 3. Key Features Configured

#### Dynamic SSL Certificate Management
- **Job**: cert-sync-job.yaml
- **Type**: Kubernetes Job with ArgoCD Sync hook (sync-wave: -1)
- **Trigger**: Runs on every ArgoCD sync to refresh certificate
- **Function**:
  - Extracts PostgreSQL SSL certificate from platform-db-cluster-0
  - Base64 encodes certificate
  - Patches infisical-secrets with DB_ROOT_CERT
- **RBAC**: Cross-namespace access (infisical → platform-db-pg)
- **ArgoCD Integration**:
  - Secret annotated with `argocd.argoproj.io/compare-options: IgnoreExtraneous`
  - ArgoCD ignores runtime changes to DB_ROOT_CERT field
  - No drift detection for dynamically managed certificate

#### Authentication
- **GitHub OAuth**: Configured for SSO
- **SMTP**: ProficientNow Platform Admin email
- **SAML**: Organization slug configured (pnats)

#### Integrations
- **GitHub**: App connection for GitHub Secrets sync
- **AWS**: IAM credentials for AWS Secrets Manager integration

### 4. Files Created/Modified

```
v0.2.0/platform/charts/infisical/
├── Chart.yaml                              # Chart metadata with sync-wave 300
├── values.yaml                             # Correct chart structure (backend:)
├── cert-sync-job.yaml                      # Dynamic certificate sync Job
└── secrets/
    ├── README.md                           # Secret management instructions
    ├── .gitignore                          # Protects unsealed secrets
    ├── infisical-secrets.secret            # Template with actual secrets (NOT committed)
    └── infisical-secrets-sealed.yaml       # Sealed secret (safe to commit)
```

### 5. Supporting Infrastructure Updates

**PostgreSQL Service Configuration** (platform-db.yaml):
```yaml
serviceAnnotations: {}
masterServiceAnnotations: {}
replicaServiceAnnotations: {}
```
- Explicitly disables external-dns
- Internal-only access via cluster DNS

**Redis Configuration** (redis-configmap.yaml):
- Fixed inline comment syntax errors
- Proper namespace assignment

## Current Status

### ✅ Completed
1. Chart structure corrected (backend: vs infisical:)
2. MongoDB deployment disabled (mongodb.enabled: false)
3. PostgreSQL connection via pooler configured
4. Redis Sentinel integration configured
5. SSL/TLS certificate auto-sync job created
6. CORS allowed origins in JSON array format
7. DB_READ_REPLICAS in correct uppercase format
8. Ingress configuration with Let's Encrypt
9. SMTP email configuration
10. GitHub OAuth authentication

### ⏳ Pending User Action
1. **Seal the secret** using kubeseal:
   ```bash
   kubeseal --controller-name=sealed-secrets \
     --controller-namespace=sealed-secrets \
     -f v0.2.0/platform/charts/infisical/secrets/infisical-secrets.secret \
     -o yaml > v0.2.0/platform/charts/infisical/secrets/infisical-secrets-sealed.yaml
   ```

2. **Commit and push**:
   ```bash
   git add v0.2.0/platform/charts/infisical/
   git add v0.2.0/platform/databases/platform/platform-db.yaml
   git add v0.2.0/platform/redis/platform-kv/cluster/redis-configmap.yaml
   git commit -m "feat(infisical): add secret management platform with auto-cert sync"
   git push
   ```

3. **Monitor ArgoCD sync**:
   - Watch cert-sync-job PreSync hook execution
   - Verify infisical-backend pods start successfully
   - Check database migrations complete
   - Confirm web UI accessible at https://secrets.pnats.cloud

## Architecture Flow

```
┌─────────────────────────────────────────────────────────┐
│                    ArgoCD Sync                          │
│  (Triggered on every git push or manual sync)           │
└─────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────┐
│  Sync Hook (wave: -1): postgres-cert-sync Job           │
│  - Runs BEFORE main resources                           │
│  - Extract cert from platform-db-cluster-0              │
│  - Base64 encode                                        │
│  - Patch infisical-secrets with DB_ROOT_CERT            │
│  - Job deleted before next sync (BeforeHookCreation)    │
└─────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────┐
│  Sealed Secret → Kubernetes Secret                      │
│  infisical-secrets-sealed.yaml → infisical-secrets      │
│                                                          │
│  ArgoCD Annotations:                                    │
│  - compare-options: IgnoreExtraneous                    │
│  - sync-options: Prune=false                            │
│  → ArgoCD ignores DB_ROOT_CERT changes                  │
└─────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────┐
│  Infisical Backend Deployment (2 replicas)              │
│  - Reads env vars from infisical-secrets                │
│  - Connects to PostgreSQL via pooler (SSL)              │
│  - Connects to Redis Sentinel                           │
│  - Runs database migrations                             │
└─────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────┐
│  Ingress: secrets.pnats.cloud                           │
│  - Let's Encrypt TLS                                    │
│  - nginx ingress controller                             │
└─────────────────────────────────────────────────────────┘
```

## Secret Bootstrap Strategy (4-Tier)

```
Tier 1: Sealed Secrets (kubeseal)
  └── Encrypts bootstrap secrets for Git storage
      │
Tier 2: Infisical Platform
  └── Central secret management with web UI
      │
Tier 3: Infisical Secrets Operator
  └── Syncs secrets from Infisical → Kubernetes
      │
Tier 4: Application Secrets
  └── Applications consume secrets from Kubernetes
```

## Known Issues Resolved

1. ✅ Redis ConfigMap inline comment syntax errors
2. ✅ PostgreSQL external-dns wrong domain annotations
3. ✅ Infisical using default values (wrong structure)
4. ✅ MongoDB being deployed (disabled bundled chart)
5. ✅ CORS_ALLOWED_ORIGINS invalid JSON format
6. ✅ DB_READ_REPLICAS wrong key casing
7. ✅ SSL certificate self-signed errors
8. ✅ Connection pooler ECONNREFUSED errors
9. ✅ ArgoCD IngressClass shared resource warning

## Next Steps After Deployment

1. **Create first organization** in Infisical web UI
2. **Deploy Infisical Secrets Operator** chart
3. **Configure operator** to sync from Infisical
4. **Migrate application secrets** from Sealed Secrets to Infisical
5. **Set up RBAC** and access policies in Infisical

## Security Notes

- ⚠️ DO NOT commit infisical-secrets.secret with real values
- ✅ Only commit infisical-secrets-sealed.yaml (encrypted)
- ✅ DB_ROOT_CERT is dynamically populated (no manual management)
- ✅ All connections use internal Kubernetes DNS
- ✅ PostgreSQL connections require SSL
- ✅ GitHub OAuth secrets are scoped to pnats organization

## Documentation Links

- Infisical Docs: https://infisical.com/docs
- Helm Chart: https://github.com/Infisical/infisical/tree/main/helm-charts/infisical
- DB_ROOT_CERT: https://infisical.com/docs/self-hosting/configuration/envars
- Secrets Operator: https://github.com/Infisical/infisical/tree/main/helm-charts/secrets-operator
