resource "exoscale_security_group" "master" {
  name = "serenditree-${var.cluster_name}-master"
}

resource "exoscale_security_group_rules" "master" {
  security_group_id = exoscale_security_group.master.id
  ingress {
    protocol  = "TCP"
    cidr_list = ["0.0.0.0/0"]
    ports     = ["1936", "2379-2380", "6443", "9000-9999", "10250-10259", "30000-32767"]
  }
  ingress {
    protocol  = "UDP"
    cidr_list = ["0.0.0.0/0"]
    ports     = ["4789", "6081", "9000-9999", "30000-32767"]
  }
}

resource "exoscale_affinity" "master" {
  name = "serenditree-${var.cluster_name}-master"
  type = "host anti-affinity"
}

resource "exoscale_instance_pool" "master" {
  name            = "serenditree-${var.cluster_name}-master"
  zone            = var.zone
  instance_prefix = "master"

  size          = var.master_nodes_config.replicas
  template_id   = var.master_nodes_config.template_id
  instance_type = var.master_nodes_config.instance_type
  disk_size     = var.master_nodes_config.disk_size
  user_data     = var.user_data

  affinity_group_ids = [exoscale_affinity.master.id]
  security_group_ids = [var.default_security_group_id, exoscale_security_group.master.id]
  key_pair           = var.ssh_key_pair
}

resource "exoscale_nlb" "master" {
  name = "serenditree-${var.cluster_name}-master"
  zone = var.zone
}

resource "exoscale_nlb_service" "master_api" {
  name             = "master-api-${var.cluster_name}"
  zone             = var.zone
  nlb_id           = exoscale_nlb.master.id
  instance_pool_id = exoscale_instance_pool.master.id
  port             = 6443
  target_port      = 6443
  protocol         = "tcp"
  strategy         = "round-robin"
  healthcheck {
    port     = 6443
    mode     = "tcp"
    interval = 5
    timeout  = 3
    retries  = 1
  }
}

resource "exoscale_nlb_service" "master_machine_config_server" {
  name             = "master-machine-config-server-${var.cluster_name}"
  nlb_id           = exoscale_nlb.master.id
  zone             = var.zone
  instance_pool_id = exoscale_instance_pool.master.id
  port             = 22623
  target_port      = 22623
  protocol         = "tcp"
  strategy         = "round-robin"

  healthcheck {
    port     = 22623
    mode     = "tcp"
    interval = 5
    timeout  = 3
    retries  = 1
  }
}

resource "exoscale_nlb_service" "master_http" {
  count            = var.worker_nodes_enabled ? 0 : 1
  name             = "serenditree-${var.cluster_name}-http"
  nlb_id           = exoscale_nlb.master.id
  zone             = var.zone
  instance_pool_id = exoscale_instance_pool.master.id
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

resource "exoscale_nlb_service" "master_https" {
  count            = var.worker_nodes_enabled ? 0 : 1
  name             = "serenditree-${var.cluster_name}-https"
  nlb_id           = exoscale_nlb.master.id
  zone             = var.zone
  instance_pool_id = exoscale_instance_pool.master.id
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

resource "terraform_data" "wait_for_bootstrap" {
  count      = var.bootstrap_enabled ? 1 : 0
  provisioner "local-exec" {
    command = "openshift-install --dir=${var.assets_dir} wait-for bootstrap-complete"
  }
}

resource "exoscale_domain_record" "api" {
  depends_on = [terraform_data.wait_for_bootstrap]

  name        = "api.${var.cluster_name}"
  domain      = var.base_domain.id
  record_type = "A"
  ttl         = 3600
  content     = exoscale_nlb.master.ip_address
}

resource "exoscale_domain_record" "api_int" {
  depends_on = [terraform_data.wait_for_bootstrap]

  name        = "api-int.${var.cluster_name}"
  domain      = var.base_domain.id
  record_type = "A"
  ttl         = 3600
  content     = exoscale_nlb.master.ip_address
}

resource "exoscale_domain_record" "apps" {
  count       = var.worker_nodes_enabled ? 0 : 1
  name        = "*.apps.${var.cluster_name}"
  domain      = var.base_domain.id
  record_type = "A"
  ttl         = 3600
  content     = exoscale_nlb.master.ip_address
}
