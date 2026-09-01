########################################################################################################################
# Init
########################################################################################################################
provider "exoscale" {
  key            = var.api_key
  secret         = var.api_secret
  timeout        = 120
  gzip_user_data = false
}

data "exoscale_domain" "base" {
  name = var.base_domain
}

data "exoscale_security_group" "default" {
  // ICMP, SSH, HTTP, HTTPS
  name = "default"
}
########################################################################################################################
# Bootstrap
########################################################################################################################
module "bootstrap" {
  source               = "modules/bootstrap"
  bootstrap_enabled    = var.bootstrap_enabled
  worker_nodes_enabled = var.worker_nodes_enabled

  zone         = var.zone
  base_domain  = data.exoscale_domain.base
  cluster_name = var.cluster_name

  ssh_key_pair              = var.ssh_key_pair
  default_security_group_id = data.exoscale_security_group.default.id

  bootstrap_node_config = var.master_nodes
  master_nodes_config   = var.master_nodes
  worker_nodes_config   = var.worker_nodes
}
########################################################################################################################
# Master
########################################################################################################################
module "master" {
  source               = "modules/master"
  depends_on           = [module.bootstrap]
  bootstrap_enabled    = var.bootstrap_enabled
  assets_dir           = module.bootstrap.assets_dir
  worker_nodes_enabled = var.worker_nodes_enabled

  zone         = var.zone
  base_domain  = data.exoscale_domain.base
  cluster_name = var.cluster_name

  ssh_key_pair              = var.ssh_key_pair
  default_security_group_id = data.exoscale_security_group.default.id

  master_nodes_config = var.master_nodes
  user_data           = module.bootstrap.ignition_master
}
########################################################################################################################
# Worker
########################################################################################################################
module "worker" {
  source               = "modules/worker"
  for_each             = { for node_group in var.worker_nodes : node_group.name => node_group }
  depends_on           = [module.master]
  worker_nodes_enabled = var.worker_nodes_enabled

  zone         = var.zone
  base_domain  = data.exoscale_domain.base
  cluster_name = var.cluster_name

  ssh_key_pair              = var.ssh_key_pair
  default_security_group_id = data.exoscale_security_group.default.id

  worker_nodes_config = each.value
  user_data           = module.bootstrap.ignition_worker

  kubeconfig = module.bootstrap.kubeconfig
}
########################################################################################################################
# Completion
########################################################################################################################
resource "terraform_data" "wait_for_install" {
  depends_on = [module.master, module.worker]
  provisioner "local-exec" {
    command = "openshift-install --dir=${module.bootstrap.assets_dir} wait-for install-complete"
  }
}
