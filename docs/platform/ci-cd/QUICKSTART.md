# Complete GitOps Pipeline - Quick Start Guide

## 📋 Overview

This is a complete, production-ready GitOps CI/CD pipeline using:
- **Tekton** for CI pipelines
- **Harbor** for container registry with vulnerability scanning
- **Verdaccio** for NPM packages
- **Kargo** for progressive delivery
- **ArgoCD** for GitOps deployment
- **Argo Rollouts** for advanced deployment strategies

---

## 🗂️ Documentation Structure

1. **git-flow-diagram.mermaid** - Git branching strategy visualization
2. **overall-architecture.mermaid** - Complete system architecture
3. **tekton-ci-pipeline.mermaid** - Tekton pipeline flow
4. **kargo-cd-pipeline.mermaid** - Kargo progressive delivery
5. **sequence-diagram.mermaid** - End-to-end workflow
6. **implementation-guide.md** - Core concepts and setup
7. **tekton-configs.md** - Complete Tekton configurations
8. **kargo-configs.md** - Kargo stages and promotions
9. **argocd-rollouts-configs.md** - ArgoCD and deployment strategies
10. **gitops-repo-structure.md** - GitOps repository layout
11. **sandbox-implementation.md** - Sandbox environment setup

---

## 🚀 Quick Start

### Prerequisites

1. Two Kubernetes clusters (staging + production)
2. GitHub repository (monorepo)
3. Domain name with DNS access
4. SSL certificates (Let's Encrypt)

### Installation Order

```bash
# 1. Install Tekton (Staging Cluster)
kubectl apply -f https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml
kubectl apply -f https://storage.googleapis.com/tekton-releases/triggers/latest/release.yaml

# 2. Install Harbor (Both Clusters)
helm install harbor harbor/harbor -f harbor-values.yaml

# 3. Install Verdaccio (Staging Cluster)
helm install verdaccio verdaccio/verdaccio -f verdaccio-values.yaml

# 4. Install ArgoCD (Both Clusters)
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 5. Install Argo Rollouts (Production Cluster)
kubectl create namespace argo-rollouts
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml

# 6. Install Kargo (Both Clusters)
helm install kargo kargo/kargo --namespace kargo --create-namespace
```

---

## 📊 Environment Matrix

| Environment | Cluster | Namespace | Strategy | Auto-Promote | Maturity |
|-------------|---------|-----------|----------|--------------|----------|
| **Dev** | Staging | dev | Recreate | ✅ Yes | Alpha |
| **Staging** | Staging | staging | Rolling | ✅ Yes | Alpha |
| **UAT** | Staging | uat | Rolling | ❌ Manual | Beta |
| **Pre-Prod** | Production | preprod | Canary | ❌ Manual | Beta |
| **Production** | Production | production | Blue-Green | ❌ Manual | Stable |
| **Preview** | Staging | pr-{n} | Recreate | ✅ Auto | PR Build |
| **Sandbox** | Production | sandbox | N/A | ⏰ Scheduled | Stable Clone |

---

## 🔄 Complete Workflow

### 1. Feature Development (PR Flow)

```
Developer creates PR
    ↓
Tekton detects PR webhook
    ↓
Run lint & unit tests
    ↓
Build container image (tag: pr-123-abc123)
    ↓
Push to Harbor
    ↓
Trivy scans for vulnerabilities
    ↓
├─ If HIGH/CRITICAL found
│  ├─ Comment on PR with vulnerabilities
│  └─ Request changes
│
└─ If clean
   ├─ Deploy to preview namespace (pr-123)
   ├─ Comment PR with URL: pr-123-user-service.preview.yourdomain.com
   └─ Developer tests and approves
```

### 2. Merge to Develop (Alpha Build)

```
PR merged to develop
    ↓
Tekton builds all changed services
    ↓
Auto-version: v1.2.3-alpha.20241114153045
    ↓
Push to Harbor with tags:
  - v1.2.3-alpha.20241114153045
  - alpha
  - latest-alpha
    ↓
Create git tag
    ↓
Update GitOps repo
    ↓
Kargo detects new freight
    ↓
Auto-promote to dev → staging
    ↓
Run integration & E2E tests
    ↓
Auto-promote to UAT (if tests pass)
```

### 3. Release Preparation (Beta)

```
Create release branch: release/v1.2.0
    ↓
Auto-version: v1.2.0-beta.1
    ↓
Deploy to UAT
    ↓
Manual testing & bug fixes
    ↓
Each fix: v1.2.0-beta.2, beta.3, etc.
    ↓
UAT approval
    ↓
Promote to pre-prod (canary deployment)
```

### 4. Pre-Production (Canary)

```
Kargo promotes to pre-prod
    ↓
Argo Rollouts starts canary:
  Step 1: 10% traffic → Wait 5 min → Check metrics
  Step 2: 25% traffic → Wait 10 min → Check metrics
  Step 3: 50% traffic → Wait 10 min → Check metrics
  Step 4: 75% traffic → Wait 10 min → Check metrics
  Step 5: 100% traffic
    ↓
Monitor error rates, latency, CPU, memory
    ↓
├─ If metrics fail
│  └─ Automatic rollback
│
└─ If metrics pass
   └─ Ready for production
```

### 5. Production (Blue-Green)

```
Manual promotion to production
    ↓
Argo Rollouts deploys green environment
    ↓
Run smoke tests on preview service
    ↓
Manual verification
    ↓
Manual promotion
    ↓
Switch traffic to green
    ↓
Wait 10 minutes (observation period)
    ↓
Scale down blue environment
```

### 6. Sandbox (Daily Sync)

```
CronJob triggers at midnight
    ↓
Export production manifests
    ↓
Transform for sandbox namespace
    ↓
Clone & anonymize production database
    ↓
Deploy to sandbox namespace
    ↓
Expose via https://sandbox.yourdomain.com
    ↓
Set TTL: 24 hours
    ↓
After 24h: Delete and re-sync
```

---

## 🏷️ Versioning Strategy

### Semantic Versioning

```
v{major}.{minor}.{patch}-{maturity}.{build}
```

### Examples

```bash
# Alpha (Development)
v1.2.3-alpha.20241114153045
v1.2.3-alpha.20241114160022
v1.2.3-alpha.20241115091234

# Beta (Release Candidates)
v1.2.0-beta.1
v1.2.0-beta.2
v1.2.0-beta.3

# Stable (Production)
v1.2.0
v1.2.1  # Hotfix
v1.3.0  # Next feature release
```

### Image Tags

```bash
# Full version
harbor.yourdomain.com/services/user-service:v1.2.3-alpha.20241114153045

# Maturity tags (updated on each build)
harbor.yourdomain.com/services/user-service:alpha
harbor.yourdomain.com/services/user-service:beta
harbor.yourdomain.com/services/user-service:stable
harbor.yourdomain.com/services/user-service:latest

# PR builds
harbor.yourdomain.com/services/user-service:pr-123-abc123
```

---

## 🎯 Key Features

### ✅ Fully Automated CI/CD
- PR validation with preview environments
- Automatic alpha builds on develop merge
- Beta builds on release branches
- Stable builds on main merge

### ✅ Security First
- Vulnerability scanning with Trivy
- Automatic PR updates on CVE detection
- Image signing with Cosign
- SBOM generation

### ✅ Progressive Delivery
- Automatic promotion through environments
- Manual gates for critical stages
- Metrics-based validation
- Automatic rollbacks

### ✅ Zero-Downtime Deployments
- Canary deployments in pre-prod
- Blue-green deployments in production
- Health checks and smoke tests

### ✅ Complete Observability
- Prometheus metrics integration
- Error rate monitoring
- Latency tracking
- Resource utilization

### ✅ Developer Experience
- Preview environment for every PR
- Direct PR comments with URLs
- Version selection and rollback
- Sandbox for experimentation

---

## 🔐 Security Considerations

### 1. Secrets Management

```yaml
# Use sealed secrets or external secrets operator
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: prod-secrets
spec:
  encryptedData:
    DATABASE_URL: AgBd8f7s...
```

### 2. Network Policies

```yaml
# Isolate environments
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-cross-namespace
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - podSelector: {}
```

### 3. RBAC

```yaml
# Least privilege principle
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: developer
rules:
  - apiGroups: [""]
    resources: ["pods", "logs"]
    verbs: ["get", "list"]
```

---

## 📈 Monitoring & Alerts

### Key Metrics

1. **Deployment Success Rate**
   - Track failed vs successful deployments
   - Alert on degradation

2. **Rollback Frequency**
   - Monitor automatic rollbacks
   - Investigate patterns

3. **Lead Time**
   - Time from commit to production
   - Optimize bottlenecks

4. **Change Failure Rate**
   - Percentage of deployments causing incidents
   - Target: < 15%

5. **MTTR (Mean Time To Recovery)**
   - Time to restore service after failure
   - Target: < 1 hour

---

## 🛠️ Troubleshooting

### Common Issues

1. **Tekton pipeline stuck**
   ```bash
   kubectl get pipelineruns -n tekton-pipelines
   kubectl logs -f -n tekton-pipelines <pipelinerun-name>
   ```

2. **ArgoCD app out of sync**
   ```bash
   kubectl get application -n argocd
   argocd app sync <app-name>
   ```

3. **Kargo promotion failed**
   ```bash
   kubectl get freight -n myapp
   kubectl describe stage <stage-name> -n myapp
   ```

4. **Rollout stuck in canary**
   ```bash
   kubectl argo rollouts get rollout <name> -n preprod
   kubectl argo rollouts abort <name> -n preprod
   ```

---

## 📚 Additional Resources

### Official Documentation

- [Tekton](https://tekton.dev)
- [Harbor](https://goharbor.io)
- [Kargo](https://kargo.akuity.io)
- [ArgoCD](https://argo-cd.readthedocs.io)
- [Argo Rollouts](https://argoproj.github.io/argo-rollouts)

### Community

- Tekton Slack: #tekton-pipelines
- ArgoCD Slack: #argo-cd
- CNCF Slack: #gitops

---

## 🎓 Training Path

### Week 1: Foundations
- Set up Kubernetes clusters
- Install Tekton and create first pipeline
- Configure Harbor registry

### Week 2: CI Pipeline
- Create PR validation pipeline
- Implement vulnerability scanning
- Set up preview environments

### Week 3: CD Pipeline
- Install Kargo and ArgoCD
- Configure stages and promotions
- Test automatic promotions

### Week 4: Advanced Deployments
- Implement canary deployments
- Configure blue-green strategy
- Set up metrics analysis

### Week 5: Production Ready
- Configure monitoring and alerts
- Implement sandbox environment
- Document runbooks

---

## 🚨 Production Checklist

Before going live:

- [ ] All clusters configured with HA
- [ ] Backup and disaster recovery tested
- [ ] Secrets properly encrypted
- [ ] Network policies enforced
- [ ] RBAC configured
- [ ] Monitoring and alerting active
- [ ] Runbooks documented
- [ ] Team trained on procedures
- [ ] Rollback procedures tested
- [ ] Load testing completed

---

## 📞 Support

For issues or questions:
1. Check documentation in this repository
2. Search GitHub issues
3. Ask in community Slack channels
4. Create GitHub issue with logs

---

## 🎉 You're Ready!

You now have a complete, production-ready GitOps pipeline with:
- ✅ Automated CI/CD from PR to production
- ✅ Progressive delivery with safety gates
- ✅ Zero-downtime deployments
- ✅ Complete observability
- ✅ Security scanning at every stage
- ✅ Preview environments for testing
- ✅ Sandbox for experimentation

**Happy Deploying! 🚀**
