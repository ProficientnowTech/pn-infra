# VM Images Module
# Manages pre-baked VM images and provides role-to-image mappings

# Local image definitions for available pre-baked images
locals {
  # Available base OS images (these would be built by Packer)
  base_images = {
    "ubuntu-2204" = {
      display_name = "Ubuntu 22.04 LTS"
      os_type      = "ubuntu"
      os_version   = "22.04"
      image_id     = "ubuntu-2204-base"
    }
    "debian-12" = {
      display_name = "Debian 12"
      os_type      = "debian" 
      os_version   = "12"
      image_id     = "debian-12-base"
    }
  }

  # Role-to-image mappings
  role_images = {
    "k8s-master"     = "ubuntu-2204"
    "k8s-worker"     = "ubuntu-2204"
    "k8s-bootstrap"  = "ubuntu-2204"
    "k8s-worker-gpu" = "ubuntu-2204"
    "k8s-ceph-mon"   = "ubuntu-2204"
    "k8s-ceph-mgr"   = "ubuntu-2204"
    "k8s-ceph-osd"   = "ubuntu-2204"
    "ans-controller" = "ubuntu-2204"
    "fw-opnsense"    = "debian-12"
    "auth-identity"  = "ubuntu-2204"
  }
}

# Image registry configuration for VMs to reference
resource "local_file" "image_registry" {
  content = jsonencode({
    environment = var.global_config.environment
    base_images = local.base_images
    role_images = local.role_images
    created_at  = timestamp()
  })

  filename = "${path.root}/image-registry-${var.global_config.environment}.json"
}