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
