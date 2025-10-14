# Deployment Configuration Checklist

This checklist ensures all required configurations are set before running the 2-phase deployment system.

## Pre-Deployment Configuration

### 1. Repository and Git Configuration

- [ ] **Git Repository URL** configured in inventory
  ```yaml
  git_repository_url: "https://github.com/your-org/pn-infra.git"
  git_repository_branch: "v1.2.0-p0-infra"  # or main
  ```

- [ ] **Git Repository Access** verified
  ```bash
  git clone https://github.com/your-org/pn-infra.git
  cd pn-infra && git checkout v1.2.0-p0-infra
  ```

- [ ] **Repository structure** matches expected paths:
  ```
  v0.2.0/
  ├── configs/           # Infrastructure configurations
  ├── platform/          # Platform applications
  └── bootstrap/         # Bootstrap scripts and manifests
  ```

### 2. Domain and DNS Configuration

- [ ] **Cluster Domain** configured
  ```yaml
  cluster_domain: "your-domain.com"
  ```

- [ ] **ArgoCD Hostname** configured
  ```yaml
  argocd_hostname: "argocd.your-domain.com"
  ```

- [ ] **DNS Records** configured (if using external access):
  - [ ] `argocd.your-domain.com` → LoadBalancer IP
  - [ ] `grafana.your-domain.com` → LoadBalancer IP (optional)
  - [ ] Wildcard DNS: `*.your-domain.com` → LoadBalancer IP (recommended)

- [ ] **Let's Encrypt Email** configured
  ```yaml
  letsencrypt_email: "admin@your-domain.com"
  ```

### 3. Network Configuration

- [ ] **MetalLB IP Range** configured for your network
  ```yaml
  metallb_ip_range: "192.168.1.100-192.168.1.150"
  ```

- [ ] **IP Range Verification**:
  - [ ] IP range is available and not used by DHCP
  - [ ] IP range is routable from your clients
  - [ ] Sufficient IPs for services (minimum 10 IPs recommended)

- [ ] **Network Connectivity**:
  - [ ] All nodes can communicate with each other
  - [ ] Nodes have internet access for image pulls
  - [ ] Firewall allows Kubernetes required ports

### 4. Storage Configuration

- [ ] **Storage Nodes** prepared for Rook-Ceph:
  - [ ] At least 3 worker nodes with storage
  - [ ] Each node has at least 1 unused block device (minimum 10GB)
  - [ ] Block devices are unpartitioned and unformatted
  - [ ] Storage devices are locally attached (not network storage)

- [ ] **Storage Requirements** verified:
  ```bash
  # Check available block devices on each storage node
  lsblk
  # Should show unused devices like /dev/sdb, /dev/sdc, etc.
  ```

### 5. Resource Requirements

- [ ] **Cluster Resources** sufficient:
  ```yaml
  # Minimum requirements
  total_cpu_cores: 16      # Recommended: 32+
  total_memory_gb: 32      # Recommended: 64+
  storage_nodes: 3         # Minimum for Ceph
  ```

- [ ] **Node Resources** per role:
  - [ ] **Control Plane**: 4 CPU, 8GB RAM, 50GB disk
  - [ ] **Worker Nodes**: 4 CPU, 8GB RAM, 100GB disk
  - [ ] **Storage Nodes**: 4 CPU, 8GB RAM, 100GB+ for Ceph

## Phase-Specific Configuration

### Phase 1: Complete Kubernetes Cluster (Kubespray)

- [ ] **Kubespray Inventory** configured:
  ```
  v0.2.0/cluster/inventory/pn-production/
  ├── inventory.ini              # Node definitions
  ├── group_vars/all/            # Global configuration
  └── group_vars/k8s_cluster/    # Cluster configuration
  ```

- [ ] **Kubespray Addons** enabled:
  ```yaml
  # group_vars/k8s_cluster/addons.yml
  ingress_nginx_enabled: true
  cert_manager_enabled: true
  metallb_enabled: true
  local_path_provisioner_enabled: true
  multus_enabled: true
  calico_enabled: true
  argocd_enabled: true                # ArgoCD deployed in Phase 1
  argocd_admin_password: "dev@Supreme2354"
  ```

- [ ] **SSH Access** configured:
  - [ ] SSH keys distributed to all nodes
  - [ ] Ansible user has sudo privileges
  - [ ] SSH connectivity verified from control node

- [ ] **Docker** installed and running:
  ```bash
  docker info
  ```

### Phase 2: Template-Driven Platform Applications

- [ ] **Platform Applications** configured:
  ```yaml
  # v0.2.0/platform/target-chart/values-production.yaml
  applications:
    - name: metallb-config        # sync-wave: -1
    - name: ingress-nginx-config  # sync-wave: -1
    - name: cert-manager-config   # sync-wave: -1
    - name: rook-ceph             # sync-wave: 1
    - name: rook-ceph-cluster     # sync-wave: 2
    - name: vault                 # sync-wave: 3
    - name: prometheus            # sync-wave: 4
    - name: grafana               # sync-wave: 5
    - name: kuberay-crds          # sync-wave: 6
    - name: kuberay-operator      # sync-wave: 7
    - name: gpu-operator          # sync-wave: 8
  ```

- [ ] **Modular Stack Configuration**:
  ```bash
  # Base infrastructure only
  ./bootstrap-template-driven.sh deploy --stack base
  
  # Add monitoring
  ./bootstrap-template-driven.sh deploy --stack monitoring
  
  # Add ML infrastructure
  ./bootstrap-template-driven.sh deploy --stack ml
  
  # Deploy everything
  ./bootstrap-template-driven.sh deploy --stack all
  ```

## Security Configuration

### SSL/TLS Configuration

- [ ] **Certificate Management** configured:
  ```yaml
  # Let's Encrypt issuers
  letsencrypt_prod_issuer: "letsencrypt-prod"
  letsencrypt_staging_issuer: "letsencrypt-staging"
  
  # Enable SSL for services
  argocd_ssl_enabled: true
  grafana_ssl_enabled: true
  ```

### RBAC Configuration

- [ ] **ArgoCD Projects** and roles configured:
  ```yaml
  # Bootstrap project for infrastructure
  bootstrap_project_name: "bootstrap"
  
  # Platform project for applications
  platform_project_name: "platform"
  ```

- [ ] **User Access** planned:
  - [ ] ArgoCD admin access
  - [ ] Developer access levels
  - [ ] Service account permissions

### Network Security

- [ ] **Network Policies** planned:
  - [ ] Default deny-all policy
  - [ ] ArgoCD specific policies
  - [ ] Service-to-service communication rules

- [ ] **Pod Security Standards** configured:
  ```yaml
  pod_security_enforce: "restricted"
  pod_security_audit: "restricted"
  pod_security_warn: "restricted"
  ```

## Validation Commands

### Pre-Deployment Validation

```bash
# Validate Kubespray configuration
cd v0.2.0/cluster
./kubespray.sh validate

# Validate template-driven platform
cd v0.2.0/platform/bootstrap
./bootstrap-template-driven.sh validate
```

### Configuration Verification

```bash
# Verify Docker is running
docker info

# Test SSH connectivity
ssh -i ~/.ssh/id_rsa user@your-node-ip

# Validate Helm templates
helm template v0.2.0/platform/target-chart -f v0.2.0/platform/target-chart/values-production.yaml
```

### Network Validation

```bash
# Test MetalLB IP range availability
nmap -sn 192.168.1.100-150

# Check DNS resolution
nslookup argocd.your-domain.com
nslookup your-domain.com
```

## Backup and Recovery Planning

### Before Migration

- [ ] **Backup existing configurations**:
  ```bash
  # Backup current kubeconfig
  cp ~/.kube/config ~/.kube/config.backup.$(date +%s)
  
  # Backup important namespaces (if migrating)
  kubectl get all --all-namespaces -o yaml > cluster-backup.yaml
  ```

- [ ] **Document current state**:
  - [ ] List of running applications
  - [ ] Storage configurations
  - [ ] Network configurations
  - [ ] Security policies

### Recovery Procedures

- [ ] **Reset procedures** tested:
  ```bash
  # Reset cluster completely
  cd v0.2.0/cluster
  ./kubespray.sh reset
  
  # Redeploy cluster
  ./kubespray.sh deploy
  ```

## Final Checklist

### Before Running Bootstrap

- [ ] All configuration files updated with correct values
- [ ] DNS records configured (if using external access)
- [ ] Storage devices prepared on storage nodes
- [ ] SSH connectivity verified to all nodes
- [ ] Backup procedures completed
- [ ] Team notified of maintenance window
- [ ] Rollback plan documented

### Configuration Files to Update

- [ ] `v0.2.0/cluster/inventory/pn-production/group_vars/all/all.yml`
- [ ] `v0.2.0/cluster/inventory/pn-production/group_vars/k8s_cluster/addons.yml`
- [ ] `v0.2.0/platform/target-chart/values-production.yaml` (repository URLs and applications)
- [ ] `v0.2.0/platform/charts/*/values.yaml` (application-specific configurations)

### Post-Deployment Verification

- [ ] **Phase 1**: Complete cluster with ArgoCD running
  ```bash
  kubectl get nodes
  kubectl get pods -n argocd
  kubectl get svc argocd-server -n argocd
  ```
- [ ] **Phase 2**: All platform applications synced and healthy
  ```bash
  kubectl get applications -n argocd
  kubectl get pods -A
  ```
- [ ] **Monitoring**: Prometheus collecting metrics, Grafana accessible
- [ ] **Storage**: Ceph cluster healthy, storage classes available
- [ ] **Security**: Network policies active, SSL certificates valid

## Troubleshooting Reference

### Common Configuration Issues

1. **DNS Resolution**: Ensure DNS records point to correct LoadBalancer IPs
2. **IP Range Conflicts**: Verify MetalLB range doesn't conflict with DHCP
3. **Storage Devices**: Ensure block devices are unpartitioned and available
4. **SSH Access**: Verify SSH keys and sudo access on all nodes
5. **Resource Constraints**: Check CPU/memory requirements are met

### Validation Scripts

Both phases include validation capabilities:
- `kubespray.sh validate`: Node connectivity, Docker, SSH access
- `bootstrap-template-driven.sh validate`: Helm templates, ArgoCD readiness

Run these validations before deployment to catch configuration issues early.

## Support Information

### Documentation Locations

- **Deployment Guide**: `v0.2.0/README.md`
- **Kubespray Operations**: `v0.2.0/cluster/kubespray.sh --help`
- **Template System**: `v0.2.0/platform/target-chart/README.md`
- **Bootstrap Script**: `v0.2.0/platform/bootstrap/bootstrap-template-driven.sh --help`

### Log Locations

- **Kubespray Logs**: Docker container output
- **ArgoCD Logs**: `kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server`
- **Application Logs**: `kubectl logs -n <namespace> <pod-name>`

This checklist ensures a successful deployment using the 2-phase architecture.