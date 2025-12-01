variable "global_config" {
  description = "Global configuration including environment"
  type = object({
    environment     = string
    resource_prefix = string
    proxmox_config = object({
      endpoint  = string
      api_token = string
      node_name = string
      datastore = string
    })
  })
}

variable "custom_images" {
  description = "Custom image definitions to override defaults"
  type = map(object({
    display_name = string
    os_type      = string
    os_version   = string
    image_id     = string
  }))
  default = {}
}

variable "custom_role_mappings" {
  description = "Custom role-to-image mappings"
  type        = map(string)
  default     = {}
}
