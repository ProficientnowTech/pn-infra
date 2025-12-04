# OneUptime Helm Chart

Complete, production-ready OneUptime deployment with HA, Vault-backed secrets, Keycloak SSO, and full GitOps support.

## Overview

OneUptime is a comprehensive uptime monitoring, status pages, incident management, and alerting platform. This Helm chart provides:

- **High Availability**: Multiple replicas for all critical services
- **Automated Secret Management**: GitOps-friendly workflow with SealedSecrets, Crossplane, and Vault
- **SSO Authentication**: Keycloak OIDC integration
- **Scalability**: KEDA autoscaling for ingestion and worker services
- **Observability**: Built-in telemetry and monitoring
- **Production-Ready**: Security contexts, resource limits, health probes

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                     OneUptime Platform                            │
├──────────────────────────────────────────────────────────────────┤
│                                                                    │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐                 │
│  │ Dashboard  │  │ Status     │  │ Admin      │                 │
│  │ (HA x3)    │  │ Pages      │  │ Dashboard  │                 │
│  └─────┬──────┘  └─────┬──────┘  └─────┬──────┘                 │
│        │                │                │                        │
│        └────────────────┴────────────────┘                        │
│                         │                                         │
│              ┌──────────▼──────────┐                             │
│              │  NGINX Gateway (HA) │                             │
│              └──────────┬──────────┘                             │
│                         │                                         │
├─────────────────────────┼─────────────────────────────────────────┤
│                         │ Ingress                                 │
│  ┌──────────────────────▼───────────────────────┐                │
│  │    K8s Ingress (cert-manager + external-dns) │                │
│  └──────────────────────┬───────────────────────┘                │
│                         │                                         │
│         ┌───────────────┴──────────────┐                         │
│         │                               │                         │
│  uptime.pnats.cloud         status.pnats.cloud                   │
│                                                                    │
├──────────────────────────────────────────────────────────────────┤
│                    Core Services (HA)                             │
├──────────────────────────────────────────────────────────────────┤
│                                                                    │
│  ┌────────┐  ┌─────────┐  ┌──────────┐  ┌─────────────┐         │
│  │Workers │  │Workflows│  │Telemetry │  │Probe Ingest │         │
│  │(KEDA)  │  │         │  │  (KEDA)  │  │   (KEDA)    │         │
│  └────────┘  └─────────┘  └──────────┘  └─────────────┘          │
│                                                                  │
├──────────────────────────────────────────────────────────────────┤
│                      Data Layer                                  │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌────────────┐  ┌──────────┐  ┌────────────┐                    │
│  │ PostgreSQL │  │  Redis   │  │ ClickHouse │                    │
│  │  (50GB)    │  │  (20GB)  │  │  (100GB)   │                    │
│  └────────────┘  └──────────┘  └────────────┘                    │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│                    Security & Auth                                │
├──────────────────────────────────────────────────────────────────┤
│                                                                    │
│  ┌─────────────┐         ┌──────────────┐                        │
│  │  Keycloak   │────────▶│   OneUptime  │                        │
│  │  SSO/OIDC   │         │  (OIDC Auth) │                        │
│  └─────────────┘         └──────────────┘                        │
│                                                                    │
│  ┌─────────────┐         ┌──────────────┐                        │
│  │   Vault     │────────▶│   External   │                        │
│  │  (Secrets)  │         │   Secrets    │                        │
│  └─────────────┘         └──────────────┘                        │
│                                                                    │
└──────────────────────────────────────────────────────────────────┘
```

## Features

### High Availability
- **3 replicas** for Dashboard, App, Accounts, Workers, Workflows
- **2 replicas** for NGINX gateway, OpenTelemetry collector
- **KEDA autoscaling** for telemetry ingestion (2-30 pods)
- **PodDisruptionBudgets** for resilience

### Security
- **Keycloak SSO integration** for authentication
- **Vault-backed secrets** via External Secrets Operator
- **SealedSecrets** for GitOps-friendly secret management
- **Security contexts** with non-root users
- **TLS/SSL** via cert-manager and Let's Encrypt

### Storage
- **plt-blk-hdd-repl** storage class for all persistent volumes
- **50GB** PostgreSQL (application data)
- **100GB** ClickHouse (telemetry/analytics data)
- **20GB** Redis (caching)

### Monitoring & Observability
- **OpenTelemetry Collector** for traces, metrics, logs
- **Prometheus metrics** exposed
- **Health probes** (startup, liveness, readiness)
- **Structured logging**

### Notifications
- **Email** via SMTP (configurable)
- **Slack** webhooks for platform events
- **In-app** notifications

## Prerequisites

| Component | Version | Purpose |
|-----------|---------|---------|
| Kubernetes | 1.25+ | Container orchestration |
| Helm | 3.8+ | Package manager |
| cert-manager | 1.11+ | TLS certificates |
| external-dns | 0.13+ | DNS management |
| Sealed Secrets | 0.24+ | Encrypted secrets |
| External Secrets Operator | 0.9+ | Vault integration |
| Crossplane | 1.14+ | Infrastructure orchestration |
| Vault | 1.15+ | Secret storage |
| Keycloak | 23+ | SSO/OIDC provider |
| KEDA | 2.12+ | Autoscaling |

## Quick Start

### 1. Configure Secrets

Edit the secret files (gitignored):
```bash
cd secrets/
vim smtp.secret    # Configure email server
vim slack.secret   # Configure Slack webhooks
```

### 2. Seal Secrets

Generate encrypted SealedSecrets:
```bash
./seal-secrets.sh
```

This creates encrypted YAML files in `templates/sealed-secrets/` that are safe to commit.

### 3. Commit to Git

```bash
git add templates/sealed-secrets/*.yaml
git commit -m "chore: configure OneUptime secrets"
git push
```

### 4. Deploy via ArgoCD

Create ArgoCD Application:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: oneuptime
  namespace: argocd
spec:
  project: monitoring
  source:
    repoURL: https://github.com/yourorg/pn-infra-main
    targetRevision: main
    path: platform/stacks/monitoring/charts/oneuptime
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
```

Or manually with Helm:
```bash
helm dependency build
helm upgrade --install pn-oneuptime . \
  -n monitoring --create-namespace
```

## Configuration

### Key Values

| Parameter | Description | Default |
|-----------|-------------|---------|
| `oneuptime.host` | Main application domain | `uptime.pnats.cloud` |
| `oneuptime.statusPage.cnameRecord` | Status pages domain | `status.pnats.cloud` |
| `oneuptime.global.storageClass` | Storage class for PVCs | `plt-blk-hdd-repl` |
| `oneuptime.deployment.replicaCount` | Default replica count | `3` |
| `oneuptime.keda.enabled` | Enable KEDA autoscaling | `true` |

### Resource Requests/Limits

Optimized for production workloads:

| Service | CPU Request | Memory Request | CPU Limit | Memory Limit |
|---------|-------------|----------------|-----------|--------------|
| Dashboard | 500m | 1Gi | 2000m | 4Gi |
| Telemetry | 1000m | 2Gi | 4000m | 8Gi |
| PostgreSQL | 500m | 1Gi | 2000m | 4Gi |
| ClickHouse | 1000m | 2Gi | 4000m | 8Gi |
| Redis | 250m | 512Mi | 1000m | 2Gi |

## Secrets Management Workflow

**Complete GitOps workflow with no manual Vault operations required!**

### Architecture

```
Developer ──▶ .secret files (gitignored)
                │
                ▼
         seal-secrets.sh
                │
                ▼
        SealedSecrets (encrypted, in Git)
                │
                ▼ ArgoCD deploys
        ┌───────┴────────┐
        │                │
   Wave 0-1:        Wave 2:
   Generate         Copy to
   Secrets          Vault
        │                │
        └───────┬────────┘
                │
                ▼ Wave 4:
        External Secrets
        syncs from Vault
                │
                ▼
        Application Secrets
```

### Secret Types

1. **Auto-Generated** (Crossplane Random):
   - Database passwords (PostgreSQL, Redis, ClickHouse)
   - Encryption keys (oneuptimeSecret, encryptionSecret)
   - **No manual configuration needed**

2. **Manual Configuration** (SealedSecrets):
   - SMTP credentials
   - Slack webhook URLs
   - **Requires `.secret` file configuration**

3. **External System** (Keycloak Crossplane):
   - OIDC client secret
   - **Auto-generated and synced**

See [GITOPS-SECRETS-WORKFLOW.md](./GITOPS-SECRETS-WORKFLOW.md) for complete details.

## Access

After deployment:

- **Main Dashboard**: https://uptime.pnats.cloud
- **Status Pages**: https://status.pnats.cloud
- **Authentication**: Keycloak SSO via https://keycloak.pnats.cloud/realms/pcp

## Monitoring

### Health Checks

```bash
# Check deployment status
kubectl get pods -n monitoring -l app.kubernetes.io/name=oneuptime

# Check services
kubectl get svc -n monitoring -l app.kubernetes.io/name=oneuptime

# Check ingress
kubectl get ingress -n monitoring

# Check secrets status
kubectl get externalsecrets -n monitoring
```

### Logs

```bash
# Dashboard logs
kubectl logs -n monitoring deployment/pn-oneuptime-oneuptime-dashboard

# Worker logs
kubectl logs -n monitoring deployment/pn-oneuptime-oneuptime-worker

# Telemetry logs
kubectl logs -n monitoring deployment/pn-oneuptime-oneuptime-telemetry
```

### Metrics

OneUptime exposes Prometheus metrics on each service. ServiceMonitors are created automatically if Prometheus Operator is installed.

## Scaling

### Manual Scaling

```bash
# Scale dashboard
kubectl scale deployment pn-oneuptime-oneuptime-dashboard -n monitoring --replicas=5

# Scale workers
kubectl scale deployment pn-oneuptime-oneuptime-worker -n monitoring --replicas=5
```

### KEDA Autoscaling

KEDA is enabled for high-throughput services:

- **Telemetry**: 2-30 replicas based on queue size
- **Probe Ingest**: 2-20 replicas
- **Workers**: 2-20 replicas

Configure in `values.yaml`:
```yaml
telemetry:
  keda:
    enabled: true
    minReplicas: 2
    maxReplicas: 30
    queueSizeThreshold: 150
```

## Troubleshooting

### Pods Not Starting

Check secrets are available:
```bash
kubectl get externalsecrets -n monitoring
kubectl describe externalsecret oneuptime-core-secrets -n monitoring
```

### Database Connection Errors

Verify PostgreSQL is ready:
```bash
kubectl get pods -n monitoring -l app.kubernetes.io/name=postgresql
kubectl logs -n monitoring pn-oneuptime-oneuptime-postgresql-0
```

### OIDC Authentication Failing

Check Keycloak client configuration:
```bash
kubectl get clients.openidclient.keycloak.crossplane.io -n security
kubectl get secret pcp-oneuptime-client-secret -n security
```

### Secrets Not Syncing from Vault

Check External Secrets Operator:
```bash
kubectl logs -n external-secrets-system -l app.kubernetes.io/name=external-secrets
kubectl get clustersecretstore vault-backend
```

See [GITOPS-SECRETS-WORKFLOW.md](./GITOPS-SECRETS-WORKFLOW.md) for comprehensive troubleshooting.

## Upgrade

```bash
# Update chart dependencies
helm dependency update

# Upgrade release
helm upgrade pn-oneuptime . -n monitoring

# Or let ArgoCD handle it automatically
```

## Backup & Recovery

### Database Backups

PostgreSQL data is stored on persistent volumes with storage class `plt-blk-hdd-repl` which provides replication.

For backups:
```bash
# Manual backup
kubectl exec -n monitoring pn-oneuptime-oneuptime-postgresql-0 -- \
  pg_dump -U postgres oneuptimedb > oneuptime-backup.sql

# Restore
kubectl exec -i -n monitoring pn-oneuptime-oneuptime-postgresql-0 -- \
  psql -U postgres oneuptimedb < oneuptime-backup.sql
```

### Secret Recovery

All secrets can be recovered from Git:
1. SealedSecrets are in Git (encrypted)
2. Crossplane regenerates random passwords
3. External Secrets syncs from Vault

## Security Considerations

- **All secrets encrypted at rest** in Vault
- **TLS encryption** for all external communications
- **Non-root containers** with security contexts
- **Network policies** (if enabled in your cluster)
- **RBAC** for service accounts
- **Pod Security Standards** compatible

## Support & Documentation

- **Workflow Guide**: [GITOPS-SECRETS-WORKFLOW.md](./GITOPS-SECRETS-WORKFLOW.md)
- **Vault Setup** (legacy): [VAULT-SECRETS-SETUP.md](./VAULT-SECRETS-SETUP.md)
- **Secrets Directory**: [secrets/README.md](./secrets/README.md)
- **OneUptime Docs**: https://oneuptime.com/docs
- **GitHub Issues**: https://github.com/OneUptime/oneuptime/issues

## License

This chart follows the OneUptime license (Apache 2.0).

## Credits

- **OneUptime**: https://oneuptime.com
- **Helm Chart**: Custom chart for ProficientNow Cloud Platform
- **Maintained by**: Platform Engineering Team
