# Variables for Proxmox Resource Pools Module

variable "pools" {
  description = "List of pool names to create"
  type        = list(string)
  default     = ["k8s-platform"]
}

variable "global_config" {
  description = "Global configuration including resource prefix"
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