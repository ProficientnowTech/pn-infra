# Infrastructure Module

Organizes every infrastructure provider under a consistent layout:

```
infrastructure/
├── deploy.sh                  # Orchestrates infra phases
├── environments/              # Module-specific environment selectors (reference config packages)
└── platforms/
    ├── proxmox/               # Current MVP platform (Terraform)
    │   └── terraform/
    │       ├── nodes/        # VM creation Terraform
    │       ├── templates/    # Resource templates + packer helpers
    │       └── pools/        # Proxmox pool/SDN Terraform
    ├── baremetal/
    │   └── libvirt/          # Placeholder for future bare metal provider
    └── cloud/
        ├── aws/
        ├── gcp/
        └── azure/
```

Each provider exposes the same `run.sh` interface (`plan` / `apply`, `--env <name>`) so `deploy.sh` can orchestrate phases using the outputs from the `api` CLI and config packages.

## Quick Start

```bash
./api/bin/api generate env --id development --config core
cd infrastructure
./deploy.sh --env development --phase images    # packer builds
./deploy.sh --env development --phase nodes     # terraform apply
```

The legacy `infrastructure/modules/*` tree has been removed; add new providers under `platforms/` instead.

---

## Requirements

### Input Files

#### From Config Package (`config/packages/core/`)
- **Master Config**: `config.yaml` - Declares platform/provider selection (proxmox, aws, gcp, etc.)
- **Platform-Agnostic**:
  - `hosts.yaml` - Host definitions (name, role, cpu, memory)
  - `networks.yaml` - Network configurations (VLANs, subnets, DNS)
- **Platform-Specific** (loaded based on master config selection):
  - `platforms/proxmox.yaml` - Proxmox settings (endpoint, node_name, datastore - non-sensitive)
  - `platforms/aws.yaml` - AWS settings (region, vpc_id, instance_type)
  - `platforms/gcp.yaml`, `platforms/azure.yaml`, etc.

#### From API Outputs (`api/outputs/<env>/`)
- **metadata.json** - Master metadata file with all artifact paths
- **terraform.tfvars** - Generated HCL format variables (platform-specific based on master config)
  - Generated from: platform-agnostic configs + platform-specific config + environment overrides
  - Template used: `api/templates/infrastructure/{platform}/{provider}/terraform.tfvars.tmpl`

#### Module Environment File (`infrastructure/environments/<env>.yaml`)
- **configPackage**: Reference to config package (always "core")
- **environment**: Environment name (development, staging, production)
- **Platform-specific secrets** (based on selected platform):
  - Proxmox: `proxmox.api_token`, `proxmox.endpoint` (can override base)
  - AWS: `aws.access_key`, `aws.secret_key`
  - GCP: `gcp.credentials_json`
- **SSH keys**: `ssh.private_key_path`, `ssh.public_key`
- **Host overrides** (optional): Environment-specific IP addresses or configurations
- **Schema**: Validated against `api/schemas/environments/infrastructure.schema.yaml`

### Environment Variables
- `PROXMOX_API_TOKEN` - Alternative to yaml-based token (if preferred)
- `SSH_KEY_PATH` - SSH private key for VM access

### Required Tools
- `terraform` (version documented in provider)
- `yq` - YAML parser for environment file reading
- `jq` - JSON parser for metadata.json reading
- `openssl` - For encryption/decryption operations
- API binary: `./api/bin/api` - For artifact generation

### Folder Structure Expected
```
api/outputs/<env>/
├── metadata.json                 # Points to terraform.tfvars location
└── terraform.tfvars              # Generated HCL (Proxmox/AWS/GCP specific)

infrastructure/environments/
└── <env>.yaml                    # References config package + secrets
```

### Platform Requirements
Each platform under `platforms/{platform}/{provider}/` must expose:
- `run.sh` - Standardized interface (plan/apply/destroy)
- Support for `--env <name>` flag
- Consume tfvars from `api/outputs/<env>/terraform.tfvars`

---

## Outputs

### Generated Infrastructure
- **VMs/Instances**: Provisioned compute resources based on host definitions
- **Network Resources**: VLANs, subnets, security groups (platform-dependent)
- **Storage Resources**: Volumes, datastores configured per platform

### Terraform State Files
```
infrastructure/platforms/{platform}/{provider}/
├── templates/terraform.tfstate   # Resource templates state
├── pools/terraform.tfstate        # Resource pools state
└── nodes/terraform.tfstate        # VM/instance state
```

### Exported Data (for downstream modules)
From Terraform state (consumed by provisioner, container-orchestration):
- **Host IPs**: IP addresses assigned to VMs/instances
- **Hostnames**: Resolvable hostnames for each host
- **Network Configuration**: Gateway, DNS servers, subnet details
- **SSH Keys**: Public keys deployed to hosts
- **Resource IDs**: Platform-specific identifiers (Proxmox VM IDs, AWS instance IDs)

### Deployment Artifacts
- Packer-built images (phase: images)
- Resource templates (phase: templates)
- Deployed VMs/instances (phase: nodes)

---

## Integration Points

### Depends On
- **API Module**: Generates terraform.tfvars from YAML configs
- **Config Module**: Provides base configurations and platform-specific settings

### Consumed By
- **Provisioner Module**: Uses host IPs and SSH access to configure VMs
- **Container Orchestration Module**: Requires running VMs with network connectivity
- **Platform Module**: Needs infrastructure in place before deploying services

---

## Deployment Phases

### Phase 1: Bootstrap
```bash
./deploy.sh --env development --phase bootstrap
```
- Generates API artifacts if `api/outputs/<env>/metadata.json` is missing
- Runs: `./api/bin/api generate env --id <env> --config core`

### Phase 2: Images
```bash
./deploy.sh --env development --phase images
```
- Builds VM images using Packer (if applicable)
- Creates base templates for VM deployment
- Location: `platforms/proxmox/terraform/templates/`

### Phase 3: Templates
```bash
./deploy.sh --env development --phase templates
```
- Creates resource templates and pools
- Prepares infrastructure foundation
- Location: `platforms/proxmox/terraform/pools/`

### Phase 4: Nodes
```bash
./deploy.sh --env development --phase nodes
```
- Deploys VMs/instances based on host definitions
- Stages `terraform.tfvars` from API outputs to module directory
- Runs: `terraform apply` in `platforms/proxmox/terraform/nodes/`

### Phase 5: Ansible (Optional/Legacy)
```bash
./deploy.sh --env development --phase ansible
```
- Legacy hook for Ansible configuration
- Consider using Provisioner module instead

---

## Platform-Specific Notes

### Proxmox (Current MVP)
- **Provider**: Terraform with Proxmox provider
- **Authentication**: API token (from environment override)
- **Endpoint**: Proxmox API endpoint URL
- **Node Selection**: Specific Proxmox node for VM deployment
- **Datastore**: Storage location for VM disks

### AWS (Future)
- **Provider**: Terraform with AWS provider
- **Authentication**: Access key + secret key (from environment override)
- **Region**: AWS region for resource deployment
- **VPC**: Virtual Private Cloud configuration
- **Instance Types**: EC2 instance types per host

### GCP/Azure/Bare Metal
- Placeholder directories exist under `platforms/`
- Follow Proxmox pattern when implementing
- Ensure `run.sh` interface compatibility

---

## Switching Platforms

To switch from Proxmox to AWS:

1. Update master config (`config/packages/core/config.yaml`):
   ```yaml
   infrastructure:
     platform: aws      # Changed from proxmox
     provider: terraform
   ```

2. Ensure AWS-specific config exists: `config/packages/core/platforms/aws.yaml`

3. Create environment overrides with AWS secrets:
   ```yaml
   # infrastructure/environments/production.yaml
   configPackage: core
   environment: production
   aws:
     access_key: "AKIAXXXXXXXXXXXXXXXX"
     secret_key: "secret-key-here"
     region: us-east-1
   ```

4. Regenerate artifacts:
   ```bash
   ./api/bin/api generate env --id production --config core
   ```

5. Deploy with AWS provider:
   ```bash
   ./deploy.sh --env production --phase nodes
   ```

The API automatically selects `api/templates/infrastructure/aws/terraform/terraform.tfvars.tmpl` and generates AWS-compatible terraform.tfvars. No code changes required!
