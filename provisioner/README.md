# Provisioner Module

Contains the templating pipeline (Ansible, scripts, docs) that converts role definitions + environment data into bootable images. Builds are driven through the `api` CLI and publish metadata under `outputs/` for infrastructure providers.

```bash
./api/bin/api provision build --role k8s-master --env development
# → metadata stored in api/outputs/development/provisioner/k8s-master.json
# → image output expected under provisioner/outputs/development/k8s-master.img
```
