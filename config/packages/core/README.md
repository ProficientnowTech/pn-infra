# Core Configuration Package

Version: v1.0.0

The `core` configuration package implements the **master config pattern** for multi-platform infrastructure deployment. This package contains all YAML-based configuration data that the API CLI transforms into platform/orchestrator-specific outputs.

## Master Config Pattern

The package uses a master configuration file (`config.yaml`) that declares platform and orchestrator choices. Based on these selections, the API CLI automatically:

1. Loads platform-agnostic configs (hosts, networks)
2. Selects and loads platform-specific configs (Proxmox, AWS, GCP, Azure, or bare metal)
3. Selects and loads orchestrator-specific configs (Kubespray, Kubekey, or Kind)
4. Merges with environment-specific overrides
5. Generates native-format outputs (`.tfvars`, `.json`, `.ini`, `.yaml`)

**Key Principle**: Input variables differ by platform/orchestrator choice, but output contract remains consistent.

---

## Directory Structure

```
config/packages/core/
├── config.yaml                  # MASTER CONFIG: Declares platform & orchestrator choices
├── hosts.yaml                   # Platform-agnostic host definitions
├── networks.yaml                # Platform-agnostic network topology
├── platforms/                   # Platform-specific configurations
│   ├── proxmox.yaml            # Proxmox-specific settings
│   ├── aws.yaml                # AWS-specific settings
│   ├── gcp.yaml                # GCP-specific settings
│   ├── azure.yaml              # Azure-specific settings
│   └── baremetal.yaml          # Bare metal settings
├── orchestrators/               # Orchestrator-specific configurations
│   ├── kubespray.yaml          # Kubespray cluster settings
│   ├── kubekey.yaml            # Kubekey cluster settings
│   └── kind.yaml               # Kind (local dev) settings
├── platform/                    # Platform services configuration
│   └── stacks.yaml             # Platform stacks (monitoring, logging, etc.)
├── business/                    # Business applications configuration
│   └── apps.yaml               # Application definitions for ArgoCD
├── environments/                # Legacy/generated environment files
├── package.json                # Package manifest
└── README.md                   # This file
```

---

## Configuration Files

### Master Configuration (`config.yaml`)

Declares platform and orchestrator choices. The API reads this file first to determine which templates and configs to load.

```yaml
version: v1.0.0

infrastructure:
  platform: proxmox        # Options: proxmox, aws, gcp, azure, baremetal
  provider: terraform      # Options: terraform, pulumi, ansible

container_orchestration:
  orchestrator: kubespray  # Options: kubespray, kubekey, kind
  provider: docker         # Options: docker, podman, native

platform:
  deployment_method: helm  # Options: helm, kustomize, argocd

business:
  deployment_method: argocd  # Options: argocd, helm, kustomize
```

### Platform-Agnostic Configs

#### `hosts.yaml`
Defines compute resources (VMs/instances) with platform-independent attributes:
- Host name and role
- IP addresses
- CPU, memory, disk sizes
- Kubernetes node groups
- Labels for scheduling

#### `networks.yaml`
Defines network topology:
- VLAN configurations
- CIDR ranges
- Gateway and DNS servers
- NTP servers

### Platform-Specific Configs (`platforms/`)

Each file contains non-sensitive, platform-specific settings:

- **proxmox.yaml**: Proxmox node, datastore, network bridge, VM templates
- **aws.yaml**: Region, VPC, subnets, instance types, security groups
- **gcp.yaml**: Project ID, region, zones, network, firewall rules
- **azure.yaml**: Location, resource group, VNet, VM sizes
- **baremetal.yaml**: BMC/IPMI settings, PXE boot, RAID configuration

**Note**: Secrets (API tokens, credentials) are NOT stored here. They come from module environment files (`<module>/environments/<env>.yaml`).

### Orchestrator-Specific Configs (`orchestrators/`)

Each file contains Kubernetes cluster settings for that orchestrator:

- **kubespray.yaml**: Kubernetes version, CNI plugin, network ranges, addons
- **kubekey.yaml**: KubeKey-specific cluster configuration
- **kind.yaml**: Kind configuration for local development

### Platform Services (`platform/stacks.yaml`)

Defines which platform stacks to deploy:
- Bootstrap (namespaces, sealed-secrets)
- Storage (local-path, Longhorn, Rook-Ceph)
- Ingress (NGINX, Traefik)
- GitOps (ArgoCD)
- Monitoring (Prometheus, Grafana)
- Logging (Loki, Elasticsearch)
- Service mesh (Istio, Linkerd)
- Backup (Velero)

### Business Applications (`business/apps.yaml`)

Defines tenant/business applications deployed via ArgoCD app-of-apps:
- Application name, namespace
- Source repository and path
- Sync policies
- Helm values/Kustomize overlays

---

## How It Works

### 1. Platform Switching

To deploy on a different platform, simply update `config.yaml`:

```yaml
infrastructure:
  platform: aws        # Changed from proxmox
  provider: terraform
```

The API automatically:
- Loads `platforms/aws.yaml` instead of `platforms/proxmox.yaml`
- Selects template: `api/templates/infrastructure/aws/terraform/terraform.tfvars.tmpl`
- Generates AWS-compatible `terraform.tfvars`

**No code changes required!**

### 2. Orchestrator Switching

To use a different Kubernetes installer:

```yaml
container_orchestration:
  orchestrator: kubekey  # Changed from kubespray
  provider: docker
```

The API automatically:
- Loads `orchestrators/kubekey.yaml` instead of `orchestrators/kubespray.yaml`
- Selects template: `api/templates/container-orchestration/kubekey/config.yaml.tmpl`
- Generates Kubekey-compatible inventory

### 3. Configuration Merging

The API merges configurations in this order (later overrides earlier):

1. **Platform-agnostic configs** (`hosts.yaml`, `networks.yaml`)
2. **Platform-specific config** (e.g., `platforms/proxmox.yaml`)
3. **Orchestrator-specific config** (e.g., `orchestrators/kubespray.yaml`)
4. **Platform/business configs** (`platform/stacks.yaml`, `business/apps.yaml`)
5. **Environment overrides** (from `<module>/environments/<env>.yaml`)

### 4. Template Selection

Based on master config, API selects templates:

```
infrastructure.platform = proxmox + infrastructure.provider = terraform
→ api/templates/infrastructure/proxmox/terraform/terraform.tfvars.tmpl

container_orchestration.orchestrator = kubespray
→ api/templates/container-orchestration/kubespray/inventory.ini.tmpl
→ api/templates/container-orchestration/kubespray/group_vars/all.yaml.tmpl
```

### 5. Output Generation

Templates are rendered with merged config data and written to `api/outputs/<env>/`:

```
api/outputs/development/
├── metadata.json                    # Master metadata with artifact paths
├── terraform.tfvars                 # Infrastructure (Proxmox HCL format)
├── provisioner.json                 # Provisioner config
├── kubespray/
│   ├── inventory.ini               # Kubespray inventory (INI format)
│   └── group_vars/
│       ├── all.yaml                # Cluster-wide settings
│       └── k8s_cluster.yaml        # Kubernetes settings
├── kubesprayConfig.json            # Kubespray Docker/SSH config
├── platform.yaml                   # Platform Helm values
└── business.yaml                   # Business app-of-apps values
```

---

## Usage Examples

### Deploying on Proxmox with Kubespray

```bash
# 1. Ensure config.yaml specifies Proxmox + Kubespray
cat config/packages/core/config.yaml
# infrastructure.platform: proxmox
# container_orchestration.orchestrator: kubespray

# 2. Generate artifacts
./api/bin/api generate env --id development --config core

# 3. Deploy infrastructure
cd infrastructure
./deploy.sh --env development --phase nodes

# 4. Deploy Kubernetes with Kubespray
cd container-orchestration/providers/kubespray
./deploy.sh --env development

# 5. Deploy platform services
cd platform
./run.sh --env development

# 6. Deploy business applications
cd business
helm upgrade --install cluster-apps charts/cluster-apps \
  -f ../api/outputs/development/business.yaml
```

### Switching to AWS

```bash
# 1. Update master config
vim config/packages/core/config.yaml
# Change: infrastructure.platform: aws

# 2. Add AWS credentials to environment override
vim infrastructure/environments/development.yaml
# Add aws.access_key, aws.secret_key

# 3. Regenerate artifacts (API auto-selects AWS templates)
./api/bin/api generate env --id development --config core

# 4. Deploy on AWS
cd infrastructure
./deploy.sh --env development --phase nodes
```

### Using Kind for Local Development

```bash
# 1. Update master config
vim config/packages/core/config.yaml
# Change: container_orchestration.orchestrator: kind

# 2. Regenerate artifacts
./api/bin/api generate env --id development --config core

# 3. Deploy Kind cluster
cd container-orchestration/providers/kind
./deploy.sh --env development
```

---

## Versioning

This package follows semantic versioning:

- **Major version**: Breaking changes to config structure
- **Minor version**: New platforms/orchestrators, backward-compatible features
- **Patch version**: Bug fixes, documentation updates

Current version: **v1.0.0**

---

## Environment-Specific Overrides

Sensitive data and environment-specific settings are stored in module environment files:

- `infrastructure/environments/<env>.yaml` - Platform credentials, SSH keys
- `provisioner/environments/<env>.yaml` - Ansible vault passwords, SSH keys
- `container-orchestration/environments/<env>.yaml` - Docker settings, SSH keys, cluster overrides
- `platform/environments/<env>.yaml` - ArgoCD passwords, sealed-secrets keys, secret env vars
- `business/environments/<env>.yaml` - App-specific secrets, namespace configs

These files are validated against schemas in `api/schemas/environments/`.

---

## Adding New Platforms

To add support for a new platform (e.g., DigitalOcean):

1. Create `platforms/digitalocean.yaml` with platform-specific settings
2. Create template: `api/templates/infrastructure/digitalocean/terraform/terraform.tfvars.tmpl`
3. Update `config.yaml` to support `platform: digitalocean`
4. Update `package.json` supported_platforms list
5. Regenerate and deploy

---

## Best Practices

1. **Never store secrets in this package** - Use module environment files
2. **Keep platform-agnostic configs DRY** - `hosts.yaml` and `networks.yaml` should work across all platforms
3. **Document platform-specific requirements** - Add comments in platform YAML files
4. **Version control all changes** - Git tag releases using `vX.Y.Z` format
5. **Test config changes** - Validate with `./api/bin/api generate env --validate-only`

---

## Related Documentation

- API Module: `api/README.md` - Artifact generation and templating
- Infrastructure Module: `infrastructure/README.md` - VM/instance deployment
- Container Orchestration: `container-orchestration/README.md` - Kubernetes cluster setup
- Platform Module: `platform/README.md` - Platform services deployment
- Business Module: `business/README.md` - Application deployment

---

## Troubleshooting

**Problem**: API fails to generate artifacts
**Solution**: Check master config syntax and ensure all referenced files exist

**Problem**: Template not found error
**Solution**: Verify `config.yaml` platform/orchestrator values match available templates

**Problem**: Config validation fails
**Solution**: Run `./config/validate.sh` to check YAML syntax

---

## Support

For issues with configuration structure or API integration, see:
- OpenSpec documentation: `openspec/changes/api-config-separation/`
- API CLI help: `./api/bin/api --help`
