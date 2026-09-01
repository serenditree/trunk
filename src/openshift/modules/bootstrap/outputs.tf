output "assets_dir" {
  value = local.assets_dir
}

output "install_config_yaml" {
  value = file("${local.assets_dir}/install-config.bak.yaml")
}

output "ignition_master" {
  value = file("${local.assets_dir}/master.ign")
}

output "ignition_master_rendered" {
  value = data.ignition_config.remote_ignition[0].rendered
}

output "ignition_worker" {
  value = file("${local.assets_dir}/worker.ign")
}

output "kubeconfig" {
  value = "${local.assets_dir}/auth/kubeconfig"
}
