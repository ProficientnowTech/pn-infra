# [Chart Name] - [Brief Description]

## Status Overview

| Attribute | Value |
|-----------|-------|
| **Status** | ✅/⚠️/❌ Deployed & Operational / Degraded / Down |
| **Version** | X.Y.Z |
| **Chart Version** | X.Y.Z (if applicable) |
| **Namespace** | `namespace-name` |
| **Deployment Date** | YYYY-MM-DD |
| **Production Ready** | ✅/⚠️/❌ Yes / Partially / No |
| **Monitoring Enabled** | ✅/❌ Yes / No |
| **High Availability** | ✅/⚠️/❌ Yes / Partial / No |

## Quick Links

- **URL/Endpoint**: [https://example.pnats.cloud](https://example.pnats.cloud)
- **Dashboard**: Link to Grafana dashboard (if applicable)
- **Documentation**: Link to official docs

## Dependencies

### Hard Dependencies
List of charts/services that MUST be running for this chart to function:

- **[Chart Name]** (`chart-id`)
  - Why it's required
  - Status: ✅/⚠️/❌

### Soft Dependencies
List of charts/services that enhance functionality but aren't required:

- **[Chart Name]** - Purpose (e.g., monitoring, logging)

## Architecture

### Components Deployed

| Component | Replicas | Resources | Storage | Status |
|-----------|----------|-----------|---------|--------|
| **ComponentName** | N | XmCPU, XMi RAM | XGi | ✅/⚠️/❌ |

### Key Configuration

- Configuration parameter 1: Value and explanation
- Configuration parameter 2: Value and explanation

## Network Configuration

### External Access
- **URL**: https://example.pnats.cloud
- **Type**: Ingress/LoadBalancer/NodePort
- **TLS**: Enabled/Disabled
- **DNS**: How DNS is managed

### Internal Access
- **Service Name**: `service-name.namespace.svc:port`
- **Use Case**: When to use internal access

## Production Configuration

### High Availability
- ✅/⚠️/❌ Multiple replicas
- ✅/⚠️/❌ Pod anti-affinity
- ✅/⚠️/❌ Rolling updates
- ✅/⚠️/❌ Health checks

### Resource Management
- ✅/⚠️/❌ CPU/Memory limits
- ✅/⚠️/❌ Resource requests
- ✅/⚠️/❌ Appropriate sizing

### Security
- ✅/⚠️/❌ TLS/HTTPS
- ✅/⚠️/❌ Authentication
- ✅/⚠️/❌ Authorization
- ✅/⚠️/❌ Network policies
- ✅/⚠️/❌ Secret management

### Persistence
- ✅/⚠️/❌ Persistent volumes
- ✅/⚠️/❌ Backup strategy
- ✅/⚠️/❌ Disaster recovery plan

## Monitoring & Observability

### Metrics
- **Source**: Prometheus/Other
- **ServiceMonitor**: Enabled/Disabled
- **Dashboards**: List of Grafana dashboards

### Logs
- **Aggregation**: Loki/Other
- **Retention**: Duration
- **Query Examples**: Common log queries

### Traces
- **Status**: Enabled/Disabled
- **Backend**: Tempo/Jaeger/Other

### Alerts
- **Critical Alerts**: List of critical alerting rules
- **Warning Alerts**: List of warning alerting rules

## Known Issues

### Issue Title
- **Status**: Open/In Progress/Resolved
- **Impact**: High/Medium/Low
- **Description**: Detailed description
- **Workaround**: If available
- **Target Resolution**: Timeline
- **Tracking**: Link to issue tracker

## Enhancement Opportunities

### High Priority
1. **Enhancement Title**
   - Description
   - Expected benefit
   - Effort estimate

### Medium Priority
2. **Enhancement Title**
   - Description

### Low Priority
3. **Enhancement Title**
   - Description

## Operational Procedures

### Common Operations

#### Operation 1
```bash
# Commands to perform operation
kubectl ...
```

#### Operation 2
```bash
# Commands to perform operation
```

### Backup & Recovery

#### Backup Procedure
- Frequency: Daily/Weekly/etc
- Method: How backups are performed
- Location: Where backups are stored

#### Recovery Procedure
```bash
# Steps to recover from backup
```

## Troubleshooting

### Common Issues

#### Issue Title
```bash
# Diagnostic commands
kubectl get ...
kubectl describe ...
kubectl logs ...

# Solution steps
```

### Health Checks

```bash
# Check component health
kubectl get pods -n <namespace>
kubectl get svc -n <namespace>

# Check logs
kubectl logs -n <namespace> deployment/<name>
```

## Change Log

### YYYY-MM-DD
- ✅ Change description
- ⚠️ Warning/Issue
- ❌ Failure/Rollback

## Related Documentation

- [Related Chart 1](related-chart-1.md)
- [Related Chart 2](related-chart-2.md)
- [Official Documentation](https://example.com)
- [Architecture Docs](../../ci-cd/README.md)
