########################################################################################################################
# Instances
########################################################################################################################
resource "exoscale_anti_affinity_group" "control" {
  name = "${var.cluster_name}-control"
}

resource "exoscale_instance_pool" "control" {
  name            = "${var.cluster_name}-control"
  zone            = var.zone
  instance_prefix = "${var.cluster_name}-control"

  size          = var.control_nodes_config.replicas
  template_id   = var.template_id
  instance_type = var.control_nodes_config.instance_type
  disk_size     = var.control_nodes_config.disk_size
  user_data     = var.user_data

  anti_affinity_group_ids = [exoscale_anti_affinity_group.control.id]
  security_group_ids      = var.security_group_ids
}
########################################################################################################################
# Load balancer
########################################################################################################################
resource "exoscale_nlb" "control" {
  name        = "${var.cluster_name}-control"
  zone        = var.zone
  description = "${var.cluster_name} control plane"
}

resource "exoscale_security_group_rule" "nlb_healthcheck" {
  for_each = {
    api                   = 6443
    machine_config_server = 22623
  }

  security_group_id     = var.node_security_group_id
  description           = "${var.cluster_name} load balancer health checks to ${each.key}"
  type                  = "INGRESS"
  protocol              = "TCP"
  public_security_group = "public-nlb-healthcheck-sources"
  start_port            = each.value
  end_port              = each.value
}

resource "exoscale_security_group_rule" "nlb_api" {
  security_group_id = var.node_security_group_id
  description       = "${var.cluster_name} control plane load balancer to kube-apiserver"
  type              = "INGRESS"
  protocol          = "TCP"
  cidr              = "${exoscale_nlb.control.ip_address}/32"
  start_port        = 6443
  end_port          = 6443
}

resource "exoscale_security_group_rule" "nlb_machine_config_server" {
  security_group_id = var.node_security_group_id
  description       = "${var.cluster_name} control plane load balancer to machine config server"
  type              = "INGRESS"
  protocol          = "TCP"
  cidr              = "${exoscale_nlb.control.ip_address}/32"
  start_port        = 22623
  end_port          = 22623
}

resource "exoscale_nlb_service" "api" {
  name             = "${var.cluster_name}-api"
  zone             = var.zone
  nlb_id           = exoscale_nlb.control.id
  instance_pool_id = exoscale_instance_pool.control.id
  port             = 6443
  target_port      = 6443
  protocol         = "tcp"
  strategy         = "round-robin"

  healthcheck {
    port     = 6443
    mode     = "tcp"
    interval = 10
    timeout  = 5
    retries  = 2
  }
}

resource "exoscale_nlb_service" "machine_config_server" {
  name             = "${var.cluster_name}-machine-config-server"
  zone             = var.zone
  nlb_id           = exoscale_nlb.control.id
  instance_pool_id = exoscale_instance_pool.control.id
  port             = 22623
  target_port      = 22623
  protocol         = "tcp"
  strategy         = "round-robin"

  healthcheck {
    port     = 22623
    mode     = "tcp"
    interval = 10
    timeout  = 5
    retries  = 2
  }
}
########################################################################################################################
# Ingress fallback
########################################################################################################################
# Without dedicated compute nodes the router runs on the control plane, so *.apps has to be served from here.
resource "exoscale_nlb_service" "http" {
  count            = var.compute_nodes_enabled ? 0 : 1
  name             = "${var.cluster_name}-http"
  zone             = var.zone
  nlb_id           = exoscale_nlb.control.id
  instance_pool_id = exoscale_instance_pool.control.id
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
  count            = var.compute_nodes_enabled ? 0 : 1
  name             = "${var.cluster_name}-https"
  zone             = var.zone
  nlb_id           = exoscale_nlb.control.id
  instance_pool_id = exoscale_instance_pool.control.id
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

resource "exoscale_security_group_rule" "nlb_router_healthcheck" {
  count             = var.compute_nodes_enabled ? 0 : 1
  security_group_id = var.node_security_group_id
  description       = "${var.cluster_name} control plane load balancer to router"
  type              = "INGRESS"
  protocol          = "TCP"
  cidr              = "${exoscale_nlb.control.ip_address}/32"
  start_port        = 80
  end_port          = 443
}

resource "exoscale_security_group_rule" "nlb_router_stats" {
  count             = var.compute_nodes_enabled ? 0 : 1
  security_group_id = var.node_security_group_id
  description       = "${var.cluster_name} control plane load balancer to router health port"
  type              = "INGRESS"
  protocol          = "TCP"
  cidr              = "${exoscale_nlb.control.ip_address}/32"
  start_port        = 1936
  end_port          = 1936
}

resource "exoscale_security_group_rule" "nlb_router_healthcheck_sources" {
  count                 = var.compute_nodes_enabled ? 0 : 1
  security_group_id     = var.node_security_group_id
  description           = "${var.cluster_name} load balancer health checks to router health port"
  type                  = "INGRESS"
  protocol              = "TCP"
  public_security_group = "public-nlb-healthcheck-sources"
  start_port            = 1936
  end_port              = 1936
}
