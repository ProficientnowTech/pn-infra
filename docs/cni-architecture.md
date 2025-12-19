# CNI Architecture: Cilium Primary + Kube-OVN Secondary

## Architecture Overview

This cluster uses a **multi-CNI architecture** with:

1. **Cilium** (v1.18.4) - Primary/default CNI for all pods
   - eBPF-based networking and security
   - Kube-proxy replacement
   - L2 LoadBalancer for services
   - Network policies and observability via Hubble

2. **Multus** (v4.1.4) - Meta-plugin enabling multiple network interfaces
   - Automatically delegates to Cilium for pod primary interface
   - Enables secondary networks via NetworkAttachmentDefinitions

3. **Kube-OVN** (v1.14.20) - Secondary CNI for explicit use cases
   - Only used when explicitly requested via pod annotations
   - Primarily for KubeVirt VM networking
   - Provides OVN-based network abstractions

## Configuration Details

### Cilium Configuration

**File**: `v0.2.0/k8s-cluster/roles/cilium/files/cilium-values.yaml`

Key settings:
```yaml
# Allow Multus to manage CNI configs
cni:
  exclusive: false

# Direct API access for bootstrap
k8sServiceHost: 192.168.102.2
k8sServicePort: 6443

# Kube-proxy replacement
kubeProxyReplacement: true

# Observability with Hubble
hubble:
  enabled: true
  relay:
    enabled: true
  ui:
    enabled: true
  metrics:
    enabled:
      - dns
      - drop
      - tcp
      - flow
      - icmp
      - http
```

**Critical**: `cni.exclusive: false` allows Multus and Kube-OVN configs to coexist in `/etc/cni/net.d/`

### Kube-OVN Configuration

**File**: `v0.2.0/k8s-cluster/roles/kube_ovn/files/kube-ovn-values.yaml`

Key settings:
```yaml
# Disable network policies (Cilium handles this)
ENABLE_NP: false

# Set CNI priority to 10 (Multus uses 00, so this is lower priority)
CNI_CONFIG_PRIORITY: "10"

# CNI configuration
cni_conf:
  CNI_CONF_NAME: "10-kube-ovn.conflist"
```

**Critical**: `CNI_CONFIG_PRIORITY: "10"` ensures Kube-OVN does NOT become the default CNI

### Multus Configuration

**File**: Deployed from upstream manifest

Multus automatically:
- Uses lowest-numbered CNI config as default delegate (00-multus → Cilium)
- Makes other CNI plugins available via NetworkAttachmentDefinitions
- Provides primary interface via Cilium to all pods

## How It Works

### Default Pod Behavior

When you create a pod WITHOUT annotations:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
spec:
  containers:
  - name: app
    image: nginx
```

**Result**: Pod gets ONLY Cilium networking (eth0)

### Explicit Kube-OVN Networking

When you create a pod WITH Kube-OVN annotation:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-vm-pod
  annotations:
    k8s.v1.cni.cncf.io/networks: kube-system/kube-ovn-attachment
spec:
  containers:
  - name: vm
    image: kubevirt/virt-launcher
```

**Result**: Pod gets:
- **eth0**: Cilium networking (primary, default route)
- **net1**: Kube-OVN networking (secondary)

## NetworkAttachmentDefinition

**File**: `v0.2.0/k8s-cluster/roles/kube_ovn/files/network-attachment-definition.yaml`

```yaml
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: kube-ovn-attachment
  namespace: kube-system
spec:
  config: |
    {
      "cniVersion": "0.3.1",
      "type": "kube-ovn",
      "server_socket": "/run/openvswitch/kube-ovn-daemon.sock",
      "provider": "kube-ovn-attachment.kube-system.ovn"
    }
```

This NAD is automatically created during `./run.sh cni` deployment.

## CNI Priority Order

The CNI plugins are loaded in this order (by filename in `/etc/cni/net.d/`):

1. `00-multus.conf` - Multus meta-plugin (delegates to Cilium)
2. `05-cilium.conflist` - Cilium (default delegate)
3. `10-kube-ovn.conflist` - Kube-OVN (available via NAD)

## Observability

### Hubble UI

Access the Hubble UI for network traffic visualization:

```bash
cilium hubble ui
```

This opens http://localhost:12000 with a web interface showing:
- Pod-to-pod traffic flows
- Network policies in effect
- Dropped packets
- HTTP/DNS metrics

### Hubble CLI

Observe traffic in real-time:

```bash
# Port-forward Hubble relay
kubectl port-forward -n kube-system deployment/hubble-relay 4245:4245

# Observe all flows
hubble observe

# Filter by namespace
hubble observe --namespace default

# Filter by protocol
hubble observe --protocol tcp
```

## Network Policies

Network policies are enforced by **Cilium** for all traffic, including Kube-OVN secondary interfaces.

**Important**: When using Cilium NetworkPolicy with cross-namespace access, you must specify namespace labels:

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-cross-ns
spec:
  endpointSelector:
    matchLabels:
      app: backend
  ingress:
  - fromEndpoints:
    - matchLabels:
        app: frontend
        k8s:io.kubernetes.pod.namespace: default  # Must specify namespace
```

## Verification

After running `./run.sh cni`, verify the setup:

```bash
# Check all CNI pods are running
kubectl get pods -n kube-system | grep -E 'cilium|multus|kube-ovn'

# Check Cilium status
kubectl exec -n kube-system ds/cilium -- cilium status

# Check CNI configs on nodes
kubectl exec -n kube-system ds/cilium -- ls -la /host/etc/cni/net.d/

# Check NetworkAttachmentDefinition exists
kubectl get network-attachment-definitions -n kube-system

# Test default pod (should only have Cilium eth0)
kubectl run test --image=nginx --rm -it -- ip addr

# Test pod with Kube-OVN (should have eth0 + net1)
kubectl run test-ovn --image=nginx \
  --overrides='{"metadata":{"annotations":{"k8s.v1.cni.cncf.io/networks":"kube-system/kube-ovn-attachment"}}}' \
  --rm -it -- ip addr
```

## References

- [Multus CNI Documentation](https://k8snetworkplumbingwg.github.io/multus-cni/docs/how-to-use.html)
- [Kube-OVN Multi-NIC Documentation](https://kubeovn.github.io/docs/stable/en/advance/multi-nic/)
- [Kube-OVN with Cilium Integration](https://kubeovn.github.io/docs/v1.12.x/en/advance/with-cilium/)
- [Cilium NetworkPolicy with Kube-OVN](https://kubeovn.github.io/docs/v1.12.x/en/advance/cilium-networkpolicy/)
- [Cilium Hubble Observability](https://kubeovn.github.io/docs/v1.12.x/en/advance/cilium-hubble-observe/)
- [RKE2 Multus and Cilium](https://docs.rke2.io/networking/multus_sriov)
