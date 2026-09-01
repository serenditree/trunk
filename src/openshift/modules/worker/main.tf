resource "exoscale_security_group" "worker" {
  count = var.worker_nodes_enabled ? 1 : 0
  name  = "serenditree-${var.cluster_name}-${var.worker_nodes_config.name}"
}

resource "exoscale_security_group_rules" "worker" {
  count             = var.worker_nodes_enabled ? 1 : 0
  security_group_id = exoscale_security_group.worker[0].id
  ingress {
    protocol  = "TCP"
    ports     = ["1936", "6443", "9000-9999", "10250-10259", "30000-32767"]
    cidr_list = ["0.0.0.0/0"]
  }
  ingress {
    protocol  = "UDP"
    ports     = ["4789", "6081", "9000-9999", "30000-32767"]
    cidr_list = ["0.0.0.0/0"]
  }
}

resource "exoscale_affinity" "worker" {
  count = var.worker_nodes_enabled ? 1 : 0
  name  = "serenditree-${var.cluster_name}-${var.worker_nodes_config.name}"
  type  = "host anti-affinity"
}

resource "exoscale_instance_pool" "worker" {
  count           = var.worker_nodes_enabled ? 1 : 0
  name            = "serenditree-${var.cluster_name}-${var.worker_nodes_config.name}"
  zone            = var.zone
  instance_prefix = "worker"

  size          = var.worker_nodes_config.replicas
  template_id   = var.worker_nodes_config.template_id
  instance_type = var.worker_nodes_config.instance_type
  disk_size     = var.worker_nodes_config.disk_size
  user_data     = var.user_data

  affinity_group_ids = [exoscale_affinity.worker[0].id]
  security_group_ids = [var.default_security_group_id, exoscale_security_group.worker[0].id]
  key_pair           = var.ssh_key_pair
}

resource "terraform_data" "approve_csr" {
  count = var.worker_nodes_enabled ? 1 : 0
  provisioner "local-exec" {
    command = "bash ${path.module}/src/csr.sh"
    environment = {
      RETRIES    = 42
      KUBECONFIG = var.kubeconfig
    }
  }
}

resource "exoscale_nlb" "worker" {
  count = var.worker_nodes_enabled ? 1 : 0
  zone  = var.zone
  name  = "serenditree-${var.cluster_name}-${var.worker_nodes_config.name}"
}

resource "exoscale_nlb_service" "worker_http" {
  count            = var.worker_nodes_enabled ? 1 : 0
  name             = "serenditree-${var.cluster_name}-${var.worker_nodes_config.name}-http"
  nlb_id           = exoscale_nlb.worker[0].id
  zone             = var.zone
  instance_pool_id = exoscale_instance_pool.worker[0].id
  port             = 80
  target_port      = 80
  protocol         = "tcp"
  strategy         = "round-robin"

  healthcheck {
    port     = 80
    mode     = "tcp"
    interval = 5
    timeout  = 3
    retries  = 1
  }
}

resource "exoscale_nlb_service" "worker_https" {
  count            = var.worker_nodes_enabled ? 1 : 0
  name             = "serenditree-${var.cluster_name}-${var.worker_nodes_config.name}-https"
  nlb_id           = exoscale_nlb.worker[0].id
  zone             = var.zone
  instance_pool_id = exoscale_instance_pool.worker[0].id
  port             = 443
  target_port      = 443
  protocol         = "tcp"
  strategy         = "round-robin"

  healthcheck {
    port     = 443
    mode     = "tcp"
    interval = 5
    timeout  = 3
    retries  = 1
  }
}

resource "exoscale_domain_record" "worker" {
  count       = var.worker_nodes_enabled ? 1 : 0
  name        = "*.${var.worker_nodes_config.name}.${var.cluster_name}"
  domain      = var.base_domain.id
  record_type = "A"
  ttl         = 3600
  content     = exoscale_nlb.worker[0].ip_address
}
