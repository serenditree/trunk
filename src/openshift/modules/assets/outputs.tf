output "assets_dir" {
  description = "Directory openshift-install keeps its assets in."
  value       = local.assets_dir
}

output "kubeconfig" {
  description = "Path to the generated kubeconfig."
  value       = "${local.assets_dir}/auth/kubeconfig"
}

output "kubeadmin_password_file" {
  value = "${local.assets_dir}/auth/kubeadmin-password"
}

output "ignition_bootstrap" {
  description = "Stub ignition config pointing at the pre-signed bootstrap.ign."
  value       = data.local_file.bootstrap_stub.content
}

output "ignition_control" {
  value     = data.local_file.control_ignition.content
  sensitive = true
}

output "ignition_compute" {
  value     = data.local_file.compute_ignition.content
  sensitive = true
}

output "ignition_bucket" {
  value = var.ignition_bucket
}
