# Variables for VM Nodes Module

variable "global_config" {
  description = "Global configuration including resource prefix and Proxmox settings"
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

variable "vm_roles" {
  description = "VM roles and their configurations from bootstrap"
  type = map(object({
    count   = number
    vm_size = string
  }))
}

variable "pool_ids" {
  description = "Map of pool names to their IDs from pools module"
  type        = map(string)
}

variable "template_ids" {
  description = "Map of VM size names to template IDs from templates module"
  type        = map(string)
}

variable "vm_sizes" {
  description = "VM size specifications from templates module"
  type = map(object({
    cpu_cores        = number
    memory_dedicated = number
    disk_size        = number
    description      = string
  }))
}

variable "images_by_role" {
  description = "Image information by role from images module"
  type = map(object({
    display_name = string
    os_type      = string
    os_version   = string
    image_id     = string
    role         = string
  }))
}

variable "vm_id_start" {
  description = "Starting VM ID for node deployment"
  type        = number
  default     = 2000
}