# Bare Metal Platform

Placeholder for bare metal infrastructure providers (e.g., Libvirt, Vagrant). Each provider should live in its own subdirectory (e.g., `libvirt/`) and expose scripts/modules similar to the Proxmox/Terraform layout.

When implementing, read the config package referenced by `infrastructure/environments/<env>.yaml`, generate tfvars via the API CLI, and reuse the same `plan/apply/destroy` flags expected by `infrastructure/deploy.sh`.
