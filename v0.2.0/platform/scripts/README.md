# Platform Scripts

This directory contains production-grade scripts for managing the PN Infrastructure platform.

---

## reset-platform.sh

**WARNING: DESTRUCTIVE SCRIPT - USE WITH EXTREME CAUTION**

### Purpose

Completely wipes the platform and returns the Kubernetes cluster to a pristine state, as if freshly installed.

### What It Does

The script performs a comprehensive cleanup in the following order:

1. **Deletes all ArgoCD applications** - Removes all app definitions and managed resources
2. **Removes all Helm releases** - Uninstalls all Helm charts across all namespaces
3. **Cleans Rook Ceph cluster** - Enables cleanup policy and removes Ceph resources
4. **Deletes all PVCs and PVs** - Removes all persistent volumes and claims
5. **Deletes platform namespaces** - Removes all non-system namespaces
6. **Removes all CRDs** - Deletes Custom Resource Definitions (except system CRDs)
7. **Wipes Ceph data from disks** - Zeros out all Ceph OSD disks on all nodes
8. **Removes Rook state** - Cleans /var/lib/rook from all nodes
9. **Cleanup remaining resources** - Removes webhooks, API services, cluster roles, storage classes
10. **Verifies cluster state** - Confirms cluster is in pristine state

### Affected Nodes and Devices

The script will wipe data from the following devices:

| Node | Devices | Notes |
|------|---------|-------|
| k8s-master-01 | /dev/sdb | Single OSD device |
| k8s-master-02 | /dev/sdb | Single OSD device |
| k8s-master-03 | /dev/sdb | Single OSD device |
| k8s-master-04 | /dev/sda, /dev/sdb, /dev/sdc, /dev/sdd, /dev/sde | 5 OSD devices |
| k8s-worker-02 | /dev/sdb | Single OSD device |
| k8s-worker-10 | /dev/sda, /dev/sdb | 2 OSD devices (includes /dev/sda) |

**Total: 12 disks across 6 nodes will be wiped**

### Data Wiping Method

For each device, the script:
1. Unmounts any mounted filesystems
2. Removes LVM volumes (if present)
3. Wipes filesystem signatures with `wipefs`
4. Zeros out first 1GB of disk
5. Zeros out last 1GB of disk
6. Updates kernel partition table
7. Discards all blocks (TRIM/UNMAP)

This ensures complete data destruction and prevents any Ceph metadata from remaining.

### Usage

#### Basic Usage (with confirmations)
```bash
./reset-platform.sh
```

You will be prompted to:
1. Type `yes-destroy-everything` to confirm
2. Type `confirm` to double-confirm

#### Force Mode (continues on errors)
```bash
./reset-platform.sh --force
```

#### Skip Confirmations (DANGEROUS - for automation only)
```bash
./reset-platform.sh --skip-confirmation
```

#### Combined Flags
```bash
./reset-platform.sh --force --skip-confirmation
```

### Prerequisites

- `kubectl` installed and configured
- Access to Kubernetes cluster with admin permissions
- `helm` installed (optional - script continues without it)
- Network access to all nodes

### Protected Resources

The following resources are **NOT** deleted:

- `default` namespace
- `kube-system` namespace
- `kube-public` namespace
- `kube-node-lease` namespace
- `metallb-system` namespace (MetalLB system namespace)
- System CRDs: `certificatesigningrequests.certificates.k8s.io`
- MetalLB CRDs: `ipaddresspools.metallb.io`, `l2advertisements.metallb.io`, `bfdprofiles.metallb.io`, `bgpadvertisements.metallb.io`, `bgppeers.metallb.io`, `communities.metallb.io`
- Core Kubernetes cluster roles and bindings

### Execution Time

Typical execution time: **15-30 minutes** depending on:
- Number of applications deployed
- Amount of data stored
- Cluster size and performance
- Network speed to nodes

### Log Files

The script creates a detailed log file at:
```
/tmp/platform-reset-YYYYMMDD-HHMMSS.log
```

### Safety Features

1. **Double Confirmation Required**
   - Must type `yes-destroy-everything`
   - Must type `confirm` again

2. **Protected Namespaces**
   - System namespaces cannot be deleted
   - Prevents breaking core Kubernetes

3. **Graceful Finalizer Removal**
   - Removes finalizers before deletion
   - Prevents stuck resources

4. **Timeout Handling**
   - 60-120 second timeouts for operations
   - Force deletion if stuck

5. **Error Handling**
   - Continues or exits based on `--force` flag
   - Logs all errors for troubleshooting

6. **Verification Step**
   - Final verification of cluster state
   - Reports any remaining resources

### What Gets Deleted

#### Applications (43 total)
- All ArgoCD applications
- All Helm releases
- All platform workloads

#### Namespaces (~25 total)
- argocd
- monitoring (Prometheus, Grafana, Loki, Tempo)
- rook-ceph
- vault
- keycloak
- harbor
- temporal
- backstage
- tekton-pipelines
- kafka
- postgres-operator
- external-secrets
- crossplane-system
- kubevirt
- kargo
- And all other platform namespaces

#### Data
- All PostgreSQL databases (3 clusters, 8 instances)
- All Redis data
- All container images (Harbor registry)
- All Grafana dashboards and configs
- All Vault secrets
- All Keycloak users and realms
- All Temporal workflows
- All application data on PVCs
- All Ceph data (100% wiped from disks)

#### Kubernetes Resources
- All CRDs (Custom Resource Definitions)
- All PVCs (Persistent Volume Claims)
- All PVs (Persistent Volumes)
- All Storage Classes
- Custom ClusterRoles and ClusterRoleBindings
- ValidatingWebhookConfigurations
- MutatingWebhookConfigurations
- Non-system API Services

### Post-Reset Verification

After the script completes, verify the cluster state:

```bash
# Check only system namespaces remain
kubectl get namespaces

# Verify no PVCs or PVs
kubectl get pvc --all-namespaces
kubectl get pv

# Verify no custom CRDs
kubectl get crds

# Check nodes are healthy
kubectl get nodes

# Verify no storage classes
kubectl get storageclass

# Check system pods are running
kubectl get pods -n kube-system
```

Expected output:
- Only 5 namespaces: default, kube-system, kube-public, kube-node-lease, metallb-system
- 0 PVCs and 0 PVs
- Only system CRDs: certificatesigningrequests.certificates.k8s.io and MetalLB CRDs (6 total)
- All nodes in Ready state
- 0 storage classes
- All kube-system and metallb-system pods Running

### Verifying Disk Cleanup

SSH to each node and verify disks are clean:

```bash
# On each node
lsblk                    # Should show raw disks with no partitions
pvs                      # Should show no LVM physical volumes
lvs                      # Should show no logical volumes
ls /var/lib/rook         # Should not exist or be empty

# Check device is truly clean
wipefs /dev/sdb          # Should show no signatures
blkid /dev/sdb           # Should return nothing
```

### Troubleshooting

#### Stuck Namespaces
If namespaces are stuck in "Terminating":
```bash
# Check for resources with finalizers
kubectl api-resources --verbs=list --namespaced -o name | \
  xargs -n 1 kubectl get --show-kind --ignore-not-found -n <namespace>

# Force remove namespace
kubectl get namespace <namespace> -o json | \
  jq '.spec.finalizers = []' | \
  kubectl replace --raw "/api/v1/namespaces/<namespace>/finalize" -f -
```

#### PVs Stuck in Released
```bash
# Remove finalizers from PV
kubectl patch pv <pv-name> -p '{"metadata":{"finalizers":null}}'

# Force delete
kubectl delete pv <pv-name> --force --grace-period=0
```

#### CRDs Not Deleting
```bash
# Check for custom resources still using the CRD
kubectl get <crd-name> --all-namespaces

# Remove finalizers
kubectl patch crd <crd-name> -p '{"metadata":{"finalizers":null}}'

# Force delete
kubectl delete crd <crd-name> --force --grace-period=0
```

#### Disk Still Shows Partitions
```bash
# SSH to node
ssh <node>

# Manually wipe disk
sudo wipefs --all --force /dev/sdb
sudo dd if=/dev/zero of=/dev/sdb bs=1M count=1024
sudo partprobe /dev/sdb
sudo blkdiscard /dev/sdb
```

### Recovery After Reset

To redeploy the platform after reset:

1. **Verify cluster is clean** (see Post-Reset Verification above)

2. **Redeploy platform from scratch**
   ```bash
   # Follow deployment order from COMPLETE-PLATFORM-DIAGRAM.md
   # Start with Layer 0: Foundation
   kubectl apply -f v0.2.0/platform/charts/cert-manager/
   kubectl apply -f v0.2.0/platform/charts/rook-ceph/

   # Then Layer 1: Core Infrastructure
   # ... and so on
   ```

3. **Or use ArgoCD bootstrap**
   ```bash
   # Install ArgoCD first
   kubectl create namespace argocd
   kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

   # Apply platform-app (app-of-apps)
   kubectl apply -f v0.2.0/platform/charts/platform-app/
   ```

### When to Use This Script

**Use this script when:**
- ✅ Migrating to new infrastructure
- ✅ Major platform version upgrade requiring clean state
- ✅ Cluster has become unrecoverable/corrupted
- ✅ Testing disaster recovery procedures
- ✅ Decommissioning the platform
- ✅ Reclaiming disk space from Ceph

**DO NOT use this script when:**
- ❌ You just want to restart a single application
- ❌ You're troubleshooting a specific issue
- ❌ You need to recover data (backup first!)
- ❌ In production without full backup and approval
- ❌ You're not absolutely certain

### Backup Before Reset

**CRITICAL: BACKUP EVERYTHING BEFORE RUNNING THIS SCRIPT**

```bash
# 1. Backup Vault data
kubectl exec -n vault vault-0 -- vault operator raft snapshot save /tmp/vault-backup.snap
kubectl cp vault/vault-0:/tmp/vault-backup.snap ./vault-backup-$(date +%Y%m%d).snap

# 2. Backup Keycloak database
kubectl exec -n keycloak keycloak-postgresql-0 -- \
  pg_dump -U bn_keycloak bitnami_keycloak > keycloak-backup-$(date +%Y%m%d).sql

# 3. Backup Temporal databases
kubectl exec -n temporal temporal-postgres-0 -- \
  pg_dump -U temporal temporal > temporal-backup-$(date +%Y%m%d).sql

# 4. Backup Harbor data (S3 bucket)
# Use your S3 backup tool (rclone, aws s3 sync, etc.)

# 5. Backup Git repositories
# Ensure all configs are pushed to Git

# 6. Backup Grafana dashboards
# Use Grafana API or manual export

# 7. Export all ArgoCD applications
kubectl get applications -n argocd -o yaml > argocd-apps-backup-$(date +%Y%m%d).yaml

# 8. Encrypt and store backups securely
tar czf platform-backup-$(date +%Y%m%d).tar.gz *.snap *.sql *.yaml
gpg --encrypt --recipient platform-team@example.com platform-backup-$(date +%Y%m%d).tar.gz
```

### Script Exit Codes

- `0` - Success (cluster reset completed)
- `1` - Error (failed to complete reset)
- Exits on user cancellation

### Example Output

```
═══════════════════════════════════════════════════════════════════════════
                   Platform Reset Script v1.0
═══════════════════════════════════════════════════════════════════════════

[INFO] Starting platform reset at 2025-11-19 14:30:00
[INFO] Log file: /tmp/platform-reset-20251119-143000.log

[STEP] Checking prerequisites...
[INFO] Prerequisites check passed

╔═══════════════════════════════════════════════════════════════════════════╗
║                      ⚠️  CRITICAL WARNING  ⚠️                              ║
║  This script will PERMANENTLY DESTROY ALL DATA in the platform...         ║
╚═══════════════════════════════════════════════════════════════════════════╝

Do you want to continue? Type 'yes-destroy-everything' to proceed: yes-destroy-everything
Are you ABSOLUTELY sure? Type 'confirm' to proceed: confirm

[INFO] User confirmed platform reset

[STEP] Step 1: Deleting all ArgoCD applications...
[INFO] Found 43 ArgoCD applications
[INFO] Removing finalizers from application.argoproj.io/argocd-self
...
[INFO] All ArgoCD applications deleted

[STEP] Step 2: Deleting all Helm releases...
[INFO] Found 15 Helm releases
[INFO] Uninstalling Helm release: grafana (namespace: monitoring)
...
[INFO] All Helm releases deleted

[STEP] Step 3: Cleaning Rook Ceph cluster...
[INFO] Enabling Ceph cleanup policy...
[INFO] Deleting CephCluster...
...
[INFO] Rook Ceph cluster cleanup initiated

[STEP] Step 4: Deleting all PVCs and PVs...
[INFO] Found 47 PVCs
[INFO] Deleting PVC: monitoring/prometheus-data
...
[INFO] All PVCs and PVs deleted

[STEP] Step 5: Deleting platform namespaces...
[INFO] Deleting namespaces: argocd monitoring rook-ceph vault keycloak...
...
[INFO] All namespaces deleted

[STEP] Step 6: Deleting all Custom Resource Definitions (CRDs)...
[INFO] Found 157 CRDs
[INFO] Deleting CRD: applications.argoproj.io
...
[INFO] All CRDs deleted

[STEP] Step 7: Cleaning Ceph data from all nodes...
[INFO] Cleaning Ceph devices on all nodes...
[INFO] Processing node: k8s-master-01
[INFO]   Cleaning device: /dev/sdb on k8s-master-01
...
[INFO] Ceph device cleanup completed

[STEP] Step 8: Removing Rook Ceph state from nodes...
[INFO] Cleaning Rook state on node: k8s-master-01
...
[INFO] Rook state cleanup completed

[STEP] Step 9: Cleaning up remaining resources...
[INFO] Deleting webhook configurations...
...
[INFO] Remaining resources cleaned up

[STEP] Step 10: Verifying cluster state...
[INFO] ✓ Only system namespaces remain
[INFO] ✓ No PVCs remaining
[INFO] ✓ No PVs remaining
[INFO] ✓ Only system CRDs remain
[INFO] ✓ No storage classes remaining
[INFO] ✓ Cluster verification passed - cluster is in pristine state

═══════════════════════════════════════════════════════════════════════════
[INFO] Platform reset completed at 2025-11-19 14:47:35
[INFO] Full log available at: /tmp/platform-reset-20251119-143000.log
═══════════════════════════════════════════════════════════════════════════

Next steps:
1. Verify cluster state: kubectl get all --all-namespaces
2. Check nodes are ready: kubectl get nodes
3. Verify disks are clean on nodes
4. Redeploy platform from scratch
```

### Support

For issues or questions:
1. Check the log file: `/tmp/platform-reset-*.log`
2. Review troubleshooting section above
3. Consult platform documentation
4. Contact platform team

---

**Last Updated**: 2025-11-19
**Script Version**: 1.0
**Author**: Platform Team
