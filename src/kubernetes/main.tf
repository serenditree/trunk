########################################################################################################################
# Init
########################################################################################################################
provider "exoscale" {
  key     = var.api_key
  secret  = var.api_secret
  timeout = 240
}
########################################################################################################################
# Gateway
########################################################################################################################
module "serenditree_gateway" {
  source = "./modules/gateway"
  providers = {
    exoscale = exoscale
  }

  name   = var.name
  zone   = var.zone_compute_1
  host   = var.host
  issuer = var.issuer
}
########################################################################################################################
# Private network
########################################################################################################################
resource "exoscale_private_network" "serenditree" {
  zone = var.zone_compute_1
  name = var.name

  netmask  = "255.255.252.0"
  start_ip = "172.16.0.20"
  end_ip   = "172.16.3.253"
}
########################################################################################################################
# Anti affinity
########################################################################################################################
resource "exoscale_anti_affinity_group" "serenditree" {
  for_each = var.compute_nodes

  name = "${var.name}-${each.key}"
}
########################################################################################################################
# Cluster
########################################################################################################################
resource "exoscale_sks_cluster" "serenditree" {
  name              = var.name
  version           = var.kubernetes_version
  cni               = var.cni
  zone              = var.zone_compute_1
  service_level     = var.service_level
  auto_upgrade      = var.auto_upgrade
  exoscale_csi      = var.csi
  exoscale_ccm      = true
  metrics_server    = true
  enable_kube_proxy = var.cni == "" ? false : true
  enable_karpenter  = startswith(var.auto_scaler, "karpenter")
}
########################################################################################################################
# Kubeconfig
########################################################################################################################
resource "exoscale_sks_kubeconfig" "serenditree_kubeconfig" {
  zone       = exoscale_sks_cluster.serenditree.zone
  cluster_id = exoscale_sks_cluster.serenditree.id

  user        = "kubeadmin/${var.name}"
  groups      = ["system:masters"]
  ttl_seconds = 2629800
}

resource "local_sensitive_file" "serenditree_kubeconfig_file" {
  filename        = "kubeconfig"
  content         = exoscale_sks_kubeconfig.serenditree_kubeconfig.kubeconfig
  file_permission = "0600"
}
########################################################################################################################
# Compute nodes
########################################################################################################################
resource "exoscale_sks_nodepool" "serenditree" {
  for_each = { for k, v in var.compute_nodes : k => v if var.auto_scaler != "karpenter-only" } # Keep type when empty

  zone            = var.zone_compute_1
  cluster_id      = exoscale_sks_cluster.serenditree.id
  name            = "${var.name}-${each.key}"
  instance_type   = each.value.instance_type
  size            = each.value.replicas
  disk_size       = each.value.disk_size
  instance_prefix = "${var.name}-${each.key}"

  labels = {
    "serenditree.io/stage"     = each.key
    "serenditree.io/node-role" = "root" # scheduling of root-pods
  }

  private_network_ids     = [exoscale_private_network.serenditree.id]
  security_group_ids      = [exoscale_security_group.serenditree.id]
  anti_affinity_group_ids = [exoscale_anti_affinity_group.serenditree[each.key].id]
}
