# Inventory Staging

Kubespray inventories are no longer edited in-place. Instead, run `./api/bin/api generate env --id <env>` to materialize the package-provided inventory under `api/outputs/<env>/kubespray/`. The deploy/reset scripts copy those generated files into this directory at runtime so engineers always consume the config tracked in `config/packages/<package>/`.
