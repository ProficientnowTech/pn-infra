# Generated from images module environment config
# Environment: development

global_config = {
  environment     = "development"
  resource_prefix = "development-images"
  proxmox_config = {
    endpoint  = "https://proxmox.dev.local:8006/api2/json"
    api_token = "null"
    node_name = "pve-dev"
    datastore = "local-lvm"
  }
}

custom_images = {}

custom_role_mappings = {}
