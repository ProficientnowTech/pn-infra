# Cloud Providers

Placeholder for infrastructure providers targeting public clouds (AWS/GCP/Azure). Each provider should mirror the folder structure used by the Proxmox Terraform stack.

When implemented, providers must read environment + config data emitted by the API CLI and expose the same `plan/apply/destroy` interface consumed by `infrastructure/deploy.sh`.
