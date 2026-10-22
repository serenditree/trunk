########################################################################################################################
# Init
########################################################################################################################
locals {
  assets_dir = abspath("${path.root}/.assets/${var.cluster_name}")

  compute_replicas = var.compute_nodes_enabled ? sum([for group in var.compute_nodes_config : group.replicas]) : 0

  networking = {
    networkType    = var.network_type
    clusterNetwork = [{ cidr = var.cluster_network, hostPrefix = var.cluster_network_host_prefix }]
    serviceNetwork = [var.service_network]
  }

  install_config = {
    apiVersion = "v1"
    baseDomain = var.base_domain
    metadata   = { name = var.cluster_name }
    controlPlane = {
      # The pool names are fixed by openshift-install: "master" for the control plane, "worker" for compute.
      name           = "master"
      replicas       = var.control_nodes_config.replicas
      hyperthreading = var.control_nodes_config.hyperthreading
      architecture   = var.control_nodes_config.architecture
    }
    compute = [{
      name           = "worker"
      replicas       = local.compute_replicas
      hyperthreading = var.compute_nodes_enabled ? var.compute_nodes_config[0].hyperthreading : "Enabled"
      architecture   = var.compute_nodes_enabled ? var.compute_nodes_config[0].architecture : var.control_nodes_config.architecture
    }]
    networking = local.networking
    platform   = { none = {} }
    fips       = var.fips
  }
}
########################################################################################################################
# Assets
########################################################################################################################
resource "terraform_data" "assets" {
  triggers_replace = {
    install_config = jsonencode(local.install_config)
    bucket         = var.ignition_bucket
  }

  provisioner "local-exec" {
    command = "bash ${path.module}/src/assets.sh"
    environment = {
      EXOSCALE_ZONE = var.zone

      ASSETS_DIR          = local.assets_dir
      INSTALL_CONFIG      = jsonencode(local.install_config)
      PULL_SECRET_FILE    = pathexpand(var.pull_secret_file)
      SSH_PUBLIC_KEY_FILE = pathexpand(var.ssh_public_key_file)

      CONTROL_PLANE_SCHEDULABLE = var.compute_nodes_enabled ? "false" : "true"
      INGRESS_REPLICAS          = var.ingress_replicas

      IGNITION_BUCKET  = var.ignition_bucket
      IGNITION_URL_TTL = var.ignition_url_ttl
    }
  }
}
########################################################################################################################
# Generated files
########################################################################################################################
data "local_file" "bootstrap_stub" {
  depends_on = [terraform_data.assets]
  filename   = "${local.assets_dir}/bootstrap.remote.ign"
}

data "local_file" "control_ignition" {
  depends_on = [terraform_data.assets]
  filename   = "${local.assets_dir}/master.ign"
}

data "local_file" "compute_ignition" {
  depends_on = [terraform_data.assets]
  filename   = "${local.assets_dir}/worker.ign"
}
