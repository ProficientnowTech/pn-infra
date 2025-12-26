# Database Operator Admin UI Ingress Configurations

This directory contains ingress configurations and deployment guides for database operator admin UIs.

## Operators with Admin UIs

| Operator | UI Type | Port | Authentication | Ingress File |
|----------|---------|------|----------------|--------------|
| **StackGres** | Built-in Web Console | 80 (HTTP) / 9443 (HTTPS) | Username/Password | `stackgres-ingress.yaml` |
| **Zalando PostgreSQL** | Separate UI Component | 80 (HTTP) | Kubeconfig/RBAC | `zalando-postgres-ui-values.yaml` |
| **ScyllaDB** | Monitoring Stack (Grafana) | 3000 | admin/admin (optional) | `scylladb-monitoring-ingress.yaml` |
| **Percona MongoDB** | PMM Server | 443 (HTTPS) | admin/admin (default) | `percona-pmm-ingress.yaml` |
| **CloudNativePG** | No built-in UI | - | Use Grafana | N/A |

## Quick Start

### Prerequisites

1. **Ingress Controller** (NGINX) installed:
```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace
```

2. **Cert-Manager** for TLS certificates:
```bash
helm repo add jetstack https://charts.jetstack.io
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true
```

3. **ClusterIssuer** for Let's Encrypt:
```bash
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
```

## 1. StackGres Admin UI

### Deploy Ingress

```bash
# Apply ingress (already configured for pnats.cloud)
kubectl apply -f stackgres-ingress.yaml
```

### Access

1. Navigate to `https://stackgres.pnats.cloud`
2. Get credentials:
```bash
kubectl get secret -n stackgres-postgres-operator stackgres-restapi \
  --template '{{ printf "Username: %s\nPassword: %s\n" (.data.k8sUsername | base64decode) (.data.clearPassword | base64decode) }}'
```

### Features

- Cluster creation and management
- Resource monitoring
- Configuration management
- Backup and restore operations
- Light/dark mode UI

### Security Notes

- **Change default password** after first login (via Settings)
- Consider enabling **basic authentication** at ingress level
- Use **IP allowlisting** for production environments
- Admin UI access should be restricted to database administrators

## 2. Zalando PostgreSQL Operator UI

### Deploy UI Chart

The UI is a **separate Helm chart** from the operator:

```bash
# Add UI chart repository
helm repo add postgres-operator-ui-charts \
  https://opensource.zalando.com/postgres-operator/charts/postgres-operator-ui

# Install UI (already configured for pnats.cloud)
helm install postgres-operator-ui \
  postgres-operator-ui-charts/postgres-operator-ui \
  -f zalando-postgres-ui-values.yaml \
  -n zalando-postgres-operator
```

### Access

1. Navigate to `https://postgres-ui.pnats.cloud`
2. **Authentication**: Uses your kubeconfig context
   - No separate login required
   - Authenticated via Kubernetes RBAC

### Features

- Create and configure PostgreSQL clusters
- Monitor cluster status
- Edit cluster manifests
- Clone existing clusters
- View operator logs
- Delete clusters

### Security Notes

- **RBAC-based authentication** - ensure proper Kubernetes roles
- UI talks to Kubernetes API server
- Only accessible to users with appropriate permissions
- Consider network policies to restrict access

## 3. ScyllaDB Monitoring Stack

### Deploy Monitoring

ScyllaDB monitoring is typically deployed via the monitoring stack:

```bash
# Clone monitoring repository
git clone https://github.com/scylladb/scylla-monitoring.git
cd scylla-monitoring

# Start monitoring stack with authentication
./start-all.sh -d /path/to/data -s <scylla-node-ip> -a

# Or deploy via Kubernetes manifests (if available)
```

### Deploy Ingress

```bash
# Apply ingress (already configured for pnats.cloud)
kubectl apply -f scylladb-monitoring-ingress.yaml
```

### Access

1. Navigate to `https://scylla-monitoring.pnats.cloud`
2. **Default credentials** (if authentication enabled):
   - Username: `admin`
   - Password: `admin`
3. **Change password** on first login

### Features (Grafana Dashboards)

- **Scylla Overview**: Real-time cluster monitoring
- **CQL Query Analysis**: Query performance metrics
- **OS Metrics**: System-level monitoring
- **Scylla Manager**: Backup and repair tasks
- **Advisor**: Automated problem identification

### Security Notes

- Enable authentication with `-a` flag when starting monitoring
- Change default Grafana password immediately
- Use OAuth/SSO for production (Grafana supports LDAP, OAuth, SAML)
- Restrict access to monitoring namespace

## 4. Percona Monitoring and Management (PMM)

### Deploy PMM Server

```bash
# Add Percona Helm repo
helm repo add percona https://percona.github.io/percona-helm-charts/

# Install PMM Server
helm install pmm percona/pmm \
  --namespace monitoring \
  --create-namespace \
  --set service.type=ClusterIP
```

### Deploy Ingress

```bash
# Apply ingress (already configured for pnats.cloud)
kubectl apply -f percona-pmm-ingress.yaml
```

### Configure MongoDB to Use PMM

Add to your `PerconaServerMongoDB` CR:

```yaml
spec:
  pmm:
    enabled: true
    image:
      repository: percona/pmm-client
      tag: 3.4.1
    serverHost: pmm-service.monitoring.svc.cluster.local
```

### Access

1. Navigate to `https://pmm.pnats.cloud`
2. **Default credentials**:
   - Username: `admin`
   - Password: `admin`
3. **Change password immediately** via UI (Settings → Change Password)

### Features

- **MongoDB Dashboards**:
  - Instances Overview
  - MongoDB Cluster Summary
  - Replica Set Summary
  - MongoDB PBM Details (backup monitoring)
- **Query Analytics**: Detailed query performance analysis
- **Alerting**: Built-in alert rules
- **Backup Monitoring**: Track backup status and history

### Security Notes

- **CRITICAL**: Change default password immediately
- PMM 3.x requires **gRPC support** in NGINX ingress
- Password stored in `pmm-secret` Kubernetes secret
- Use TLS for all connections
- Consider using **service account tokens** (PMM 3.x) instead of API keys

## 5. CloudNativePG (No Built-in UI)

CloudNativePG does **not provide a built-in admin UI**. Use standard Kubernetes tools:

### Monitoring Approach

1. **Prometheus** for metrics collection (port 9187)
2. **Grafana** for visualization
3. **kubectl** with `cnpg` plugin for CLI management

### Deploy Grafana Dashboard

```bash
# Import Grafana dashboard
# Dashboard ID: 20417 (from Grafana Labs)
# Or use: https://github.com/cloudnative-pg/grafana-dashboards/blob/main/charts/cluster/grafana-dashboard.json
```

### Enable Metrics

In CloudNativePG values:
```yaml
cloudnative-pg:
  monitoring:
    podMonitorEnabled: true  # Requires Prometheus Operator
```

## Security Best Practices

### 1. TLS Configuration

Always use TLS for admin UIs:
- Use **cert-manager** for automated certificate management
- Configure **ClusterIssuer** for Let's Encrypt or internal CA
- Enable **SSL redirect** in ingress annotations

### 2. Authentication

- **Change default passwords immediately**
- Use **strong passwords** (minimum 16 characters)
- Enable **two-factor authentication** where supported
- Consider **SSO integration** (OAuth, LDAP, SAML)

### 3. Access Control

#### IP Allowlisting

```yaml
annotations:
  nginx.ingress.kubernetes.io/whitelist-source-range: "10.0.0.0/8,192.168.0.0/16"
```

#### Basic Authentication (additional layer)

```bash
# Create htpasswd file
htpasswd -c auth admin

# Create secret
kubectl create secret generic basic-auth \
  --from-file=auth \
  -n <namespace>

# Add to ingress annotations
annotations:
  nginx.ingress.kubernetes.io/auth-type: basic
  nginx.ingress.kubernetes.io/auth-secret: basic-auth
  nginx.ingress.kubernetes.io/auth-realm: 'Authentication Required'
```

#### Network Policies

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: admin-ui-access
  namespace: stackgres-postgres-operator
spec:
  podSelector:
    matchLabels:
      app: stackgres-restapi
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    ports:
    - port: 80
```

### 4. Monitoring and Auditing

- **Enable access logs** in ingress controller
- **Monitor authentication failures**
- **Set up alerts** for suspicious activity
- **Regular security audits** of UI access

### 5. Production Deployment Checklist

- [ ] TLS certificates configured (cert-manager)
- [ ] Default passwords changed
- [ ] IP allowlisting configured
- [ ] Network policies in place
- [ ] RBAC properly configured
- [ ] Monitoring and alerting enabled
- [ ] Backup of admin credentials
- [ ] Documentation of access procedures
- [ ] Regular security updates scheduled

## Troubleshooting

### Ingress Not Working

```bash
# Check ingress status
kubectl get ingress -A

# Check ingress controller logs
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller

# Verify service endpoints
kubectl get endpoints -n <namespace>

# Test internal connectivity
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl http://<service-name>.<namespace>.svc:80
```

### Certificate Issues

```bash
# Check certificate status
kubectl get certificate -A

# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager

# Describe certificate
kubectl describe certificate <cert-name> -n <namespace>
```

### Authentication Failures

```bash
# For StackGres, verify credentials
kubectl get secret stackgres-restapi -n stackgres-postgres-operator -o yaml

# For PMM, check PMM logs
kubectl logs -n monitoring deployment/pmm-server

# For Zalando UI, verify RBAC
kubectl auth can-i list postgresqls --as=system:serviceaccount:<namespace>:postgres-operator-ui
```

## References

- [StackGres Admin UI Documentation](https://stackgres.io/doc/latest/administration/adminui/)
- [Zalando Postgres Operator UI](https://github.com/zalando/postgres-operator/blob/master/docs/operator-ui.md)
- [ScyllaDB Monitoring Stack](https://monitoring.docs.scylladb.com/)
- [Percona PMM Documentation](https://docs.percona.com/percona-monitoring-and-management/)
- [NGINX Ingress Annotations](https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/annotations/)
- [Cert-Manager Documentation](https://cert-manager.io/docs/)
