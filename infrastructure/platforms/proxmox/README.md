# Proxmox Platform

Contains Terraform-based provisioning workflows for Proxmox VE. Providers live under `terraform/` (e.g., `nodes`, `templates`, `pools`) and follow the same run.sh interface used before the refactor. Each runner expects tfvars emitted by `api/bootstrap/run.sh` / `./api/bin/api generate env ...`.
