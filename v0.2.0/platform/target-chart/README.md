# Target Chart - Platform Application Factory

This chart implements the **Template-Driven Application Factory** pattern to generate ArgoCD applications for platform infrastructure components.

## Overview

The target-chart generates multiple ArgoCD Applications from a single configuration, allowing you to deploy different combinations of platform services across environments.

## Stack Configurations

### 🏭 Production Stack (`values-production.yaml`)
**Full platform infrastructure for production workloads**

**Applications (13 total):**
```
Infrastructure Foundation:
├── metallb (LoadBalancer)
├── ingress-nginx (Ingress Controller)  
├── cert-manager (TLS Certificates)
├── metallb-config, ingress-nginx-config, cert-manager-config

Storage Platform:
├── rook-ceph (Ceph Operator)
├── rook-ceph-cluster (Storage Cluster)

Security Platform:
├── vault (Secret Management)

Monitoring Platform:
├── prometheus (Metrics Collection)
├── grafana (Metrics Visualization)

ML Infrastructure:
├── kuberay-crds, kuberay-operator (Ray ML Framework)
└── gpu-operator (NVIDIA GPU Support)
```

### 🧪 Staging Stack (`values-staging.yaml`)
**Production-like environment without ML infrastructure**

**Applications (10 total):** Infrastructure + Storage + Security + Monitoring
**Excluded:** ML infrastructure components

### 🔨 Development Stack (`values-development.yaml`)
**Minimal stack for development**

**Applications (4 total):** Storage + Monitoring only
**Excluded:** Infrastructure foundation, security, ML

---

## Configuration Values

### Core Configuration

```yaml
# Repository settings
default:
  repoURL: 'git@github.com:pnow-devsupreme/pn-infra.git'
  targetRevision: 'main'

# Stack identifier  
stackName: 'production'  # Used in labels and naming

# Applications to deploy
applications:
  - name: app-name
    namespace: target-namespace
    annotations:
      argocd.argoproj.io/sync-wave: '1'
```

### Global Settings

```yaml
global:
  # ArgoCD project for all applications
  project: 'platform'
  
  # Sync policy for all applications
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - 'CreateNamespace=true'
      - 'RespectIgnoreDifferences=true'
  
  # Retry configuration
  retry:
    limit: 3
    backoff:
      duration: '5s'
      factor: 2
      maxDuration: '3m'

  # Hooks configuration (production only)
  hooks:
    enabled: true
    validation:
      infrastructure: true  # Validate infrastructure components
      storage: true         # Validate storage components
    healthChecks:
      rookCeph: true       # Ceph cluster health checks
      monitoring: true     # Monitoring stack health checks
    notifications:
      syncFailure: true    # Notify on sync failures
```

### Labels and Annotations

```yaml
# Labels applied to ALL generated applications
commonLabels:
  app.kubernetes.io/managed-by: 'target-chart'
  app.kubernetes.io/part-of: 'platform-infrastructure'
  platform.pn-infra.io/stack: 'platform'
  platform.pn-infra.io/environment: 'production'

# Annotations applied to ALL generated applications  
commonAnnotations:
  platform.pn-infra.io/generated-by: 'target-chart'
```

**Auto-generated labels for each application:**
- `platform.pn-infra.io/application: "{app-name}"`
- `platform.pn-infra.io/stack: "{stackName}"`

---

## Sync Wave Strategy

Applications deploy in orchestrated waves to handle dependencies:

| Wave | Components | Purpose |
|------|------------|---------|
| **-4** | metallb | Load balancer foundation |
| **-3** | ingress-nginx | Ingress controller |
| **-2** | cert-manager | TLS certificate management |
| **-1** | *-config | Configuration for foundation |
| **1** | rook-ceph | Storage operator |
| **2** | rook-ceph-cluster | Storage cluster |
| **3** | vault | Secret management |
| **4** | prometheus | Metrics collection |
| **5** | grafana | Metrics visualization |
| **6** | kuberay-crds | ML framework CRDs |
| **7** | kuberay-operator | ML framework operator |
| **8** | gpu-operator | GPU support |

---

## Usage

### Deploy Production Stack
```bash
# Via root application (recommended)
kubectl apply -f ../bootstrap/platform-root-template-driven.yaml

# Direct deployment
helm template platform-prod . -f values-production.yaml | kubectl apply -f -
```

### Deploy Staging Stack
```bash
helm template platform-staging . -f values-staging.yaml | kubectl apply -f -
```

### Deploy Development Stack
```bash
helm template platform-dev . -f values-development.yaml | kubectl apply -f -
```

### Preview Generated Applications
```bash
# See all applications that will be created
helm template test . -f values-production.yaml

# See specific application
helm template test . -f values-production.yaml | grep -A 20 "name: vault"
```

---

## Environment Differences

| Feature | Production | Staging | Development |
|---------|------------|---------|-------------|
| **Repository** | SSH (git@) | HTTPS | HTTPS |
| **Applications** | All 13 | 10 (no ML) | 4 (minimal) |
| **Hooks** | All enabled | Reduced monitoring | Disabled |
| **Retry Policy** | Conservative | Standard | Fast |
| **Validation** | Full | Infrastructure + Storage | None |

---

## Customization

### Adding New Applications
```yaml
applications:
  - name: my-new-app
    namespace: my-namespace
    annotations:
      argocd.argoproj.io/sync-wave: '10'  # Deploy after platform
```

### Environment-Specific Values
Create new `values-{environment}.yaml` files following the existing pattern.

### Custom Labels
Add environment-specific labels to `commonLabels` in each values file.