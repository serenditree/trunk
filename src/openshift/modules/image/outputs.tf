output "template_id" {
  description = "Identifier of the RHCOS template the nodes boot from."
  value       = trimspace(data.local_file.template_id.content)
}

output "template_name" {
  value = local.name
}

output "template_bucket" {
  value = var.template_bucket
}

output "release" {
  description = "RHCOS release the local openshift-install expects."
  value       = local.release
}
