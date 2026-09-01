########################################################################################################################
# Outputs
########################################################################################################################
output "serenditree_endpoint" {
  value = exoscale_sks_cluster.serenditree.endpoint
}

output "serenditree_kubeconfig" {
  value = join("/", [path.cwd, local_sensitive_file.serenditree_kubeconfig_file.filename])
}
