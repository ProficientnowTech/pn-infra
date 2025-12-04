# Crossplane Provider Examples

Example resources demonstrating how to use the installed Crossplane providers for declarative infrastructure management.

## Provider Examples

### Environment Configs (`environment-configs.yaml`)

EnvironmentConfig resources provide shared configuration data for Crossplane compositions. These enable:

- Platform-wide defaults (domain, storage classes, resource limits)
- Environment-specific overrides (dev, staging, production)
- Team-specific configurations

**Usage**: Reference EnvironmentConfigs in compositions via `function-environment-configs` to inject shared settings.

### Vault Resources (`vault-resources.yaml`)

Declarative Vault configuration management including:

- Secret engine mounts (KV v2, PKI, Transit)
- Authentication backends (Kubernetes auth)
- Policies for access control
- Kubernetes auth roles for External Secrets Operator
- GitOps-managed `KVSecretV2` examples for developer-platform workloads (Backstage sample included)

> **Note:** Bootstrap secrets are now defined via `platform/bootstrap/secrets/specs/*.yaml`. The `KVSecretV2`
> samples remain useful for bespoke cases but the default flow relies on SealedSecret → PushSecret → Vault
> without editing `values.yaml`.

**Prerequisites**: Vault must be deployed and the vault-admin-token secret must exist in crossplane-system namespace. See `docs/platform/security/dev-workload-integration.md` for the full workflow and sync-wave diagrams.

### ArgoCD Resources (`argocd-resources.yaml`)

Declarative ArgoCD project and application management including:

- Projects with RBAC and source/destination policies
- Application definitions for GitOps deployments
- Repository connections
- Multi-environment application configurations

**Prerequisites**: ArgoCD must be deployed and the argocd-admin-token secret must exist in crossplane-system namespace.

### Azure AD Resources (`azuread-resources.yaml`)

Declarative Azure Active Directory management including:

- Application registrations (OIDC/SAML)
- Service principals
- Groups and group memberships
- Application passwords (client secrets)
- Keycloak ↔ Azure AD SAML federation setup

**Prerequisites**:
- Azure AD tenant configured
- Service principal with Directory API permissions
- azuread-service-principal secret in crossplane-system namespace
- Azure AD ProviderConfig enabled in values.yaml

**Note**: Azure AD provider is disabled by default. Enable in `values.yaml` and follow the checklist in `docs/platform/security/dev-workload-integration.md`:

```yaml
providerConfig:
  azuread:
    enabled: true
    tenantId: "your-tenant-id"
```

After applying the federation example (`azuread-keycloak-federation.yaml`), Keycloak automatically consumes the generated `azuread-keycloak-oidc-credentials` secret and Azure AD groups can be mapped directly into Keycloak group-based RBAC (Harbor registry scopes, Verdaccio publishers, etc.).

## Applying Examples

Examples can be applied directly or used as templates for custom resources:

```bash
# Apply all environment configs
kubectl apply -f examples/environment-configs.yaml

# Apply Vault configuration
kubectl apply -f examples/vault-resources.yaml

# Apply ArgoCD projects
kubectl apply -f examples/argocd-resources.yaml

# Apply Azure AD resources (requires credentials)
kubectl apply -f examples/azuread-resources.yaml
```

## Required Secrets

Before using these examples, ensure the following secrets exist:

**Vault Provider**:
```bash
kubectl create secret generic vault-admin-token \
  --from-literal=token="<vault-root-token>" \
  -n crossplane-system
```

**ArgoCD Provider**:
```bash
kubectl create secret generic argocd-admin-token \
  --from-literal=token="<argocd-api-token>" \
  -n crossplane-system
```

**Azure AD Provider** (if enabled):
```bash
kubectl create secret generic azuread-service-principal \
  --from-literal=credentials='{"clientId":"<sp-client-id>","clientSecret":"<sp-secret>","tenantId":"<tenant-id>"}' \
  -n crossplane-system
```

## Integration Patterns

### Pattern 1: Automated Vault Setup

Replace manual `kubectl exec` Vault commands with declarative resources:

**Before** (manual):
```bash
kubectl exec -n vault vault-0 -- vault secrets enable -path=secret/myapp kv-v2
kubectl exec -n vault vault-0 -- vault policy write myapp-policy -
kubectl exec -n vault vault-0 -- vault write auth/kubernetes/role/myapp ...
```

**After** (declarative):
Apply `vault-resources.yaml` with your application-specific mount, policy, and role.

### Pattern 2: GitOps ArgoCD Management

Manage ArgoCD projects and applications as code:

**Before**: Manual creation via ArgoCD UI or CLI

**After**: Define projects and applications in Git, let Crossplane create them

### Pattern 3: Azure AD ↔ Keycloak Federation

Automate SAML/OIDC federation between Keycloak and Azure AD:

1. Create Azure AD app registration (azuread-resources.yaml)
2. Create Keycloak identity provider (keycloak chart)
3. Both managed declaratively via Crossplane

### Pattern 4: Shared Configuration with EnvironmentConfigs

Use environment configs in compositions to reduce duplication:

```yaml
# Composition references environment configs
apiVersion: apiextensions.crossplane.io/v1
kind: Composition
spec:
  mode: Pipeline
  pipeline:
    - step: load-environment
      functionRef:
        name: function-environment-configs
      input:
        spec:
          environmentConfigs:
            - type: Reference
              ref:
                name: platform-defaults
            - type: Selector
              selector:
                matchLabels:
                  - key: environment
                    valueFromFieldPath: spec.environment
```

## Next Steps

1. Review the ENHANCEMENT_PLAN.md for comprehensive integration scenarios
2. Create custom EnvironmentConfigs for your environments
3. Migrate existing Vault configuration to declarative resources
4. Define ArgoCD projects for your teams
5. Integrate Azure AD if using Microsoft identity platform
