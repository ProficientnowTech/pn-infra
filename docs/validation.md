# Validation Log – Modular Infra Refactor

**Date:** 2024-12-02  
**Environment:** development  
**Config Package:** core@v0.2.0

## Steps

1. **Generate environment artifacts**
   ```bash
   ./api/bin/api generate env --id development --config core --skip-validate
   ```
   - Outputs: `api/outputs/development/{ansible.yml, terraform.tfvars, provisioner.json, kubespray/…}`

2. **Provisioner build smoke-test**
   ```bash
   ./api/bin/api provision build --role k8s-master --env development
   ```
   - Image artifact: `provisioner/outputs/development/k8s-master.img`
   - Metadata: `api/outputs/development/provisioner/k8s-master.json`

3. **Infrastructure dry run**
   ```bash
   cd infrastructure
   ./deploy.sh --env development --dry-run
   ```
   - Confirms API outputs are staged and Terraform variables copied into `platforms/proxmox/terraform/*/terraform.tfvars`.

4. **Kubespray validation (inventory from API outputs)**
   ```bash
   cd container-orchestration/providers/kubespray
   ./deploy.sh validate --env development --dry-run
   ```
   - Inventory staged to `providers/kubespray/inventory/current`
   - Docker image `quay.io/kubespray/kubespray:v2.28.1` pulled successfully.

5. **Documentation + business chart sync**
   ```bash
   helm upgrade --install cluster-apps business/charts/cluster-apps \
     -f api/outputs/development/business.yaml --dry-run
   ```

## Result

All steps completed without errors using the new API-driven workflow. The `go test ./...` suite (with local cache) also passes, covering the new CLI logic.
