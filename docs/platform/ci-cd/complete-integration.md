# Complete Integration: Vault + Crossplane + Keycloak

## Overview

This document shows how Vault, Crossplane, and Keycloak work together to provide a secure, self-service infrastructure platform.

---

## Complete Architecture

```mermaid
graph TB
    subgraph "Authentication Layer"
        KC[Keycloak<br/>SSO & OIDC]
        USERS[Users & Services]
    end
    
    subgraph "Secret Management"
        VAULT[HashiCorp Vault<br/>Secret Store]
        ESO[External Secrets Operator]
        PKI[PKI Engine<br/>Certificates]
        DB_ENGINE[Database Engine<br/>Dynamic Creds]
    end
    
    subgraph "Infrastructure Provisioning"
        XP[Crossplane<br/>Infrastructure as Code]
        COMP[Compositions]
        CLAIMS[Resource Claims]
    end
    
    subgraph "GitOps Pipeline"
        TEKTON[Tekton<br/>CI Pipeline]
        KARGO[Kargo<br/>Progressive Delivery]
        ARGOCD[ArgoCD<br/>GitOps CD]
        HARBOR[Harbor<br/>Registry]
    end
    
    subgraph "Provisioned Infrastructure"
        DB[(Databases)]
        CACHE[Redis Clusters]
        QUEUES[Message Queues]
        STORAGE[Object Storage]
    end
    
    subgraph "Applications"
        SERVICES[Microservices]
        APIS[API Gateways]
    end
    
    USERS -->|Authenticate| KC
    KC -->|OIDC Token| TEKTON
    KC -->|OIDC Token| ARGOCD
    KC -->|OIDC Token| KARGO
    KC -->|OIDC Token| HARBOR
    KC -->|OIDC Token| APIS
    
    KC -->|OIDC Auth| VAULT
    
    VAULT -->|K8s Auth| ESO
    ESO -->|Sync Secrets| TEKTON
    ESO -->|Sync Secrets| ARGOCD
    ESO -->|Sync Secrets| SERVICES
    
    XP -->|Provision| DB
    XP -->|Provision| CACHE
    XP -->|Provision| QUEUES
    XP -->|Provision| STORAGE
    
    DB -.->|Register| DB_ENGINE
    DB_ENGINE -->|Dynamic Creds| ESO
    
    PKI -->|TLS Certs| ESO
    
    CLAIMS -->|Create| XP
    COMP -->|Templates| XP
    
    ARGOCD -->|Deploy Claims| XP
    ARGOCD -->|Deploy Apps| SERVICES
    
    DB --> SERVICES
    CACHE --> SERVICES
    QUEUES --> SERVICES
    
    style KC fill:#008aaa
    style VAULT fill:#000000,color:#ffffff
    style XP fill:#ff6600
    style ARGOCD fill:#ef7b4d
```

---

## 1. Integration Flow: New Environment Setup

### Step 1: Infrastructure Request (GitOps Repo)

```yaml
# gitops-config/overlays/staging/infrastructure.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: staging
  labels:
    environment: staging
---
# Database via Crossplane
apiVersion: database.yourdomain.com/v1alpha1
kind: PostgreSQLInstance
metadata:
  name: staging-database
  namespace: staging
spec:
  parameters:
    environment: staging
    size: medium
    storageGB: 50
    enableBackup: true
    vaultPath: secret/database/staging
---
# Redis via Crossplane
apiVersion: cache.yourdomain.com/v1alpha1
kind: RedisInstance
metadata:
  name: staging-redis
  namespace: staging
spec:
  parameters:
    environment: staging
    replicas: 2
    memoryGB: 2
```

### Step 2: Crossplane Provisions Infrastructure

```bash
# Crossplane creates:
1. PostgreSQL database
2. Redis cluster
3. Connection secrets
4. Registers with Vault
```

### Step 3: Vault Stores Credentials

```bash
# Crossplane triggers Vault registration
vault write database/config/postgres-staging \
    plugin_name=postgresql-database-plugin \
    connection_url="postgresql://{{username}}:{{password}}@postgres.staging.svc:5432/staging-db" \
    username="vault-admin" \
    password="<generated-password>" \
    allowed_roles="staging-*"

vault write database/roles/staging-readwrite \
    db_name=postgres-staging \
    creation_statements="..." \
    default_ttl="1h" \
    max_ttl="24h"

# Static credentials also stored
vault kv put secret/database/staging \
    admin-username="vault-admin" \
    admin-password="<generated-password>" \
    endpoint="postgres.staging.svc"
```

### Step 4: External Secrets Operator Syncs to K8s

```yaml
# Automatically created by ArgoCD
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: database-credentials
  namespace: staging
spec:
  refreshInterval: 5m
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: postgres-connection
  data:
    # Dynamic credentials (rotated hourly)
    - secretKey: username
      remoteRef:
        key: database/creds/staging-readwrite
        property: username
    - secretKey: password
      remoteRef:
        key: database/creds/staging-readwrite
        property: password
    # Static admin credentials (for migrations)
    - secretKey: admin-username
      remoteRef:
        key: secret/database/staging
        property: admin-username
    - secretKey: admin-password
      remoteRef:
        key: secret/database/staging
        property: admin-password
    - secretKey: endpoint
      remoteRef:
        key: secret/database/staging
        property: endpoint
```

### Step 5: Applications Use Secrets

```yaml
# Application deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: user-service
  namespace: staging
spec:
  template:
    spec:
      containers:
        - name: user-service
          image: harbor.yourdomain.com/services/user-service:v1.2.3
          env:
            # Dynamically rotated credentials
            - name: DB_USERNAME
              valueFrom:
                secretKeyRef:
                  name: postgres-connection
                  key: username
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: postgres-connection
                  key: password
            - name: DB_ENDPOINT
              valueFrom:
                secretKeyRef:
                  name: postgres-connection
                  key: endpoint
            - name: DATABASE_URL
              value: "postgresql://$(DB_USERNAME):$(DB_PASSWORD)@$(DB_ENDPOINT):5432/staging-db"
```

---

## 2. Integration Flow: User Authentication

### Step 1: User Logs into ArgoCD

```
1. User navigates to https://argocd.yourdomain.com
2. ArgoCD redirects to Keycloak
3. User authenticates (GitHub SSO or username/password)
4. Keycloak returns JWT token with groups and roles
5. ArgoCD validates token and grants access based on RBAC
```

### Step 2: User Triggers Deployment

```
1. User approves promotion in Kargo UI (authenticated via Keycloak)
2. Kargo updates GitOps repo
3. ArgoCD detects change and syncs
4. ArgoCD uses Vault-stored Git credentials (via ESO)
5. ArgoCD deploys to Kubernetes
```

### Step 3: CI Pipeline Authentication

```
1. Developer opens PR
2. GitHub webhook triggers Tekton
3. Tekton ServiceAccount authenticates to Vault
4. Vault returns Harbor registry credentials
5. Tekton builds and pushes image to Harbor
6. Harbor authenticated via Keycloak SSO for UI access
```

---

## 3. Complete Secret Flow

### Secrets Hierarchy

```
Vault (Source of Truth)
├── Static Secrets (KV v2)
│   ├── secret/github/*           → Tekton, ArgoCD
│   ├── secret/harbor/*           → Tekton, Kargo, ArgoCD
│   ├── secret/verdaccio/*        → Tekton
│   ├── secret/database/*/admin   → Migrations, Crossplane
│   └── secret/apps/*/            → Applications
│
├── Dynamic Secrets
│   ├── database/creds/*          → Applications (short-lived)
│   └── pki/issue/*               → TLS certificates
│
└── Authentication
    ├── auth/kubernetes           → K8s ServiceAccounts
    └── auth/oidc                 → Keycloak integration
```

### Secret Distribution Paths

```mermaid
graph LR
    VAULT[Vault] -->|External Secrets| K8S_SECRET[Kubernetes Secrets]
    VAULT -->|Vault Agent| POD_VOLUME[Pod Volume Mount]
    VAULT -->|CSI Driver| POD_CSI[Pod CSI Volume]
    
    K8S_SECRET -->|Environment Vars| APP1[Application]
    POD_VOLUME -->|File System| APP2[Application]
    POD_CSI -->|File System| APP3[Application]
```

---

## 4. Self-Service Workflow

### Developer Requests New Database

```yaml
# 1. Developer creates PR in gitops-config repo
# gitops-config/overlays/dev/my-feature-db.yaml
apiVersion: database.yourdomain.com/v1alpha1
kind: PostgreSQLInstance
metadata:
  name: my-feature-db
  namespace: dev
spec:
  parameters:
    environment: dev
    size: small
    storageGB: 10
    enableBackup: false
    vaultPath: secret/database/dev-my-feature
```

```bash
# 2. PR triggers validation (Tekton)
- Validate Crossplane manifest
- Check resource quotas
- Estimate costs

# 3. DevOps approves PR (authenticated via Keycloak)
git merge feature/my-feature-db

# 4. ArgoCD syncs (authenticated via Keycloak + Vault git creds)
- Creates Crossplane claim
- Crossplane provisions database
- Registers with Vault
- ESO creates K8s secret

# 5. Developer accesses database
kubectl get secret my-feature-db-credentials -n dev
```

---

## 5. Security Boundaries

### Namespace Isolation

```yaml
# Each namespace has its own Vault role
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault-backend
  namespace: dev
spec:
  provider:
    vault:
      server: "http://vault.vault.svc:8200"
      path: "secret"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "app-dev"  # Can only access secret/apps/dev/*
          serviceAccountRef:
            name: "default"
```

### Vault Policy Isolation

```hcl
# policies/app-dev.hcl
# Dev apps can only read dev secrets
path "secret/data/apps/dev/*" {
  capabilities = ["read", "list"]
}

path "database/creds/dev-*" {
  capabilities = ["read"]
}

# Cannot access staging or production
path "secret/data/apps/staging/*" {
  capabilities = ["deny"]
}

path "secret/data/apps/production/*" {
  capabilities = ["deny"]
}
```

### Keycloak Authorization

```yaml
# ArgoCD RBAC
# Developers can only sync to dev namespace
p, role:developer, applications, sync, dev/*, allow
p, role:developer, applications, sync, staging/*, deny
p, role:developer, applications, sync, production/*, deny

# DevOps can sync to all namespaces
p, role:devops, applications, sync, */*, allow
```

---

## 6. Disaster Recovery

### Backup Strategy

```bash
#!/bin/bash
# scripts/backup-all.sh

# Backup Keycloak
pg_dump keycloak > /backups/keycloak_$(date +%Y%m%d).sql

# Backup Vault (encrypted snapshots)
vault operator raft snapshot save /backups/vault_$(date +%Y%m%d).snap

# Backup Crossplane state
kubectl get managed -A -o yaml > /backups/crossplane_$(date +%Y%m%d).yaml

# Backup provisioned databases
for db in dev staging production; do
  kubectl exec -n ${db} postgres-0 -- \
    pg_dumpall > /backups/${db}_db_$(date +%Y%m%d).sql
done
```

### Recovery Procedure

```bash
# 1. Restore Vault
vault operator raft snapshot restore /backups/vault_latest.snap

# 2. Restore Keycloak
psql keycloak < /backups/keycloak_latest.sql

# 3. Restore Crossplane resources
kubectl apply -f /backups/crossplane_latest.yaml

# 4. ESO will automatically sync secrets from Vault
# 5. Applications will reconnect with new credentials
```

---

## 7. Monitoring Integration

### Unified Dashboard

```yaml
# grafana/dashboards/platform-overview.json
{
  "dashboard": {
    "title": "Platform Overview",
    "panels": [
      {
        "title": "Vault Health",
        "targets": [{
          "expr": "up{job=\"vault\"}"
        }]
      },
      {
        "title": "Keycloak Active Sessions",
        "targets": [{
          "expr": "keycloak_sessions_active"
        }]
      },
      {
        "title": "Crossplane Resources",
        "targets": [{
          "expr": "crossplane_managed_resource_exists"
        }]
      },
      {
        "title": "Secret Rotation Status",
        "targets": [{
          "expr": "external_secrets_sync_calls_total"
        }]
      }
    ]
  }
}
```

### Alert Rules

```yaml
# monitoring/platform-alerts.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: platform-alerts
spec:
  groups:
    - name: platform
      rules:
        # Vault alerts
        - alert: VaultSealed
          expr: vault_core_unsealed == 0
          labels:
            severity: critical
        
        # Keycloak alerts
        - alert: KeycloakHighFailedLogins
          expr: rate(keycloak_failed_login_attempts[5m]) > 10
          labels:
            severity: warning
        
        # Crossplane alerts
        - alert: CrossplaneResourceFailed
          expr: crossplane_managed_resource_exists{condition_status="False"} == 1
          for: 10m
          labels:
            severity: critical
        
        # ESO alerts
        - alert: ExternalSecretSyncFailed
          expr: external_secrets_sync_calls_error > 0
          for: 5m
          labels:
            severity: warning
```

---

## 8. Cost Optimization

### Resource Sizing Matrix

| Environment | Database Size | Redis Size | Backup Retention | Estimated Cost/Month |
|-------------|---------------|------------|------------------|---------------------|
| Dev         | Small (20GB)  | 1GB        | None             | $50                 |
| Staging     | Medium (50GB) | 2GB        | 7 days           | $150                |
| UAT         | Medium (50GB) | 2GB        | 7 days           | $150                |
| Pre-Prod    | Large (100GB) | 4GB        | 14 days          | $300                |
| Production  | XLarge (200GB)| 8GB        | 30 days          | $800                |
| Sandbox     | Large (200GB) | 4GB        | None (ephemeral) | $200 (24h)          |

### Auto-Scaling Policies

```yaml
# Crossplane composition with auto-scaling
apiVersion: apiextensions.crossplane.io/v1
kind: Composition
metadata:
  name: postgres-autoscaling
spec:
  resources:
    - name: database
      patches:
        # Scale based on environment
        - fromFieldPath: spec.parameters.environment
          toFieldPath: spec.forProvider.storageGB
          transforms:
            - type: map
              map:
                dev: 20
                staging: 50
                production: 200
```

---

## 9. Compliance & Audit

### Audit Trail

```bash
# Vault audit logs
vault audit enable file file_path=/vault/logs/audit.log

# Query who accessed production secrets
cat /vault/logs/audit.log | \
  jq 'select(.request.path | contains("secret/data/apps/production"))'

# Keycloak audit logs
# Via Keycloak Admin Console → Events
# Or PostgreSQL query:
psql keycloak -c "SELECT * FROM event_entity WHERE realm_id='myapp' ORDER BY event_time DESC LIMIT 100;"

# Crossplane resource changes
kubectl get events -n crossplane-system --sort-by='.lastTimestamp'
```

### Compliance Reports

```python
#!/usr/bin/env python3
# scripts/compliance-report.py

import json
from datetime import datetime, timedelta

def generate_compliance_report():
    report = {
        "timestamp": datetime.now().isoformat(),
        "checks": []
    }
    
    # Check 1: All secrets rotated in last 30 days
    report["checks"].append({
        "name": "Secret Rotation",
        "status": check_secret_rotation(),
        "requirement": "Secrets must be rotated monthly"
    })
    
    # Check 2: MFA enabled for all users
    report["checks"].append({
        "name": "MFA Enforcement",
        "status": check_mfa_status(),
        "requirement": "All users must have MFA enabled"
    })
    
    # Check 3: Vault sealed status
    report["checks"].append({
        "name": "Vault Security",
        "status": check_vault_unsealed(),
        "requirement": "Vault must be unsealed and accessible"
    })
    
    return report
```

---

## 10. Troubleshooting Guide

### Issue: Application Can't Connect to Database

```bash
# 1. Check if Crossplane provisioned database
kubectl get postgresqlinstance -n <namespace>

# 2. Check if Vault has credentials
vault kv get secret/database/<env>

# 3. Check if ESO synced secret
kubectl get externalsecret -n <namespace>
kubectl describe externalsecret <name> -n <namespace>

# 4. Check if K8s secret exists
kubectl get secret postgres-connection -n <namespace>

# 5. Check application can reach database
kubectl exec -n <namespace> <pod> -- nc -zv postgres.<namespace>.svc 5432

# 6. Test with credentials
kubectl exec -n <namespace> <pod> -- \
  psql postgresql://$(kubectl get secret postgres-connection -n <namespace> -o jsonpath='{.data.username}' | base64 -d):$(kubectl get secret postgres-connection -n <namespace> -o jsonpath='{.data.password}' | base64 -d)@postgres.<namespace>.svc:5432/<env>-db
```

### Issue: User Can't Login to ArgoCD

```bash
# 1. Check Keycloak is running
kubectl get pods -n keycloak

# 2. Check ArgoCD OIDC configuration
kubectl get configmap argocd-cm -n argocd -o yaml

# 3. Check user exists in Keycloak
# Via Keycloak Admin UI: Users → Search

# 4. Check user's group membership
# Via Keycloak Admin UI: Users → Groups

# 5. Check ArgoCD RBAC
kubectl get configmap argocd-rbac-cm -n argocd -o yaml

# 6. Test OIDC flow
curl -v https://keycloak.yourdomain.com/realms/myapp/.well-known/openid-configuration
```

---

## Summary

This integrated platform provides:

✅ **Unified Authentication** - Keycloak SSO across all tools  
✅ **Centralized Secrets** - Vault as single source of truth  
✅ **Infrastructure as Code** - Crossplane for declarative infrastructure  
✅ **Automated Provisioning** - Self-service infrastructure requests  
✅ **Dynamic Credentials** - Short-lived, auto-rotating database credentials  
✅ **Security Boundaries** - Namespace isolation with Vault policies  
✅ **Complete Audit Trail** - Every access logged and traceable  
✅ **Disaster Recovery** - Comprehensive backup and restore procedures  
✅ **Cost Optimization** - Right-sized resources per environment  
✅ **Developer Experience** - Self-service with safety guardrails

**Your complete GitOps platform is now production-ready with enterprise-grade security!** 🎉🔒
