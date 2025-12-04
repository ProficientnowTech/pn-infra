# Azure AD Integration - Quick Start

Quick reference for enabling Azure AD federation with Keycloak.

## What This Does

Enables Microsoft users from your Azure AD to login to platform applications (ArgoCD, Grafana, Backstage) using their Microsoft credentials.

**User Experience**:
1. User visits ArgoCD/Grafana
2. Clicks "Sign in with Microsoft"
3. Logs in with Microsoft credentials
4. Automatically gets access based on Azure AD group membership
5. SSO works across all platform applications

## Prerequisites

- Azure AD tenant with admin access
- Azure AD users you want to grant platform access
- Crossplane deployed
- Keycloak deployed

## 5-Minute Setup

### 1. Get Azure Tenant ID

```bash
az login
az account show --query tenantId -o tsv
# Save this as TENANT_ID
```

### 2. Create Azure Service Principal

```bash
az ad sp create-for-rbac \
  --name "crossplane-azuread-provider" \
  --role "Application Administrator"

# Save the output (appId, password, tenant)
```

### 3. Grant API Permissions

```bash
# Get the service principal
SP_ID=$(az ad sp list --display-name "crossplane-azuread-provider" --query "[0].id" -o tsv)

# Required Microsoft Graph API permissions
az ad app permission add --id <APP_ID> --api 00000003-0000-0000-c000-000000000000 \
  --api-permissions \
    e1fe6dd8-ba31-4d61-89e7-88639da4683d=Scope \
    a154be20-db9c-4678-8ab7-66f6cc099a59=Scope \
    bc024368-1153-4739-b217-4326f2e966d0=Scope

# Grant admin consent
az ad app permission admin-consent --id <APP_ID>
```

### 4. Create Kubernetes Secret

```bash
kubectl create secret generic azuread-service-principal \
  --from-literal=credentials='{"clientId":"<CLIENT_ID>","clientSecret":"<CLIENT_SECRET>","tenantId":"<TENANT_ID>"}' \
  -n crossplane-system
```

### 5. Enable Azure AD Provider

Update `crossplane/values.yaml`:

```yaml
providerConfig:
  azuread:
    enabled: true
    tenantId: "<YOUR_TENANT_ID>"
```

Deploy:
```bash
cd platform/stacks/security/charts/crossplane
helm upgrade crossplane . -n crossplane-system
```

### 6. Create Azure AD Resources

```bash
# Apply Crossplane resources to create Azure AD app and groups
kubectl apply -f examples/azuread-keycloak-federation.yaml

# Wait for creation
kubectl wait --for=condition=ready application.azuread.upbound.io/keycloak-oidc-federation
```

### 7. Get Application Details

```bash
# Get the Client ID
kubectl get application.azuread.upbound.io keycloak-oidc-federation \
  -o jsonpath='{.status.atProvider.applicationId}'
# Output: 12345678-1234-1234-1234-123456789012

# The client secret is automatically created as a K8s secret
kubectl get secret azuread-keycloak-oidc-credentials -n keycloak
```

### 8. Update Keycloak Configuration

Edit `keycloak/values.yaml`:

Replace `<AZURE_TENANT_ID>` with your actual tenant ID in these URLs:
```yaml
identityProviders:
  - alias: azuread
    enabled: true
    config:
      clientId: "<CLIENT_ID_FROM_STEP_7>"
      authorizationUrl: "https://login.microsoftonline.com/<YOUR_TENANT_ID>/oauth2/v2.0/authorize"
      tokenUrl: "https://login.microsoftonline.com/<YOUR_TENANT_ID>/oauth2/v2.0/token"
      # ... other URLs
```

Deploy:
```bash
cd platform/stacks/security/charts/keycloak
helm upgrade keycloak . -n keycloak
```

### 9. Add Users to Azure AD Groups

**Get user Object IDs**:
```bash
az ad user list --query "[].{Name:displayName, Email:mail, ObjectId:id}" -o table
```

**Add users via Crossplane**:

Edit `crossplane/examples/azuread-keycloak-federation.yaml`, uncomment and update:

```yaml
apiVersion: groupmember.azuread.upbound.io/v1beta1
kind: GroupMember
metadata:
  name: admin-john-doe
spec:
  forProvider:
    groupObjectIdSelector:
      matchLabels:
        platform-group: admins
    memberObjectId: "<USER_OBJECT_ID>"
```

Apply:
```bash
kubectl apply -f crossplane/examples/azuread-keycloak-federation.yaml
```

### 10. Test

1. Go to `https://argocd.pnats.cloud` (or any platform app)
2. Click "LOG IN VIA KEYCLOAK"
3. Click "Sign in with Microsoft"
4. Login with Microsoft credentials
5. You should be logged into the application!

## Configuration Summary

**What was created**:
- Azure AD app registration for Keycloak OIDC
- Azure AD groups: Platform Admins, Platform Developers, Platform Viewers
- Keycloak identity provider for Azure AD
- Automatic user provisioning (JIT)
- Group mapping between Azure AD and Keycloak

**Azure AD Groups → Platform Access**:
| Azure AD Group | Access Level | ArgoCD | Grafana |
|---|---|---|---|
| Platform Admins | Full admin | Admin | Admin |
| Platform Developers | Developer | Edit/Sync | Editor |
| Platform Viewers | Read-only | View | Viewer |

## Common Issues

### Issue: Can't see "Sign in with Microsoft" button

**Solution**: Check identity provider is deployed:
```bash
kubectl get identityprovider.keycloak.crossplane.io -n keycloak
```

### Issue: Redirect URI mismatch

**Solution**: Verify redirect URI in Azure AD matches:
```
https://keycloak.pnats.cloud/realms/proficientnow/broker/azuread/endpoint
```

### Issue: No groups assigned to user

**Solution**: Configure groups claim in Azure AD:
1. Azure Portal → App registrations → Your app
2. Token configuration → Add groups claim
3. Select "Security groups" → "Group ID"

### Issue: Permission errors in Crossplane

**Solution**: Verify service principal permissions:
```bash
az ad sp show --id <SP_ID> --query appRoles
```

Ensure admin consent was granted.

## User Login Flow

```
User → Platform App → Keycloak → "Sign in with Microsoft" →
Azure AD Login → Authenticate → Return to Keycloak →
Create/Update User → Map Groups → Return to App → Access Granted
```

## Next Steps

- Review full integration guide: `AZUREAD_INTEGRATION.md`
- Configure MFA in Azure AD Conditional Access
- Set up audit logging
- Review group memberships regularly

## Quick Commands Reference

```bash
# Check Azure AD provider health
kubectl get provider provider-azuread -n crossplane-system

# View Azure AD resources
kubectl get application.azuread.upbound.io
kubectl get group.azuread.upbound.io
kubectl get groupmember.azuread.upbound.io

# Check Keycloak identity provider
kubectl get identityprovider.keycloak.crossplane.io -n keycloak

# View Keycloak logs
kubectl logs -l app.kubernetes.io/name=keycloak -n keycloak --tail=50

# Test Azure AD authentication
az login --tenant <TENANT_ID>

# List Azure AD groups
az ad group list --query "[].{Name:displayName, ObjectId:id}" -o table

# List group members
az ad group member list --group "Platform Admins" \
  --query "[].{Name:displayName, Email:mail}" -o table
```
