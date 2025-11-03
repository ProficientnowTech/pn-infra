# Storage Architecture Q&A Summary

**IMPORTANT NOTE**: This document represents the **Phase 2 future architecture** for when larger storage capacity (160TB+ with 8×20TB disks) becomes available.

**Current Phase 1 Implementation**: See `openspec/project.md` for what's deployed NOW:
- 4 nodes with 500GB disks each
- 2TB raw capacity / ~667GB usable (3-way replication)
- Suitable for dev/staging and learning
- Simple 3-pool setup: replicapool (RBD), cephfs (CephFS), objectstore (S3/Swift)

Use this document as a **reference for future production deployment** when you're ready to scale with proper automation via `pnow-ats-v3/infrastructure`.

---

**Date**: 2025-10-31
**Context**: Planning comprehensive Ceph storage architecture for platform scaling from 1.5TB to 150TB+

---

## Executive Summary

**Current State**: 1.5TB raw (4× 500GB nodes)
**Target State**: ~182TB raw capacity
**Timeline**: Rapid expansion - hardware already available
**Strategy**: Tiered approach with intelligent data placement based on criticality and access patterns

---

## 1. Capacity & Growth

**Q: Timeline for scaling from 1.5TB to 150TB?**
- **A**: Rapid expansion - disks already on server, just need to integrate nodes
- Hardware ready, not gradual growth over time

**Q: Storage distribution?**
- **A**:
  - **Current**: 4 nodes × 500GB = 2TB raw
  - **To be added**:
    - 1 node: 8× 20TB HDDs = 160TB raw (will be 6× 20TB after redistribution)
    - 1 node: ~20TB (will become 2× 20TB after getting 1 disk)
    - 1 node: 800GB M.2 NVMe (fastest, hot tier)
  - **Total**: ~182TB raw capacity after redistribution

---

## 2. Storage Node Topology (Final Design)

**After disk redistribution strategy**:

### Node A (Large Storage Node)
- **Config**: 6× 20TB HDDs = 120TB raw
- **EC Profile**: 4+2 (can lose 2 disks)
- **Usable**: ~80TB
- **Purpose**: Bulk/Telemetry pool
- **Rationale**: Originally had 8× 20TB, but moving 2 disks improves failure domains and critical pool capacity

### Node B (Medium Storage)
- **Config**: 2× 20TB = 40TB raw
- **Purpose**: Part of critical replicated pool
- **Note**: Originally had 1× 20TB, receives 1 disk from Node A

### Node C (Small + Large Disk)
- **Config**: 4× 500GB + 1× 20TB = 21.5TB raw
- **Purpose**: Part of critical replicated pool
- **Note**: Receives 1 disk from Node A

### Node D (Performance Tier)
- **Config**: 800GB M.2 NVMe SSD
- **Purpose**: Hot tier for application data
- **Note**: Fastest storage in cluster, ~800GB after OS allocation

### Critical-Replicated Pool Capacity
- **Total raw**: 40TB + 21.5TB + worker nodes = ~62TB raw
- **Usable** (3-way replication): **~20TB**
- **More than sufficient** for critical data (pessimistic 1-year: ~1TB needed)

**Rationale for disk redistribution**:
- Improves failure domains (data spread across more nodes)
- Increases critical pool capacity significantly
- Avoids stacking redundancy (no HW RAID + Ceph EC + future multi-site replication)
- Future-proofs for multi-AZ/region expansion

---

## 3. Risk Tolerance & Failure Domains

**Q: With 160TB on single node, what's acceptable risk?**
- **A**: Option C - Tiered approach based on data criticality

**Critical data** (Multi-node 3-way replication):
- Platform databases (Authentik, secrets, GitOps state)
- Application databases (StackGres clusters)
- Kubernetes backups
- Application data: **250GB (optimistic) to 500GB (pessimistic) for 1 year**
- Replicated across Node B, Node C, and other nodes

**Acceptable risk data** (Single node, EC 4+2):
- Logs, metrics, traces (all layers)
- Backups/archives
- Build artifacts/caches
- Media/large files

**Rationale**:
- Startup budget constraints - can't afford full replication at 150TB scale
- Critical data volume is manageable with existing smaller nodes
- Bulk data can tolerate single-node risk with disk-level EC
- Plan to expand to multi-site/multi-AZ later

---

## 4. Data Classification & Tiers

### 4.1 Layer Classification

**Application Layer**:
- User-generated content (resumes, attachments, company data, candidate profiles)
- Application databases (transactional data)
- Application object storage

**Platform Layer**:
- GitOps configs, ArgoCD state
- Secrets (Infisical/Vault)
- Platform databases (Authentik, internal services)
- Container images, Helm charts
- Kubernetes backups (etcd snapshots)

**Infrastructure Layer**:
- Node metrics, Ceph metrics
- Hardware health data
- Network device metrics
- Storage metrics

**Application-Infrastructure Layer**:
- Team-managed infrastructure services
- Team-specific platform components

### 4.2 Criticality Levels

**CRITICAL**:
- Affects operations/SLA
- Audit logs, security events, error logs
- Application databases
- Platform secrets

**MODERATE**:
- Useful for debugging
- Debug logs, performance metrics
- Non-critical databases

**LOW**:
- Nice-to-have
- Infrastructure telemetry
- Cost analysis data
- Verbose logs

### 4.3 Storage Access Tiers (4-tier model)

**Tier 1 - Hottest**:
- Latest data, fastest queries
- NVMe M.2 SSD (800GB)
- Most expensive per GB

**Tier 2 - Warm**:
- Recent data, good performance
- Replicated HDD pool

**Tier 3 - Cold**:
- Older data, slower access
- EC HDD pool, cheaper

**Tier 4 - Archive**:
- Oldest before deletion
- EC HDD pool, cheapest

---

## 5. Retention Policies

### 5.1 Application Data (User/Company/Candidate Data)
- **Retention**: 5+ years (compliance-driven)
- **Compliance**: SOC 2 Type 1 & 2, GDPR
- **Deletion**: Only on user request or legal requirement
- **NOT subject to automatic lifecycle deletion**

### 5.2 Telemetry Data (Operational)

**LOW Criticality** (infrastructure telemetry, cost analysis):
- Hottest: 7 days
- Warm: 30 days
- Cold: 90 days
- Archive: 1 year → **DELETE**

**MODERATE Criticality** (debugging, performance):
- Hottest: 15 days
- Warm: 90 days
- Cold: 180 days
- Archive: 1 year → **DELETE**

**CRITICAL Criticality** (operations, SLA):
- Hottest: 30 days
- Warm: 180 days
- Cold: 1 year
- Archive: 2 years → **DELETE**

**VERY CRITICAL** (audit, security events):
- Hottest: 90 days
- Warm: 1 year
- Cold: 3 years
- Archive: 5 years → **DELETE**

### 5.3 Object Storage Retention

**No lifecycle policies** (keep indefinitely):
- User documents, resumes, attachments
- Company data, candidate profiles
- Application user-generated content

**With lifecycle policies** (4-tier retention):
- Application audit logs
- Authentik logs, platform logs
- Telemetry data stored in S3 format
- Organized by bucket prefixes:
  - `s3://app-data/users/*` → No lifecycle
  - `s3://app-data/audit-logs/*` → Retention by criticality
  - `s3://telemetry/platform-logs/*` → 4-tier lifecycle

---

## 6. Growth & Capacity Projections

### 6.1 Application Data Growth
- **Current**: 100GB (mostly object storage)
- **Growth rate**: 12.5GB every 2 weeks (**linear, non-compounding**)
- **6 months**: ~262GB
- **1 year**: ~425GB
- **Matches estimate**: 250-500GB pessimistic range ✅

### 6.2 Telemetry Data Volume
- **Current**: Minimal, no baseline data
- **Expected**: 1GB/day minimum
- **Scales with**: Platform growth, team onboarding

---

## 7. Erasure Coding Strategy

### 7.1 Large Node (6× 20TB after redistribution)

**Profile**: EC 4+2
- Can lose 2 disks
- Usable: ~80TB (66.7% efficiency)
- Overhead: 1.5x
- **Rationale**: Need higher safety with fewer disks after redistribution

**Why not EC 6+2?**
- After moving 2 disks to other nodes, only 6 disks remain
- 4+2 is appropriate for 6-disk configuration
- Balances capacity vs fault tolerance

### 7.2 Can EC profiles change later?
- ❌ Can't modify existing pool's EC profile
- ✅ Can create NEW pools with different profiles
- ✅ Migrate data between pools
- **Strategy**: Start with EC 4+2, create new pools when expanding to multi-node

---

## 8. StackGres Database Architecture

### 8.1 Cluster Organization Strategy

**Hybrid Approach** (Option C):

**Heavy/Critical services** (Dedicated clusters):
- Authentik (user authentication)
- Infisical/Vault (secrets management)
- High-traffic application databases
- Resource-intensive workloads

**Light/Shared services** (Shared cluster):
- Internal tools
- Monitoring databases
- Low-traffic services
- Platform supporting services

**Team flexibility**:
- Application teams choose based on needs
- Can request dedicated or shared clusters

**Rationale**:
- Eliminates noisy neighbor problems
- Resource-hungry apps get dedicated resources
- Save resources on low-intensity apps
- Pragmatic for startup scale

### 8.2 Backup Strategy

**Local Ceph (RGW/S3)** - Fast recovery:
- Daily/hourly backups
- Quick restore capability
- Retention: TBD per criticality

**External S3 (offsite DR)** - Disaster recovery:
- **Monthly** snapshots only
- **Retention**: 6 months max (6 monthly backups)
- Cost-optimized for startup
- Critical platform DBs only

**Rationale**:
- Local for operational recovery
- External for catastrophic failures
- Monthly external = cost effective
- 6-month retention balances safety vs cost

---

## 9. Intelligent Tiering Strategy

### 9.1 Access Pattern-Based Sharding

**Phase 1: Initial deployment (Month 1-3)**:
- All application data → M.2 NVMe (800GB hot tier)
- Monitor access patterns:
  - Query frequency
  - Last access time
  - Read/write ratios
- Build heatmap of data access

**Phase 2: Pattern-based movement (After 3 months)**:

**Hot data** (frequently accessed):
- Stay on M.2 NVMe
- Recent records
- Active user sessions
- Frequently queried data

**Warm data** (occasional access):
- Move to Critical-Replicated HDD pool
- Older records still needed
- Historical queries

**Cold data** (rare access):
- Archive tier
- Compliance retention
- Rarely touched data

### 9.2 Implementation

**Tools**:
- Use existing tools (pg_partman for PostgreSQL partitioning)
- StackGres built-in features
- Automated tiering jobs

**Threshold definitions**:
- Context-dependent (varies by data type)
- Some cases: 7 days = hottest
- Then: 30d, 90d, etc. based on criticality
- Not one-size-fits-all

**Benefits**:
- Cost-optimized storage usage
- Performance where needed
- Transparent to applications
- Scales with data growth

**Rationale**:
- Access-pattern-based beats simple time-based
- M.2 NVMe for truly hot data maximizes ROI
- Automatic tiering reduces operational burden
- Prepared for future multi-AZ expansion

---

## 10. Ceph Pool Architecture

### 10.1 Four Main Pools

**Pool 1: Critical-Replicated**
- **Replication**: 3-way across multiple nodes
- **Nodes**: Node B (2×20TB), Node C (4×500GB + 1×20TB), workers
- **Capacity**: ~62TB raw → **~20TB usable**
- **Contents**:
  - Application databases (StackGres)
  - Platform databases (Authentik, secrets)
  - K8s backups, GitOps state
  - Critical application data

**Pool 2: Application-Object**
- **EC**: 4+2 on single node (Node A)
- **Capacity**: ~30-50TB usable allocation
- **Contents**:
  - Application S3 buckets
  - User files, resumes, documents
  - High-performance object storage

**Pool 3: Bulk-Object**
- **EC**: 4+2 on single node (Node A)
- **Capacity**: ~30TB usable allocation
- **Contents**:
  - Backups, archives
  - Build artifacts, CI/CD caches
  - Container images
  - Shared with Pool 2 on same hardware

**Pool 4: Telemetry**
- **EC**: 4+2 on single node (Node A)
- **Capacity**: Remaining capacity (~remaining)
- **Contents**:
  - All logs, metrics, traces (all layers)
  - Cheapest storage tier
  - Acceptable loss tolerance

### 10.2 NVMe Hot Tier

**Not a separate pool** - integrated with Critical-Replicated pool:
- M.2 NVMe used as performance tier
- Application hot data placed here initially
- Tiered down to HDD based on access patterns
- Partition available space for Ceph

---

## 11. StorageClass Naming Convention

**Format**: `{layer}-{type}-{medium}-{tier/purpose}`

### 11.1 Abbreviations

**Layers**:
- `app` = Application
- `plt` = Platform
- `infra` = Infrastructure
- `app-infra` = Application-Infrastructure

**Types**:
- `blk` = Block storage (RBD)
- `fs` = Filesystem (CephFS)
- `obj` = Object storage (S3/RGW)

**Medium**:
- `nvme` = NVMe SSD (M.2)
- `hdd` = Hard disk drive

**Tier/Purpose**:
- `hot` = High performance tier
- `repl` = Replicated (3-way)
- `ec` = Erasure coded
- `s3` = S3-compatible

### 11.2 Examples

**Application Layer**:
- `app-blk-nvme-hot` - App data on NVMe (hottest tier)
- `app-blk-hdd-repl` - App databases on replicated HDD
- `app-obj-s3` - App object storage

**Platform Layer**:
- `plt-blk-hdd-repl` - Platform DBs
- `plt-obj-s3` - Platform backups, GitOps

**Infrastructure Layer**:
- `infra-blk-hdd-ec` - Infrastructure telemetry (bulk EC)
- `infra-obj-s3` - Infrastructure logs/metrics

**Application-Infrastructure Layer**:
- `app-infra-blk-hdd-repl` - Team-managed databases
- `app-infra-obj-s3` - Team-managed object storage

**Shared**:
- `fs-ceph` - CephFS (shared across layers)

**Total**: ~12-15 StorageClasses for granular control

---

## 12. Multi-Tenancy & Quotas

**Q: How many teams expected?**
- **A**: Currently 1 team, 1 SaaS. Will scale to multiple teams.

**Q: Quota enforcement?**
- **A**: **Soft quotas** with monitoring/alerts
  - No hard blocks (startup flexibility)
  - Alerts when approaching limits
  - Manual intervention if needed

**Rationale**:
- Single team now doesn't need hard enforcement
- Soft quotas provide visibility
- Can switch to hard quotas as needed
- Teams can grow without artificial blocks

---

## 13. Performance Requirements

**Q: Performance expectations?**
- **A**: "Best effort" initially with optimization based on monitoring

**Performance hierarchy**:
1. **High priority**: Application data (DBs, object storage)
   - Read replicas, caching, fast storage
   - Low latency, high throughput
2. **Medium priority**: Platform services
3. **Low priority**: Infrastructure telemetry (best effort)

**Implementation**:
- Start with baseline configs
- Monitor performance metrics
- Optimize based on actual workload patterns
- M.2 NVMe for critical app hot data

---

## 14. Migration & Deployment

**Q: Include migration steps?**
- **A**: Document **target state** only
  - User will handle physical disk movement
  - User will handle node integration
  - Focus on end-state configuration

**Target state documentation**:
- Final node topology
- Pool configurations
- StorageClass definitions
- Retention policies
- NOT step-by-step migration procedure

---

## 15. Key Architectural Decisions & Rationale

### 15.1 Why no Hardware RAID?

**Decision**: JBOD (Just a Bunch of Disks) with Ceph software redundancy

**Rationale**:
- **Avoids redundancy stacking**: HW RAID + Ceph EC + future multi-site = 8-16 copies wasteful
- **Flexibility**: Can change EC profiles, adapt to growth
- **Multi-AZ ready**: Designed for future cross-site replication
- **Cost**: No RAID controller overhead
- **Ceph-native**: Let Ceph manage redundancy end-to-end

### 15.2 Why move 2 disks instead of 1?

**Decision**: Move 2× 20TB from 8-disk node to other nodes

**Rationale**:
- **Better failure domains**: Data spread across more physical nodes
- **Critical pool capacity**: Increases from ~14TB to ~20TB usable
- **Still viable EC**: Node A with 6 disks can still run EC 4+2
- **Risk reduction**: 160TB single-node risk → distributed risk
- **Balanced**: Keeps bulk capacity while improving critical capacity

### 15.3 Why M.2 NVMe for hot tier?

**Decision**: Use 800GB M.2 as performance tier for application hot data

**Rationale**:
- **Fastest storage available**: Maximize performance for active data
- **Access pattern optimization**: Hot data identified through monitoring
- **Cost-effective**: Only truly hot data uses expensive storage
- **Tiering enabler**: Makes intelligent tiering viable
- **Transparent**: Applications don't need to know about tiering

### 15.4 Why access-pattern-based tiering vs time-based?

**Decision**: Move data between tiers based on access frequency, not just age

**Rationale**:
- **More accurate**: Old data might still be hot (frequently accessed)
- **Cost-optimized**: Only hot data uses expensive storage
- **Performance-optimized**: Cold data on old records doesn't waste NVMe
- **Context-aware**: Different data types have different access patterns
- **Better than simple rules**: 7-day-old data might be cold, or hot

---

## 16. Open Questions & Future Considerations

### 16.1 Firewall Issue Resolution
- Currently blocked: Sophos firewall blocking traffic with "Invalid TCP state"
- Source: 192.168.100.133 (not a cluster node) trying to reach API server VIP
- Action needed: Review firewall rules for LAN-to-LAN traffic

### 16.2 Node Label Changes
- Risk: Changed `role` label on master nodes (might affect kube-vip, rook-ceph)
- Current labels needed for:
  - kube-vip placement
  - rook-ceph OSD placement (`role=storage-node`, `ceph-osd=enabled`)
- Action needed: Verify labels don't break critical services

### 16.3 Rook-Ceph Cluster Status
- Currently stuck "Progressing" for extended period
- Only 2/3 monitors running
- No managers or OSDs deployed
- Likely related to label changes
- Need to resolve before storage architecture implementation

---

## 17. Success Criteria

**Phase 1 (Current - 1.5TB)**:
- ✅ Basic Ceph cluster operational
- ✅ 3-way replication for critical data
- ✅ StorageClasses defined and usable

**Phase 2 (Disk redistribution - 182TB)**:
- ✅ Nodes reconfigured with redistributed disks
- ✅ All 4 pools operational (Critical, App-Object, Bulk-Object, Telemetry)
- ✅ EC 4+2 working on large node
- ✅ M.2 NVMe integrated as hot tier

**Phase 3 (Intelligent tiering)**:
- ✅ Access pattern monitoring operational
- ✅ Automated tiering between NVMe and HDD
- ✅ Data movement based on patterns, not just time

**Phase 4 (Multi-tenancy)**:
- ✅ Soft quotas per team/layer
- ✅ Usage monitoring and alerting
- ✅ Multiple teams onboarded

**Phase 5 (Future - Multi-AZ/Region)**:
- ✅ Cross-site replication
- ✅ Disaster recovery tested
- ✅ Geographic redundancy

---

## 18. Next Steps

1. **Resolve immediate issues**:
   - Fix rook-ceph-cluster stuck deployment
   - Verify node labels don't break services
   - Address firewall if needed

2. **Create OpenSpec documentation**:
   - Study both repositories (pnow-ats-v3 + pn-infra-main)
   - Populate project.md with complete infrastructure story
   - Create storage architecture change proposal

3. **Implement storage architecture**:
   - Follow OpenSpec workflow
   - Create change proposal with all designs
   - Get approval before implementation
   - Execute in phases

---

**Document Owner**: DevSupreme
**Last Updated**: 2025-10-31
**Status**: Planning phase - awaiting OpenSpec documentation
