# Vault Chart

ArgoCD Application for HashiCorp Vault secret management platform.

## Purpose

Deploys HashiCorp Vault for centralized secret management, encryption, and identity-based access across the platform infrastructure.

## Configuration

### Chart Values (`values.yaml`)

```yaml
# Global repository settings
global:
  repoURL: "git@github.com:pnow-devsupreme/pn-infra.git"
  targetRevision: "main"
  enabled: true        # Enable Vault deployment
  tlsDisable: false    # Enforce TLS encryption

# Labels configuration
labels:
  component: security           # Component type for Kubernetes labels
  managed-by: argocd           # Override default Helm with ArgoCD

# Vault server configuration
server:
  enabled: true
  image:
    repository: hashicorp/vault
    tag: 1.18.3
    pullPolicy: IfNotPresent

  resources:
    requests:
      memory: 256Mi
      cpu: 250m
    limits:
      memory: 512Mi
      cpu: 500m

  # Health checks
  readinessProbe:
    enabled: true
    path: "/v1/sys/health?standbyok=true&sealedcode=204&uninitcode=204"
  livenessProbe:
    enabled: true
    path: "/v1/sys/health?standbyok=true"
    initialDelaySeconds: 60
```

### Key Configuration Options

| Setting | Default | Purpose |
|---------|---------|---------|
| `global.enabled` | `true` | Enable/disable Vault deployment |
| `global.tlsDisable` | `false` | Force TLS encryption (security) |
| `labels.component` | `security` | Kubernetes component label |
| `labels.managed-by` | `argocd` | Management tool identifier |
| `server.enabled` | `true` | Enable Vault server |
| `server.image.tag` | `1.18.3` | Vault version |

### Resource Configuration

**Default Resources:**
- **CPU Request**: 250m (0.25 cores)
- **Memory Request**: 256Mi
- **CPU Limit**: 500m (0.5 cores)
- **Memory Limit**: 512Mi

**Health Checks:**
- **Readiness**: Checks if Vault can serve requests
- **Liveness**: Checks if Vault process is healthy

## Generated Application

When deployed via target-chart, creates ArgoCD Application with:

```yaml
metadata:
  name: vault
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: '3'  # Deploy after storage
  labels:
    # From chart helper
    helm.sh/chart: vault-0.1.0
    app.kubernetes.io/name: vault
    app.kubernetes.io/instance: {release-name}
    app.kubernetes.io/version: "1.18.3"
    app.kubernetes.io/managed-by: argocd
    app.kubernetes.io/component: security

    # From target-chart commonLabels
    app.kubernetes.io/part-of: platform-infrastructure
    platform.pn-infra.io/stack: platform
    platform.pn-infra.io/environment: {environment}
    platform.pn-infra.io/application: "vault"

spec:
  project: platform
  sources:
    - repoURL: https://helm.releases.hashicorp.com
      chart: vault
      targetRevision: 0.29.2
      helm:
        releaseName: vault
        valueFiles:
          - $values/platform/charts/vault/values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: vault
```

## Deployment

**Sync Wave**: `3` - Deploys after storage (waves 1-2) but before monitoring (waves 4-5)

**Dependencies:**
- Kubernetes cluster
- Persistent storage (via rook-ceph)
- Network policies configured

**Target Namespace**: `vault`

## Security Features

- **TLS Enforced**: All communication encrypted
- **Health Checks**: Readiness and liveness probes configured
- **Resource Limits**: Prevents resource exhaustion
- **Namespace Isolation**: Deployed in dedicated namespace

## Customization

### Environment-Specific Values
Override in target-chart environment files:
```yaml
# In target-chart/values-production.yaml applications section
- name: vault
  namespace: vault
  helm:
    parameters:
      - name: server.resources.requests.memory
        value: "512Mi"
```

### Development vs Production
- **Development**: Smaller resource requests, relaxed security
- **Production**: Higher resource limits, strict security policies

## Troubleshooting

### Check Application Status
```bash
kubectl get application vault -n argocd
```

### Check Vault Pod Status
```bash
kubectl get pods -n vault
kubectl logs -n vault deployment/vault
```

### Check Vault Health
```bash
kubectl exec -n vault deployment/vault -- vault status
```
