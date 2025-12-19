# Multi-Cluster Network Architecture: On-Prem + Contabo + OVH

## Executive Summary

This document defines the network architecture for a **multi-region, multi-cluster platform** spanning:
- **On-Prem Cluster** (Hyderabad, India) - Authority cluster
- **Contabo Cluster** (Cloud provider) - Edge/cache cluster
- **OVH Cluster** (Cloud provider) - Edge/cache cluster

**Key Principle**: Physical infrastructure (on-prem) uses VLAN-backed networks. Cloud clusters use pure overlay networks with the same logical abstractions.

---

## Architectural Constraints

### Physical Infrastructure vs Cloud Providers

| Aspect | On-Prem (Hyderabad) | Cloud (Contabo/OVH) |
|--------|---------------------|---------------------|
| **Network Control** | Full control of physical switches, VLAN trunking | Provider-managed VPCs, no VLAN access |
| **VLAN Support** | ✅ 802.1Q VLAN trunking available | ❌ No VLAN access (abstracted by provider) |
| **Network Segmentation** | Physical VLANs 100-109 | Software-defined security groups, subnets |
| **Hardware** | Baremetal + Proxmox VMs | Baremetal VMs (provider-managed) |
| **Networking Model** | Underlay (VLAN) + Overlay (Kube-OVN) | Pure Overlay (Kube-OVN) |

**Conclusion**: We **CANNOT and SHOULD NOT** replicate the VLAN architecture to cloud providers. Instead, we use **consistent logical network abstractions** with different underlying implementations.

---

## Network Architecture Strategy

### 1. On-Prem Cluster (Hyderabad) - Authority

**Role**: Authoritative cluster - source of truth for all data

**Networking Model**: VLAN-backed underlay + Kube-OVN overlay

**Physical Network Architecture**:
```
┌─────────────────────────────────────────────────────────┐
│ Physical Switches with 802.1Q VLAN Trunking             │
│ VLANs 100-109 configured                                │
└─────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────┐
│ Node NICs (Trunked: VLAN 100-109)                       │
│ Baremetal nodes + Proxmox VMs                           │
└─────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────┐
│ Kube-OVN: VLAN-Backed Logical Networks                  │
│ - net-mgmt (VLAN 100)                                   │
│ - net-storage-public (VLAN 101)                         │
│ - net-storage-cluster (VLAN 102)                        │
│ - net-internal (VLAN 103)                               │
│ - net-platform (VLAN 104)                               │
│ - net-vcluster-eastwest (VLAN 105)                      │
│ - net-replication (VLAN 106)                            │
│ - net-ingress (VLAN 107)                                │
│ - net-tenant-saas (VLAN 108)                            │
└─────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────┐
│ Cilium: Policy Enforcement + L2 LoadBalancer            │
└─────────────────────────────────────────────────────────┘
```

**Pod CIDR**: `10.16.0.0/16` (Kube-OVN default subnet)
**Service CIDR**: `10.233.0.0/18`
**External LoadBalancer Pool**: `103.110.174.18/29`

**Infrastructure**:
- 3-5 node etcd cluster (voting members, non-WAN)
- Ceph cluster with OSDs on baremetal-heavy nodes
- Kafka cluster (primaries)
- PostgreSQL primaries
- Platform services (Vault, IAM, monitoring)

---

### 2. Cloud Clusters (Contabo, OVH) - Edge/Cache

**Role**: Edge clusters - read replicas, caching, buffering, geographic proximity

**Networking Model**: Pure overlay (NO VLANs, cloud provider managed underlay)

**Logical Network Architecture**:
```
┌─────────────────────────────────────────────────────────┐
│ Cloud Provider VPC/Networking (Provider-Managed)        │
│ Security Groups, Subnets, NAT, Internet Gateway         │
└─────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────┐
│ Baremetal VMs (Provider-Managed Hypervisor)             │
│ Single NIC per node                                     │
└─────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────┐
│ Kube-OVN: Pure Overlay Logical Networks (NO VLANs)     │
│ - net-mgmt (overlay)                                    │
│ - net-storage-public (overlay)                          │
│ - net-internal (overlay)                                │
│ - net-platform (overlay)                                │
│ - net-vcluster-eastwest (overlay)                       │
│ - net-replication (overlay)                             │
│ - net-ingress (overlay)                                 │
│ - net-tenant-saas (overlay)                             │
└─────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────┐
│ Cilium: Policy Enforcement                              │
│ (No L2 LoadBalancer - use cloud provider LB)            │
└─────────────────────────────────────────────────────────┘
```

**Pod CIDRs** (NON-OVERLAPPING):
- Contabo: `10.17.0.0/16`
- OVH: `10.18.0.0/16`

**Service CIDRs**:
- Contabo: `10.233.64.0/18`
- OVH: `10.233.128.0/18`

**Infrastructure**:
- NO etcd (connects to on-prem etcd for read-only)
- Read-replica databases (promotable for Enterprise tier)
- Kafka brokers (buffering, writable during failover)
- MinIO edge caching
- NO authoritative platform services (Vault, IAM read-only)

**Load Balancing**:
- Use **cloud provider LoadBalancer** (Contabo/OVH LB services)
- NO Cilium L2 announcements (not applicable in cloud)

---

## Inter-Cluster Connectivity: OVN-IC + WireGuard

### OVN-IC Architecture

**OVN-IC (OVN Interconnection)** provides pod-to-pod communication across clusters via tunnel encapsulation.

```
┌──────────────────────────────────────────────────────────────┐
│              Centralized OVN-IC Database Cluster             │
│                   (Raft-based, 3+ nodes)                     │
│                                                              │
│  - OVN-IC Northbound DB (cluster configuration)             │
│  - OVN-IC Southbound DB (runtime state)                     │
│  - Deployed on: Separate HA VMs or Kubernetes pods          │
│  - Accessible from all 3 clusters                           │
└──────────────────────────────────────────────────────────────┘
                         ↑
         ┌───────────────┼───────────────┐
         │               │               │
    ┌────▼────┐    ┌────▼────┐    ┌────▼────┐
    │ On-Prem │    │ Contabo │    │   OVH   │
    │ Cluster │    │ Cluster │    │ Cluster │
    │         │    │         │    │         │
    │ AZ: pn- │    │AZ: pn-  │    │AZ: pn-  │
    │ main    │    │ contabo │    │  ovh    │
    └─────────┘    └─────────┘    └─────────┘
```

**OVN-IC Configuration**:

Each cluster connects to the centralized OVN-IC database:

```yaml
# Kube-OVN values for each cluster
ENABLE_IC: true
IC_DB_HOST: "<ovn-ic-db-endpoint>"  # Centralized DB endpoint
IC_NB_PORT: 6645
IC_SB_PORT: 6646
IC_GATEWAY_NODES: "node1,node2,node3"  # Gateway nodes per cluster
AZ_NAME: "pn-main" | "pn-contabo" | "pn-ovh"
```

**Cluster IDs**:
- On-Prem (Hyderabad): `cluster.id: 1`
- Contabo: `cluster.id: 2`
- OVH: `cluster.id: 3`

**Route Exchange**: Manual routing mode (NOT automatic)
- Prevents accidental subnet leakage
- Explicit route definitions for controlled cross-cluster communication
- Example: Allow `net-ingress` on-prem → `net-platform` on edge clusters

### WireGuard Encryption Layer

**All inter-cluster traffic encrypted via WireGuard tunnels**:

```
On-Prem Gateway Nodes ←→ WireGuard Tunnel ←→ Contabo Gateway Nodes
On-Prem Gateway Nodes ←→ WireGuard Tunnel ←→ OVH Gateway Nodes
Contabo Gateway Nodes ←→ WireGuard Tunnel ←→ OVH Gateway Nodes (optional)
```

**WireGuard Configuration**:
- Each cluster has 2-3 designated gateway nodes
- WireGuard mesh or hub-and-spoke topology
- OVN-IC tunnels run INSIDE WireGuard tunnels for encryption
- No plaintext cross-cluster traffic

**Traffic Flow Example**:
1. Pod on on-prem cluster wants to communicate with pod on Contabo
2. OVN routes traffic to on-prem gateway node
3. WireGuard encrypts traffic
4. Encrypted tunnel to Contabo gateway node
5. WireGuard decrypts traffic
6. OVN routes to destination pod on Contabo

---

## Multi-Region Failover Strategy

### Ingress Failover (Automatic)

**Cloudflare as Global Load Balancer**:

```
                    ┌──────────────┐
                    │  Cloudflare  │
                    │  (Global LB) │
                    └──────┬───────┘
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
   ┌────▼────┐        ┌────▼────┐       ┌────▼────┐
   │ On-Prem │        │ Contabo │       │   OVH   │
   │ Ingress │        │ Ingress │       │ Ingress │
   │ (Primary)│       │(Standby)│       │(Standby)│
   └─────────┘        └─────────┘       └─────────┘
```

**Cloudflare Configuration**:
- Health checks every 30s to all 3 origins
- Automatic traffic routing to healthy origins
- Geographic routing for latency optimization
- DDoS protection at edge

**Failover Behavior**:
- On-prem healthy: 100% traffic to on-prem
- On-prem down: Traffic splits to Contabo + OVH
- Automatic failback when on-prem returns

### Database Failover (Tier-Aware)

**Standard/Business Tier**: Read-only during on-prem outage

**Enterprise Tier**: Full continuity with promotion

```
┌─────────────────────────────────────────────────────────┐
│ Normal State: On-Prem Authority                         │
│                                                         │
│  On-Prem: PostgreSQL Primary (writes)                  │
│     ↓ async replication                                │
│  Contabo: PostgreSQL Read-Replica                      │
│  OVH: PostgreSQL Read-Replica                          │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ Failover State: Edge Promoted (Enterprise Only)        │
│                                                         │
│  On-Prem: PostgreSQL Primary (UNREACHABLE)             │
│     ✗ replication broken                               │
│  Contabo: PostgreSQL Primary (PROMOTED, writes)        │
│  OVH: PostgreSQL Read-Replica (replicates from Contabo)│
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ Recovery State: Reconciliation                          │
│                                                         │
│  Contabo: Freeze writes briefly                         │
│  On-Prem: Reconcile WAL, resolve conflicts             │
│  On-Prem: Resume as Primary                             │
│  Contabo/OVH: Demote to read-replicas                   │
└─────────────────────────────────────────────────────────┘
```

**Failover Decision Logic**:
1. Monitor replication lag continuously
2. Detect on-prem primary unreachability (consensus-based)
3. Acquire fencing token (prevents split-brain)
4. Promote Contabo replica to primary
5. Update DNS/service discovery
6. Resume writes with full auditability

**Recovery Logic**:
1. Freeze writes on edge primary
2. WAL-based reconciliation (deterministic conflict resolution)
3. Demote edge primary back to replica
4. Resume on-prem authority

### Messaging Continuity (Kafka)

**Normal State**:
- On-prem: Authoritative Kafka brokers
- Edge: Mirror makers or consumer replicas

**Failover State**:
- Edge Kafka brokers become writable
- Messages buffer locally
- Backlog grows (bounded by disk)

**Recovery State**:
- Edge brokers replicate buffered messages to on-prem
- Offset reconciliation
- Resume on-prem authority

---

## High Availability Design

### Control Plane HA

**On-Prem**:
- 3-5 node etcd cluster (Raft quorum)
- Multiple API server instances (load balanced by kube-vip)
- Multiple controller-manager instances (leader election)
- Multiple scheduler instances (leader election)
- **NO cross-WAN etcd** (consensus over WAN = latency death)

**Edge Clusters**:
- 3 node etcd cluster (local quorum)
- Independent control plane
- NO dependency on on-prem for cluster operations
- Can operate during on-prem outage

### Data Plane HA

**On-Prem**:
- Ceph cluster (3x replication, baremetal OSDs)
- PostgreSQL HA with Patroni (3-node cluster, synchronous replication)
- Kafka cluster (3+ brokers, replication factor 3)
- MinIO distributed mode

**Edge Clusters**:
- Read-replicas for databases
- Kafka brokers for buffering
- MinIO edge caching (promotable)
- NO authoritative storage (depends on on-prem for source of truth)

### Network HA

**On-Prem**:
- Multiple gateway nodes for OVN-IC (3+ nodes)
- Multiple WireGuard endpoints
- Cilium L2 LoadBalancer with multiple announcers
- External LoadBalancer pool with automatic failover

**Edge Clusters**:
- Multiple gateway nodes for OVN-IC
- Multiple WireGuard endpoints
- Cloud provider LoadBalancer (provider-managed HA)

---

## Scalability Strategy

### Horizontal Scaling Within Clusters

**On-Prem**:
- Worker nodes: Add more nodes to Kubespray inventory, run `./run.sh scale`
- Ceph OSDs: Add more baremetal nodes with disks
- Kafka brokers: Add brokers to cluster
- vClusters: Create new vClusters for tenant isolation

**Edge Clusters**:
- Worker nodes: Provision more VMs from cloud provider, add to cluster
- No scaling of authoritative services (read-replicas only)

### Geographic Scaling (New Regions)

To add a new region (e.g., AWS us-east-1):

1. **Deploy new Kubernetes cluster** in target region
2. **Configure Kube-OVN** in pure overlay mode (same logical networks)
3. **Connect to OVN-IC database** with unique AZ name
4. **Establish WireGuard tunnels** to existing clusters
5. **Configure replication** (async from on-prem)
6. **Update Cloudflare** origin pools

**New Region CIDRs**:
- AWS us-east-1: `10.19.0.0/16`
- GCP europe-west1: `10.20.0.0/16`
- Azure eastus: `10.21.0.0/16`

### vCluster Scaling (Multi-Tenancy)

Each tenant gets isolated vCluster:

**On-Prem (Production vClusters)**:
- Deployed on vm-medium nodes
- Full isolation (API, RBAC, CRDs, admission)
- Own logical network on `net-vcluster-eastwest` (VLAN 105)
- Cilium enforces tenant boundaries

**Edge Clusters (Enterprise Tenant Continuity)**:
- Scoped vClusters for Enterprise tenants
- Read-replica databases accessible
- Kafka topics writable during failover
- Demoted automatically on recovery

---

## Network Isolation and Security

### Intra-Cluster Isolation

**On-Prem (VLAN-backed)**:

| Logical Network | VLAN | Isolation Level | Access Control |
|-----------------|------|-----------------|----------------|
| net-mgmt | 100 | Low | Node agents only |
| net-storage-public | 101 | Medium | Ceph clients |
| net-storage-cluster | 102 | **High** | Ceph OSDs only (private) |
| net-internal | 103 | Medium | Control plane |
| net-platform | 104 | Medium | Platform services (IAM, Vault) |
| net-vcluster-eastwest | 105 | **High** | Per-vCluster isolation (private) |
| net-replication | 106 | **High** | Replication only (private) |
| net-ingress | 107 | Low | Ingress/egress gateways |
| net-tenant-saas | 108 | Medium | Customer-facing traffic |

**Edge Clusters (Overlay-based)**:
- Same logical network names
- Cilium enforces isolation (no VLAN hardware enforcement)
- More reliance on software policy

### Inter-Cluster Security

**Zero-Trust WAN Assumptions**:
- All inter-cluster links treated as **untrusted**
- **WireGuard encryption mandatory** for all cross-cluster traffic
- **No plaintext traffic** across WAN
- Mutual TLS for application-level communication
- Certificate-based authentication for OVN-IC

**Blast Radius Containment**:
- Edge cluster compromise: Does NOT expose on-prem secrets or data
- On-prem outage: Edge clusters continue serving (degraded for Standard/Business)
- Network partition: Each cluster operates independently

---

## Network Performance Considerations

### Latency Expectations

| Path | Expected Latency | Acceptable Max |
|------|------------------|----------------|
| On-Prem Pod ↔ Pod | < 1ms | 5ms |
| On-Prem Pod ↔ Contabo Pod | 50-100ms | 200ms |
| On-Prem Pod ↔ OVH Pod | 80-150ms | 250ms |
| Contabo Pod ↔ OVH Pod | 100-200ms | 300ms |

**Design Principle**: **Minimize cross-cluster synchronous communication**
- No synchronous database queries across clusters
- No synchronous API calls across clusters
- Async replication only
- Local caching aggressively

### Bandwidth Optimization

**Replication Traffic Prioritization**:
- Database WAL shipping: High priority
- Kafka replication: Medium priority
- Object storage sync: Low priority (background)

**Traffic Throttling**:
- Rate limits on cross-cluster replication
- Prevent single tenant saturating WAN links
- QoS policies on gateway nodes

**On-Prem (1 GbE currently)**:
- Ceph replication traffic throttled to avoid starvation
- Future: 10 GbE upgrade with dedicated NICs

**Cloud (Provider-Dependent)**:
- Typically 1-10 Gbps depending on VM size
- Provider network costs apply for egress

---

## Deployment Architecture Differences

### On-Prem Cluster CNI Configuration

**Kube-OVN Values**:
```yaml
# VLAN underlay mode
underlay:
  enabled: true
  VLAN_INTERFACE_NAME: "eth0"
  VLAN_ID_RANGE: "100-109"

# Logical networks with VLAN backing
subnets:
  - name: net-internal
    cidr: 192.168.103.0/24
    vlan: 103
    underlay: true
```

**Cilium Values**:
```yaml
# L2 LoadBalancer on physical network
l2announcements:
  enabled: true
loadBalancer:
  ipPool:
    - cidr: 103.110.174.18/29
```

### Cloud Cluster CNI Configuration

**Kube-OVN Values**:
```yaml
# Pure overlay mode (NO VLANs)
underlay:
  enabled: false  # KEY DIFFERENCE

# Logical networks as pure overlay
subnets:
  - name: net-internal
    cidr: 10.17.10.0/24  # Different CIDR per cluster
    underlay: false
    natOutgoing: true
```

**Cilium Values**:
```yaml
# NO L2 LoadBalancer (use cloud provider LB)
l2announcements:
  enabled: false  # KEY DIFFERENCE

# Cloud provider integration
loadBalancer:
  mode: "cloud"  # Use provider LB
```

---

## Implementation Roadmap

### Phase 1: On-Prem Foundation (Current)
- ✅ Deploy on-prem cluster with VLAN-backed networks
- ✅ Cilium as primary CNI
- ✅ Kube-OVN as secondary CNI for multi-NIC
- ✅ 9 VLAN-backed logical networks
- ⏳ NetworkAttachmentDefinitions for VLAN access

### Phase 2: Centralized OVN-IC Database
- Deploy 3-node OVN-IC database cluster
- HA deployment (Raft consensus)
- Accessible from all future cluster locations
- Monitoring and alerting

### Phase 3: WireGuard Mesh
- Configure gateway nodes on on-prem cluster
- Set up WireGuard mesh topology
- Establish encrypted tunnels (pending edge clusters)
- Test tunnel failover and performance

### Phase 4: Contabo Cluster Deployment
- Provision baremetal VMs from Contabo
- Deploy Kubernetes cluster (pure overlay networking)
- Configure Kube-OVN in overlay mode (CIDR: 10.17.0.0/16)
- Connect to OVN-IC database (AZ: pn-contabo)
- Establish WireGuard tunnels to on-prem
- Configure replication (PostgreSQL read-replica, Kafka mirroring)

### Phase 5: OVH Cluster Deployment
- Provision baremetal VMs from OVH
- Deploy Kubernetes cluster (pure overlay networking)
- Configure Kube-OVN in overlay mode (CIDR: 10.18.0.0/16)
- Connect to OVN-IC database (AZ: pn-ovh)
- Establish WireGuard tunnels to on-prem and Contabo
- Configure replication

### Phase 6: Ingress and Failover
- Configure Cloudflare with all 3 origins
- Implement health checks
- Test automatic failover scenarios
- Implement database promotion logic (Enterprise tier)
- Test recovery and reconciliation

### Phase 7: Monitoring and Observability
- Unified Prometheus federation across clusters
- Cross-cluster tracing with OpenTelemetry
- Centralized logging (Loki federation)
- Network flow monitoring via Hubble
- Replication lag alerting

---

## Summary: Do We Replicate VLANs?

**Answer: NO**

- **On-Prem**: VLAN-backed networks (physical infrastructure control)
- **Cloud**: Pure overlay networks (provider-managed underlay)
- **Consistency**: Same logical network abstractions across all clusters
- **Connectivity**: OVN-IC + WireGuard for encrypted inter-cluster communication
- **Failover**: Application-level failover, not network-level
- **Authority**: On-prem is source of truth, edge clusters are cache/buffer

**Multi-Region HA Strategy**:
1. **Control Plane**: Independent per cluster (no cross-WAN etcd)
2. **Data Plane**: Async replication, promotable read-replicas (Enterprise)
3. **Ingress**: Cloudflare global load balancing with automatic failover
4. **Network**: OVN-IC overlay mesh with WireGuard encryption
5. **Isolation**: Blast radius contained per cluster, graceful degradation

This architecture achieves **multi-region, multi-AZ, HA, distributed, scalable platform** without requiring identical physical infrastructure across sites.
