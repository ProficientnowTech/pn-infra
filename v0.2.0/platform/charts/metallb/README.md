# MetalLB Chart

ArgoCD Application for MetalLB load balancer in bare metal Kubernetes clusters.

## Purpose

Deploys MetalLB to provide LoadBalancer service type support in bare metal Kubernetes clusters, enabling external access to services like ArgoCD, ingress controllers, and applications.

## Configuration

### Chart Values (`values.yaml`)

```yaml
# Global repository settings
global:
  name: metallb
  targetNamespace: argocd
  syncWave: "-4"              # Deploy first in infrastructure foundation
  project: platform
  server: https://kubernetes.default.svc

# Labels configuration
labels:
  component: infrastructure    # Component type for Kubernetes labels
  managed-by: argocd          # Override default Helm with ArgoCD

# MetalLB configuration
chart:
  version: '0.14.8'           # Helm chart version

namespace: 'metallb-system'   # Target deployment namespace

# Sync policy configuration
syncPolicy:
  automated:
    prune: true
    selfHeal: true
  retry:
    limit: 5
    backoff:
      duration: "5s"
      factor: 2
      maxDuration: "3m"
```

### Key Configuration Options

| Setting | Default | Purpose |
|---------|---------|---------|
| `labels.component` | `infrastructure` | Kubernetes component label |
| `labels.managed-by` | `argocd` | Management tool identifier |
| `chart.version` | `'0.14.8'` | MetalLB Helm chart version |
| `namespace` | `'metallb-system'` | Target deployment namespace |
| `global.syncWave` | `"-4"` | Deploy first in infrastructure |

## Generated Application

When deployed via target-chart, creates ArgoCD Application with:

```yaml
metadata:
  name: metallb
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: '-4'  # Deploy first
  labels:
    # From chart helper
    helm.sh/chart: metallb-0.1.0
    app.kubernetes.io/name: metallb
    app.kubernetes.io/instance: {release-name}
    app.kubernetes.io/managed-by: argocd
    app.kubernetes.io/component: infrastructure
    
    # From target-chart commonLabels
    app.kubernetes.io/part-of: platform-infrastructure
    platform.pn-infra.io/stack: platform
    platform.pn-infra.io/environment: {environment}
    platform.pn-infra.io/application: "metallb"

spec:
  project: platform
  sources:
    - repoURL: https://metallb.github.io/metallb
      chart: metallb
      targetRevision: 0.14.8
      helm:
        releaseName: metallb
        values: |
          controller:
            enabled: true
          speaker:
            enabled: true
            frr:
              enabled: false
  destination:
    server: https://kubernetes.default.svc
    namespace: metallb-system
```

## Deployment

**Sync Wave**: `-4` - Deploys first in infrastructure foundation
**Dependencies**: None (foundational component)
**Target Namespace**: `metallb-system`

## Components Deployed

### Controller
- **Purpose**: Watches for LoadBalancer services and assigns external IPs
- **Replicas**: 1 (can be scaled for HA)
- **Resources**: Minimal CPU and memory requirements

### Speaker  
- **Purpose**: Announces assigned IPs via ARP/NDP or BGP
- **Deployment**: DaemonSet (runs on all nodes)
- **Protocols**: ARP/NDP announcements (BGP disabled by default)

## IP Address Management

MetalLB requires configuration of IP address pools after deployment. This is handled by the `metallb-config` chart (sync-wave -1).

### Address Pool Configuration
```yaml
# Configured via metallb-config chart
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: first-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.1.240-192.168.1.250  # Available IP range
```

### L2Advertisement
```yaml
# Enables ARP-based IP announcement
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default
  namespace: metallb-system
spec:
  ipAddressPools:
  - first-pool
```

## Network Requirements

### Layer 2 Mode (Default)
- **IP Range**: Unused IP addresses in the same subnet as cluster nodes
- **ARP**: Nodes must be able to respond to ARP requests for assigned IPs
- **Limitations**: Single node failure can cause brief service interruption

### BGP Mode (Advanced)
- **BGP Router**: External BGP router required
- **AS Numbers**: BGP autonomous system configuration needed
- **Benefits**: True high availability and load distribution

## Service Integration

Once deployed, Kubernetes services can use `type: LoadBalancer`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-service
spec:
  type: LoadBalancer        # MetalLB will assign external IP
  selector:
    app: my-app
  ports:
  - port: 80
    targetPort: 8080
```

## Platform Integration

**Used by these platform services:**
- **ArgoCD Server**: External web UI access
- **Ingress Controllers**: External traffic entry point
- **Monitoring**: External access to Grafana/Prometheus (if configured)

## Troubleshooting

### Check MetalLB Status
```bash
kubectl get pods -n metallb-system
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system
```

### Check Service IP Assignment
```bash
kubectl get services --all-namespaces -o wide | grep LoadBalancer
```

### Debug IP Assignment Issues
```bash
kubectl logs -n metallb-system deployment/controller
kubectl logs -n metallb-system daemonset/speaker
```

### Verify Address Pools
```bash
kubectl describe ipaddresspool -n metallb-system
```

### Check Node Connectivity
```bash
# From external network, ping assigned IPs
ping 192.168.1.240

# Check ARP table on router/switch
arp -a | grep 192.168.1.240
```

## Security Considerations

### Network Policies
```yaml
# Allow speaker to receive traffic
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: metallb-speaker
  namespace: metallb-system
spec:
  podSelector:
    matchLabels:
      app: metallb
      component: speaker
  policyTypes:
  - Ingress
  ingress:
  - from: []  # Allow all ingress for ARP/BGP
```

### RBAC
- MetalLB requires cluster-wide permissions to watch services
- Speaker requires host network access for ARP announcements
- Controller needs to update service status

## Customization

### Layer 2 Configuration
```yaml
# Default configuration in chart
speaker:
  enabled: true
  frr:
    enabled: false  # Use kernel ARP instead of FRR
```

### BGP Configuration
```yaml
speaker:
  frr:
    enabled: true   # Enable FRR for BGP
  # Additional BGP configuration in metallb-config chart
```

### High Availability
```yaml
controller:
  replicas: 2      # Multiple controller instances
  nodeSelector:
    node-role: infrastructure  # Deploy on specific nodes
```