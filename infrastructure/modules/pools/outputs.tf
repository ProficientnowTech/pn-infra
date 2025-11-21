# Outputs for Proxmox Resource Pools Module

output "pool_ids" {
  description = "Map of pool names to their IDs"
  value       = { for k, v in proxmox_virtual_environment_pool.pools : k => v.pool_id }
}

output "pool_names" {
  description = "List of created pool names"
  value       = [for pool in proxmox_virtual_environment_pool.pools : pool.pool_id]
}