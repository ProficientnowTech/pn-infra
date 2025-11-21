# Complete GitOps Architecture Implementation Guide

## Table of Contents
1. [Git Branching Strategy](#git-branching-strategy)
2. [Monorepo Structure](#monorepo-structure)
3. [Semantic Versioning & Maturity Tags](#semantic-versioning)
4. [Tekton CI Pipeline](#tekton-ci-pipeline)
5. [Harbor Registry Configuration](#harbor-registry)
6. [Verdaccio NPM Registry](#verdaccio-registry)
7. [Kargo Progressive Delivery](#kargo-progressive-delivery)
8. [ArgoCD & Argo Rollouts](#argocd-rollouts)
9. [Environment Configuration](#environment-configuration)
10. [Sandbox Environment](#sandbox-environment)
11. [Preview Environments](#preview-environments)
12. [Complete Configuration Examples](#configuration-examples)

---

## 1. Git Branching Strategy

### Branch Structure
```
main (production-ready, stable tags only)
├── develop (integration branch, alpha tags)
├── release/v1.x.x (beta tags)
├── feature/service-name-feature (feature development)
└── hotfix/issue-description (emergency fixes)
```

### Branch Naming Convention
- **Feature branches**: `feature/[service-name]-[feature-description]`
  - Example: `feature/user-service-oauth2`
  - Example: `feature/payment-service-stripe-integration`
  
- **Release branches**: `release/v[major].[minor].[patch]`
  - Example: `release/v1.2.0`
  
- **Hotfix branches**: `hotfix/[issue-description]`
  - Example: `hotfix/security-cve-2024-1234`

### Workflow Steps

#### Feature Development (PR to develop)
1. Developer creates feature branch from `develop`
2. Implements changes with unit tests
3. Opens PR to `develop` branch
4. CI pipeline runs:
   - Linting
   - Unit tests
   - Build images (tag: `pr-{number}-{short-sha}`)
   - Security scan
   - Deploy preview environment
5. If vulnerabilities found → Request changes
6. Once approved → Merge to `develop`
7. Auto-tag: `v1.2.3-alpha.{timestamp}`

#### Release Preparation (develop to main)
1. Create release branch from `develop`: `release/v1.2.0`
2. Auto-tag: `v1.2.0-beta.1`
3. Deploy to staging for testing
4. Bug fixes → `v1.2.0-beta.2`, `v1.2.0-beta.3`, etc.
5. Once stable → Merge to `main`
6. Tag: `v1.2.0` (stable)
7. Merge back to `develop`

#### Hotfix (Production Emergency)
1. Create hotfix branch from `main`
2. Fix issue with tests
3. Tag: `v1.2.1` (patch version)
4. Merge to `main` and `develop`

---

## 2. Monorepo Structure

```
/
├── .github/
│   └── workflows/          # GitHub Actions for non-Tekton tasks
├── services/               # Microservices
│   ├── user-service/
│   │   ├── src/
│   │   ├── tests/
│   │   ├── Dockerfile
│   │   ├── package.json    # or requirements.txt
│   │   └── .dockerignore
│   ├── payment-service/
│   └── notification-service/
├── packages/               # Shared TypeScript packages
│   ├── common-types/
│   │   ├── src/
│   │   ├── tests/
│   │   └── package.json
│   ├── api-client/
│   └── utils/
├── config/                 # Separate GitOps config repo reference
├── tekton/
│   ├── pipelines/
│   ├── tasks/
│   ├── triggers/
│   └── interceptors/
├── kargo/
│   ├── warehouses/
│   ├── stages/
│   └── promotions/
├── argocd/
│   ├── applications/
│   └── app-of-apps.yaml
├── scripts/
│   ├── version.sh
│   └── detect-changes.sh
├── package.json            # Root package.json for workspace
├── lerna.json              # Or nx.json for monorepo management
└── README.md
```

---

## 3. Semantic Versioning & Maturity Tags

### Version Format
```
v{major}.{minor}.{patch}-{maturity}.{build}
```

### Maturity Levels

#### Alpha (Bleeding Edge - Development)
- **Format**: `v1.2.3-alpha.{timestamp}`
- **Generated**: On every merge to `develop`
- **Example**: `v1.2.3-alpha.20241114153045`
- **Tags**: 
  - Full version tag
  - `alpha` (latest alpha)
  - `latest-alpha`
- **Environment**: Development → Staging
- **Stability**: Experimental, breaking changes possible

#### Beta (Feature Complete - Release Candidates)
- **Format**: `v1.2.3-beta.{increment}`
- **Generated**: On release branch creation and bug fixes
- **Example**: `v1.2.0-beta.1`, `v1.2.0-beta.2`
- **Tags**:
  - Full version tag
  - `beta` (latest beta)
  - `latest-beta`
- **Environment**: UAT → Pre-Production
- **Stability**: Feature complete, bug fixes only

#### Stable (Production Ready)
- **Format**: `v{major}.{minor}.{patch}`
- **Generated**: On merge to `main`
- **Example**: `v1.2.0`
- **Tags**:
  - Full version tag
  - `stable` (latest stable)
  - `latest`
  - `v1.2` (minor version)
  - `v1` (major version)
- **Environment**: Production
- **Stability**: Production-ready, fully tested

### Version Bumping Rules

```bash
# Alpha (automatic on develop merge)
v1.2.3-alpha.20241114153045

# Beta (release branch)
v1.2.0-beta.1  # First release candidate
v1.2.0-beta.2  # Bug fix
v1.2.0-beta.3  # Another bug fix

# Stable (main merge)
v1.2.0  # Promoted from beta

# Hotfix (patch)
v1.2.1  # Security or critical bug fix

# Next feature cycle
v1.3.0-alpha.20241115093022
```

---

## 4. Tekton CI Pipeline

### Pipeline Structure

We need 4 main pipelines:
1. **PR Validation Pipeline** - Triggered on PR open/update
2. **Alpha Build Pipeline** - Triggered on merge to develop
3. **Beta Build Pipeline** - Triggered on release branch
4. **Stable Release Pipeline** - Triggered on merge to main
5. **Package Build Pipeline** - For TypeScript packages

### Tekton Installation

```bash
# Install Tekton Pipelines
kubectl apply -f https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml

# Install Tekton Triggers
kubectl apply -f https://storage.googleapis.com/tekton-releases/triggers/latest/release.yaml

# Install Tekton Dashboard
kubectl apply -f https://storage.googleapis.com/tekton-releases/dashboard/latest/release.yaml
```

### Key Tekton Concepts

- **Task**: Reusable unit of work (e.g., git-clone, docker-build)
- **Pipeline**: Sequence of tasks
- **PipelineRun**: Execution instance of a pipeline
- **EventListener**: Listens for webhooks
- **Trigger**: Creates PipelineRun from event
- **TriggerBinding**: Extracts data from webhook payload
- **TriggerTemplate**: Template for creating PipelineRun

---

## 5. Harbor Registry Configuration

### Harbor Setup

```yaml
# Harbor installation with Helm
helm repo add harbor https://helm.goharbor.io
helm repo update

helm install harbor harbor/harbor \
  --namespace harbor \
  --create-namespace \
  --set expose.type=loadBalancer \
  --set expose.tls.enabled=true \
  --set persistence.enabled=true \
  --set harborAdminPassword="YourSecurePassword" \
  --set trivy.enabled=true
```

### Project Structure in Harbor

```
harbor.yourdomain.com/
├── services/           # Container images for services
│   ├── user-service
│   ├── payment-service
│   └── notification-service
└── base-images/        # Base images
    ├── node
    └── python
```

### Tagging Strategy in Harbor

For each image build:
```
harbor.yourdomain.com/services/user-service:v1.2.3-alpha.20241114153045
harbor.yourdomain.com/services/user-service:alpha
harbor.yourdomain.com/services/user-service:latest-alpha
harbor.yourdomain.com/services/user-service:pr-123-abc123  # PR builds
```

### Harbor Vulnerability Scanning

**Automatic Scanning Configuration:**
```yaml
# Harbor project-level scanning policy
scan_on_push: true
prevent_vulnerable_images: true
severity_threshold: "high"  # Block high & critical CVEs
```

**Webhook to GitHub:**
Configure Harbor webhook to post scan results to GitHub PR as comments.

---

## 6. Verdaccio NPM Registry

### Verdaccio Setup

```yaml
# verdaccio-values.yaml
persistence:
  enabled: true
  storageClass: "your-storage-class"
  size: 50Gi

service:
  type: LoadBalancer
  port: 4873

configMap: |
  storage: /verdaccio/storage
  
  auth:
    htpasswd:
      file: /verdaccio/htpasswd
  
  uplinks:
    npmjs:
      url: https://registry.npmjs.org/
  
  packages:
    '@yourorg/*':
      access: $authenticated
      publish: $authenticated
      unpublish: $authenticated
    
    '**':
      access: $all
      publish: $authenticated
      proxy: npmjs

  logs:
    - { type: stdout, format: pretty, level: http }
```

```bash
# Install Verdaccio
helm repo add verdaccio https://charts.verdaccio.org
helm install verdaccio verdaccio/verdaccio \
  -f verdaccio-values.yaml \
  --namespace verdaccio \
  --create-namespace
```

### Package Naming Convention

```
@yourorg/common-types
@yourorg/api-client
@yourorg/utils
@yourorg/logger
```

### Package Versioning (Aligned with Images)

```json
{
  "name": "@yourorg/common-types",
  "version": "1.2.3-alpha.20241114153045",
  "publishConfig": {
    "registry": "https://verdaccio.yourdomain.com"
  }
}
```

---

## 7. Kargo Progressive Delivery

### Kargo Installation

```bash
# Install Kargo
helm repo add kargo https://charts.kargo.io
helm repo update

helm install kargo kargo/kargo \
  --namespace kargo \
  --create-namespace \
  --set api.enabled=true \
  --set controller.enabled=true
```

### Kargo Concepts

- **Warehouse**: Tracks artifacts (images, packages) from registries
- **Stage**: Represents an environment (dev, staging, prod)
- **Promotion**: Moving artifacts between stages
- **Freight**: A collection of artifacts being promoted

### Stage Progression

```
Warehouse → Dev → Staging → UAT → Pre-Prod → Production
           (auto)  (auto)   (manual) (manual)   (manual)
```

---

## 8. ArgoCD & Argo Rollouts

### ArgoCD Installation

```bash
# Install ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Install Argo Rollouts
kubectl create namespace argo-rollouts
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
```

### Deployment Strategies by Environment

| Environment | Strategy | Description |
|-------------|----------|-------------|
| Development | Recreate | Fast, no downtime needed |
| Staging | Rolling Update | Standard rolling deployment |
| UAT | Rolling Update | Standard rolling deployment |
| Pre-Prod | Canary | 10% → 25% → 50% → 100% |
| Production | Blue-Green | Zero-downtime switch |

---

## 9. Environment Configuration

### Environment Matrix

| Environment | Cluster | Namespace | Access | Database | Purpose |
|-------------|---------|-----------|---------|----------|---------|
| Preview (PR) | Staging | pr-{number} | Public | Ephemeral | PR testing |
| Development | Staging | dev | Internal | Dev DB | Alpha builds |
| Staging | Staging | staging | Internal | Staging DB | Integration tests |
| UAT | Staging | uat | Internal | UAT DB | User acceptance |
| Pre-Prod | Production | pre-prod | Internal | Prod Clone | Canary testing |
| Production | Production | production | Public | Prod DB | Live traffic |
| Sandbox | Production | sandbox | Internal | Test Data | Experimentation |

### DNS & Ingress Strategy

```
# PR Preview
pr-123-user-service.preview.yourdomain.com

# Development
user-service.dev.yourdomain.com

# Staging
user-service.staging.yourdomain.com

# UAT
user-service.uat.yourdomain.com

# Pre-Production
user-service.preprod.yourdomain.com

# Production
user-service.yourdomain.com

# Sandbox
user-service.sandbox.yourdomain.com
```

---

## 10. Sandbox Environment

### Sandbox Requirements

1. **Daily Production Clone**: Replicate production state
2. **24-hour TTL**: Reset after 24 hours
3. **Test Database**: Realistic test data, not production data
4. **Read-only from Production**: Changes don't propagate back
5. **Public Access**: Exposed for testing
6. **Configurable TTL**: Can be adjusted

### Implementation Strategy

**CronJob for Daily Sync:**
```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: sandbox-sync
  namespace: production
spec:
  schedule: "0 0 * * *"  # Daily at midnight
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: sync
            image: your-sync-image
            env:
            - name: TTL_HOURS
              value: "24"
            command:
            - /bin/bash
            - -c
            - |
              # 1. Get current production state
              # 2. Clone k8s resources to sandbox namespace
              # 3. Update ConfigMaps with sandbox DB
              # 4. Set TTL annotation
              # 5. Deploy to sandbox
```

**Sandbox Sync Logic:**
```bash
#!/bin/bash
# sandbox-sync.sh

# 1. Export production manifests
kubectl get deployment,service,configmap -n production -o yaml > prod-state.yaml

# 2. Transform for sandbox
sed 's/namespace: production/namespace: sandbox/g' prod-state.yaml > sandbox-state.yaml

# 3. Update database connections
yq eval '.data.DATABASE_URL = "postgresql://sandbox-db:5432/test"' -i sandbox-state.yaml

# 4. Add TTL annotation
yq eval '.metadata.annotations.ttl = "24h"' -i sandbox-state.yaml

# 5. Apply to sandbox
kubectl apply -f sandbox-state.yaml

# 6. Schedule cleanup
at now + 24 hours <<EOF
kubectl delete namespace sandbox
kubectl create namespace sandbox
EOF
```

### Sandbox Database Strategy

**Option 1: Anonymized Production Clone**
```bash
# Daily job: Clone and anonymize production DB
pg_dump production_db | \
  anonymize_pii.py | \
  psql sandbox_db
```

**Option 2: Synthetic Test Data**
```bash
# Use Faker or similar to generate realistic data
python generate_test_data.py --records 10000 --db sandbox_db
```

---

## 11. Preview Environments

### PR Preview Creation

**Automatic Preview Deployment:**
1. PR opened → Tekton builds image with tag `pr-{number}-{sha}`
2. Tekton creates temporary ArgoCD Application
3. ArgoCD deploys to namespace `pr-{number}`
4. Tekton comments on PR with preview URL

### Preview Environment Lifecycle

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: pr-123
  annotations:
    preview: "true"
    pr-number: "123"
    ttl: "7d"  # Auto-delete after 7 days
    created-at: "2024-11-14T15:30:45Z"
```

**Cleanup Strategy:**
```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: preview-cleanup
spec:
  schedule: "0 */6 * * *"  # Every 6 hours
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: cleanup
            image: bitnami/kubectl
            command:
            - /bin/bash
            - -c
            - |
              # Delete preview namespaces older than 7 days
              kubectl get namespace -l preview=true -o json | \
              jq -r '.items[] | select(.metadata.annotations."created-at" | fromdateiso8601 < (now - 604800)) | .metadata.name' | \
              xargs -r kubectl delete namespace
```

---

## 12. Repository Structure

### Application Repository (Monorepo)
```
github.com/yourorg/application-monorepo
```

### GitOps Configuration Repository
```
github.com/yourorg/gitops-config
├── base/
│   ├── user-service/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── configmap.yaml
│   │   └── kustomization.yaml
│   └── payment-service/
├── overlays/
│   ├── dev/
│   │   ├── kustomization.yaml
│   │   └── patches/
│   ├── staging/
│   ├── uat/
│   ├── preprod/
│   └── production/
├── argocd/
│   ├── applications/
│   │   ├── user-service-dev.yaml
│   │   ├── user-service-staging.yaml
│   │   └── user-service-prod.yaml
│   └── app-of-apps.yaml
└── kargo/
    ├── warehouses/
    ├── stages/
    └── promotions/
```

---

## Summary of Tools & Versions

| Tool | Purpose | Version | Notes |
|------|---------|---------|-------|
| Tekton | CI Pipelines | Latest | Event-driven builds |
| Harbor | Container Registry | 2.x | With Trivy scanning |
| Verdaccio | NPM Registry | Latest | For TypeScript packages |
| Kargo | Progressive Delivery | Latest | Stage promotions |
| ArgoCD | GitOps CD | 2.x | Kubernetes deployments |
| Argo Rollouts | Advanced Deployments | Latest | Canary & Blue-Green |
| Trivy | Vulnerability Scanning | Latest | Integrated with Harbor |
| Kustomize | Manifest Management | Latest | Environment overlays |

---

This architecture provides:
- ✅ Automated CI/CD from PR to production
- ✅ Progressive delivery with gates
- ✅ Security scanning at every stage
- ✅ Preview environments for every PR
- ✅ Semantic versioning with alpha/beta/stable tags
- ✅ Monorepo support for services and packages
- ✅ Sandbox environment for safe testing
- ✅ Zero-downtime deployments in production
- ✅ Full traceability from code to deployment
