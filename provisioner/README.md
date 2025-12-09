# Provisioner Module

Contains the templating pipeline (Ansible, scripts, docs) that converts role definitions + environment data into bootable images. Builds are driven through the `api` CLI and publish metadata under `api/outputs/<env>/provisioner/` for infrastructure providers.

```bash
# 1. Materialize the config package for an environment
./api/bin/api generate env --id development --config core --skip-validate

# 2. Build an image for a specific role (static + dynamic config resolved from API outputs)
./api/bin/api provision build --role k8s-master --env development

# → metadata stored in api/outputs/development/provisioner/k8s-master.json
# → image output stored under provisioner/outputs/development/k8s-master.img
```

See `provisioner/scripts/smoke-test.sh` for a quick validation routine that exercises the flow end to end.

---

## Requirements

### Input Files
- **From Config**: Role definitions (base configuration per role)
- **From API**: `api/outputs/<env>/provisioner.json` - Merged config (static + dynamic)
- **Module Environment**: `provisioner/environments/<env>.yaml` - Ansible vault passwords, SSH keys, role overrides

### Required Tools
- Ansible 2.x+
- Python 3.x
- SSH access to target hosts

### Folder Structure
```
provisioner/
├── ansible.cfg
├── requirements.yml
├── inventories/<env>/hosts.yml
├── playbooks/site.yml
└── roles/
    ├── base/
    ├── software/
    ├── system_settings/
    ├── disk_management/
    ├── identity_users/
    ├── directories/
    ├── networking/
    └── security/
```

---

## Outputs

### Provisioned Images
- **Location**: `provisioner/outputs/<env>/<role>.img`
- **Metadata**: `api/outputs/<env>/provisioner/<role>.json`
  - Role name, environment, artifact path, checksum
  - Remote storage placeholders (bucket, path)
  - Build timestamp

### Configured Hosts
- VMs/instances with applied role configuration
- Base system (timezone, locale, logging)
- Software packages installed
- System settings applied
- Users/directories created
- Network configuration
- Security hardening (if enabled)

---

## Integration
- **Depends On**: Infrastructure (VMs must exist), API (generates config)
- **Consumed By**: Container Orchestration (expects configured hosts)
