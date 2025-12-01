# Outputs for VM Nodes Module

output "vm_inventory" {
  description = "Ansible inventory structure with VM details"
  value = {
    all = {
      hosts = {
        for k, v in proxmox_virtual_environment_vm.vms : v.name => {
          ansible_host = v.ipv4_addresses[1][0] # First non-loopback IP
          vm_id        = v.vm_id
          role         = k
          vm_size      = var.vm_roles[k].vm_size
          cpu_cores    = var.vm_sizes[var.vm_roles[k].vm_size].cpu_cores
          memory_mb    = var.vm_sizes[var.vm_roles[k].vm_size].memory_dedicated
          disk_size_gb = var.vm_sizes[var.vm_roles[k].vm_size].disk_size
          networks     = [for net in local.role_networks[k] : "${net.bridge} (VLAN ${net.vlan_id})"]
        }
      }
      children = {
        for role in distinct([for k, v in var.vm_roles : k]) : "${role}s" => {
          hosts = {
            for k, v in proxmox_virtual_environment_vm.vms : v.name => {} if k == role
          }
        }
      }
    }
  }
}

output "vm_details" {
  description = "Detailed VM information"
  value = {
    for k, v in proxmox_virtual_environment_vm.vms : k => {
      vm_id      = v.vm_id
      name       = v.name
      role       = k
      vm_size    = var.vm_roles[k].vm_size
      ip_address = length(v.ipv4_addresses) > 1 ? v.ipv4_addresses[1][0] : null
      status     = v.status
    }
  }
}

output "ansible_inventory_file" {
  description = "Ansible inventory in YAML format"
  value = yamlencode({
    all = {
      children = {
        for role in distinct([for k, v in var.vm_roles : k]) : "${role}s" => {
          hosts = {
            for k, v in proxmox_virtual_environment_vm.vms : v.name => {
              ansible_host = length(v.ipv4_addresses) > 1 ? v.ipv4_addresses[1][0] : null
              vm_id        = v.vm_id
              role         = k
              vm_size      = var.vm_roles[k].vm_size
            } if k == role
          }
        }
      }
    }
  })
}