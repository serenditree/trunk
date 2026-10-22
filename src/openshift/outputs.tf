output "zone" {
  value = var.zone
}

output "cluster_domain" {
  description = "Domain the cluster is reachable under."
  value       = local.cluster_domain
}

output "console_url" {
  value = "https://console-openshift-console.apps.${local.cluster_domain}"
}

output "api_url" {
  value = "https://api.${local.cluster_domain}:6443"
}

output "api_cidr" {
  description = "Networks allowed to reach the Kubernetes API."
  value       = var.api_cidr
}

output "assets_dir" {
  description = "The openshift-install state directory. Keep it - destroying the cluster needs it."
  value       = module.assets.assets_dir
}

output "kubeconfig" {
  description = "export KUBECONFIG=<this> to talk to the cluster."
  value       = module.assets.kubeconfig
}

output "kubeadmin_password_file" {
  description = "Initial password for the kubeadmin user."
  value       = module.assets.kubeadmin_password_file
}

output "csi_api_key" {
  description = "IAM key the CSI driver authenticates with."
  value       = one(exoscale_iam_api_key.csi[*].key)
}

output "csi_api_secret" {
  description = "Secret of the CSI driver's IAM key."
  value       = one(exoscale_iam_api_key.csi[*].secret)
  sensitive   = true
}

output "rhcos_release" {
  description = "RHCOS build the nodes boot from."
  value       = module.image.release
}

output "template_name" {
  value = module.image.template_name
}

output "template_bucket" {
  value = module.image.template_bucket
}

output "ignition_bucket" {
  description = "SOS bucket holding bootstrap.ign."
  value       = module.assets.ignition_bucket
}

output "control_plane_ip" {
  description = "Control plane load balancer address."
  value       = module.control.nlb_ip_address
}

output "ingress_ip" {
  description = "Address *.apps resolves to."
  value       = local.ingress_ip
}

output "bootstrap_ip" {
  description = "Bootstrap node address."
  value       = module.bootstrap.ip_address
}
