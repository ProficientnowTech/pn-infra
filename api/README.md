# API Module

Provides the Go-based CLI (`cmd/api`) that validates schemas/definitions, generates environment artifacts, and orchestrates provisioner builds. Schemas and definitions live directly under `api/schemas/` and `api/definitions/`, and CLI outputs land in `api/outputs/<env>/` for other modules. Versioning is managed via Git tags/releases rather than directory names. Legacy bootstrap scripts (`api/bootstrap/...`) also live here so everything that touches schemas stays colocated with the CLI.

## Usage

```bash
# Validate role/size/disk/vlan definitions
./bin/api validate --target definitions

# Generate environment artifacts from a config package (writes api/outputs/<env>/ metadata.json + files/*)
./bin/api generate env --id development --config core --skip-validate

# Build a provisioner artifact + metadata (includes checksum + remote placeholders)
./bin/api provision build --role k8s-master --env development

# Run the legacy bootstrap workflow (until native Go cmd lands)
./bootstrap/run.sh --env development
```

The generated `metadata.json` exposes a `files` map (e.g., `terraform`, `kubesprayInventory`, `provisioner`) that downstream scripts consume via `jq`.
