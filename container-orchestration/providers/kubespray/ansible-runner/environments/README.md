# Environments

Environment configs now come from `config/` packages and are emitted via the `api` CLI. Run `./api/bin/api generate env --id <env>` to populate `api/outputs/<env>/ansible.yml`; the Kubespray runner copies that file into `group_vars/`.
