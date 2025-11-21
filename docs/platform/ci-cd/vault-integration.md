# Vault Secret Management Integration

## Overview

With HashiCorp Vault deployed, we'll implement a secure, centralized secret management strategy across all environments and tools.

---

## Architecture Diagram

```mermaid
graph TB
    subgraph "HashiCorp Vault"
        VAULT[Vault Server<br/>Central Secret Store]
        KV[KV Secrets Engine<br/>Application Secrets]
        PKI[PKI Engine<br/>Certificates]
        DB[Database Engine<br/>Dynamic Credentials]
        AUTH[Auth Methods<br/>Kubernetes, OIDC]
    end
    
    subgraph "Secret Distribution"
        ESO[External Secrets Operator]
        VAULT_AGENT[Vault Agent Injector]
        CSI[Vault CSI Driver]
    end
    
    subgraph "Consumers"
        TEKTON[Tekton Pipelines<br/>CI/CD Secrets]
        ARGOCD[ArgoCD<br/>Git & Registry Credentials]
        APPS[Applications<br/>Runtime Secrets]
        KARGO[Kargo<br/>Registry Access]
    end
    
    subgraph "Authentication"
        KC[Keycloak<br/>OIDC Provider]
        K8S_SA[Kubernetes ServiceAccounts]
    end
    
    VAULT --> KV
    VAULT --> PKI
    VAULT --> DB
    VAULT --> AUTH
    
    KC -->|OIDC Auth| AUTH
    K8S_SA -->|K8s Auth| AUTH
    
    AUTH -->|Authenticate| ESO
    AUTH -->|Authenticate| VAULT_AGENT
    AUTH -->|Authenticate| CSI
    
    ESO -->|Sync Secrets| TEKTON
    ESO -->|Sync Secrets| ARGOCD
    ESO -->|Sync Secrets| KARGO
    
    VAULT_AGENT -->|Inject Secrets| APPS
    CSI -->|Mount Secrets| APPS
    
    KV -->|Application Config| ESO
    DB -->|Dynamic DB Creds| ESO
    PKI -->|TLS Certificates| ESO
    
    style VAULT fill:#000000,color:#ffffff
    style KC fill:#008aaa
    style ESO fill:#326ce5
    style VAULT_AGENT fill:#326ce5
```

---

## 1. Vault Setup

### Vault Policies

```hcl
# policies/tekton-policy.hcl
# Policy for Tekton pipelines
path "secret/data/tekton/*" {
  capabilities = ["read", "list"]
}

path "secret/data/harbor/*" {
  capabilities = ["read", "list"]
}

path "secret/data/verdaccio/*" {
  capabilities = ["read", "list"]
}

path "secret/data/github/*" {
  capabilities = ["read", "list"]
}

path "database/creds/tekton-db" {
  capabilities = ["read"]
}
```

```hcl
# policies/argocd-policy.hcl
# Policy for ArgoCD
path "secret/data/argocd/*" {
  capabilities = ["read", "list"]
}

path "secret/data/gitops-repo/*" {
  capabilities = ["read", "list"]
}

path "secret/data/harbor/*" {
  capabilities = ["read", "list"]
}

path "secret/data/clusters/*" {
  capabilities = ["read", "list"]
}
```

```hcl
# policies/kargo-policy.hcl
# Policy for Kargo
path "secret/data/kargo/*" {
  capabilities = ["read", "list"]
}

path "secret/data/harbor/*" {
  capabilities = ["read", "list"]
}

path "secret/data/verdaccio/*" {
  capabilities = ["read", "list"]
}
```

```hcl
# policies/app-policy.hcl
# Policy for applications
path "secret/data/apps/{{identity.entity.aliases.AUTH_METHOD_ACCESSOR.metadata.service_account_namespace}}/*" {
  capabilities = ["read", "list"]
}

path "database/creds/{{identity.entity.aliases.AUTH_METHOD_ACCESSOR.metadata.service_account_namespace}}-*" {
  capabilities = ["read"]
}
```

### Apply Policies

```bash
# Apply policies to Vault
vault policy write tekton policies/tekton-policy.hcl
vault policy write argocd policies/argocd-policy.hcl
vault policy write kargo policies/kargo-policy.hcl
vault policy write app policies/app-policy.hcl
```

---

## 2. Kubernetes Authentication

### Enable Kubernetes Auth Method

```bash
# Enable Kubernetes auth
vault auth enable kubernetes

# Configure Kubernetes auth
vault write auth/kubernetes/config \
    kubernetes_host="https://kubernetes.default.svc:443" \
    kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
    token_reviewer_jwt=@/var/run/secrets/kubernetes.io/serviceaccount/token
```

### Create Vault Roles

```bash
# Tekton role
vault write auth/kubernetes/role/tekton \
    bound_service_account_names=tekton-triggers-sa,tekton-pipelines-sa \
    bound_service_account_namespaces=tekton-pipelines \
    policies=tekton \
    ttl=1h

# ArgoCD role
vault write auth/kubernetes/role/argocd \
    bound_service_account_names=argocd-server,argocd-application-controller \
    bound_service_account_namespaces=argocd \
    policies=argocd \
    ttl=1h

# Kargo role
vault write auth/kubernetes/role/kargo \
    bound_service_account_names=kargo-controller \
    bound_service_account_namespaces=kargo \
    policies=kargo \
    ttl=1h

# Application role (per namespace)
vault write auth/kubernetes/role/app-dev \
    bound_service_account_names=* \
    bound_service_account_namespaces=dev \
    policies=app \
    ttl=24h

vault write auth/kubernetes/role/app-staging \
    bound_service_account_names=* \
    bound_service_account_namespaces=staging \
    policies=app \
    ttl=24h

vault write auth/kubernetes/role/app-production \
    bound_service_account_names=* \
    bound_service_account_namespaces=production \
    policies=app \
    ttl=24h
```

---

## 3. External Secrets Operator (ESO)

### Install ESO

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm install external-secrets \
    external-secrets/external-secrets \
    -n external-secrets-system \
    --create-namespace \
    --set installCRDs=true
```

### SecretStore Configuration

```yaml
# vault/secretstore-tekton.yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault-backend
  namespace: tekton-pipelines
spec:
  provider:
    vault:
      server: "http://vault.vault.svc:8200"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "tekton"
          serviceAccountRef:
            name: "tekton-triggers-sa"
---
# vault/secretstore-argocd.yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault-backend
  namespace: argocd
spec:
  provider:
    vault:
      server: "http://vault.vault.svc:8200"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "argocd"
          serviceAccountRef:
            name: "argocd-server"
---
# vault/secretstore-kargo.yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault-backend
  namespace: kargo
spec:
  provider:
    vault:
      server: "http://vault.vault.svc:8200"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "kargo"
          serviceAccountRef:
            name: "kargo-controller"
```

### ClusterSecretStore (for all namespaces)

```yaml
# vault/cluster-secretstore.yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: vault-backend
spec:
  provider:
    vault:
      server: "http://vault.vault.svc:8200"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "app-{{.namespace}}"
          serviceAccountRef:
            name: "default"
```

---

## 4. Storing Secrets in Vault

### Store Secrets via CLI

```bash
# GitHub credentials
vault kv put secret/github \
    token="ghp_xxxxxxxxxxxxxxxxxxxx" \
    webhook-secret="your-webhook-secret"

# Harbor credentials
vault kv put secret/harbor \
    username="admin" \
    password="Harbor12345" \
    url="https://harbor.yourdomain.com"

# Verdaccio credentials
vault kv put secret/verdaccio \
    token="your-verdaccio-token" \
    url="https://verdaccio.yourdomain.com"

# ArgoCD repository credentials
vault kv put secret/argocd/gitops-repo \
    url="https://github.com/yourorg/gitops-config.git" \
    username="git" \
    password="ghp_xxxxxxxxxxxxxxxxxxxx"

# Kargo Harbor credentials
vault kv put secret/kargo/harbor \
    username="kargo" \
    password="KargoPassword123"

# Application secrets (per environment)
vault kv put secret/apps/dev/user-service \
    database-url="postgresql://user:pass@postgres.dev.svc:5432/userdb" \
    redis-url="redis://redis.dev.svc:6379" \
    jwt-secret="dev-jwt-secret-key" \
    api-key="dev-api-key"

vault kv put secret/apps/production/user-service \
    database-url="postgresql://user:pass@postgres.production.svc:5432/userdb" \
    redis-url="redis://redis.production.svc:6379" \
    jwt-secret="prod-jwt-secret-key" \
    api-key="prod-api-key"
```

---

## 5. ExternalSecret Definitions

### Tekton Secrets

```yaml
# vault/external-secrets/tekton-github.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: github-secret
  namespace: tekton-pipelines
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  
  target:
    name: github-secret
    creationPolicy: Owner
  
  data:
    - secretKey: token
      remoteRef:
        key: github
        property: token
    
    - secretKey: secretToken
      remoteRef:
        key: github
        property: webhook-secret
---
# vault/external-secrets/tekton-harbor.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: harbor-secret
  namespace: tekton-pipelines
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  
  target:
    name: harbor-secret
    creationPolicy: Owner
    template:
      type: kubernetes.io/dockerconfigjson
      data:
        .dockerconfigjson: |
          {
            "auths": {
              "{{ .url }}": {
                "username": "{{ .username }}",
                "password": "{{ .password }}",
                "auth": "{{ printf "%s:%s" .username .password | b64enc }}"
              }
            }
          }
  
  data:
    - secretKey: username
      remoteRef:
        key: harbor
        property: username
    
    - secretKey: password
      remoteRef:
        key: harbor
        property: password
    
    - secretKey: url
      remoteRef:
        key: harbor
        property: url
---
# vault/external-secrets/tekton-verdaccio.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: verdaccio-secret
  namespace: tekton-pipelines
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  
  target:
    name: verdaccio-secret
    creationPolicy: Owner
    template:
      data:
        .npmrc: |
          //{{ .url | replace "https://" "" }}/:_authToken={{ .token }}
  
  data:
    - secretKey: token
      remoteRef:
        key: verdaccio
        property: token
    
    - secretKey: url
      remoteRef:
        key: verdaccio
        property: url
```

### ArgoCD Secrets

```yaml
# vault/external-secrets/argocd-repo.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: gitops-repo-secret
  namespace: argocd
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  
  target:
    name: gitops-repo-secret
    creationPolicy: Owner
    template:
      metadata:
        labels:
          argocd.argoproj.io/secret-type: repository
      data:
        type: git
        url: "{{ .url }}"
        username: "{{ .username }}"
        password: "{{ .password }}"
  
  data:
    - secretKey: url
      remoteRef:
        key: argocd/gitops-repo
        property: url
    
    - secretKey: username
      remoteRef:
        key: argocd/gitops-repo
        property: username
    
    - secretKey: password
      remoteRef:
        key: argocd/gitops-repo
        property: password
---
# vault/external-secrets/argocd-harbor.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: harbor-registry-secret
  namespace: argocd
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  
  target:
    name: harbor-registry-secret
    creationPolicy: Owner
    template:
      type: kubernetes.io/dockerconfigjson
      data:
        .dockerconfigjson: |
          {
            "auths": {
              "{{ .url }}": {
                "username": "{{ .username }}",
                "password": "{{ .password }}",
                "auth": "{{ printf "%s:%s" .username .password | b64enc }}"
              }
            }
          }
  
  data:
    - secretKey: username
      remoteRef:
        key: harbor
        property: username
    
    - secretKey: password
      remoteRef:
        key: harbor
        property: password
    
    - secretKey: url
      remoteRef:
        key: harbor
        property: url
```

### Application Secrets (per environment)

```yaml
# vault/external-secrets/app-dev-user-service.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: user-service-secret
  namespace: dev
spec:
  refreshInterval: 5m
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  
  target:
    name: user-service-secret
    creationPolicy: Owner
  
  data:
    - secretKey: DATABASE_URL
      remoteRef:
        key: apps/dev/user-service
        property: database-url
    
    - secretKey: REDIS_URL
      remoteRef:
        key: apps/dev/user-service
        property: redis-url
    
    - secretKey: JWT_SECRET
      remoteRef:
        key: apps/dev/user-service
        property: jwt-secret
    
    - secretKey: API_KEY
      remoteRef:
        key: apps/dev/user-service
        property: api-key
```

---

## 6. Dynamic Database Credentials

### Enable Database Secrets Engine

```bash
# Enable database secrets engine
vault secrets enable database

# Configure PostgreSQL connection
vault write database/config/postgres-dev \
    plugin_name=postgresql-database-plugin \
    allowed_roles="dev-readonly,dev-readwrite" \
    connection_url="postgresql://{{username}}:{{password}}@postgres.dev.svc:5432/userdb?sslmode=disable" \
    username="vault" \
    password="vaultpassword"

# Create roles
vault write database/roles/dev-readonly \
    db_name=postgres-dev \
    creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
        GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
    default_ttl="1h" \
    max_ttl="24h"

vault write database/roles/dev-readwrite \
    db_name=postgres-dev \
    creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
        GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
    default_ttl="1h" \
    max_ttl="24h"
```

### Use Dynamic Credentials in ExternalSecret

```yaml
# vault/external-secrets/app-dynamic-db.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: user-service-db-creds
  namespace: dev
spec:
  refreshInterval: 30m  # Refresh before expiry
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  
  target:
    name: user-service-db-creds
    creationPolicy: Owner
    template:
      data:
        DATABASE_URL: "postgresql://{{ .username }}:{{ .password }}@postgres.dev.svc:5432/userdb"
  
  data:
    - secretKey: username
      remoteRef:
        key: database/creds/dev-readwrite
        property: username
    
    - secretKey: password
      remoteRef:
        key: database/creds/dev-readwrite
        property: password
```

---

## 7. Vault Agent Injector (Alternative Method)

### Install Vault Agent Injector

```bash
helm install vault hashicorp/vault \
    --namespace vault \
    --set "injector.enabled=true" \
    --set "server.enabled=false"
```

### Use Annotations for Secret Injection

```yaml
# Example deployment with Vault Agent Injector
apiVersion: apps/v1
kind: Deployment
metadata:
  name: user-service
  namespace: dev
spec:
  template:
    metadata:
      annotations:
        vault.hashicorp.com/agent-inject: "true"
        vault.hashicorp.com/role: "app-dev"
        vault.hashicorp.com/agent-inject-secret-config: "secret/data/apps/dev/user-service"
        vault.hashicorp.com/agent-inject-template-config: |
          {{- with secret "secret/data/apps/dev/user-service" -}}
          export DATABASE_URL="{{ .Data.data.database-url }}"
          export REDIS_URL="{{ .Data.data.redis-url }}"
          export JWT_SECRET="{{ .Data.data.jwt-secret }}"
          export API_KEY="{{ .Data.data.api-key }}"
          {{- end }}
    spec:
      serviceAccountName: user-service
      containers:
        - name: user-service
          image: harbor.yourdomain.com/services/user-service:v1.2.3
          command: ["/bin/sh", "-c"]
          args:
            - source /vault/secrets/config && exec node server.js
```

---

## 8. PKI Engine for TLS Certificates

### Enable PKI Engine

```bash
# Enable PKI
vault secrets enable pki
vault secrets tune -max-lease-ttl=87600h pki

# Generate root CA
vault write -field=certificate pki/root/generate/internal \
    common_name="yourdomain.com" \
    ttl=87600h > CA_cert.crt

# Configure URLs
vault write pki/config/urls \
    issuing_certificates="http://vault.vault.svc:8200/v1/pki/ca" \
    crl_distribution_points="http://vault.vault.svc:8200/v1/pki/crl"

# Create role
vault write pki/roles/yourdomain-dot-com \
    allowed_domains="yourdomain.com" \
    allow_subdomains=true \
    max_ttl="720h"
```

### Use PKI with cert-manager

```yaml
# vault/cert-manager-issuer.yaml
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: vault-issuer
  namespace: production
spec:
  vault:
    server: http://vault.vault.svc:8200
    path: pki/sign/yourdomain-dot-com
    auth:
      kubernetes:
        mountPath: /v1/auth/kubernetes
        role: cert-manager
        serviceAccountRef:
          name: cert-manager
```

---

## 9. Secrets Rotation Strategy

### Automated Rotation with ESO

```yaml
# vault/external-secrets/rotating-secret.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: rotating-db-secret
  namespace: production
spec:
  refreshInterval: 15m  # Check every 15 minutes
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  
  target:
    name: db-credentials
    creationPolicy: Owner
    deletionPolicy: Retain  # Keep old secret during rotation
  
  data:
    - secretKey: username
      remoteRef:
        key: database/creds/production-readwrite
        property: username
    
    - secretKey: password
      remoteRef:
        key: database/creds/production-readwrite
        property: password
```

### Trigger Pod Restart on Secret Change

```yaml
# Use Reloader to restart pods on secret change
apiVersion: apps/v1
kind: Deployment
metadata:
  name: user-service
  namespace: production
  annotations:
    reloader.stakater.com/auto: "true"  # Auto-restart on secret change
spec:
  template:
    spec:
      containers:
        - name: user-service
          envFrom:
            - secretRef:
                name: db-credentials
```

---

## 10. Monitoring Vault Secret Access

### Enable Audit Logging

```bash
# Enable audit logging
vault audit enable file file_path=/vault/logs/audit.log

# Query audit logs for secret access
kubectl exec -n vault vault-0 -- cat /vault/logs/audit.log | \
  jq 'select(.request.path | contains("secret/data/apps"))'
```

### Prometheus Metrics

```yaml
# vault/servicemonitor.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: vault
  namespace: vault
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: vault
  endpoints:
    - port: metrics
      path: /v1/sys/metrics
      params:
        format: ['prometheus']
```

---

## Summary

This Vault integration provides:

✅ **Centralized Secret Management** - All secrets in Vault  
✅ **Kubernetes Auth** - Service account-based authentication  
✅ **External Secrets Operator** - Automatic K8s secret sync  
✅ **Dynamic Credentials** - Short-lived database credentials  
✅ **Secret Rotation** - Automated with configurable refresh  
✅ **PKI Integration** - TLS certificate management  
✅ **Audit Logging** - Complete secret access tracking  
✅ **Policy-based Access** - Least privilege principle  
✅ **Multiple Methods** - ESO and Vault Agent Injector
