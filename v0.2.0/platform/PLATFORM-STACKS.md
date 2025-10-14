# Platform Stacks Documentation

This document describes the platform deployment stacks, their configurations, and the purpose of each component.

## Overview

The platform uses a **Template-Driven Application Factory** pattern via the `target-chart` to deploy different combinations of infrastructure applications across environments.

## Stack Configurations

### 🏭 Production Stack
**File:** `target-chart/values-production.yaml`
**Purpose:** Full platform infrastructure for production workloads

#### Applications Deployed (14 total)
```
GitOps Platform:
├── argocd (sync-wave: 0)            # GitOps deployment tool (self-managed)
│
Infrastructure Foundation:
├── metallb (sync-wave: -4)          # Load balancer
├── ingress-nginx (sync-wave: -3)    # Ingress controller
├── cert-manager (sync-wave: -2)     # TLS certificate management
├── metallb-config (sync-wave: -1)   # MetalLB IP pool configuration
├── ingress-nginx-config (-1)        # Nginx ingress configuration
├── cert-manager-config (-1)         # Let's Encrypt issuer configuration
│
Storage Platform:
├── rook-ceph (sync-wave: 1)         # Ceph operator
├── rook-ceph-cluster (sync-wave: 2) # Ceph storage cluster
│
Security Platform:
├── vault (sync-wave: 3)             # Secret management
│
Monitoring Platform:
├── prometheus (sync-wave: 4)        # Metrics collection
├── grafana (sync-wave: 5)           # Metrics visualization
│
ML Infrastructure Platform:
├── kuberay-crds (sync-wave: 6)      # Ray CRDs for ML workloads
├── kuberay-operator (sync-wave: 7)  # Ray operator
└── gpu-operator (sync-wave: 8)      # NVIDIA GPU support
```

#### Key Configuration
```yaml
stackName: 'production'
default:
  repoURL: 'git@github.com:pnow-devsupreme/pn-infra.git'
  targetRevision: 'main'

# All hooks enabled for production safety
global:
  hooks:
    enabled: true
    validation:
      infrastructure: true
      storage: true
    healthChecks:
      rookCeph: true
      monitoring: true
    notifications:
      syncFailure: true
```

---

### 🧪 Staging Stack
**File:** `target-chart/values-staging.yaml`
**Purpose:** Production-like environment without ML infrastructure for testing

#### Applications Deployed (11 total)
```
GitOps Platform:
├── argocd (sync-wave: 0)            # GitOps deployment tool (self-managed)
│
Infrastructure Foundation:
├── metallb (sync-wave: -4)
├── ingress-nginx (sync-wave: -3)
├── cert-manager (sync-wave: -2)
├── metallb-config (sync-wave: -1)
├── ingress-nginx-config (-1)
├── cert-manager-config (-1)
│
Storage Platform:
├── rook-ceph (sync-wave: 1)
├── rook-ceph-cluster (sync-wave: 2)
│
Security Platform:
├── vault (sync-wave: 3)
│
Monitoring Platform:
├── prometheus (sync-wave: 4)
└── grafana (sync-wave: 5)

❌ EXCLUDED: ML infrastructure (kuberay-*, gpu-operator)
```

#### Key Configuration
```yaml
stackName: 'staging'
default:
  repoURL: 'git@github.com:pnow-devsupreme/pn-infra.git'  # HTTPS for staging
  targetRevision: 'main'

# Reduced monitoring validation for faster feedback
global:
  hooks:
    healthChecks:
      monitoring: false
```

---

### 🔨 Development Stack
**File:** `target-chart/values-development.yaml`
**Purpose:** Minimal stack for development and testing

#### Applications Deployed (5 total)
```
GitOps Platform:
├── argocd (sync-wave: 0)            # GitOps deployment tool (self-managed)
│
Storage Platform:
├── rook-ceph (sync-wave: 1)
├── rook-ceph-cluster (sync-wave: 2)
│
Monitoring Platform:
├── prometheus (sync-wave: 3)
└── grafana (sync-wave: 4)

❌ EXCLUDED: Infrastructure foundation, security, ML infrastructure
```

#### Key Configuration
```yaml
stackName: 'development'

# Faster retry policy for development
global:
  retry:
    limit: 2
    backoff:
      duration: '3s'
      maxDuration: '1m'
```

---

## Common Labels and Annotations

### Labels Applied to All Applications

| Label | Purpose | Example Value |
|-------|---------|---------------|
| `app.kubernetes.io/managed-by` | Deployment tool | `target-chart` |
| `app.kubernetes.io/part-of` | System component | `platform-infrastructure` |
| `platform.pn-infra.io/stack` | Platform identifier | `platform` |
| `platform.pn-infra.io/environment` | Environment name | `production` |

**Auto-Generated Labels:**
- `platform.pn-infra.io/application: "{app-name}"` - Specific application name
- `platform.pn-infra.io/stack: "{stackName}"` - Stack instance name

### Annotations Applied to All Applications

| Annotation | Purpose | Value |
|------------|---------|-------|
| `platform.pn-infra.io/generated-by` | Generation source | `target-chart` |

---

## Why These Labels Are Required

### Kubernetes Standard Labels
- **`app.kubernetes.io/managed-by`**: Identifies the tool managing the resource (required for proper lifecycle management)
- **`app.kubernetes.io/part-of`**: Groups related applications together (useful for monitoring and operations)

### Platform-Specific Labels
- **`platform.pn-infra.io/stack`**: Identifies this as platform infrastructure (vs. application workloads)
- **`platform.pn-infra.io/environment`**: Environment-specific operations and policies
- **`platform.pn-infra.io/application`**: Fine-grained application identification for debugging

### Auto-Generated Labels
- **`platform.pn-infra.io/application`**: Each app gets its specific name for targeted operations
- **`platform.pn-infra.io/stack`**: Instance-specific stack name (e.g., "production", "staging-eu")

---

## Sync Wave Strategy

Applications deploy in carefully orchestrated waves to ensure dependencies:

**Wave 0**: GitOps platform (ArgoCD self-management)
**Wave -4 to -1**: Infrastructure foundation
**Wave 1-2**: Storage foundation
**Wave 3**: Security platform
**Wave 4-5**: Monitoring platform
**Wave 6-8**: ML infrastructure platform

This ensures that ArgoCD is deployed first for self-management, followed by networking, storage, and security before monitoring and ML workloads deploy.

---

## Repository Configuration

### Production
- **URL**: `git@github.com:pnow-devsupreme/pn-infra.git` (SSH for security)
- **Branch**: `main` (stable releases)

### Staging/Development
- **URL**: `git@github.com:pnow-devsupreme/pn-infra.git` (HTTPS for simplicity)
- **Branch**: `main` (testing latest changes)

---

## Usage

### Deploy Production Stack
```bash
# Deploy ArgoCD first (self-management)
kubectl apply -f bootstrap/platform-root-template-driven.yaml

# ArgoCD will then deploy all platform applications via target-chart
```

### Deploy Custom Stack
```bash
cd target-chart
helm template my-stack . -f values-staging.yaml | kubectl apply -f -
```

### View Generated Applications
```bash
cd target-chart
helm template test . -f values-production.yaml
```
