# Outputs for VM Images Module

output "base_images" {
  description = "Available base OS images"
  value       = local.base_images
}

output "role_image_mappings" {
  description = "Mapping of roles to their corresponding base images"
  value       = local.role_images
}

output "image_registry_file" {
  description = "Path to the generated image registry file"
  value       = local_file.image_registry.filename
}

output "images_by_role" {
  description = "Complete image information by role"
  value = {
    for role, image_key in local.role_images : role => merge(
      local.base_images[image_key],
      { role = role }
    )
  }
}