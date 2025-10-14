# ArgoCD Chart

ArgoCD Application for self-managed ArgoCD deployment.

## Purpose

Deploys ArgoCD for GitOps-based continuous deployment, enabling declarative infrastructure and application management across the platform.

## Configuration

### Chart Values (`values.yaml`)

```yaml
# Global repository settings
global:
  repoURL: "git@github.com:pnow-devsupreme/pn-infra.git"
  targetRevision: "main"

# Labels configuration
labels:
  component: gitops            # Component type for Kubernetes labels
  managed-by: argocd          # Override default Helm with ArgoCD

# ArgoCD version configuration
argocd:
  version: "7.7.8"            # Argo Helm chart version
  appVersion: "v2.13.1"       # ArgoCD application version

# ArgoCD Server configuration
server:
  name: server
  replicas: 2                 # High availability

  # Autoscaling
  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 5
    targetCPUUtilizationPercentage: 70
    targetMemoryUtilizationPercentage: 80

  # Resources
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi

  # Service configuration
  service:
    type: LoadBalancer         # External access via MetalLB
    port: 80
    portName: http

  # Ingress configuration
  ingress:
    enabled: true
    ingressClassName: nginx
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
      nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
      nginx.ingress.kubernetes.io/backend-protocol: "GRPC"
    hosts:
      - host: argocd.platform.local
        paths:
          - path: /
            pathType: Prefix
    tls:
      - secretName: argocd-server-tls
        hosts:
          - argocd.platform.local

# Application Controller
controller:
  name: application-controller
  replicas: 2

  resources:
    requests:
      cpu: 250m
      memory: 512Mi
    limits:
      cpu: 1000m
      memory: 2Gi

# Repo Server
repoServer:
  name: repo-server
  replicas: 2

  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 1000m
      memory: 1Gi

  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 5

# Redis configuration
redis:
  enabled: true
  name: redis

  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi

# RBAC configuration
rbac:
  create: true
  policy.default: role:readonly
  policy.csv: |
    p, role:admin, applications, *, */*, allow
    p, role:admin, clusters, *, *, allow
    p, role:admin, repositories, *, *, allow
    p, role:readonly, applications, get, */*, allow
    p, role:readonly, applications, sync, */*, allow
    g, argocd-admins, role:admin
```

### Key Configuration Options

| Setting | Default | Purpose |
|---------|---------|---------|
| `labels.component` | `gitops` | Kubernetes component label |
| `labels.managed-by` | `argocd` | Management tool identifier |
| `argocd.version` | `"7.7.8"` | Helm chart version |
| `argocd.appVersion` | `"v2.13.1"` | ArgoCD application version |
| `server.replicas` | `2` | High availability replicas |
| `server.service.type` | `LoadBalancer` | External access method |
| `server.ingress.enabled` | `true` | Enable HTTPS ingress |
| `controller.replicas` | `2` | Controller replicas for HA |
| `repoServer.autoscaling.enabled` | `true` | Auto-scale repo server |

### High Availability Configuration

**Server**: 2 replicas with autoscaling (2-5 replicas)
**Controller**: 2 replicas for active-passive HA
**Repo Server**: 2 replicas with autoscaling (2-5 replicas)
**Redis**: Single instance (consider Redis HA for production)

### Access Configuration

**LoadBalancer Service**: External IP via MetalLB
**Ingress**: HTTPS with automatic TLS certificates
**Domain**: `argocd.platform.local`

## Generated Application

When deployed via target-chart, creates ArgoCD Application with:

```yaml
metadata:
  name: argocd
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: '0'  # Deploy first (self-management)
    argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true
  labels:
    # From chart helper
    helm.sh/chart: argocd-0.1.0
    app.kubernetes.io/name: argocd
    app.kubernetes.io/instance: {release-name}
    app.kubernetes.io/managed-by: argocd
    app.kubernetes.io/component: gitops

spec:
  project: default             # Uses default project for self-management
  sources:
    - repoURL: https://argoproj.github.io/argo-helm
      chart: argo-cd
      targetRevision: 7.7.8
      helm:
        releaseName: argocd
        valueFiles:
          - $values/platform/charts/argocd/values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
```

## Deployment

**Sync Wave**: `0` - Deploys first for self-management
**Self-Management**: ArgoCD manages its own deployment
**Target Namespace**: `argocd`

## Repository Configuration

Pre-configured repositories for platform management:

```yaml
repositories:
  - type: git
    url: git@github.com:pnow-devsupreme/pn-infra.git
    name: pn-infra
  - type: helm
    url: https://argoproj.github.io/argo-helm
    name: argo
  - type: helm
    url: https://charts.rook.io/release
    name: rook-release
  - type: helm
    url: https://helm.releases.hashicorp.com
    name: hashicorp
  - type: helm
    url: https://prometheus-community.github.io/helm-charts
    name: prometheus-community
  - type: helm
    url: https://grafana.github.io/helm-charts
    name: grafana
  - type: helm
    url: https://ray-project.github.io/kuberay-helm/
    name: kuberay
  - type: helm
    url: https://helm.ngc.nvidia.com/nvidia
    name: nvidia
```

## Security Configuration

### RBAC Policies
- **Default Policy**: `readonly` - Users have read-only access by default
- **Admin Role**: Full access to applications, clusters, repositories
- **Readonly Role**: Get and sync permissions only

### TLS Configuration
- **Force SSL Redirect**: All HTTP traffic redirected to HTTPS
- **Automatic Certificates**: cert-manager integration for TLS
- **GRPC Backend**: Secure communication with ArgoCD API

## Access and Authentication

### Web UI Access
- **URL**: `https://argocd.platform.local`
- **LoadBalancer IP**: Assigned by MetalLB
- **Default Credentials**: `admin` / (auto-generated password)

### CLI Access
```bash
# Get admin password
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d

# Login via CLI
argocd login argocd.platform.local --username admin
```

## Monitoring Integration

**Metrics Enabled**: Server, controller, and repo server expose Prometheus metrics
**Service Monitors**: Automatic discovery by Prometheus
**Grafana Dashboards**: Pre-configured ArgoCD dashboards available

## Customization

### External Authentication
```yaml
# In values.yaml server.config
configs:
  cm:
    oidc.config: |
      name: OIDC
      issuer: https://your-oidc-provider.com
      clientId: argocd
      clientSecret: $oidc.clientSecret
```

### Resource Scaling
```yaml
# For larger deployments
server:
  autoscaling:
    maxReplicas: 10
    targetCPUUtilizationPercentage: 50

controller:
  resources:
    limits:
      cpu: 2000m
      memory: 4Gi
```

## Troubleshooting

### Check ArgoCD Status
```bash
kubectl get application argocd -n argocd
kubectl get pods -n argocd
```

### Access ArgoCD Logs
```bash
kubectl logs -n argocd deployment/argocd-server
kubectl logs -n argocd deployment/argocd-application-controller
```

### Reset Admin Password
```bash
kubectl patch secret argocd-secret -n argocd -p '{"data":{"admin.password":null,"admin.passwordMtime":null}}'
kubectl scale deployment argocd-server -n argocd --replicas=0
kubectl scale deployment argocd-server -n argocd --replicas=1
```
