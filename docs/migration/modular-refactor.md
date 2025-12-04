# Modular Repository Refactor – Migration Notes

This document explains how the legacy infrastructure layout maps into the new modular architecture introduced by `refactor-modular-infra-repo`.

## Directory Mapping

| Legacy Location | New Home | Notes |
|-----------------|----------|-------|
| `infrastructure/modules/bootstrap` | `api/` + `config/` | Schema validation, inventory generation, and config composition now live in the Go CLI + config packages. |
| `infrastructure/modules/templates/provisioner` | `provisioner/` | Image templating is a top-level module invoked through `api provision build`. |
| `k8s-cluster/`, `kubernetes/` | `container-orchestration/providers/kubespray/` | Provider interface with `deploy/reset/validate` entrypoints and inventory staging via API outputs. |
| `infrastructure/modules/nodes` | `infrastructure/platforms/proxmox/terraform/nodes` | Terraform code grouped under `platforms/<platform>/<provider>/`. |
| `platform/` + business workloads | `platform/` + `business/` + `docs/` | Platform, business apps, and documentation are isolated modules that consume API outputs. |

## Migration Checklist

1. **Generate API artifacts**
   ```bash
   ./api/bin/api generate env --id development --config core --skip-validate
   ```
   This writes inventories, Terraform variables, provisioner config, and metadata under `api/outputs/development/`.

2. **Backfill existing assets (optional)**
   Use `./scripts/backfill-api-outputs.sh --env development --config core --tfvars <old-tfvars> --inventory <old-inventory-dir>` if you need to seed the new outputs directory with artifacts produced before the refactor.

3. **Provisioner builds**
   ```bash
   ./api/bin/api provision build --role k8s-master --env development
   ```
   The CLI writes artifact metadata to `api/outputs/<env>/provisioner/` and the image to `provisioner/outputs/<env>/`.

4. **Infrastructure phases**
   The orchestrator now stages Terraform variables from API outputs before each phase:
   ```bash
   cd infrastructure
   ./deploy.sh --env development --phase images
   ./deploy.sh --env development --phase templates
   ./deploy.sh --env development --phase nodes
   ```

5. **Container orchestration + platform**
   Run the Kubespray provider with the same environment flag so it pulls the generated inventory:
   ```bash
   cd container-orchestration/providers/kubespray
   ./deploy.sh --env development
   ```
   Platform and business modules consume the same API outputs (`platform/environments/<env>.yaml` only selects the config package now).

## Breaking Changes

- Local environment files (`business/environments/*.yaml`, `provisioner/environments/*.yaml`, etc.) now **only** declare the `configPackage` and `environment`. Real values live in `config/packages/<id>/`.
- Scripts require `jq` because they parse `api/outputs/<env>/metadata.json`.
- Kubespray inventory files are sourced from `config/packages/core/kubespray/inventory/` instead of `providers/kubespray/inventory/`.

## Validation

See `docs/validation.md` for the latest recorded end-to-end run (API generate → provision build → infrastructure deploy → Kubespray deploy → platform/apps).
