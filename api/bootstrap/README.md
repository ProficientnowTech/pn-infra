# Bootstrap (Legacy Workflow)

Formerly located under `infrastructure/modules/bootstrap`, these scripts now live inside the `api/` module so that schema/definition-driven generation is colocated with the CLI. The existing bash workflows (run/test/validate) continue to work for now, but new orchestration/validation should eventually move into native Go subcommands.

Consumers should invoke `api/bootstrap/run.sh` (or, preferably, the Go CLI once extended) to render Packer inputs, Terraform tfvars, and other role metadata. The script now writes directly into `infrastructure/platforms/proxmox/terraform/{templates,pools,nodes}` and `container-orchestration/providers/kubespray/ansible-runner/environments/`, so no additional copy steps are required.
