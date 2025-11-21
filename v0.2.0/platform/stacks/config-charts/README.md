# Platform Apps Configuration

## Overview

The `platform/apps/` directory contains **application configuration charts** that are deployed and managed BY platform applications (like ArgoCD, ingress-nginx, cert-manager, etc.), NOT by the target-chart factory pattern.

## Directory Purpose

### What This Directory Is For

This directory contains Helm charts that provide **additional configurations** for platform applications. These configs are:

- **Managed by their parent applications** (via ArgoCD multi-source pattern)
- **Deployed alongside the main application** but kept separate for clarity
- **Not core application deployments** (those are in `platform/charts/`)
- **Configuration overlays** like Ingress, ConfigMaps, Secrets, additional resources

### Architecture Flow

```
target-chart (Root Factory)
└── Deploys Applications from charts/
    └── argocd-self Application (multi-source)
        ├── Source 1: ArgoCD Helm chart → Core deployment
        ├── Source 2: Values reference → Configuration
        └── Source 3: apps/argocd-config → Additional configs (Ingress, ConfigMaps, etc.)
```

## Directory Structure

```
platform/apps/
├── README.md                    # This file
├── argocd-config/              # ArgoCD additional configs
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
│       ├── ingress.yaml        # ArgoCD Ingress
│       └── argocd-cm.yaml      # ArgoCD ConfigMap
│
├── ingress-nginx-config/       # Future: ingress-nginx configs
├── cert-manager-config/        # Future: cert-manager configs
└── external-dns-config/        # Future: external-dns configs
```

## What Should Be Included Here

✅ **Include:**
- Ingress resources for platform applications
- ConfigMaps with application-specific settings
- Additional Secrets (not managed by core Helm chart)
- Custom NetworkPolicies
- ServiceMonitors (Prometheus monitoring configs)
- Additional RBAC resources
- CRD instances (not the CRD definitions themselves)

❌ **Do NOT Include:**
- Core application deployments (those go in `platform/charts/`)
- Application CRD definitions (those are in the main Helm charts)
- Infrastructure-level configs (those are bootstrap configs)
- Standalone applications (those should have their own Application resource)

## Creating a New App Config Chart

### Step 1: Create Directory Structure

```bash
mkdir -p platform/apps/<app-name>-config/templates
```

### Step 2: Create Chart.yaml

```yaml
apiVersion: v2
name: <app-name>-config
description: <App Name> additional configuration (Ingress, ConfigMaps, etc.)
type: application
version: 0.1.0
appVersion: "1.0"

keywords:
- <app-name>
- configuration

annotations:
  category: <Category>
  platform.pn-infra.io/component: <app-name>-config
  platform.pn-infra.io/sync-wave: "1"
```

### Step 3: Create values.yaml

```yaml
---
# Global configuration
global:
  repoURL: https://github.com/pnow-devsupreme/pn-infra.git
  targetRevision: 'main'

# Common labels - applied to all resources (informational)
commonLabels:
  platform.pnats.cloud/owner: 'Shaik Noorullah'
  platform.pnats.cloud/org: ProficientNowTech
  platform.pnats.cloud/docs: docs.pnats.cloud/config-charts/#<app-name>-config
  platform.pnats.cloud/chart-version: 0.1.0
  platform.pnats.cloud/maintained-by: platform-team

# Common selectors - used for selecting/matching resources
commonSelectors:
  app.kubernetes.io/part-of: <app-name>-app
  app.kubernetes.io/managed-by: argocd
  app.kubernetes.io/version: <version>
  platform.pnats.cloud/layer: platform
  platform.pnats.cloud/environment: production
  platform.pnats.cloud/tier: critical
  platform.pnats.cloud/team: platform-team
  platform.pnats.cloud/owner-email: snoorullah@proficientnowtech.com
  platform.pnats.cloud/monitoring-enabled: "true"
  platform.pnats.cloud/backup-policy: daily
  platform.pnats.cloud/cost-center: platform-ops
  platform.pnats.cloud/git-commit: HEAD
  platform.pnats.cloud/release-id: manual-deploy

# Namespace
<app-name>:
  namespace: <namespace>

# Resource configurations...
```

### Step 4: Create Templates

Each template should follow this pattern:

```yaml
{{- if .Values.<resource>.enabled }}
---
apiVersion: <api-version>
kind: <Kind>
metadata:
  name: {{ .Values.<resource>.name }}
  namespace: {{ .Values.<app-name>.namespace }}
  labels:
    {{- range $key, $value := .Values.commonLabels }}
    {{ $key }}: {{ $value }}
    {{- end }}
    {{- range $key, $value := .Values.commonSelectors }}
    {{ $key }}: {{ $value }}
    {{- end }}
    {{- range $key, $value := .Values.<resource>.labels }}
    {{ $key }}: {{ $value }}
    {{- end }}
    app.kubernetes.io/instance: {{ .Release.Name }}
  {{- if .Values.<resource>.annotations }}
  annotations:
    {{- toYaml .Values.<resource>.annotations | nindent 4 }}
  {{- end }}
spec:
  # Resource spec here
{{- end }}
```

### Step 5: Update Parent Application

Add the config chart as a source in `platform/charts/<app-name>/templates/application.yaml`:

```yaml
sources:
  - repoURL: <helm-chart-repo>
    chart: <app-name>
    targetRevision: <version>
    helm:
      releaseName: <app-name>
      valueFiles:
        - $<app-name>-values/v0.2.0/platform/charts/<app-name>/values.yaml
  - repoURL: {{ .Values.global.repoURL }}
    targetRevision: {{ .Values.global.targetRevision }}
    ref: <app-name>-values
  - repoURL: {{ .Values.global.repoURL }}
    targetRevision: {{ .Values.global.targetRevision }}
    path: v0.2.0/platform/apps/<app-name>-config
    helm:
      releaseName: <app-name>-config
```

## Label and Selector Reference

### Common Labels (Informational Only)

These labels provide **metadata** but are NOT used for resource selection:

| Label | Purpose | Example |
|-------|---------|---------|
| `platform.pnats.cloud/owner` | Human-readable owner name | `Shaik Noorullah` |
| `platform.pnats.cloud/org` | Organization name | `ProficientNowTech` |
| `platform.pnats.cloud/docs` | Documentation URL | `docs.pnats.cloud/...` |
| `platform.pnats.cloud/chart-version` | Helm chart version | `0.1.0` |
| `platform.pnats.cloud/maintained-by` | Maintenance team | `platform-team` |

**Why separate?** These values change frequently or are too specific for queries.

### Common Selectors (Used for Queries)

These labels are **stable** and used for `kubectl` queries and resource selection:

#### Core Identification

| Selector | Purpose | Example | Usage |
|----------|---------|---------|-------|
| `app.kubernetes.io/name` | Resource-specific name | `argocd-server-ingress` | Identify specific resource type |
| `app.kubernetes.io/component` | Component type | `ingress-config` | Group by component |
| `app.kubernetes.io/part-of` | Application group | `argocd-app` | `kubectl get all -l app.kubernetes.io/part-of=argocd-app` |
| `app.kubernetes.io/managed-by` | Management tool | `argocd` | `kubectl get all -l app.kubernetes.io/managed-by=argocd` |
| `app.kubernetes.io/version` | Application version | `v3.1.8` | `kubectl get all -l app.kubernetes.io/version=v3.1.8` |
| `app.kubernetes.io/instance` | Release instance | `argocd-config` | Unique per Helm release |

#### Platform Organization

| Selector | Purpose | Example | Usage |
|----------|---------|---------|-------|
| `platform.pnats.cloud/layer` | Platform layer | `platform` | `kubectl get all -l platform.pnats.cloud/layer=platform` |
| `platform.pnats.cloud/environment` | Environment | `production` | `kubectl get all -l platform.pnats.cloud/environment=production` |
| `platform.pnats.cloud/tier` | Criticality tier | `critical` | `kubectl get all -l platform.pnats.cloud/tier=critical` |

**Layer Values:**
- `platform` - Platform services (ArgoCD, ingress, cert-manager)
- `infrastructure` - Infrastructure (DNS, load balancers)
- `storage` - Storage systems (databases, Rook-Ceph)
- `monitoring` - Observability (Prometheus, Grafana)
- `security` - Security tools (Vault, policy engines)
- `business` - Business applications
- `data` - Data processing/analytics

**Tier Values:**
- `critical` - Business-critical, 24/7 monitoring
- `high` - High priority, business hours support
- `medium` - Standard priority
- `low` - Best effort

#### Team/Ownership

| Selector | Purpose | Example | Usage |
|----------|---------|---------|-------|
| `platform.pnats.cloud/team` | Owning team | `platform-team` | Route alerts to team |
| `platform.pnats.cloud/owner-email` | Owner contact | `snoorullah@proficientnowtech.com` | Access control, notifications |

#### Operational

| Selector | Purpose | Example | Usage |
|----------|---------|---------|-------|
| `platform.pnats.cloud/monitoring-enabled` | Prometheus target | `"true"` | ServiceMonitor selection |
| `platform.pnats.cloud/backup-policy` | Backup schedule | `daily` | Backup tool selection |
| `platform.pnats.cloud/cost-center` | Cost allocation | `platform-ops` | Cost tracking queries |

#### Version Tracking

| Selector | Purpose | Example | Usage |
|----------|---------|---------|-------|
| `platform.pnats.cloud/git-commit` | Git commit SHA | `abc123def` | Trace deployments to source |
| `platform.pnats.cloud/release-id` | Release identifier | `20250123-001` | Track deployment batches |

**Note:** These are set to placeholder values (`HEAD`, `manual-deploy`) and should be replaced by CI/CD.

## Testing

### 1. Template Rendering Test

```bash
# Test individual chart
helm template <app-name>-config platform/apps/<app-name>-config --namespace <namespace>

# Test with debug
helm template <app-name>-config platform/apps/<app-name>-config --namespace <namespace> --debug
```

### 2. Dry-Run Test

```bash
# Test without applying
helm install <app-name>-config platform/apps/<app-name>-config \
  --namespace <namespace> \
  --dry-run \
  --debug
```

### 3. Values Override Test

```bash
# Test with custom values
helm template <app-name>-config platform/apps/<app-name>-config \
  --set commonSelectors.platform\.pnats\.cloud/environment=staging
```

### 4. Label Verification

```bash
# Check labels on rendered resources
helm template <app-name>-config platform/apps/<app-name>-config | grep -A 20 "labels:"
```

## Debugging

### Common Issues

#### Issue: Template fails to render

```bash
# Check syntax
helm lint platform/apps/<app-name>-config

# Show verbose errors
helm template <app-name>-config platform/apps/<app-name>-config --debug 2>&1 | less
```

#### Issue: Labels not appearing

Check template uses correct loops:
```yaml
labels:
  {{- range $key, $value := .Values.commonLabels }}
  {{ $key }}: {{ $value }}
  {{- end }}
  {{- range $key, $value := .Values.commonSelectors }}
  {{ $key }}: {{ $value }}
  {{- end }}
```

#### Issue: Values not being used

```bash
# Check values are being read
helm template <app-name>-config platform/apps/<app-name>-config --debug | grep -A 5 "USER-SUPPLIED VALUES"
```

### ArgoCD Debugging

```bash
# Check Application status
kubectl get application -n argocd <app-name>-self -o yaml

# Check Application events
kubectl describe application -n argocd <app-name>-self

# Check sync status
argocd app get <app-name>-self

# Force sync
argocd app sync <app-name>-self --force
```

## Using Selectors

### Query Examples

```bash
# Get all resources for argocd-app
kubectl get all -l app.kubernetes.io/part-of=argocd-app

# Get all platform layer resources
kubectl get all -l platform.pnats.cloud/layer=platform

# Get all critical tier resources
kubectl get all -l platform.pnats.cloud/tier=critical

# Get resources by team
kubectl get all -l platform.pnats.cloud/team=platform-team

# Get resources by environment
kubectl get all -l platform.pnats.cloud/environment=production

# Get resources with monitoring enabled
kubectl get all -l platform.pnats.cloud/monitoring-enabled=true

# Get resources by specific version
kubectl get all -l app.kubernetes.io/version=v3.1.8

# Combine multiple selectors
kubectl get all -l "platform.pnats.cloud/layer=platform,platform.pnats.cloud/tier=critical"
```

### NetworkPolicy Example

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-platform-critical
spec:
  podSelector:
    matchLabels:
      platform.pnats.cloud/layer: platform
      platform.pnats.cloud/tier: critical
  ingress:
  - from:
    - podSelector:
        matchLabels:
          platform.pnats.cloud/layer: platform
```

### ServiceMonitor Example

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: platform-metrics
spec:
  selector:
    matchLabels:
      platform.pnats.cloud/monitoring-enabled: "true"
      platform.pnats.cloud/layer: platform
```

## Best Practices

### 1. No Defaults in Templates

❌ **Bad:**
```yaml
name: {{ .Values.resource.name | default "my-resource" }}
```

✅ **Good:**
```yaml
name: {{ .Values.resource.name }}
```

**Why?** All values should be explicit in values.yaml for visibility and debuggability.

### 2. Dynamic Label Loops

❌ **Bad:**
```yaml
labels:
  app.kubernetes.io/name: {{ .Values.labels.name }}
  app.kubernetes.io/component: {{ .Values.labels.component }}
```

✅ **Good:**
```yaml
labels:
  {{- range $key, $value := .Values.commonLabels }}
  {{ $key }}: {{ $value }}
  {{- end }}
  {{- range $key, $value := .Values.commonSelectors }}
  {{ $key }}: {{ $value }}
  {{- end }}
```

**Why?** Loops make it easy to add/remove labels without changing templates.

### 3. Separate Common and Specific

✅ **Good:**
```yaml
commonSelectors:
  app.kubernetes.io/part-of: argocd-app
  platform.pnats.cloud/layer: platform

ingress:
  labels:
    app.kubernetes.io/name: argocd-server-ingress
    app.kubernetes.io/component: ingress-config
```

**Why?** Clear separation between shared and resource-specific labels.

### 4. Use Conditional Rendering

✅ **Good:**
```yaml
{{- if .Values.resource.enabled }}
---
apiVersion: v1
kind: ConfigMap
# ...
{{- end }}
```

**Why?** Allows enabling/disabling resources via values.

### 5. Keys with Special Characters

For keys with dashes (like `part-of`), use the `index` function OR use in loops:

```yaml
# In loops (recommended)
{{- range $key, $value := .Values.commonSelectors }}
{{ $key }}: {{ $value }}
{{- end }}

# Direct access (if needed)
{{ index .Values.commonSelectors "app.kubernetes.io/part-of" }}
```

## Example: Adding ingress-nginx-config

```bash
# 1. Create directory
mkdir -p platform/apps/ingress-nginx-config/templates

# 2. Copy and customize from argocd-config
cp platform/apps/argocd-config/Chart.yaml platform/apps/ingress-nginx-config/
cp platform/apps/argocd-config/values.yaml platform/apps/ingress-nginx-config/

# 3. Update Chart.yaml
# Change name, description, etc.

# 4. Update values.yaml
# Change app.kubernetes.io/part-of: ingress-nginx-app
# Change labels.name, labels.component
# Change namespace

# 5. Create templates (ConfigMaps, Secrets, etc.)
cat > platform/apps/ingress-nginx-config/templates/configmap.yaml <<EOF
{{- if .Values.configMap.enabled }}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Values.configMap.name }}
  namespace: {{ .Values.ingressNginx.namespace }}
  labels:
    {{- range \$key, \$value := .Values.commonLabels }}
    {{ \$key }}: {{ \$value }}
    {{- end }}
    {{- range \$key, \$value := .Values.commonSelectors }}
    {{ \$key }}: {{ \$value }}
    {{- end }}
    {{- range \$key, \$value := .Values.configMap.labels }}
    {{ \$key }}: {{ \$value }}
    {{- end }}
    app.kubernetes.io/instance: {{ .Release.Name }}
data:
  {{- toYaml .Values.configMap.data | nindent 2 }}
{{- end }}
EOF

# 6. Test
helm template ingress-nginx-config platform/apps/ingress-nginx-config --namespace ingress-nginx

# 7. Update parent Application in platform/charts/ingress-nginx/
# Add third source pointing to platform/apps/ingress-nginx-config
```

## Support

For questions or issues:
- **Documentation:** docs.pnats.cloud/platform/apps/
- **Owner:** Shaik Noorullah (snoorullah@proficientnowtech.com)
- **Team:** platform-team
- **Repository:** https://github.com/pnow-devsupreme/pn-infra

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 0.1.0 | 2025-01-23 | Initial documentation with argocd-config example |
