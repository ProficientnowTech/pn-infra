# Keycloak - Identity and Access Management

Enterprise-grade identity and access management solution providing SSO, OIDC, SAML 2.0, and OAuth 2.0 for the ProficientNow platform.

## Overview

This chart deploys Keycloak with:
- **Embedded PostgreSQL database** for high availability
- **Sealed Secrets** for credential management
- **Crossplane GitOps** for declarative Keycloak configuration
- **Pre-configured realm** (`proficientnow`) with OIDC/SAML support
- **GitHub OAuth** identity provider integration
- **OIDC clients** for ArgoCD, Grafana, Backstage pre-configured
- **Default user groups** (platform-admins, platform-developers, platform-viewers)
- **ArgoCD sync-waves** for ordered deployment

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                          GitOps Flow                                 │
│                                                                      │
│  values.yaml → ArgoCD → Crossplane → Keycloak API                  │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                    Keycloak (2 replicas)                     │
│  ┌───────────────────────────────────────────────────────┐  │
│  │   Realm: proficientnow (Crossplane CRD)               │  │
│  │   ├── Identity Providers (Crossplane CRD)             │  │
│  │   │   ├── GitHub OAuth ✓                              │  │
│  │   │   └── Google OAuth (disabled)                     │  │
│  │   ├── OIDC Clients (Crossplane CRD)                   │  │
│  │   │   ├── ArgoCD ✓                                    │  │
│  │   │   ├── Grafana ✓                                   │  │
│  │   │   └── Backstage ✓                                 │  │
│  │   └── Groups (Crossplane CRD)                         │  │
│  │       ├── platform-admins                             │  │
│  │       ├── platform-developers                         │  │
│  │       └── platform-viewers                            │  │
│  └───────────────────────────────────────────────────────┘  │
└──────────────────────┬──────────────────────────────────────┘
                       │
           ┌───────────┴───────────┐
           │                       │
    ┌──────▼──────┐         ┌─────▼──────┐
    │  PostgreSQL │         │ Crossplane │
    │  (embedded) │         │  Provider  │
    └─────────────┘         └────────────┘
```

### Deployment Order (ArgoCD Sync Waves)

```
Wave 0: ProviderConfig (Crossplane → Keycloak connection)
   ↓
Wave 1: Realm (proficientnow)
   ↓
Wave 2: Clients (ArgoCD, Grafana, Backstage)
   ↓
Wave 3: Identity Providers (GitHub, Google)
   ↓
Wave 4: Groups (platform-admins, platform-developers, platform-viewers)
```

## Prerequisites

1. **Crossplane** with Keycloak Provider must be installed:
   ```bash
   kubectl get providers
   # Should show: provider-keycloak
   ```

2. **Storage Class** `plt-blk-hdd-repl` must be available

3. **Ingress Controller** (nginx) with cert-manager

## Installation

### Automated Secret Initialization

This chart includes a **safe, automated secret initialization Job** that:

✅ **Creates secrets ONLY if they don't exist** (prevents accidental credential rotation)
✅ **Generates strong random passwords automatically**
✅ **Runs as ArgoCD PreSync hook** (executes before main deployment)
✅ **Never modifies existing secrets** (database-safe)

**What gets created:**
- `keycloak-admin-secret` - Keycloak admin console password
- `keycloak-postgresql-secret` - PostgreSQL database credentials
- `keycloak-github-oauth` - GitHub OAuth credentials (placeholder values)

**Safety guarantees:**
1. Secrets are generated **ONCE** and never modified automatically
2. Existing secrets are always **skipped** to prevent breaking database connections
3. To rotate credentials, you must **manually delete the secret first**

### Step 1: (Optional) Pre-Create Secrets

If you want to control the credentials instead of auto-generation:

```bash
# Create namespace first
kubectl create namespace keycloak

# 1. Keycloak Admin Password (optional - will be auto-generated if not present)
kubectl create secret generic keycloak-admin-secret \
  --from-literal=admin-password='YOUR_STRONG_ADMIN_PASSWORD' \
  -n keycloak

# 2. PostgreSQL Passwords (optional - will be auto-generated if not present)
kubectl create secret generic keycloak-postgresql-secret \
  --from-literal=postgres-password='YOUR_POSTGRES_ADMIN_PASSWORD' \
  --from-literal=password='YOUR_KEYCLOAK_DB_PASSWORD' \
  -n keycloak

# 3. GitHub OAuth Credentials (recommended - replace placeholder)
# First, create GitHub OAuth App at: https://github.com/settings/developers
# Authorization callback URL: https://keycloak.pnats.cloud/realms/proficientnow/broker/github/endpoint

kubectl create secret generic keycloak-github-oauth \
  --from-literal=client-id='YOUR_GITHUB_OAUTH_CLIENT_ID' \
  --from-literal=client-secret='YOUR_GITHUB_OAUTH_CLIENT_SECRET' \
  -n keycloak
```

### Step 2: Install Keycloak

```bash
# Add dependencies
helm dependency update

# Install
helm install keycloak . -n keycloak --create-namespace

# Or upgrade
helm upgrade --install keycloak . -n keycloak
```

### Step 3: Verify Installation

```bash
# Check secret initialization job
kubectl get jobs -n keycloak | grep secret-init
kubectl logs -l app.kubernetes.io/component=secret-init -n keycloak

# Verify secrets were created
kubectl get secrets -n keycloak | grep -E "keycloak-admin|keycloak-postgresql|keycloak-github"

# Check Keycloak pods
kubectl get pods -n keycloak

# Check Crossplane resources
kubectl get realm,client,identityprovider,group -n keycloak

# Verify Crossplane provider config
kubectl get providerconfig -n keycloak

# Access Keycloak
echo "https://keycloak.pnats.cloud"
```

### Retrieving Auto-Generated Credentials

If secrets were auto-generated, retrieve them:

```bash
# Keycloak admin password
kubectl get secret keycloak-admin-secret -n keycloak -o jsonpath='{.data.admin-password}' | base64 -d
echo

# PostgreSQL passwords
kubectl get secret keycloak-postgresql-secret -n keycloak -o jsonpath='{.data.postgres-password}' | base64 -d
echo
kubectl get secret keycloak-postgresql-secret -n keycloak -o jsonpath='{.data.password}' | base64 -d
echo

# Check if GitHub OAuth needs updating
kubectl get secret keycloak-github-oauth -n keycloak -o jsonpath='{.data.client-id}' | base64 -d
# If this shows "REPLACE_WITH_GITHUB_CLIENT_ID", update the secret with real credentials
```

### Updating GitHub OAuth Credentials

If the placeholder was created, update it:

```bash
# Delete placeholder secret
kubectl delete secret keycloak-github-oauth -n keycloak

# Create with real credentials
kubectl create secret generic keycloak-github-oauth \
  --from-literal=client-id='YOUR_REAL_GITHUB_CLIENT_ID' \
  --from-literal=client-secret='YOUR_REAL_GITHUB_CLIENT_SECRET' \
  -n keycloak

# Restart Keycloak to pick up new credentials
kubectl rollout restart deployment keycloak-keycloak -n keycloak
```

## GitOps Configuration Management

### How It Works

This chart uses **Crossplane Keycloak Provider** for declarative configuration management. All Keycloak resources (realms, clients, identity providers, groups) are defined in `values.yaml` and managed as Kubernetes Custom Resources.

**Benefits:**
- ✅ Full GitOps workflow - configuration in git
- ✅ Drift detection and automatic reconciliation
- ✅ Ordered deployment via ArgoCD sync-waves
- ✅ No manual Keycloak admin console changes needed
- ✅ Infrastructure as Code for identity management

### Adding a New OIDC Client

Edit `values.yaml`:

```yaml
clients:
  # ... existing clients ...

  # Add new client
  - name: my-new-app
    enabled: true
    clientId: my-new-app
    displayName: "My New Application"
    description: "Custom application"
    publicClient: false
    secret: "REPLACE_WITH_CLIENT_SECRET"
    protocol: openid-connect

    # Flow Configuration
    standardFlowEnabled: true
    implicitFlowEnabled: false
    directAccessGrantsEnabled: true

    # URLs
    rootUrl: "https://myapp.pnats.cloud"
    baseUrl: "https://myapp.pnats.cloud"
    redirectUris:
      - "https://myapp.pnats.cloud/oauth/callback"
    webOrigins:
      - "https://myapp.pnats.cloud"

    # Create Kubernetes Secret with credentials
    createSecret: true
```

Commit and push - ArgoCD will automatically create the client in Keycloak!

### Adding a New Identity Provider

For Azure AD OIDC provider:

```yaml
identityProviders:
  # ... existing providers ...

  # Add Azure AD
  - alias: azure-ad
    enabled: true
    providerId: oidc
    displayName: "Azure Active Directory"

    config:
      clientId: "YOUR_AZURE_CLIENT_ID"
      clientSecretSecretName: keycloak-azure-oauth
      clientSecretSecretKey: client-secret
      authorizationUrl: "https://login.microsoftonline.com/{tenant}/oauth2/v2.0/authorize"
      tokenUrl: "https://login.microsoftonline.com/{tenant}/oauth2/v2.0/token"
      userInfoUrl: "https://graph.microsoft.com/oidc/userinfo"
      jwksUrl: "https://login.microsoftonline.com/{tenant}/discovery/v2.0/keys"
      issuer: "https://login.microsoftonline.com/{tenant}/v2.0"
      defaultScope: "openid profile email"
      syncMode: "IMPORT"
```

Create the sealed secret for Azure credentials:

```bash
kubectl create secret generic keycloak-azure-oauth \
  --from-literal=client-secret='YOUR_AZURE_CLIENT_SECRET' \
  --dry-run=client -o yaml | \
  kubeseal --controller-name=sealed-secrets \
           --controller-namespace=sealed-secrets \
           --format=yaml | \
  kubectl apply -f - -n keycloak
```

### Adding a New Group

```yaml
groups:
  # ... existing groups ...

  # Add custom group
  - name: platform-auditors
    enabled: true
    path: "/platform-auditors"
    attributes:
      description:
        - "Platform auditors with read-only audit access"
    realmRoles:
      - offline_access
    clientRoles:
      argocd:
        - viewer
      grafana:
        - viewer
```

### Modifying Realm Settings

Update realm configuration in `values.yaml`:

```yaml
realm:
  # Enable user registration
  registrationAllowed: true

  # Require email verification
  verifyEmail: true

  # Customize password policy
  passwordPolicy: "length(16) and digits(2) and lowerCase(1) and upperCase(1) and specialChars(2) and notUsername"

  # Adjust token lifespans
  accessTokenLifespan: 600  # 10 minutes
  ssoSessionIdleTimeout: 3600  # 1 hour
```

### Checking Crossplane Resource Status

```bash
# Check all Keycloak Crossplane resources
kubectl get realm,client,identityprovider,group -n keycloak

# Describe specific resource
kubectl describe client proficientnow-argocd -n keycloak

# Check Crossplane provider logs
kubectl logs -l pkg.crossplane.io/provider=provider-keycloak -n crossplane-system

# View ArgoCD external link to Keycloak admin
kubectl get realm proficientnow -n keycloak -o jsonpath='{.metadata.annotations.link\.argocd\.argoproj\.io/external-link}'
```

### Troubleshooting Crossplane

If Crossplane resources show errors:

```bash
# Check ProviderConfig connection
kubectl describe providerconfig keycloak-provider-config -n keycloak

# Verify admin secret exists
kubectl get secret keycloak-admin-secret -n keycloak

# Check if Keycloak is accessible
kubectl run curl-test --rm -i --tty --image=curlimages/curl -- \
  curl -v http://keycloak-keycloak:80/health/ready

# Re-sync Crossplane resources
kubectl annotate client proficientnow-argocd -n keycloak \
  crossplane.io/paused=false --overwrite
```

## Post-Installation Configuration

### Access Admin Console

1. Navigate to: `https://keycloak.pnats.cloud`
2. Click "Administration Console"
3. Login with:
   - Username: `admin`
   - Password: (from sealed secret)

### Verify Realm Configuration

The `proficientnow` realm is automatically configured via Crossplane with:

1. **Identity Providers**:
   - GitHub OAuth (enabled, requires GitHub OAuth app setup)
   - Google OAuth (disabled by default, can be enabled)

2. **OIDC Clients** (with auto-generated Kubernetes secrets):
   - `argocd` - GitOps platform
   - `grafana` - Monitoring and observability
   - `backstage` - Developer portal

3. **Groups** (with pre-configured roles):
   - `platform-admins` - Full admin access to all services
   - `platform-developers` - Read-write access
   - `platform-viewers` - Read-only access

### Create Users

Users can be created via:

**Option 1: Admin Console**
```
1. Go to https://keycloak.pnats.cloud
2. Login to Administration Console
3. Select realm "proficientnow"
4. Users → Add User
5. Set username, email, first/last name
6. Credentials tab → Set Password (uncheck "Temporary")
7. Groups tab → Join Group (platform-admins/platform-developers/platform-viewers)
```

**Option 2: GitHub OAuth (Recommended)**
- Users login via "Sign in with GitHub"
- Automatically creates user account
- Manually assign group membership after first login

## Integrating Applications

### ArgoCD OIDC Integration

The Keycloak chart automatically creates a secret `proficientnow-argocd-client-secret` with all necessary OIDC configuration.

Reference it in ArgoCD:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  url: https://argocd.pnats.cloud
  oidc.config: |
    name: Keycloak
    issuer: https://keycloak.pnats.cloud/realms/proficientnow
    clientID: argocd
    clientSecret: $oidc.keycloak.clientSecret
    requestedScopes:
      - openid
      - profile
      - email
      - roles
    requestedIDTokenClaims:
      groups:
        essential: true
```

Create ArgoCD secret referencing the auto-generated secret:
```bash
# Extract client secret from Keycloak-generated secret
CLIENT_SECRET=$(kubectl get secret proficientnow-argocd-client-secret -n keycloak -o jsonpath='{.data.client-secret}' | base64 -d)

# Create ArgoCD secret
kubectl patch secret argocd-secret -n argocd --type merge -p "{\"data\":{\"oidc.keycloak.clientSecret\":\"$(echo -n $CLIENT_SECRET | base64 -w0)\"}}"
```

Configure RBAC in `argocd-rbac-cm`:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: argocd
data:
  policy.csv: |
    g, platform-admins, role:admin
    g, platform-developers, role:developer
    g, platform-viewers, role:readonly

  policy.default: role:readonly
  scopes: '[groups]'
```

### Grafana OIDC Integration

The Keycloak chart automatically creates a secret `proficientnow-grafana-client-secret`.

Update Grafana values:

```yaml
grafana:
  grafana.ini:
    server:
      root_url: https://grafana.pnats.cloud

    auth.generic_oauth:
      enabled: true
      name: Keycloak
      allow_sign_up: true
      auto_login: false

      # Reference the auto-generated secret
      client_id: grafana
      client_secret: $__file{/etc/secrets/oauth/client-secret}

      scopes: openid profile email roles
      auth_url: https://keycloak.pnats.cloud/realms/proficientnow/protocol/openid-connect/auth
      token_url: https://keycloak.pnats.cloud/realms/proficientnow/protocol/openid-connect/token
      api_url: https://keycloak.pnats.cloud/realms/proficientnow/protocol/openid-connect/userinfo

      # Map Keycloak groups to Grafana roles
      role_attribute_path: |
        contains(groups[*], 'platform-admins') && 'Admin' || contains(groups[*], 'platform-developers') && 'Editor' || 'Viewer'
      role_attribute_strict: true

  # Mount the secret
  extraSecretMounts:
    - name: oauth-secret
      secretName: proficientnow-grafana-client-secret
      defaultMode: 0440
      mountPath: /etc/secrets/oauth
      readOnly: true
```

### Backstage OIDC Integration

The Keycloak chart automatically creates a secret `proficientnow-backstage-client-secret`.

Configure Backstage `app-config.yaml`:

```yaml
auth:
  environment: production
  providers:
    oidc:
      production:
        metadataUrl: https://keycloak.pnats.cloud/realms/proficientnow/.well-known/openid-configuration
        clientId: backstage
        clientSecret: ${OAUTH_CLIENT_SECRET}
        prompt: auto
        scope: 'openid profile email'
        signIn:
          resolvers:
            - resolver: preferredUsernameMatchingUserEntityName

# Mount the secret as environment variable
# In Backstage deployment:
env:
  - name: OAUTH_CLIENT_SECRET
    valueFrom:
      secretKeyRef:
        name: proficientnow-backstage-client-secret
        key: client-secret
```

### Client Secrets Reference

All pre-configured clients have auto-generated Kubernetes secrets:

```bash
# View all client secrets
kubectl get secrets -n keycloak | grep client-secret

# Extract client credentials
kubectl get secret proficientnow-argocd-client-secret -n keycloak -o yaml
kubectl get secret proficientnow-grafana-client-secret -n keycloak -o yaml
kubectl get secret proficientnow-backstage-client-secret -n keycloak -o yaml

# Each secret contains:
# - client-id: The OIDC client ID
# - client-secret: The client secret
# - issuer-url: Full issuer URL
# - token-url: Token endpoint URL
# - auth-url: Authorization endpoint URL
# - userinfo-url: UserInfo endpoint URL
# - jwks-url: JWKS endpoint URL
```

## Secret Management and Rotation

### How Secret Initialization Works

The `secret-init-job.yaml` implements a **safe, idempotent** secret creation pattern:

1. **Pre-Sync Hook**: Runs as ArgoCD PreSync hook (wave -1) before any other resources
2. **Existence Check**: Checks if each secret exists before creating
3. **Create Once**: Only creates secrets that don't exist
4. **Never Modifies**: Existing secrets are NEVER modified to prevent breaking database connections
5. **Auto-Cleanup**: Job is automatically deleted after 5 minutes (ttlSecondsAfterFinished: 300)

### Credential Rotation (Advanced)

**⚠️ WARNING**: Rotating PostgreSQL credentials requires careful coordination to prevent database connection failures.

#### Rotating Keycloak Admin Password

Safe - does not affect database:

```bash
# 1. Delete existing secret
kubectl delete secret keycloak-admin-secret -n keycloak

# 2. Create new secret
kubectl create secret generic keycloak-admin-secret \
  --from-literal=admin-password='NEW_STRONG_PASSWORD' \
  -n keycloak

# 3. Restart Keycloak
kubectl rollout restart deployment keycloak-keycloak -n keycloak
```

#### Rotating PostgreSQL Credentials

**⚠️ DANGEROUS**: Requires database password change AND secret update in correct order.

```bash
# DO NOT DO THIS unless you know what you're doing!
# Incorrect rotation will break the database connection.

# Correct procedure:
# 1. Connect to PostgreSQL and change passwords
kubectl exec -it keycloak-postgresql-0 -n keycloak -- psql -U postgres

# In psql:
ALTER USER postgres WITH PASSWORD 'new_postgres_password';
ALTER USER bn_keycloak WITH PASSWORD 'new_keycloak_password';
\q

# 2. Update secret IMMEDIATELY
kubectl delete secret keycloak-postgresql-secret -n keycloak
kubectl create secret generic keycloak-postgresql-secret \
  --from-literal=postgres-password='new_postgres_password' \
  --from-literal=password='new_keycloak_password' \
  -n keycloak

# 3. Restart PostgreSQL and Keycloak
kubectl rollout restart statefulset keycloak-postgresql -n keycloak
kubectl rollout restart deployment keycloak-keycloak -n keycloak
```

**Recommendation**: Don't rotate PostgreSQL credentials unless absolutely necessary. The database is internal and isolated.

#### Rotating GitHub OAuth Credentials

Safe - can be done anytime:

```bash
# 1. Create new GitHub OAuth app or regenerate secret
# 2. Delete old secret
kubectl delete secret keycloak-github-oauth -n keycloak

# 3. Create new secret
kubectl create secret generic keycloak-github-oauth \
  --from-literal=client-id='NEW_GITHUB_CLIENT_ID' \
  --from-literal=client-secret='NEW_GITHUB_CLIENT_SECRET' \
  -n keycloak

# 4. Restart Keycloak
kubectl rollout restart deployment keycloak-keycloak -n keycloak

# Note: The Crossplane IdentityProvider resource will automatically
# pick up the new credentials from the secret reference
```

## Upgrading

```bash
# Update dependencies
helm dependency update

# Upgrade (secrets will NOT be regenerated if they exist)
helm upgrade keycloak . -n keycloak

# The secret-init job will run again but skip all existing secrets
# Check job logs to confirm:
kubectl logs -l app.kubernetes.io/component=secret-init -n keycloak

# Restart pods if needed
kubectl rollout restart deployment keycloak-keycloak -n keycloak
```

## Backup and Restore

### Backup PostgreSQL

```bash
# Exec into PostgreSQL pod
kubectl exec -it keycloak-postgresql-0 -n keycloak -- bash

# Dump database
pg_dump -U bn_keycloak bitnami_keycloak > /tmp/keycloak-backup.sql

# Copy backup
kubectl cp keycloak/keycloak-postgresql-0:/tmp/keycloak-backup.sql ./keycloak-backup.sql
```

### Restore PostgreSQL

```bash
# Copy backup to pod
kubectl cp ./keycloak-backup.sql keycloak/keycloak-postgresql-0:/tmp/keycloak-backup.sql

# Restore
kubectl exec -it keycloak-postgresql-0 -n keycloak -- \
  psql -U bn_keycloak bitnami_keycloak < /tmp/keycloak-backup.sql
```

## Troubleshooting

### Pods Not Starting

```bash
# Check pod status
kubectl describe pod -n keycloak keycloak-0

# Check logs
kubectl logs -n keycloak keycloak-0 -f

# Common issues:
# 1. Sealed secrets not applied
# 2. Storage class not available
# 3. PostgreSQL not ready
```

### Realm Configuration Job Failed

```bash
# Check job logs
kubectl logs -n keycloak job/keycloak-realm-config

# Manually trigger configuration
kubectl delete job keycloak-realm-config -n keycloak
helm upgrade keycloak . -n keycloak
```

### GitHub OAuth Not Working

1. Verify GitHub OAuth App settings:
   - Homepage URL: `https://keycloak.pnats.cloud`
   - Authorization callback URL: `https://keycloak.pnats.cloud/realms/proficientnow/broker/github/endpoint`

2. Check sealed secret:
   ```bash
   kubectl get secret keycloak-github-oauth -n keycloak
   ```

3. Restart Keycloak:
   ```bash
   kubectl rollout restart deployment keycloak -n keycloak
   ```

## Security Considerations

1. **Passwords**: Use strong, randomly generated passwords
2. **Sealed Secrets**: Never commit unsealed secrets to git
3. **Admin Access**: Restrict admin console access
4. **Client Secrets**: Rotate client secrets regularly
5. **Session Timeout**: Configure appropriate session timeouts
6. **Rate Limiting**: Enable brute force protection (already configured)

## Resources

- [Keycloak Documentation](https://www.keycloak.org/documentation)
- [OIDC Specification](https://openid.net/specs/openid-connect-core-1_0.html)
- [SAML 2.0 Specification](http://docs.oasis-open.org/security/saml/Post2.0/sstc-saml-tech-overview-2.0.html)
- [Bitnami Keycloak Chart](https://github.com/bitnami/charts/tree/main/bitnami/keycloak)

## Support

For issues or questions:
- Platform Team: snoorullah@proficientnowtech.com
- Internal Documentation: [Platform Docs](https://docs.pnats.cloud)
