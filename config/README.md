# Config Module

Stores reusable configuration packages that modules reference from their `environments/` files. Each package lives under `packages/<id>/` with a `package.json` manifest describing contents (environment IDs, referenced files, metadata). Versioning is handled via the manifest + Git releases rather than directory names.

## Usage

```bash
# List the manifest
cat packages/core/package.json

# Generate environment artifacts that reference the package
./api/bin/api generate env --id development --config core
```

When updating a package, bump the manifest `version` field and tag the repo. Modules reference packages via `configPackage: <id>` inside their `environments/<env>.yaml`.
