# Database Admin UI URLs - pnats.cloud

All database operator admin UIs are configured for the `pnats.cloud` domain.

## Admin UI Access URLs

### StackGres PostgreSQL Operator
- **URL**: https://stackgres.pnats.cloud
- **Authentication**: Username/Password
- **Default User**: `admin`
- **Get Password**:
  ```bash
  kubectl get secret -n stackgres-postgres-operator stackgres-restapi \
    --template '{{ printf "Username: %s\nPassword: %s\n" (.data.k8sUsername | base64decode) (.data.clearPassword | base64decode) }}'
  ```
- **Ingress File**: `stackgres-ingress.yaml`

### Zalando PostgreSQL Operator UI
- **URL**: https://postgres-ui.pnats.cloud
- **Authentication**: Kubernetes RBAC (uses kubeconfig)
- **No Credentials Required**: Authenticated via K8s API
- **Ingress Config**: Included in `zalando-postgres-ui-values.yaml`

### ScyllaDB Monitoring Stack
- **URL**: https://scylla-monitoring.pnats.cloud
- **Dashboard**: Grafana-based monitoring
- **Default Credentials** (if auth enabled):
  - Username: `admin`
  - Password: `admin` (change on first login)
- **Ingress File**: `scylladb-monitoring-ingress.yaml`

### Percona Monitoring and Management (PMM)
- **URL**: https://pmm.pnats.cloud
- **Monitors**: Percona MongoDB (and other Percona databases)
- **Default Credentials**:
  - Username: `admin`
  - Password: `admin`
- **CRITICAL**: Change password immediately after first login
- **Ingress File**: `percona-pmm-ingress.yaml`
- **Special Requirements**: gRPC support enabled in NGINX ingress

### CloudNativePG
- **No Built-in Admin UI**: Use Prometheus metrics + Grafana dashboards
- **Metrics Port**: 9187
- **Grafana Dashboard ID**: 20417

## DNS Configuration Required

Add the following DNS A/CNAME records pointing to your ingress controller's external IP:

```
stackgres.pnats.cloud           → <INGRESS_CONTROLLER_IP>
postgres-ui.pnats.cloud         → <INGRESS_CONTROLLER_IP>
scylla-monitoring.pnats.cloud   → <INGRESS_CONTROLLER_IP>
pmm.pnats.cloud                 → <INGRESS_CONTROLLER_IP>
```

### Get Ingress Controller IP

```bash
# For LoadBalancer service
kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# For NodePort (use any node IP)
kubectl get nodes -o wide
```

## TLS Certificates

All ingresses are configured to use **cert-manager** with the `letsencrypt-prod` ClusterIssuer.

### Prerequisites

1. **Cert-Manager** must be installed
2. **ClusterIssuer** must be created:

```bash
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@pnats.cloud
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
```

3. **DNS records** must be configured and propagated

### Certificate Status

Check certificate status:
```bash
kubectl get certificate -A
kubectl describe certificate <cert-name> -n <namespace>
```

## Security Recommendations

### 1. Change Default Passwords
- ✅ **StackGres**: Change via Web UI → Settings
- ✅ **ScyllaDB**: Change Grafana password on first login
- ✅ **PMM**: CRITICAL - change immediately via UI

### 2. Enable IP Allowlisting

Uncomment and configure in each ingress file:
```yaml
annotations:
  nginx.ingress.kubernetes.io/whitelist-source-range: "10.0.0.0/8,YOUR_OFFICE_IP/32"
```

### 3. Additional Basic Auth (Optional)

Add an extra authentication layer:
```bash
# Create htpasswd file
htpasswd -c auth admin

# Create secret
kubectl create secret generic basic-auth \
  --from-file=auth \
  -n <namespace>

# Add to ingress annotations
nginx.ingress.kubernetes.io/auth-type: basic
nginx.ingress.kubernetes.io/auth-secret: basic-auth
```

### 4. Network Policies

Restrict pod-to-pod communication:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: admin-ui-access
  namespace: <namespace>
spec:
  podSelector:
    matchLabels:
      app: <admin-ui-app>
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
```

## Deployment Order

1. **Install Ingress Controller**
   ```bash
   helm install ingress-nginx ingress-nginx/ingress-nginx -n ingress-nginx --create-namespace
   ```

2. **Install Cert-Manager**
   ```bash
   helm install cert-manager jetstack/cert-manager -n cert-manager --create-namespace --set crds.enabled=true
   ```

3. **Create ClusterIssuer**
   ```bash
   kubectl apply -f clusterissuer.yaml
   ```

4. **Configure DNS** (point domains to ingress controller IP)

5. **Deploy Database Operators** (via ArgoCD or Helm)

6. **Deploy Ingress Resources**
   ```bash
   kubectl apply -f stackgres-ingress.yaml
   kubectl apply -f scylladb-monitoring-ingress.yaml
   kubectl apply -f percona-pmm-ingress.yaml

   # Zalando UI (via Helm)
   helm install postgres-operator-ui postgres-operator-ui-charts/postgres-operator-ui \
     -f zalando-postgres-ui-values.yaml \
     -n zalando-postgres-operator
   ```

7. **Verify Certificates**
   ```bash
   kubectl get certificate -A
   ```

8. **Access Admin UIs** and change default passwords

## Troubleshooting

### Certificate Not Issued

```bash
# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager -f

# Check certificate status
kubectl describe certificate <cert-name> -n <namespace>

# Check DNS propagation
nslookup stackgres.pnats.cloud
```

### 502 Bad Gateway

```bash
# Check backend service exists
kubectl get svc -n <namespace>

# Check pods are running
kubectl get pods -n <namespace>

# Check ingress backend
kubectl describe ingress <ingress-name> -n <namespace>
```

### Authentication Fails

```bash
# StackGres: Verify secret exists
kubectl get secret stackgres-restapi -n stackgres-postgres-operator

# PMM: Check PMM logs
kubectl logs -n monitoring deployment/pmm-server

# Zalando: Verify RBAC
kubectl auth can-i list postgresqls --as=system:serviceaccount:<namespace>:postgres-operator-ui
```

## Monitoring Access

Once deployed, you can monitor all database systems:

- **StackGres**: Full cluster lifecycle management
- **Zalando**: PostgreSQL cluster operations
- **ScyllaDB**: Performance metrics, query analysis, cluster health
- **PMM**: MongoDB cluster monitoring, query analytics, backup status

All accessible through your browser at the respective `pnats.cloud` subdomains with proper TLS encryption.
