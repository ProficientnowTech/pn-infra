# ArgoCD Self-Management Setup (Template-Driven Pattern)

## Overview

This implements the complete template-driven pattern where ArgoCD manages itself through the same template-driven system used for platform applications.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│              Template-Driven ArgoCD Pattern                 │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. Initial Bootstrap (via Kubespray)                      │
│     ┌─────────────────┐                                    │
│     │ Plain K8s       │  ──┐                               │
│     │ ArgoCD Install  │    │                               │
│     └─────────────────┘    │                               │
│                            │                               │
│  2. Self-Management Transition                             │
│     ┌─────────────────┐    │   ┌──────────────────┐       │
│     │ Apply Self-     │ ◄──┘   │ ArgoCD Chart     │       │
│     │ Management App  │        │ (charts/argocd) │       │
│     └─────────────────┘        └──────────────────┘       │
│                            │                               │
│  3. Template-Driven Management                            │
│     ┌─────────────────┐    │   ┌──────────────────┐       │
│     │ ArgoCD manages  │ ◄──────│ Target-Chart     │       │
│     │ itself via      │        │ Generation       │       │
│     │ Application     │        └──────────────────┘       │
│     └─────────────────┘                                   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Files Created

### 1. ArgoCD Self-Management Chart
- **`charts/argocd/Chart.yaml`** - Chart metadata with self-management annotations
- **`charts/argocd/values.yaml`** - Complete ArgoCD Helm configuration
- **`charts/argocd/templates/application.yaml`** - ArgoCD Application template
- **`charts/argocd/templates/_helpers.tpl`** - Helm helpers

### 2. Bootstrap Applications
- **`bootstrap/argocd-self-management.yaml`** - Direct self-referencing application
- **`bootstrap/platform-argocd.yaml`** - Target-chart based ArgoCD application  
- **`bootstrap/values-argocd.yaml`** - Values for ArgoCD stack

## Implementation Steps

### Phase 1: Initial Deployment (via Kubespray)
```bash
# This is handled by Kubespray - creates initial ArgoCD installation
# ArgoCD is deployed via Helm in argocd namespace
```

### Phase 2: Apply Self-Management
```bash
# After ArgoCD is running from Kubespray, apply self-management
kubectl apply -f bootstrap/argocd-self-management.yaml

# OR use the target-chart approach
kubectl apply -f bootstrap/platform-argocd.yaml
```

### Phase 3: Validate Self-Management
```bash
# Check that ArgoCD is managing itself
kubectl get applications -n argocd | grep argocd

# Verify sync status
kubectl describe application argocd-self-management -n argocd
```

## Key Features

### Self-Management Safeguards
- **Sync Wave -1**: ArgoCD deploys before all other applications
- **Prune=false**: Prevents ArgoCD from accidentally deleting itself
- **Comprehensive ignoreDifferences**: Avoids conflicts with runtime state
- **SkipDryRunOnMissingResource**: Handles bootstrap edge cases

### High Availability Configuration
- **Server Replicas**: 2 instances with autoscaling
- **Controller Replicas**: 2 instances for HA
- **Repo Server**: 2 replicas with autoscaling  
- **Redis**: Configured for production use

### Security Features
- **RBAC**: Comprehensive role-based access control
- **TLS**: Full TLS encryption with cert-manager
- **Network Policies**: Restricted network access
- **Security Contexts**: Non-root containers

## Integration with Platform Stacks

The ArgoCD self-management integrates with the existing template-driven platform stacks:

```
Sync Wave Order:
-1: ArgoCD Self-Management
 0: Platform Bootstrap Applications  
 1: Storage (rook-ceph)
 2: Storage Cluster (rook-ceph-cluster)
 3: Secrets (vault)
 4: Monitoring (prometheus)
 5: Visualization (grafana)
 6: ML CRDs (kuberay-crds)
 7: ML Operator (kuberay-operator)
 8: GPU Operator (gpu-operator)
```

## Bootstrap Sequence

1. **Kubespray** deploys initial ArgoCD
2. **ArgoCD Self-Management Application** is applied
3. **ArgoCD transitions** to managing itself via GitOps
4. **Platform Bootstrap Applications** deploy platform stacks
5. **All platform services** are managed via template-driven system

## Troubleshooting

### Common Issues

**Application Stuck in Sync**
```bash
# Check for conflicts in ignoreDifferences
kubectl describe application argocd-self-management -n argocd
```

**ArgoCD Components Not Updating**
```bash
# Verify prune is disabled to prevent self-deletion
kubectl get application argocd-self-management -n argocd -o yaml | grep prune
```

**Self-Reference Conflicts**
```bash
# Check that ArgoCD isn't trying to manage the application that manages it
kubectl get applications -n argocd -o yaml | grep -A5 -B5 "argocd-self"
```

## Validation Commands

```bash
# Test template generation
helm template platform-argocd target-chart -f bootstrap/values-argocd.yaml

# Test individual chart
helm template argocd-self charts/argocd

# Verify sync wave ordering
kubectl get applications -n argocd -o custom-columns=NAME:.metadata.name,SYNC-WAVE:.metadata.annotations.argocd\.argoproj\.io/sync-wave

# Check self-management status
kubectl get application argocd-self-management -n argocd -o jsonpath='{.status.sync.status}'
```

This completes the template-driven pattern implementation with ArgoCD self-management capability.