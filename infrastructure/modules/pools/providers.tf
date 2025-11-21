# Provider configuration for Proxmox Resource Pools Module

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.45"
    }
  }
}