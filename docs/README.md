# Docs Module

Centralizes architectural references, runbooks, validation notes, and the `fuma-docs` site that will ultimately be hosted via the platform. Each document lives under `docs/<topic>/`. The `docs/fuma-docs` directory holds the scaffold for the documentation application (Helm/Argo manifests, content stubs).

Key subdirectories:
- `docs/general/`: high-level guides
- `docs/platform/*`: stack-specific procedures
- `docs/fuma-docs/`: documentation site deployed via the business module
- `docs/migration/`: change logs and migration notes
- `docs/validation.md`: latest end-to-end verification report
