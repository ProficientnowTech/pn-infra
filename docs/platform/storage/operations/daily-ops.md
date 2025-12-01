# Ceph Storage Operations Guide

**Document Version**: 1.0.0
**Last Updated**: 2025-11-24

---

## Table of Contents

1. [Daily Operations](#daily-operations)
2. [Health Monitoring](#health-monitoring)
3. [Common Tasks](#common-tasks)
4. [Troubleshooting](#troubleshooting)
5. [Scaling Operations](#scaling-operations)
6. [Maintenance Procedures](#maintenance-procedures)
7. [Emergency Procedures](#emergency-procedures)

---

## Daily Operations

### Health Check Routine

**Quick health check** (run daily):

```bash
# 1. Cluster status
kubectl -n pn-k8s-storage-hyd-a exec -it deploy/rook-ceph-tools -- \
  ceph status

# 2. OSD status
kubectl -n pn-k8s-storage-hyd-a exec -it deploy/rook-ceph-tools -- \
  ceph osd status

# 3. Pool usage
kubectl -n pn-k8s-storage-hyd-a exec -it deploy/rook-ceph-tools -- \
  ceph df

# 4. Recent warnings
kubectl -n pn-k8s-storage-hyd-a exec -it deploy/rook-ceph-tools -- \
  ceph health detail
```

### Expected Healthy Output

**ceph status**:
```
  cluster:
    id:     <cluster-id>
    health: HEALTH_OK

  services:
    mon: 3 daemons, quorum k8s-master-01,k8s-master-02,k8s-master-03
    mgr: k8s-master-01(active), standbys: k8s-master-02
    osd: 11 osds: 11 up, 11 in

  data:
    pools:   3 pools, 256 pgs
    objects: 1.23k objects, 45 GiB
    usage:   135 GiB used, 1.87 TiB / 2 TiB avail
    pgs:     256 active+clean
```

**Key indicators**:
- `health: HEALTH_OK` - No issues
- All OSDs `up` and `in` - All storage available
- All PGs `active+clean` - Data healthy and accessible

---

## Health Monitoring

### Health States

| State | Severity | Action Required |
|-------|----------|-----------------|
| `HEALTH_OK` | None | Normal operation |
| `HEALTH_WARN` | Low-Medium | Investigate, may resolve automatically |
| `HEALTH_ERR` | High | Immediate action required |

### Common Warnings (HEALTH_WARN)

#### 1. Placement Group (PG) States

**Warning**: `pgs degraded`
```
HEALTH_WARN 12 pgs degraded
```

**Cause**: OSD temporarily down, data being recovered
**Action**: Monitor recovery progress
```bash
ceph -w  # Watch cluster events
```

**Auto-resolves**: Usually within minutes to hours

---

**Warning**: `pgs undersized`
```
HEALTH_WARN 24 pgs undersized
```

**Cause**: Not enough replicas (e.g., OSD down, replication ongoing)
**Action**: Check OSD status
```bash
ceph osd tree
```

**Fix**: Ensure all OSDs are up, wait for recovery

---

**Warning**: `pgs stuck`
```
HEALTH_WARN 8 pgs stuck unclean
```

**Cause**: PG unable to reach active+clean state
**Action**: Investigate stuck PGs
```bash
ceph pg dump_stuck
```

**Fix**: May require OSD restart or manual intervention

---

#### 2. OSD Warnings

**Warning**: `osds down`
```
HEALTH_WARN 1 osds down
```

**Cause**: OSD daemon stopped or node unreachable
**Action**: Check OSD pod
```bash
kubectl -n pn-k8s-storage-hyd-a get pods -l app=rook-ceph-osd
kubectl -n pn-k8s-storage-hyd-a logs <osd-pod-name>
```

**Fix**: Restart OSD pod or investigate node issues

---

**Warning**: `osds full/nearfull`
```
HEALTH_WARN 2 nearfull osd(s)
```

**Cause**: OSD reaching capacity threshold
- `nearfull`: 85% full (warning)
- `full`: 95% full (stops writes)

**Action**: Check OSD usage
```bash
ceph osd df tree
```

**Fix**:
1. Delete old data
2. Add more OSDs
3. Rebalance data

---

#### 3. Monitor Warnings

**Warning**: `mon clock skew`
```
HEALTH_WARN clock skew detected
```

**Cause**: Time drift between monitor nodes
**Action**: Check NTP sync
```bash
# On each monitor node
timedatectl status
systemctl status systemd-timesyncd
```

**Fix**: Ensure NTP is syncing correctly

---

### Monitoring Tools

#### 1. Ceph Dashboard

**Access**: `https://ceph.pnats.cloud`

**Features**:
- Visual cluster overview
- Pool and OSD usage graphs
- Performance metrics
- Alert history

**Login**:
```bash
# Get admin password
kubectl -n pn-k8s-storage-hyd-a get secret rook-ceph-dashboard-password \
  -o jsonpath="{['data']['password']}" | base64 -d
```

---

#### 2. Prometheus Metrics

**Metrics endpoint**: Scraped by Prometheus from MGR module

**Key metrics**:
- `ceph_cluster_total_bytes` - Total capacity
- `ceph_cluster_total_used_bytes` - Used capacity
- `ceph_osd_up` - OSD status
- `ceph_pool_wr` - Pool write IOPS
- `ceph_pool_rd` - Pool read IOPS

---

#### 3. Watch Cluster Events

**Real-time monitoring**:
```bash
kubectl -n pn-k8s-storage-hyd-a exec -it deploy/rook-ceph-tools -- \
  ceph -w
```

**Output**:
```
cluster:
  ...

2025/11/24 10:30:15 osd.3 [192.168.104.44:6800] boot
2025/11/24 10:30:20 mon.k8s-master-01 [192.168.103.41:3300]
  health HEALTH_WARN 12 pgs degraded
2025/11/24 10:32:45 health HEALTH_OK
```

---

## Common Tasks

### 1. Add a New OSD

**Scenario**: New disk added to existing node

**Steps**:

1. **Update values.yaml**:
```yaml
cephClusterSpec:
  storage:
    nodes:
      - name: "k8s-worker-10"
        devices:
          - name: "/dev/sda"
          - name: "/dev/sdb"
          - name: "/dev/sdc"  # New disk
```

2. **Apply changes**:
```bash
cd platform/stacks/storage/charts/rook-ceph-cluster
helm upgrade rook-ceph-cluster . -n pn-k8s-storage-hyd-a
```

3. **Monitor OSD creation**:
```bash
kubectl -n pn-k8s-storage-hyd-a get pods -l app=rook-ceph-osd -w
```

4. **Verify new OSD**:
```bash
kubectl -n pn-k8s-storage-hyd-a exec -it deploy/rook-ceph-tools -- \
  ceph osd tree
```

Expected: New OSD appears with status `up` and `in`

5. **Watch rebalancing**:
```bash
kubectl -n pn-k8s-storage-hyd-a exec -it deploy/rook-ceph-tools -- \
  ceph -w
```

**Rebalancing impact**:
- Data automatically redistributes to new OSD
- Duration depends on total data and cluster network bandwidth
- Client I/O may experience slight latency increase

---

### 2. Remove an OSD

**Scenario**: Decommission disk or node

**Steps**:

1. **Mark OSD out** (stop new data placement):
```bash
kubectl -n pn-k8s-storage-hyd-a exec -it deploy/rook-ceph-tools -- \
  ceph osd out <osd-id>
```

2. **Wait for data migration**:
```bash
kubectl -n pn-k8s-storage-hyd-a exec -it deploy/rook-ceph-tools -- \
  ceph osd df  # Check OSD usage → should reach 0%
```

3. **Stop OSD**:
```bash
kubectl -n pn-k8s-storage-hyd-a exec -it deploy/rook-ceph-tools -- \
  ceph osd down <osd-id>
```

4. **Remove OSD from CRUSH**:
```bash
kubectl -n pn-k8s-storage-hyd-a exec -it deploy/rook-ceph-tools -- \
  ceph osd crush remove osd.<osd-id>
```

5. **Delete OSD auth**:
```bash
kubectl -n pn-k8s-storage-hyd-a exec -it deploy/rook-ceph-tools -- \
  ceph auth del osd.<osd-id>
```

6. **Remove OSD**:
```bash
kubectl -n pn-k8s-storage-hyd-a exec -it deploy/rook-ceph-tools -- \
  ceph osd rm <osd-id>
```

7. **Update values.yaml** (remove disk from node config)

8. **Apply changes**:
```bash
helm upgrade rook-ceph-cluster . -n pn-k8s-storage-hyd-a
```

---

### 3. Expand a PVC

**Scenario**: Application needs more storage

**Prerequisite**: StorageClass has `allowVolumeExpansion: true` (already configured)

**Steps**:

1. **Edit PVC**:
```bash
kubectl -n <namespace> edit pvc <pvc-name>
```

2. **Update size**:
```yaml
spec:
  resources:
    requests:
      storage: 100Gi  # Increase from 50Gi
```

3. **Monitor expansion**:
```bash
kubectl -n <namespace> get pvc <pvc-name> -w
```

Expected: `STATUS` changes from `Bound` → `FilesystemResizePending` → `Bound`

4. **Verify new size**:
```bash
kubectl -n <namespace> describe pvc <pvc-name>
```

**Note**: Pod must restart to see new size (filesystem resize)

---

### 4. Create S3 User

**Scenario**: New application needs S3 access

**Steps**:

1. **Add user to values.yaml**:
```yaml
cephObjectStoreUsers:
- name: new-app-user
  store: app-objectstore
  displayName: "New Application User"
  quotas:
    maxSize: "50Gi"
    maxObjects: 100000
```

2. **Apply changes**:
```bash
helm upgrade rook-ceph-cluster . -n pn-k8s-storage-hyd-a
```

3. **Retrieve credentials**:
```bash
kubectl -n pn-k8s-storage-hyd-a get secret \
  rook-ceph-object-user-app-objectstore-new-app-user \
  -o jsonpath='{.data.AccessKey}' | base64 -d
```

4. **Provide to application** (as Kubernetes Secret)

---

### 5. Backup Configuration

**What to backup**:
- Ceph configuration
- CRUSH map
- Pool configurations
- User credentials

**Backup script**:
```bash
#!/bin/bash
BACKUP_DIR="/backup/ceph/$(date +%Y%m%d)"
mkdir -p $BACKUP_DIR

# 1. Ceph configuration
kubectl -n pn-k8s-storage-hyd-a exec -it deploy/rook-ceph-tools -- \
  ceph config dump > $BACKUP_DIR/ceph-config.txt

# 2. CRUSH map
kubectl -n pn-k8s-storage-hyd-a exec -it deploy/rook-ceph-tools -- \
  ceph osd getcrushmap -o - | crushtool -d - > $BACKUP_DIR/crushmap.txt

# 3. Pool info
kubectl -n pn-k8s-storage-hyd-a exec -it deploy/rook-ceph-tools -- \
  ceph osd pool ls detail > $BACKUP_DIR/pools.txt

# 4. Helm values
cp platform/stacks/storage/charts/rook-ceph-cluster/values.yaml \
  $BACKUP_DIR/values.yaml

# 5. CRDs
kubectl get cephcluster,cephblockpool,cephfilesystem,cephobjectstore \
  -n pn-k8s-storage-hyd-a -o yaml > $BACKUP_DIR/ceph-crds.yaml
```

---

## Troubleshooting

### Issue 1: Cluster HEALTH_ERR

**Symptoms**:
```
health: HEALTH_ERR
        insufficient standby MDS daemons available
```

**Diagnosis**:
```bash
kubectl -n pn-k8s-storage-hyd-a get pods -l app=rook-ceph-mds
```

**Common causes**:
- MDS pod crash loop
- Resource limits exceeded
- Configuration error

**Fix**:
1. Check MDS logs
2. Increase resource limits if needed
3. Restart MDS pods

---

### Issue 2: Slow Requests

**Symptoms**:
```
health: HEALTH_WARN
        30 osds have slow requests
```

**Diagnosis**:
```bash
# Check slow ops
kubectl -n pn-k8s-storage-hyd-a exec -it deploy/rook-ceph-tools -- \
  ceph daemon osd.<id> dump_historic_slow_ops

# Check OSD performance
kubectl -n pn-k8s-storage-hyd-a exec -it deploy/rook-ceph-tools -- \
  ceph osd perf
```

**Common causes**:
- Network latency (check cluster network)
- Disk I/O bottleneck
- Heavy rebalancing

**Fix**:
1. Check network connectivity
2. Monitor disk I/O (iostat)
3. Throttle recovery if needed:
```bash
ceph tell osd.* injectargs '--osd-recovery-max-active 1'
```

---

### Issue 3: PVC Stuck Pending

**Symptoms**:
```bash
kubectl get pvc
NAME       STATUS    VOLUME   CAPACITY   STORAGECLASS
my-pvc     Pending                       app-blk-hdd-repl
```

**Diagnosis**:
```bash
kubectl describe pvc my-pvc
```

**Common causes**:
- Pool not ready
- CSI driver not running
- StorageClass doesn't exist

**Fix**:
1. Check pool status:
```bash
kubectl -n pn-k8s-storage-hyd-a get cephblockpool
```

2. Check CSI driver:
```bash
kubectl -n pn-k8s-storage-hyd-a get pods -l app=csi-rbdplugin
```

3. Check StorageClass:
```bash
kubectl get storageclass app-blk-hdd-repl
```

---

### Issue 4: RGW Not Accessible

**Symptoms**: S3 endpoint returns 503 or connection timeout

**Diagnosis**:
```bash
# Check RGW pods
kubectl -n pn-k8s-storage-hyd-a get pods -l app=rook-ceph-rgw

# Check ingress
kubectl -n pn-k8s-storage-hyd-a get ingress

# Check service
kubectl -n pn-k8s-storage-hyd-a get svc -l app=rook-ceph-rgw
```

**Common causes**:
- RGW pod crash loop
- Ingress misconfiguration
- Certificate issues

**Fix**:
1. Check RGW logs
2. Verify ingress TLS certificate
3. Test internal connectivity:
```bash
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -I http://rook-ceph-rgw-app-objectstore.pn-k8s-storage-hyd-a
```

---

## Scaling Operations

### Horizontal Scaling (Add Nodes)

**Goal**: Increase total capacity by adding new storage nodes

**Steps**:

1. **Prepare new node**:
   - Add to Kubernetes cluster
   - Label as storage node:
   ```bash
   kubectl label node <new-node> role=storage
   kubectl label node <new-node> ceph-osd=enabled
   ```
   - Configure storage VLANs (192.168.103.x, 192.168.104.x)

2. **Add node to Ceph cluster**:
```yaml
# values.yaml
cephClusterSpec:
  storage:
    nodes:
      # ... existing nodes
      - name: "new-node"
        devices:
          - name: "/dev/sdb"
```

3. **Apply changes**:
```bash
helm upgrade rook-ceph-cluster . -n pn-k8s-storage-hyd-a
```

4. **Monitor OSD deployment**:
```bash
kubectl -n pn-k8s-storage-hyd-a get pods -l app=rook-ceph-osd -w
```

5. **Verify new OSDs**:
```bash
kubectl -n pn-k8s-storage-hyd-a exec -it deploy/rook-ceph-tools -- \
  ceph osd tree
```

6. **Data rebalances automatically** (may take hours to days)

---

### Vertical Scaling (Add Disks to Existing Node)

**Goal**: Increase capacity on existing nodes

**Steps**: Same as "Add a New OSD" in Common Tasks

---

### Capacity Planning

**Monitor capacity trends**:
```bash
# Current usage
kubectl -n pn-k8s-storage-hyd-a exec -it deploy/rook-ceph-tools -- \
  ceph df

# Pool-specific usage
kubectl -n pn-k8s-storage-hyd-a exec -it deploy/rook-ceph-tools -- \
  rados df
```

**Add capacity when**:
- Any pool reaches 70% capacity
- `nearfull` warnings appear
- Growth trend indicates capacity exhaustion within 3 months

**Capacity thresholds**:
- `mon_osd_nearfull_ratio`: 0.85 (warning at 85%)
- `mon_osd_full_ratio`: 0.95 (reject writes at 95%)

---

## Maintenance Procedures

### Rolling Update of Ceph Daemons

**Update Ceph version**:

1. **Update Chart.yaml**:
```yaml
dependencies:
- name: rook-ceph-cluster
  version: 1.18.8  # New version
  repository: https://charts.rook.io/release
```

2. **Update dependencies**:
```bash
helm dependency update
```

3. **Apply upgrade**:
```bash
helm upgrade rook-ceph-cluster . -n pn-k8s-storage-hyd-a
```

4. **Monitor upgrade**:
```bash
kubectl -n pn-k8s-storage-hyd-a get pods -w
```

**Rook performs rolling update**:
- Monitors → OSDs → MDS → RGW
- One daemon at a time
- Waits for health before proceeding

---

### Node Maintenance

**Scenario**: Node requires OS updates or hardware maintenance

**Steps**:

1. **Drain node** (move workloads):
```bash
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
```

**Note**: OSDs remain running (use toleration for control-plane)

2. **Perform maintenance**

3. **Uncordon node**:
```bash
kubectl uncordon <node>
```

4. **Verify cluster health**:
```bash
kubectl -n pn-k8s-storage-hyd-a exec -it deploy/rook-ceph-tools -- \
  ceph status
```

---

## Emergency Procedures

### Complete Cluster Failure

**Scenario**: All nodes down simultaneously

**Recovery**:

1. **Bring nodes online**
2. **Check Mon quorum**:
```bash
kubectl -n pn-k8s-storage-hyd-a exec -it deploy/rook-ceph-tools -- \
  ceph mon stat
```

3. **If Mon quorum lost**, may need to recreate Mon:
   - Follow Rook disaster recovery guide
   - Restore from Mon database backup

4. **Wait for OSDs to rejoin**:
```bash
ceph -w  # Watch cluster recovery
```

---

### Data Corruption

**Scenario**: Inconsistent PGs detected

**Symptoms**:
```
health: HEALTH_ERR
        1 scrub errors
        Possible data damage: 1 pg inconsistent
```

**Recovery**:

1. **Identify affected PG**:
```bash
ceph health detail
```

2. **Attempt repair**:
```bash
ceph pg repair <pg-id>
```

3. **If repair fails**, investigate object-level inconsistency:
```bash
rados list-inconsistent-obj <pg-id> --format=json
```

4. **Manual recovery** may require restoring from backup

---

## References

### Upstream Documentation

- **Ceph Operations**: https://docs.ceph.com/en/reef/rados/operations/
- **Troubleshooting**: https://docs.ceph.com/en/reef/rados/troubleshooting/
- **Rook Disaster Recovery**: https://rook.io/docs/rook/latest-release/Troubleshooting/disaster-recovery/

### Related Documentation

- [Main Index](../README.md)
- [Pool Architecture](../architecture/pools.md)
- [Network Configuration](../architecture/network.md)

---

**Maintained by**: Platform Team
**On-Call Contact**: Platform Team Slack Channel
