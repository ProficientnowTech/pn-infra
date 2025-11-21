# VM Nodes Module  
# Deploys VMs using size templates and pre-baked images with role-specific configurations

# Create VMs based on bootstrap-generated configuration
resource "proxmox_virtual_environment_vm" "vms" {
  for_each = var.vm_roles

  node_name = var.global_config.proxmox_config.node_name
  pool_id   = var.pool_ids["k8s-platform"]
  
  # Generate VM ID and name
  vm_id = var.vm_id_start + index(keys(var.vm_roles), each.key) * 10
  name  = "${var.global_config.resource_prefix}-${each.key}-${format("%02d", 1)}"
  
  # Use pre-baked image for the role
  clone {
    vm_id = var.images_by_role[each.key].image_id
  }

  # Apply size template specifications
  cpu {
    cores = var.vm_sizes[each.value.vm_size].cpu_cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.vm_sizes[each.value.vm_size].memory_dedicated
  }

  disk {
    datastore_id = var.global_config.proxmox_config.datastore
    interface    = "scsi0"
    size         = var.vm_sizes[each.value.vm_size].disk_size
  }

  # Network configuration based on role requirements
  dynamic "network_device" {
    for_each = local.role_networks[each.key]
    content {
      bridge = network_device.value.bridge
      vlan   = network_device.value.vlan_id
    }
  }

  # Cloud-init configuration
  initialization {
    user_data_file_id = "local:snippets/${each.key}-user.yml"
    
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
  }

  operating_system {
    type = "l26"
  }

  agent {
    enabled = true
  }

  tags = [
    "role:${each.key}",
    "size:${each.value.vm_size}",
    "environment:${var.global_config.environment}"
  ]

  # Ensure dependencies are created first
  depends_on = [
    var.pool_ids,
    var.template_ids
  ]
}

# Local network mappings for roles
locals {
  role_networks = {
    "ans-controller" = [
      { bridge = "vmbr106", vlan_id = 106 } # management
    ]
    "k8s-master" = [
      { bridge = "vmbr106", vlan_id = 106 }, # management  
      { bridge = "vmbr105", vlan_id = 105 }  # internal_traffic
    ]
    "k8s-worker" = [
      { bridge = "vmbr106", vlan_id = 106 }, # management
      { bridge = "vmbr105", vlan_id = 105 }, # internal_traffic  
      { bridge = "vmbr107", vlan_id = 107 }  # public_traffic
    ]
    "k8s-bootstrap" = [
      { bridge = "vmbr106", vlan_id = 106 }, # management
      { bridge = "vmbr105", vlan_id = 105 }  # internal_traffic
    ]
    "k8s-worker-gpu" = [
      { bridge = "vmbr106", vlan_id = 106 }, # management
      { bridge = "vmbr105", vlan_id = 105 }, # internal_traffic
      { bridge = "vmbr107", vlan_id = 107 }  # public_traffic
    ]
    "k8s-ceph-mon" = [
      { bridge = "vmbr106", vlan_id = 106 }, # management
      { bridge = "vmbr110", vlan_id = 110 }  # storage_public
    ]
    "k8s-ceph-mgr" = [
      { bridge = "vmbr106", vlan_id = 106 }, # management
      { bridge = "vmbr110", vlan_id = 110 }  # storage_public
    ]
    "k8s-ceph-osd" = [
      { bridge = "vmbr106", vlan_id = 106 }, # management
      { bridge = "vmbr110", vlan_id = 110 }  # storage_public
    ]
    "fw-opnsense" = [
      { bridge = "vmbr106", vlan_id = 106 }, # management
      { bridge = "vmbr107", vlan_id = 107 }  # public_traffic
    ]
    "auth-identity" = [
      { bridge = "vmbr106", vlan_id = 106 }, # management
      { bridge = "vmbr107", vlan_id = 107 }  # public_traffic
    ]
  }
}