# Proxmox Resource Pools Module
# Creates and manages Proxmox resource pools for organized VM deployment

# Create pools for organized resource management
resource "proxmox_virtual_environment_pool" "pools" {
  for_each = toset(var.pools)

  pool_id = "${var.global_config.resource_prefix}-${each.key}"
  comment = "Pool for ${each.key} workloads - Environment: ${var.global_config.environment}"
}