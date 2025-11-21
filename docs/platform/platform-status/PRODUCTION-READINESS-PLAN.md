# Production Readiness Plan

## Keycloak SSO, Vault Secrets, and Crossplane Integration

**Status**: 🔴 Not Production Ready
**Last Updated**: 2025-11-19

---

## Executive Summary

### Current State
- ✅ **Infrastructure Deployed**: Keycloak, Vault, Crossplane all running
- ⚠️ **Minimal Integration**: Only Backstage uses Keycloak SSO
- ⚠️ **Security Issues**: Hardcoded passwords, no centralized auth
- ❌ **Crossplane Unused**: No providers or compositions configured

### Target State
- ✅ **Single Sign-On**: All apps use Keycloak with GitHub OAuth
- ✅ **Centralized Secrets**: All secrets managed by Vault + External Secrets
- ✅ **Infrastructure as Code**: Common resources provisioned via Crossplane
- ✅ **Zero Hardcoded Secrets**: No passwords in Git repositories

---

## Table of Contents

1. [Critical Security Issues](#critical-security-issues)
2. [Keycloak SSO Integration Plan](#keycloak-sso-integration-plan)
3. [Vault Secrets Migration Plan](#vault-secrets-migration-plan)
4. [Crossplane Implementation Plan](#crossplane-implementation-plan)
5. [Implementation Phases](#implementation-phases)
6. [Validation & Testing](#validation--testing)
7. [Rollback Procedures](#rollback-procedures)

---

## Critical Security Issues

### 🔴 URGENT - Immediate Action Required

#### 1. Grafana Admin Password Exposed
**Location**: `v0.2.0/platform/charts/grafana/values.yaml`
**Issue**: Password "changeme" in plaintext
**Risk**: High - Observability platform access
**Impact**: 10/10 - Full access to all metrics and logs

**Action Required**:
```yaml
# Current (INSECURE):
adminPassword: changeme

# Target:
adminPassword: ${GRAFANA_ADMIN_PASSWORD}  # From Vault
```

#### 2. Keycloak Admin Credentials Hardcoded
**Location**: `v0.2.0/platform/charts/keycloak/values.yaml`
**Issue**: Multiple passwords in plaintext
**Risk**: Critical - SSO provider compromise
**Impact**: 10/10 - Full control over all authenticated users

**Exposed Credentials**:
```yaml
# Admin credentials
auth:
  adminUser: admin
  adminPassword: admin  # ← CRITICAL

# Database credentials
postgresql:
  auth:
    username: bn_keycloak
    password: bn_keycloak  # ← CRITICAL
    database: bitnami_keycloak
```

#### 3. Open Access Web UIs (No Authentication)
**Applications Affected**:
- Temporal UI (temporal-ui.pnats.cloud) - Workflow management
- Tekton Dashboard (tekton.pnats.cloud) - CI/CD pipelines
- Kubecost (cost.pnats.cloud) - Cost data

**Risk**: Medium-High - Information disclosure, unauthorized operations
**Impact**: 7/10 - Depends on data sensitivity

---

## Keycloak SSO Integration Plan

### Overview
Implement centralized authentication using Keycloak with GitHub as OAuth provider. All supported applications will use Keycloak OIDC for single sign-on.

### GitHub OAuth Configuration

#### Step 1: Create GitHub OAuth App
1. Navigate to GitHub Organization Settings → Developer Settings → OAuth Apps
2. Create new OAuth application:
   - **Application Name**: PN Infrastructure Keycloak
   - **Homepage URL**: `https://keycloak.pnats.cloud`
   - **Authorization callback URL**: `https://keycloak.pnats.cloud/realms/platform/broker/github/endpoint`
3. Save Client ID and Client Secret

#### Step 2: Configure Keycloak GitHub Identity Provider
Navigate to Keycloak Admin Console → Realm: platform → Identity Providers

```yaml
# Keycloak GitHub Identity Provider Configuration
Provider Type: GitHub
Client ID: ${GITHUB_OAUTH_CLIENT_ID}  # From GitHub OAuth App
Client Secret: ${GITHUB_OAUTH_CLIENT_SECRET}  # Store in Vault
Redirect URI: https://keycloak.pnats.cloud/realms/platform/broker/github/endpoint
Default Scopes: read:user user:email read:org
```

**Mappers**:
- Username: preferred_username ← username
- Email: email ← email
- First Name: firstName ← given_name
- Last Name: lastName ← family_name
- Organization: organization ← company

#### Step 3: Configure GitHub Organization Access Control
**Option A: Public Access** (Allow any GitHub user)
- No restrictions
- Users auto-register on first login

**Option B: Organization Members Only** (Recommended)
- Restrict to GitHub organization: `pnow-devsupreme` (or your org)
- Check organization membership via GitHub API
- Deny access if not a member

**Implementation**:
```javascript
// Keycloak Authentication Flow Script
var organizationName = "pnow-devsupreme";
var userOrganizations = user.getAttribute("organizations");

if (!userOrganizations || !userOrganizations.contains(organizationName)) {
    context.failure(AuthenticationFlowError.INVALID_USER);
} else {
    context.success();
}
```

---

### Application-Specific Integration

### 1. ArgoCD (High Priority)
**Status**: ⚠️ Dex deployed but not configured
**Method**: Dex SSO connector to Keycloak
**OAuth Support**: ✅ Native (via Dex)

#### Configuration Steps
1. Create Keycloak client for ArgoCD
2. Configure Dex connector in ArgoCD ConfigMap
3. Add RBAC policies for GitHub org/teams
4. Test GitHub → Keycloak → Dex → ArgoCD login flow

#### Keycloak Client Configuration
```yaml
# Keycloak: Create Client "argocd"
Client ID: argocd
Client Protocol: openid-connect
Access Type: confidential
Valid Redirect URIs:
  - https://argocd.pnats.cloud/auth/callback
  - https://argocd.pnats.cloud/api/dex/callback
Web Origins: https://argocd.pnats.cloud
```

#### ArgoCD Dex Configuration
```yaml
# v0.2.0/platform/charts/argocd-self/values.yaml
server:
  config:
    url: https://argocd.pnats.cloud
    dex.config: |
      connectors:
      - type: oidc
        id: keycloak
        name: Keycloak (GitHub SSO)
        config:
          issuer: https://keycloak.pnats.cloud/realms/platform
          clientID: argocd
          clientSecret: $dex.keycloak.clientSecret  # From Vault
          requestedScopes:
            - openid
            - profile
            - email
            - groups
          requestedIDTokenClaims:
            groups:
              essential: true

  rbacConfig:
    policy.default: role:readonly
    policy.csv: |
      # GitHub organization admin access
      g, pnow-devsupreme:admins, role:admin
      # GitHub organization developer access
      g, pnow-devsupreme:developers, role:developer
```

#### External Secret for Dex Client Secret
```yaml
# v0.2.0/platform/charts/argocd-self/external-secrets/dex-keycloak-secret.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: argocd-dex-keycloak
  namespace: argocd
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: argocd-secret
    creationPolicy: Merge
  data:
    - secretKey: dex.keycloak.clientSecret
      remoteRef:
        key: pn-kv/argocd
        property: keycloak-client-secret
```

---

### 2. Grafana (High Priority)
**Status**: ⚠️ Built-in auth with hardcoded password
**Method**: Native Keycloak OAuth
**OAuth Support**: ✅ Native

#### Keycloak Client Configuration
```yaml
# Keycloak: Create Client "grafana"
Client ID: grafana
Client Protocol: openid-connect
Access Type: confidential
Valid Redirect URIs:
  - https://grafana.pnats.cloud/login/generic_oauth
Web Origins: https://grafana.pnats.cloud
```

#### Grafana Configuration
```yaml
# v0.2.0/platform/charts/grafana/values.yaml
grafana.ini:
  server:
    root_url: https://grafana.pnats.cloud

  auth.generic_oauth:
    enabled: true
    name: Keycloak (GitHub SSO)
    allow_sign_up: true
    client_id: grafana
    client_secret: ${GRAFANA_KEYCLOAK_CLIENT_SECRET}  # From Vault
    scopes: openid profile email
    auth_url: https://keycloak.pnats.cloud/realms/platform/protocol/openid-connect/auth
    token_url: https://keycloak.pnats.cloud/realms/platform/protocol/openid-connect/token
    api_url: https://keycloak.pnats.cloud/realms/platform/protocol/openid-connect/userinfo
    role_attribute_path: contains(groups[*], 'grafana-admins') && 'Admin' || contains(groups[*], 'grafana-editors') && 'Editor' || 'Viewer'

  auth:
    disable_login_form: false  # Keep for emergency admin access
    oauth_auto_login: true

adminPassword: ${GRAFANA_ADMIN_PASSWORD}  # From Vault (emergency access only)
```

#### Keycloak Groups for Grafana Roles
Create groups in Keycloak realm "platform":
- `grafana-admins` → Grafana Admin role
- `grafana-editors` → Grafana Editor role
- `grafana-viewers` → Grafana Viewer role (default)

Map GitHub teams to Keycloak groups via Identity Provider mapper.

#### External Secret for Grafana
```yaml
# v0.2.0/platform/charts/grafana/external-secrets/grafana-auth.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: grafana-auth
  namespace: monitoring
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: grafana
    creationPolicy: Merge
  data:
    - secretKey: admin-password
      remoteRef:
        key: pn-kv/grafana
        property: admin-password
    - secretKey: keycloak-client-secret
      remoteRef:
        key: pn-kv/grafana
        property: keycloak-client-secret
```

---

### 3. Harbor (High Priority)
**Status**: ⚠️ Built-in authentication
**Method**: Native OIDC provider
**OAuth Support**: ✅ Native

#### Keycloak Client Configuration
```yaml
# Keycloak: Create Client "harbor"
Client ID: harbor
Client Protocol: openid-connect
Access Type: confidential
Valid Redirect URIs:
  - https://registry.pnats.cloud/c/oidc/callback
Web Origins: https://registry.pnats.cloud
Mappers:
  - Name: groups
    Mapper Type: Group Membership
    Token Claim Name: groups
```

#### Harbor Configuration
```yaml
# v0.2.0/platform/charts/harbor/values.yaml
core:
  config:
    oidc:
      enabled: true
      name: keycloak
      endpoint: https://keycloak.pnats.cloud/realms/platform
      client_id: harbor
      client_secret: ${HARBOR_KEYCLOAK_CLIENT_SECRET}  # From Vault
      group_claim_name: groups
      admin_group: harbor-admins
      scope: openid,profile,email,groups
      verify_cert: true
      auto_onboard: true
      user_claim: preferred_username
```

#### Keycloak Groups for Harbor
- `harbor-admins` → Harbor system administrator
- `harbor-developers` → Project member (push/pull)
- Default: Pull access only

---

### 4. Vault (Medium Priority)
**Status**: ⚠️ Token-based authentication
**Method**: OIDC auth method
**OAuth Support**: ✅ Native

#### Keycloak Client Configuration
```yaml
# Keycloak: Create Client "vault"
Client ID: vault
Client Protocol: openid-connect
Access Type: confidential
Valid Redirect URIs:
  - https://vault.pnats.cloud/ui/vault/auth/oidc/oidc/callback
  - https://vault.pnats.cloud/oidc/callback
  - http://localhost:8250/oidc/callback  # CLI authentication
Web Origins: https://vault.pnats.cloud
```

#### Vault OIDC Configuration
```bash
# Enable OIDC auth method
vault auth enable oidc

# Configure OIDC
vault write auth/oidc/config \
    oidc_discovery_url="https://keycloak.pnats.cloud/realms/platform" \
    oidc_client_id="vault" \
    oidc_client_secret="${VAULT_KEYCLOAK_CLIENT_SECRET}" \
    default_role="platform-user"

# Create role mapping
vault write auth/oidc/role/platform-user \
    bound_audiences="vault" \
    allowed_redirect_uris="https://vault.pnats.cloud/ui/vault/auth/oidc/oidc/callback" \
    allowed_redirect_uris="https://vault.pnats.cloud/oidc/callback" \
    allowed_redirect_uris="http://localhost:8250/oidc/callback" \
    user_claim="sub" \
    groups_claim="groups" \
    policies="default,platform-read"

# Create admin role for admins group
vault write auth/oidc/role/platform-admin \
    bound_audiences="vault" \
    allowed_redirect_uris="https://vault.pnats.cloud/ui/vault/auth/oidc/oidc/callback" \
    user_claim="sub" \
    groups_claim="groups" \
    bound_claims='{"groups":["vault-admins"]}' \
    policies="admin,platform-admin"
```

---

### 5. Kargo (Medium Priority)
**Status**: ⚠️ Basic auth (sealed secret)
**Method**: Native OIDC
**OAuth Support**: ✅ Native

#### Keycloak Client Configuration
```yaml
# Keycloak: Create Client "kargo"
Client ID: kargo
Client Protocol: openid-connect
Access Type: confidential
Valid Redirect URIs:
  - https://kargo.pnats.cloud/oauth2/callback
```

#### Kargo Configuration
```yaml
# v0.2.0/platform/charts/kargo/values.yaml
api:
  oidc:
    enabled: true
    issuerURL: https://keycloak.pnats.cloud/realms/platform
    clientID: kargo
    clientSecret: ${KARGO_KEYCLOAK_CLIENT_SECRET}  # From Vault
    cliClientID: kargo-cli
```

---

### 6. OAuth2 Proxy for Apps Without Native OAuth

For applications that don't support native OAuth/OIDC (Temporal UI, Tekton Dashboard, Kubecost), deploy OAuth2 Proxy as middleware.

#### OAuth2 Proxy Deployment Strategy

**Architecture**:
```
User → Ingress → OAuth2 Proxy → Application
                      ↓
                  Keycloak (GitHub SSO)
```

#### Keycloak Client for OAuth2 Proxy
```yaml
# Keycloak: Create Client "oauth2-proxy"
Client ID: oauth2-proxy
Client Protocol: openid-connect
Access Type: confidential
Valid Redirect URIs:
  - https://temporal-ui.pnats.cloud/oauth2/callback
  - https://tekton.pnats.cloud/oauth2/callback
  - https://cost.pnats.cloud/oauth2/callback
  - https://kubevirt.pnats.cloud/oauth2/callback
```

#### OAuth2 Proxy Helm Chart
```yaml
# v0.2.0/platform/charts/oauth2-proxy/values.yaml
config:
  clientID: oauth2-proxy
  clientSecret: ${OAUTH2_PROXY_CLIENT_SECRET}  # From Vault
  cookieSecret: ${OAUTH2_PROXY_COOKIE_SECRET}  # From Vault (random 32 bytes)
  configFile: |-
    provider = "keycloak-oidc"
    provider_display_name = "GitHub (via Keycloak)"
    redirect_url = "https://temporal-ui.pnats.cloud/oauth2/callback"
    oidc_issuer_url = "https://keycloak.pnats.cloud/realms/platform"
    email_domains = [ "*" ]
    cookie_domains = [ ".pnats.cloud" ]
    whitelist_domains = [ ".pnats.cloud" ]
    pass_access_token = true
    pass_user_headers = true
    set_xauthrequest = true
    cookie_secure = true
    cookie_httponly = true
```

#### Ingress Configuration with OAuth2 Proxy
```yaml
# Example: Temporal UI with OAuth2 Proxy
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: temporal-web
  namespace: temporal
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-production
    # OAuth2 Proxy annotations
    nginx.ingress.kubernetes.io/auth-url: "https://$host/oauth2/auth"
    nginx.ingress.kubernetes.io/auth-signin: "https://$host/oauth2/start?rd=$escaped_request_uri"
    nginx.ingress.kubernetes.io/auth-response-headers: "X-Auth-Request-User, X-Auth-Request-Email"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - temporal-ui.pnats.cloud
    secretName: temporal-ui-tls
  rules:
  - host: temporal-ui.pnats.cloud
    http:
      paths:
      - path: /oauth2
        pathType: Prefix
        backend:
          service:
            name: oauth2-proxy
            port:
              number: 4180
      - path: /
        pathType: Prefix
        backend:
          service:
            name: temporal-web
            port:
              number: 8080
```

#### Applications Requiring OAuth2 Proxy
1. **Temporal UI** - temporal-ui.pnats.cloud
2. **Tekton Dashboard** - tekton.pnats.cloud
3. **Kubecost** - cost.pnats.cloud (if no native OAuth in license)
4. **KubeVirt Manager** - kubevirt.pnats.cloud

---

### Summary: Keycloak Integration Roadmap

| Application | Method | Priority | OAuth Support | Status |
|-------------|--------|----------|---------------|--------|
| Backstage | Native OIDC | N/A | ✅ Native | ✅ Complete |
| ArgoCD | Dex connector | High | ✅ Native (Dex) | ⏳ Pending |
| Grafana | Native OAuth | High | ✅ Native | ⏳ Pending |
| Harbor | Native OIDC | High | ✅ Native | ⏳ Pending |
| Vault | OIDC auth method | Medium | ✅ Native | ⏳ Pending |
| Kargo | Native OIDC | Medium | ✅ Native | ⏳ Pending |
| Temporal UI | OAuth2 Proxy | Medium | ❌ Proxy needed | ⏳ Pending |
| Tekton Dashboard | OAuth2 Proxy | Medium | ❌ Proxy needed | ⏳ Pending |
| Kubecost | OAuth2 Proxy | Low | ⚠️ License dependent | ⏳ Pending |
| KubeVirt Manager | OAuth2 Proxy | Low | ⚠️ Limited | ⏳ Pending |
| Uptime Kuma | Built-in | N/A | ❌ Not supported | Keep built-in |
| Verdaccio | NPM auth | N/A | ⚠️ Plugin needed | Keep NPM auth |
| Ceph Dashboard | Built-in | N/A | ⚠️ SAML only | Keep built-in |

---

## Vault Secrets Migration Plan

### Overview
Migrate all secrets from Sealed Secrets and hardcoded values to HashiCorp Vault with External Secrets Operator synchronization.

### Current Secrets Landscape

#### Sealed Secrets (5 apps, ~10 secrets)
- Backstage: github-token, keycloak-client-secret
- Harbor: admin-password, database-password, s3-credentials, registry secrets
- Kargo: admin-secret, users-credentials
- Temporal: postgres credentials

#### Hardcoded in values.yaml (~5 secrets)
- Grafana: admin password ("changeme")
- Keycloak: admin password ("admin"), postgres password ("bn_keycloak")

#### Direct Kubernetes Secrets (~80 secrets)
- ArgoCD: admin password, redis credentials
- Cert-Manager: TLS certificates (51 secrets - keep as-is, managed by cert-manager)
- Monitoring: alertmanager, prometheus credentials
- Various application secrets

### Vault Secret Organization Structure

```
pn-kv/
├── argocd/
│   ├── admin-password (string)
│   ├── redis-password (string)
│   ├── dex-keycloak-client-secret (string)
│   └── notifications-slack-token (string)
├── grafana/
│   ├── admin-password (string)
│   └── keycloak-client-secret (string)
├── harbor/
│   ├── admin-password (string)
│   ├── database-password (string)
│   ├── redis-password (string)
│   ├── registry-http-secret (string)
│   ├── jobservice-secret (string)
│   └── s3-credentials (json: {accessKey, secretKey})
├── keycloak/
│   ├── admin-password (string)
│   ├── postgres-password (string)
│   └── github-oauth-client-secret (string)
├── backstage/
│   ├── github-token (string)
│   └── keycloak-client-secret (string)
├── kargo/
│   ├── admin-password (string)
│   └── users-credentials (json)
├── temporal/
│   ├── postgres-password (string) [NOTE: Managed by Zalando operator]
│   └── keycloak-client-secret (string)
├── vault/
│   ├── keycloak-client-secret (string)
│   └── root-token (string) [emergency access only]
├── oauth2-proxy/
│   ├── client-secret (string)
│   └── cookie-secret (string)
└── tekton/
    └── github-webhook-secret (string)
```

### Vault KV Engine Configuration

```bash
# Enable KV v2 secrets engine (already enabled as pn-kv)
vault secrets enable -path=pn-kv kv-v2

# Create secrets paths
vault kv put pn-kv/grafana admin-password="$(openssl rand -base64 32)"
vault kv put pn-kv/keycloak \
    admin-password="$(openssl rand -base64 32)" \
    postgres-password="$(openssl rand -base64 32)"

# ... and so on for all applications
```

### External Secrets Operator - ClusterSecretStore

Already configured:
```yaml
# Existing: v0.2.0/platform/charts/external-secrets/cluster-secret-store.yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: vault-backend
spec:
  provider:
    vault:
      server: "http://vault-active.vault.svc.cluster.local:8200"
      path: "pn-kv"
      version: "v2"
      auth:
        tokenSecretRef:
          name: "vault-init"
          namespace: "vault"
          key: "root_token"
```

### Migration Procedure (Per Application)

#### Example: Grafana Secrets Migration

**Step 1: Create secrets in Vault**
```bash
# Generate new admin password
GRAFANA_ADMIN_PASSWORD=$(openssl rand -base64 32)

# Store in Vault
vault kv put pn-kv/grafana \
    admin-password="${GRAFANA_ADMIN_PASSWORD}" \
    keycloak-client-secret="${GRAFANA_KEYCLOAK_CLIENT_SECRET}"
```

**Step 2: Create ExternalSecret manifest**
```yaml
# v0.2.0/platform/charts/grafana/external-secrets/grafana-auth.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: grafana-auth
  namespace: monitoring
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: grafana
    creationPolicy: Owner
    template:
      engineVersion: v2
      data:
        admin-password: "{{ .adminPassword }}"
        keycloak-client-secret: "{{ .keycloakClientSecret }}"
  data:
    - secretKey: adminPassword
      remoteRef:
        key: pn-kv/grafana
        property: admin-password
    - secretKey: keycloakClientSecret
      remoteRef:
        key: pn-kv/grafana
        property: keycloak-client-secret
```

**Step 3: Update application values.yaml**
```yaml
# v0.2.0/platform/charts/grafana/values.yaml
# Remove hardcoded password
# adminPassword: changeme  ← DELETE

# Reference external secret
admin:
  existingSecret: grafana
  userKey: admin-user
  passwordKey: admin-password
```

**Step 4: Verify ExternalSecret sync**
```bash
# Check ExternalSecret status
kubectl get externalsecret -n monitoring grafana-auth

# Verify Kubernetes secret created
kubectl get secret -n monitoring grafana -o yaml
```

**Step 5: Restart application**
```bash
kubectl rollout restart deployment/grafana -n monitoring
```

**Step 6: Test authentication**
```bash
# Retrieve password from Vault
vault kv get -field=admin-password pn-kv/grafana

# Test login at https://grafana.pnats.cloud
```

**Step 7: Remove Sealed Secret (if exists)**
```bash
# Delete sealed secret manifest from Git
rm v0.2.0/platform/charts/grafana/secrets/grafana-sealed.yaml
git commit -am "refactor(grafana): migrate secrets to Vault"
```

### Priority Order for Secrets Migration

#### Phase 1: Critical Security (Hardcoded Passwords)
1. Keycloak admin credentials
2. Grafana admin password

#### Phase 2: Application Secrets (High Value)
3. ArgoCD admin password + Dex client secret
4. Harbor admin password + database password + S3 credentials
5. Vault OIDC client secrets

#### Phase 3: Sealed Secrets Migration
6. Backstage (GitHub token, Keycloak secret)
7. Kargo (admin, users credentials)
8. Temporal (if not using Zalando auto-generated)

#### Phase 4: Service Accounts & API Tokens
9. Tekton webhook secrets
10. External-DNS provider credentials
11. Monitoring webhook tokens

---

## Crossplane Implementation Plan

### Overview
Implement Crossplane compositions to provision common infrastructure resources declaratively, enabling self-service and GitOps workflows.

### Current State
- ✅ Crossplane core installed
- ✅ Vault token configured (crossplane-init secret)
- ❌ No providers installed
- ❌ No compositions created
- ❌ Zero resources provisioned

### Target State
- ✅ Kubernetes provider for in-cluster resources
- ✅ Helm provider for Helm chart deployments
- ✅ Compositions for: PostgreSQL, Redis, S3 buckets, monitoring
- ✅ Self-service resource provisioning via Claims

---

### Step 1: Install Crossplane Providers

#### Provider: provider-kubernetes
**Purpose**: Manage Kubernetes resources via Crossplane

```yaml
# v0.2.0/platform/charts/crossplane/providers/provider-kubernetes.yaml
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: provider-kubernetes
spec:
  package: xpkg.upbound.io/crossplane-contrib/provider-kubernetes:v0.11.0
  packagePullPolicy: IfNotPresent
  revisionActivationPolicy: Automatic
  revisionHistoryLimit: 1
```

#### Provider: provider-helm
**Purpose**: Deploy Helm charts via Crossplane

```yaml
# v0.2.0/platform/charts/crossplane/providers/provider-helm.yaml
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: provider-helm
spec:
  package: xpkg.upbound.io/crossplane-contrib/provider-helm:v0.16.0
```

#### ProviderConfig: Kubernetes
```yaml
# v0.2.0/platform/charts/crossplane/provider-configs/kubernetes-config.yaml
apiVersion: kubernetes.crossplane.io/v1alpha1
kind: ProviderConfig
metadata:
  name: kubernetes-provider
spec:
  credentials:
    source: InjectedIdentity  # Use Crossplane service account
```

#### ProviderConfig: Helm
```yaml
# v0.2.0/platform/charts/crossplane/provider-configs/helm-config.yaml
apiVersion: helm.crossplane.io/v1beta1
kind: ProviderConfig
metadata:
  name: helm-provider
spec:
  credentials:
    source: InjectedIdentity
```

---

### Step 2: Create CompositeResourceDefinitions (XRDs)

#### XRD: PostgreSQL Cluster

```yaml
# v0.2.0/platform/charts/crossplane/compositions/xrd-postgresql.yaml
apiVersion: apiextensions.crossplane.io/v1
kind: CompositeResourceDefinition
metadata:
  name: xpostgresqls.platform.pnats.cloud
spec:
  group: platform.pnats.cloud
  names:
    kind: XPostgreSQL
    plural: xpostgresqls
  claimNames:
    kind: PostgreSQL
    plural: postgresqls
  versions:
  - name: v1alpha1
    served: true
    referenceable: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              parameters:
                type: object
                properties:
                  instanceCount:
                    type: integer
                    description: Number of PostgreSQL instances
                    default: 3
                  storageSize:
                    type: string
                    description: Storage size per instance
                    default: "50Gi"
                  version:
                    type: string
                    description: PostgreSQL version
                    default: "16"
                  databases:
                    type: array
                    description: Databases to create
                    items:
                      type: string
                  enableMonitoring:
                    type: boolean
                    description: Enable Prometheus monitoring
                    default: true
                  enableBackups:
                    type: boolean
                    description: Enable automated backups
                    default: true
                required:
                  - instanceCount
                  - storageSize
```

#### Composition: PostgreSQL via Zalando Operator

```yaml
# v0.2.0/platform/charts/crossplane/compositions/composition-postgresql.yaml
apiVersion: apiextensions.crossplane.io/v1
kind: Composition
metadata:
  name: postgresql-zalando
  labels:
    provider: zalando
spec:
  writeConnectionSecretsToNamespace: crossplane-system
  compositeTypeRef:
    apiVersion: platform.pnats.cloud/v1alpha1
    kind: XPostgreSQL

  resources:
  # 1. Namespace for PostgreSQL cluster
  - name: namespace
    base:
      apiVersion: kubernetes.crossplane.io/v1alpha1
      kind: Object
      spec:
        forProvider:
          manifest:
            apiVersion: v1
            kind: Namespace
            metadata:
              name: # patched
    patches:
    - fromFieldPath: metadata.name
      toFieldPath: spec.forProvider.manifest.metadata.name
      transforms:
      - type: string
        string:
          fmt: "postgres-%s"

  # 2. PostgreSQL cluster via Zalando operator
  - name: postgresql-cluster
    base:
      apiVersion: kubernetes.crossplane.io/v1alpha1
      kind: Object
      spec:
        forProvider:
          manifest:
            apiVersion: acid.zalan.do/v1
            kind: postgresql
            metadata:
              name: # patched
              namespace: # patched
            spec:
              teamId: platform
              postgresql:
                version: # patched
              numberOfInstances: # patched
              volume:
                size: # patched
                storageClass: ceph-block
              enableMasterLoadBalancer: false
              enableReplicaLoadBalancer: false
              enableConnectionPooler: true
              enableLogicalBackup: # patched
              users:
                app_user:
                - superuser
                - createdb
              databases:
                app_db: app_user  # patched
              resources:
                requests:
                  cpu: 500m
                  memory: 2Gi
                limits:
                  cpu: 2000m
                  memory: 4Gi
    patches:
    - fromFieldPath: metadata.name
      toFieldPath: spec.forProvider.manifest.metadata.name
    - fromFieldPath: metadata.name
      toFieldPath: spec.forProvider.manifest.metadata.namespace
      transforms:
      - type: string
        string:
          fmt: "postgres-%s"
    - fromFieldPath: spec.parameters.version
      toFieldPath: spec.forProvider.manifest.spec.postgresql.version
    - fromFieldPath: spec.parameters.instanceCount
      toFieldPath: spec.forProvider.manifest.spec.numberOfInstances
    - fromFieldPath: spec.parameters.storageSize
      toFieldPath: spec.forProvider.manifest.spec.volume.size
    - fromFieldPath: spec.parameters.enableBackups
      toFieldPath: spec.forProvider.manifest.spec.enableLogicalBackup

  # 3. ServiceMonitor for Prometheus (if monitoring enabled)
  - name: servicemonitor
    base:
      apiVersion: kubernetes.crossplane.io/v1alpha1
      kind: Object
      spec:
        forProvider:
          manifest:
            apiVersion: monitoring.coreos.com/v1
            kind: ServiceMonitor
            metadata:
              name: # patched
              namespace: # patched
            spec:
              selector:
                matchLabels:
                  application: spilo
              endpoints:
              - port: exporter
                interval: 30s
    patches:
    - fromFieldPath: metadata.name
      toFieldPath: spec.forProvider.manifest.metadata.name
      transforms:
      - type: string
        string:
          fmt: "%s-postgres"
    - fromFieldPath: metadata.name
      toFieldPath: spec.forProvider.manifest.metadata.namespace
      transforms:
      - type: string
        string:
          fmt: "postgres-%s"
    - type: PatchSet
      patchSetName: monitoring-enabled

  patchSets:
  - name: monitoring-enabled
    patches:
    - fromFieldPath: spec.parameters.enableMonitoring
      toFieldPath: spec.forProvider.manifest
      policy:
        fromFieldPath: Required
      transforms:
      - type: match
        match:
          patterns:
          - type: literal
            literal: false
            result:
              apiVersion: v1
              kind: ConfigMap  # Dummy resource when monitoring disabled
              metadata:
                name: noop
```

#### Usage Example: Claim a PostgreSQL Cluster

```yaml
# Application developer creates this claim
apiVersion: platform.pnats.cloud/v1alpha1
kind: PostgreSQL
metadata:
  name: my-app-db
  namespace: my-app
spec:
  parameters:
    instanceCount: 3
    storageSize: 100Gi
    version: "16"
    databases:
    - my_app
    - my_app_cache
    enableMonitoring: true
    enableBackups: true
  compositionSelector:
    matchLabels:
      provider: zalando
  writeConnectionSecretToRef:
    name: my-app-db-credentials
```

**Result**: Crossplane provisions:
- Namespace `postgres-my-app-db`
- 3-node PostgreSQL 16 cluster with 100Gi storage each
- Databases `my_app` and `my_app_cache`
- Connection credentials secret in `my-app` namespace
- ServiceMonitor for Prometheus
- Automated backups enabled

---

#### XRD: Redis Cluster

```yaml
# v0.2.0/platform/charts/crossplane/compositions/xrd-redis.yaml
apiVersion: apiextensions.crossplane.io/v1
kind: CompositeResourceDefinition
metadata:
  name: xredis.platform.pnats.cloud
spec:
  group: platform.pnats.cloud
  names:
    kind: XRedis
    plural: xredis
  claimNames:
    kind: Redis
    plural: redis
  versions:
  - name: v1alpha1
    served: true
    referenceable: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              parameters:
                type: object
                properties:
                  mode:
                    type: string
                    description: "standalone or cluster"
                    default: "standalone"
                    enum:
                    - standalone
                    - cluster
                  replicas:
                    type: integer
                    description: Number of Redis replicas
                    default: 1
                  storageSize:
                    type: string
                    description: Storage size (if persistence enabled)
                    default: "10Gi"
                  persistence:
                    type: boolean
                    description: Enable persistent storage
                    default: true
                  version:
                    type: string
                    description: Redis version
                    default: "7.2"
```

#### Composition: Redis via Redis Operator

Similar pattern to PostgreSQL composition using Redis Operator CRDs.

---

#### XRD: S3 Bucket (Ceph RGW)

```yaml
# v0.2.0/platform/charts/crossplane/compositions/xrd-s3bucket.yaml
apiVersion: apiextensions.crossplane.io/v1
kind: CompositeResourceDefinition
metadata:
  name: xs3buckets.platform.pnats.cloud
spec:
  group: platform.pnats.cloud
  names:
    kind: XS3Bucket
    plural: xs3buckets
  claimNames:
    kind: S3Bucket
    plural: s3buckets
  versions:
  - name: v1alpha1
    served: true
    referenceable: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              parameters:
                type: object
                properties:
                  bucketName:
                    type: string
                    description: S3 bucket name
                  region:
                    type: string
                    description: S3 region
                    default: "ap-south-2"
                  publicAccess:
                    type: boolean
                    description: Allow public read access
                    default: false
```

#### Composition: S3 Bucket via ObjectBucketClaim

```yaml
# v0.2.0/platform/charts/crossplane/compositions/composition-s3bucket.yaml
apiVersion: apiextensions.crossplane.io/v1
kind: Composition
metadata:
  name: s3bucket-ceph
spec:
  compositeTypeRef:
    apiVersion: platform.pnats.cloud/v1alpha1
    kind: XS3Bucket

  resources:
  - name: object-bucket-claim
    base:
      apiVersion: kubernetes.crossplane.io/v1alpha1
      kind: Object
      spec:
        forProvider:
          manifest:
            apiVersion: objectbucket.io/v1alpha1
            kind: ObjectBucketClaim
            metadata:
              name: # patched
              namespace: # patched
            spec:
              generateBucketName: # patched
              storageClassName: ceph-bucket
    patches:
    - fromFieldPath: spec.parameters.bucketName
      toFieldPath: spec.forProvider.manifest.spec.generateBucketName
```

---

### Step 3: Migrate Existing Resources to Crossplane

#### Migration Candidate 1: Temporal PostgreSQL

**Current**: Manual PostgreSQL manifest via Zalando operator
**Target**: Crossplane PostgreSQL claim

```yaml
# v0.2.0/platform/charts/temporal-db/postgresql-claim.yaml
apiVersion: platform.pnats.cloud/v1alpha1
kind: PostgreSQL
metadata:
  name: temporal
  namespace: temporal
spec:
  parameters:
    instanceCount: 3
    storageSize: 50Gi
    version: "16"
    databases:
    - temporal
    - temporal_visibility
    enableMonitoring: true
    enableBackups: true
  compositionSelector:
    matchLabels:
      provider: zalando
  writeConnectionSecretToRef:
    name: temporal-postgres-credentials
```

**Migration Steps**:
1. Create Crossplane PostgreSQL claim
2. Wait for new cluster to provision
3. Migrate data from old cluster to new cluster
4. Update Temporal to use new credentials
5. Delete old PostgreSQL manifest
6. Verify Temporal workflows functioning

#### Migration Candidate 2: Harbor S3 Bucket

**Current**: Manual Ceph RGW bucket configuration
**Target**: Crossplane S3Bucket claim

```yaml
# v0.2.0/platform/charts/harbor/s3-bucket-claim.yaml
apiVersion: platform.pnats.cloud/v1alpha1
kind: S3Bucket
metadata:
  name: harbor-images
  namespace: harbor
spec:
  parameters:
    bucketName: harbor
    region: ap-south-2
    publicAccess: false
  writeConnectionSecretToRef:
    name: harbor-s3-credentials
```

---

### Step 4: Self-Service Developer Experience

With Crossplane compositions in place, developers can provision infrastructure via simple YAML claims:

```yaml
# Developer creates this in their namespace
apiVersion: platform.pnats.cloud/v1alpha1
kind: PostgreSQL
metadata:
  name: my-service-db
  namespace: my-team
spec:
  parameters:
    instanceCount: 2
    storageSize: 20Gi
  writeConnectionSecretToRef:
    name: db-credentials
---
apiVersion: platform.pnats.cloud/v1alpha1
kind: Redis
metadata:
  name: my-service-cache
  namespace: my-team
spec:
  parameters:
    mode: standalone
    persistence: false
  writeConnectionSecretToRef:
    name: redis-credentials
```

**Result**: Automatically provisions fully-configured PostgreSQL cluster and Redis instance with:
- Monitoring enabled
- Backups configured
- Credentials stored in secrets
- GitOps-friendly (declarative, versioned)

---

## Implementation Phases

### Phase 1: Security Foundation (Immediate)
**Priority**: 🔴 Critical

#### Tasks
1. Rotate Grafana admin password
2. Rotate Keycloak admin credentials
3. Move secrets to Vault
4. Create External Secrets for rotated passwords
5. Deploy OAuth2 Proxy for unauthenticated UIs

**Deliverables**:
- ✅ No hardcoded passwords in Git
- ✅ Grafana admin password in Vault
- ✅ Keycloak admin password in Vault
- ✅ Temporal UI protected by OAuth2 Proxy
- ✅ Tekton Dashboard protected by OAuth2 Proxy
- ✅ Kubecost protected by OAuth2 Proxy

**Success Criteria**:
- All web UIs require authentication
- No passwords visible in Git history (squash/filter if needed)
- All admin accounts use strong generated passwords

---

### Phase 2: Keycloak SSO Integration (High Priority)
**Priority**: 🟡 High

#### Tasks
1. Configure GitHub OAuth in Keycloak
2. Create Keycloak clients for: ArgoCD, Grafana, Harbor, Vault, Kargo
3. Configure ArgoCD Dex connector
4. Configure Grafana native OAuth
5. Configure Harbor OIDC
6. Configure Vault OIDC auth method
7. Configure Kargo OIDC
8. Test end-to-end login flows

**Deliverables**:
- ✅ GitHub → Keycloak → Applications SSO working
- ✅ Users authenticate once, access all apps
- ✅ Organization-based access control (GitHub org membership)
- ✅ Role-based access via Keycloak groups

**Success Criteria**:
- User can log in to all 6 apps with single GitHub OAuth
- Access automatically revoked when removed from GitHub org
- Proper role mapping (admins, editors, viewers)

---

### Phase 3: Vault Secrets Migration (Medium Priority)
**Priority**: 🟢 Medium

#### Tasks
1. Create Vault secret structure (pn-kv paths)
2. Migrate Sealed Secrets to Vault (5 apps)
3. Create External Secret manifests for all apps
4. Update application configurations to use External Secrets
5. Test secret rotation procedures
6. Delete Sealed Secret manifests from Git

**Deliverables**:
- ✅ All application secrets in Vault
- ✅ External Secrets syncing to Kubernetes
- ✅ Sealed Secrets deprecated and removed
- ✅ Secret rotation documented and tested

**Success Criteria**:
- Zero Sealed Secrets remaining
- All secrets rotatable via Vault API
- Applications automatically pick up rotated secrets
- Audit log of all secret access in Vault

---

### Phase 4: Crossplane Infrastructure (Low Priority)
**Priority**: ⚪ Low

#### Tasks
1. Install Crossplane providers (kubernetes, helm)
2. Create XRDs for PostgreSQL, Redis, S3
3. Create Compositions using Zalando PG, Redis Operator, Ceph RGW
4. Test composition functionality
5. Migrate Temporal PostgreSQL to Crossplane
6. Migrate Harbor S3 to Crossplane
7. Document developer self-service workflows

**Deliverables**:
- ✅ Crossplane providers operational
- ✅ 3 compositions available (PostgreSQL, Redis, S3)
- ✅ At least 2 resources migrated to Crossplane
- ✅ Developer documentation for claiming resources

**Success Criteria**:
- Developers can provision PostgreSQL with single YAML claim
- Resources auto-configured with monitoring, backups
- Resource lifecycle managed via GitOps
- Reduced ops team toil for provisioning

---

## Validation & Testing

### Phase 1: Security Validation

#### Test 1: Password Rotation
```bash
# Rotate Grafana password
NEW_PASSWORD=$(openssl rand -base64 32)
vault kv put pn-kv/grafana admin-password="${NEW_PASSWORD}"

# Wait for External Secret sync (max 1 hour refresh interval)
kubectl get externalsecret -n monitoring grafana-auth -w

# Test login with new password
curl -u admin:${NEW_PASSWORD} https://grafana.pnats.cloud/api/health
```

#### Test 2: OAuth2 Proxy Protection
```bash
# Attempt unauthenticated access (should redirect to Keycloak)
curl -I https://temporal-ui.pnats.cloud
# Expected: 302 redirect to keycloak.pnats.cloud

# Authenticated access (should work)
# Login via browser, extract cookie, test API access
```

---

### Phase 2: SSO Validation

#### Test 1: GitHub → Keycloak → ArgoCD Login
```bash
# 1. Navigate to https://argocd.pnats.cloud
# 2. Click "Login via Keycloak (GitHub SSO)"
# 3. Redirected to Keycloak
# 4. Click "GitHub"
# 5. Redirected to GitHub (OAuth consent)
# 6. Approve access
# 7. Redirected back to ArgoCD (logged in)
# 8. Verify username and groups from GitHub
```

#### Test 2: Access Control (GitHub Org Membership)
```bash
# User IN GitHub org pnow-devsupreme → Access granted
# User NOT in org → Access denied

# Test by creating test user not in org
# Attempt login → Should see error "Not a member of required organization"
```

#### Test 3: Role Mapping
```bash
# GitHub team: pnow-devsupreme/admins → ArgoCD role:admin
# GitHub team: pnow-devsupreme/developers → ArgoCD role:developer

# Verify with:
argocd account get-user-info
# Should show correct groups and permissions
```

---

### Phase 3: Vault Integration Validation

#### Test 1: External Secret Sync
```bash
# Update secret in Vault
vault kv put pn-kv/harbor database-password="new-password-123"

# Wait for sync (max 1 hour)
kubectl get externalsecret -n harbor harbor-db -o jsonpath='{.status.syncedResourceVersion}'

# Verify Kubernetes secret updated
kubectl get secret -n harbor harbor-database -o jsonpath='{.data.password}' | base64 -d
```

#### Test 2: Secret Rotation Impact
```bash
# Rotate secret and verify application still works
vault kv put pn-kv/backstage github-token="new-github-token"

# Wait for sync
sleep 60

# Restart Backstage to pick up new token
kubectl rollout restart deployment/backstage -n backstage

# Test Backstage GitHub integration still works
curl https://backstage.pnats.cloud/api/catalog/entities | jq .
```

---

### Phase 4: Crossplane Validation

#### Test 1: PostgreSQL Provisioning
```bash
# Create claim
kubectl apply -f - <<EOF
apiVersion: platform.pnats.cloud/v1alpha1
kind: PostgreSQL
metadata:
  name: test-db
  namespace: default
spec:
  parameters:
    instanceCount: 2
    storageSize: 10Gi
  writeConnectionSecretToRef:
    name: test-db-creds
EOF

# Watch provisioning
kubectl get postgresql test-db -w

# Verify cluster created
kubectl get postgresql -n postgres-test-db

# Verify credentials secret
kubectl get secret test-db-creds -o yaml

# Test connection
kubectl run psql-test --rm -i --tty --image=postgres:16 --restart=Never -- \
  psql -h test-db.postgres-test-db.svc -U app_user -d app_db
```

#### Test 2: Resource Deletion & Cleanup
```bash
# Delete claim
kubectl delete postgresql test-db

# Verify PostgreSQL cluster deleted
kubectl get postgresql -n postgres-test-db
# Should be empty

# Verify namespace cleaned up
kubectl get namespace postgres-test-db
# Should not exist or be in Terminating state
```

---

## Rollback Procedures

### Phase 1: Rollback - Revert to Hardcoded Passwords

If External Secrets fail or Vault becomes unavailable:

```bash
# Emergency: Revert Grafana to hardcoded password
# Edit values.yaml
cd v0.2.0/platform/charts/grafana
git revert <commit-hash-of-vault-migration>

# Sync ArgoCD
argocd app sync grafana

# Manually set password in values.yaml temporarily
kubectl edit configmap grafana -n monitoring
# Add back: adminPassword: <emergency-password>

kubectl rollout restart deployment/grafana -n monitoring
```

### Phase 2: Rollback - Disable Keycloak SSO

If Keycloak authentication fails:

```bash
# ArgoCD: Re-enable admin user bypass
kubectl edit configmap argocd-cm -n argocd
# Remove or comment out dex.config

# Grafana: Disable OAuth, enable login form
kubectl edit configmap grafana -n monitoring
# Set: auth.generic_oauth.enabled = false
# Set: auth.disable_login_form = false

# Restart applications
kubectl rollout restart deployment/argocd-server -n argocd
kubectl rollout restart deployment/grafana -n monitoring
```

### Phase 3: Rollback - Revert to Sealed Secrets

If Vault External Secrets fail:

```bash
# Restore sealed secret manifests from Git history
git log --all --full-history -- "**/*sealed.yaml"
git checkout <commit> -- v0.2.0/platform/charts/*/secrets/*sealed.yaml

# Re-apply sealed secrets
kubectl apply -f v0.2.0/platform/charts/backstage/secrets/
kubectl apply -f v0.2.0/platform/charts/harbor/secrets/

# Delete External Secrets
kubectl delete externalsecret -n backstage backstage-secrets
kubectl delete externalsecret -n harbor harbor-secrets

# Restart applications to pick up sealed secrets
kubectl rollout restart deployment -n backstage
kubectl rollout restart deployment -n harbor
```

### Phase 4: Rollback - Revert Crossplane Resources

If Crossplane-managed resources fail:

```bash
# Backup Crossplane-managed data BEFORE rollback
# For PostgreSQL: pg_dump
kubectl exec -n postgres-temporal temporal-0 -- \
  pg_dump -U temporal temporal > temporal-backup.sql

# Delete Crossplane claim (keeps actual resource if policy = Orphan)
kubectl delete postgresql temporal

# Restore manual PostgreSQL manifest
kubectl apply -f v0.2.0/platform/charts/temporal-db/postgresql-manual.yaml

# Restore data if needed
kubectl exec -n temporal temporal-postgres-0 -- \
  psql -U temporal temporal < temporal-backup.sql
```

---

## Success Metrics

### Security Metrics
- ✅ Zero hardcoded passwords in Git repositories
- ✅ 100% of web UIs require authentication
- ✅ All admin accounts use 32+ character generated passwords
- ✅ Secret rotation tested and documented for all apps
- ✅ Vault audit log enabled and monitored

### SSO Adoption Metrics
- ✅ 10/15 web UI applications using Keycloak SSO
- ✅ Single GitHub OAuth for all supported apps
- ✅ Organization-based access control enforced
- ✅ Role-based access working (admin, editor, viewer)
- ✅ User login time < 5 seconds (GitHub → Keycloak → App)

### Operational Metrics
- ✅ All secrets centralized in Vault (80+ secrets)
- ✅ External Secrets sync success rate > 99%
- ✅ Secret rotation downtime = 0 (graceful rotation)
- ✅ Crossplane resource provisioning time < 5 minutes
- ✅ Developer self-service resource claims functioning

### Production Readiness Scorecard

| Category | Current | Target | Status |
|----------|---------|--------|--------|
| Authentication | 1/15 apps use SSO | 10/15 apps use SSO | 🔴 Not Ready |
| Secrets Management | Fragmented (3 systems) | Centralized (Vault) | 🔴 Not Ready |
| Infrastructure as Code | Manual provisioning | Crossplane compositions | 🔴 Not Ready |
| Security Posture | Hardcoded passwords | Zero secrets in Git | 🔴 Not Ready |
| Observability | Metrics/logs/traces | + Audit logs | 🟡 Partial |
| High Availability | Most apps HA | All critical apps HA | 🟢 Ready |
| Disaster Recovery | Ad-hoc backups | Automated DR tested | 🟡 Partial |

**Overall Production Readiness**: 🔴 **30%** (3/10 categories complete)

---

## Next Steps

1. **Review this plan** with team and stakeholders
2. **Prioritize phases** based on business risk and impact
3. **Assign ownership** for each phase to team members
4. **Create tracking** (Linear/Jira issues) for each task
5. **Execute Phase 1** (Security Foundation) immediately
6. **Weekly progress reviews** until production-ready

---

## Appendix: Reference Links

### Keycloak Documentation
- [Keycloak OIDC Configuration](https://www.keycloak.org/docs/latest/server_admin/#_oidc)
- [GitHub Identity Provider](https://www.keycloak.org/docs/latest/server_admin/#_github)
- [Keycloak Client Mappers](https://www.keycloak.org/docs/latest/server_admin/#_protocol-mappers)

### Vault Documentation
- [Vault KV Secrets Engine v2](https://developer.hashicorp.com/vault/docs/secrets/kv/kv-v2)
- [Vault OIDC Auth Method](https://developer.hashicorp.com/vault/docs/auth/jwt)
- [Vault External Secrets Integration](https://external-secrets.io/latest/provider/hashicorp-vault/)

### Crossplane Documentation
- [Crossplane Compositions](https://docs.crossplane.io/latest/concepts/compositions/)
- [Provider Kubernetes](https://marketplace.upbound.io/providers/crossplane-contrib/provider-kubernetes/)
- [Provider Helm](https://marketplace.upbound.io/providers/crossplane-contrib/provider-helm/)

### OAuth2 Proxy
- [OAuth2 Proxy Documentation](https://oauth2-proxy.github.io/oauth2-proxy/)
- [Keycloak OIDC Provider](https://oauth2-proxy.github.io/oauth2-proxy/docs/configuration/oauth_provider#keycloak-oidc-auth-provider)

### Application-Specific SSO Guides
- [ArgoCD Dex](https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/)
- [Grafana OAuth](https://grafana.com/docs/grafana/latest/setup-grafana/configure-security/configure-authentication/generic-oauth/)
- [Harbor OIDC](https://goharbor.io/docs/2.9.0/administration/configure-authentication/oidc-auth/)
- [Vault OIDC](https://developer.hashicorp.com/vault/tutorials/auth-methods/oidc-auth)

---

**End of Document**

For application dependencies, see [APP-DEPENDENCIES.md](APP-DEPENDENCIES.md).
