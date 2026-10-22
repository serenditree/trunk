########################################################################################################################
# Init
########################################################################################################################
locals {
  name = "${var.cluster_name}-${var.compute_nodes_config.name}"
}
########################################################################################################################
# Instances
########################################################################################################################
resource "exoscale_anti_affinity_group" "compute" {
  name        = local.name
  description = "Spreads the ${local.name} node group across hypervisors."
}

resource "exoscale_instance_pool" "compute" {
  name            = local.name
  zone            = var.zone
  instance_prefix = local.name

  size          = var.compute_nodes_config.replicas
  template_id   = var.template_id
  instance_type = var.compute_nodes_config.instance_type
  disk_size     = var.compute_nodes_config.disk_size
  user_data     = var.user_data

  anti_affinity_group_ids = [exoscale_anti_affinity_group.compute.id]
  security_group_ids      = var.security_group_ids
}
########################################################################################################################
# Load balancer
########################################################################################################################
# Every group gets its own load balancer. Which one *.apps points at is decided by the root module.
resource "exoscale_nlb" "compute" {
  name        = local.name
  zone        = var.zone
  description = "${local.name} ingress"
}

resource "exoscale_security_group_rule" "nlb_router" {
  security_group_id = var.node_security_group_id
  description       = "${local.name} load balancer to router"
  type              = "INGRESS"
  protocol          = "TCP"
  cidr              = "${exoscale_nlb.compute.ip_address}/32"
  start_port        = 80
  end_port          = 443
}

resource "exoscale_security_group_rule" "nlb_router_stats" {
  security_group_id = var.node_security_group_id
  description       = "${local.name} load balancer to router health port"
  type              = "INGRESS"
  protocol          = "TCP"
  cidr              = "${exoscale_nlb.compute.ip_address}/32"
  start_port        = 1936
  end_port          = 1936
}

resource "exoscale_security_group_rule" "nlb_router_healthcheck_sources" {
  security_group_id     = var.node_security_group_id
  description           = "${local.name} load balancer health checks to router health port"
  type                  = "INGRESS"
  protocol              = "TCP"
  public_security_group = "public-nlb-healthcheck-sources"
  start_port            = 1936
  end_port              = 1936
}

resource "exoscale_nlb_service" "http" {
  name             = "${local.name}-http"
  zone             = var.zone
  nlb_id           = exoscale_nlb.compute.id
  instance_pool_id = exoscale_instance_pool.compute.id
  port             = 80
  target_port      = 80
  protocol         = "tcp"
  strategy         = "round-robin"

  healthcheck {
    port     = 1936
    mode     = "http"
    uri      = "/healthz"
    interval = 10
    timeout  = 5
    retries  = 2
  }
}

resource "exoscale_nlb_service" "https" {
  name             = "${local.name}-https"
  zone             = var.zone
  nlb_id           = exoscale_nlb.compute.id
  instance_pool_id = exoscale_instance_pool.compute.id
  port             = 443
  target_port      = 443
  protocol         = "tcp"
  strategy         = "round-robin"

  healthcheck {
    port     = 1936
    mode     = "http"
    uri      = "/healthz"
    interval = 10
    timeout  = 5
    retries  = 2
  }
}
