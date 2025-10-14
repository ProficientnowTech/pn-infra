# Platform Hooks

ArgoCD hooks for automated validation, health checks, and failure notifications in the template-driven platform.

## Directory Structure

```
hooks/
├── validation/           # Pre-sync validation hooks
│   ├── infrastructure-presync-validation.yaml
│   └── storage-presync-hook.yaml
├── health-checks/        # Post-sync health verification
│   ├── rook-ceph-health-check.yaml
│   └── monitoring-postsync-hook.yaml
├── notifications/        # Failure and success notifications
│   └── sync-failure-notification.yaml
└── README.md            # This file
```

## Hook Categories

### Validation Hooks (Pre-Sync)
- **infrastructure-presync-validation**: Validates ArgoCD API, namespaces, CNI, ingress, cert-manager
- **storage-presync-hook**: Validates storage prerequisites before deployment

### Health Check Hooks (Post-Sync)  
- **rook-ceph-health-check**: Comprehensive Ceph cluster health validation
- **monitoring-postsync-hook**: Monitoring stack health verification

### Notification Hooks (On Failure)
- **sync-failure-notification**: Automated failure alerting and logging

## Integration with Template-Driven Platform

Hooks are integrated into application charts via conditional templates:

```yaml
# In chart templates
{{- if .Values.global.hooks.validation.infrastructure }}
apiVersion: batch/v1
kind: Job
metadata:
  annotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/sync-wave: "-10"
# ... hook definition
{{- end }}
```

## Configuration

Enable/disable hooks via values files:

```yaml
# values-production.yaml
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

## Sync Wave Ordering

- **Wave -10**: Infrastructure validation
- **Wave -5**: Storage validation  
- **Wave 2**: Rook-Ceph health check
- **Wave 5**: Monitoring validation
- **On Failure**: Sync failure notification

## Benefits

✅ **Automated Validation**: Prevents failed deployments  
✅ **Health Monitoring**: Verifies component health post-deployment  
✅ **Failure Detection**: Immediate notification of sync failures  
✅ **Production Readiness**: Enterprise-grade operational capabilities  
✅ **Environment Flexibility**: Selective hook deployment per environment