########################################################################################################################
# Init
########################################################################################################################
locals {
  config_template = abspath("${path.module}/rc/install-config.yaml")
  assets_dir      = abspath("${path.module}/assets/${var.cluster_name}")

  # Additional node config values (instance-type, disk-size,...) are ignored by openshift-install.
  control_plane = yamlencode({ controlPlane = var.master_nodes_config })
  compute = yamlencode({
    compute = var.worker_nodes_enabled ? var.worker_nodes_config : [
      {
        name     = "worker"
        replicas = 0
      }
    ]
  })
}
########################################################################################################################
# Assets
########################################################################################################################
resource "terraform_data" "create_assets" {
  count = var.bootstrap_enabled ? 1 : 0
  provisioner "local-exec" {
    command = "bash ${path.module}/src/assets.sh"
    environment = {
      CONFIG_TEMPLATE       = local.config_template
      ASSETS_DIR            = local.assets_dir
      EXOSCALE_ZONE         = var.zone
      EXOSCALE_SOS          = "sos://okd"
      CLUSTER_NAME          = var.cluster_name
      BASE_DOMAIN           = var.base_domain.name
      CONTROL_PLANE         = local.control_plane
      COMPUTE               = local.compute
      COMPUTE_NODES_ENABLED = var.worker_nodes_enabled
    }
  }
}

data "ignition_config" "remote_ignition" {
  count      = var.bootstrap_enabled ? 1 : 0
  depends_on = [terraform_data.create_assets]
  replace {
    source       = trimspace(file("${local.assets_dir}/bootstrap.src"))
    verification = filesha512("${local.assets_dir}/bootstrap.ign")
  }
}
########################################################################################################################
# Instance
########################################################################################################################
resource "exoscale_security_group" "bootstrap" {
  count = var.bootstrap_enabled ? 1 : 0
  name  = "serenditree-${var.cluster_name}-bootstrap"
}

resource "exoscale_security_group_rules" "bootstrap" {
  count             = var.bootstrap_enabled ? 1 : 0
  security_group_id = exoscale_security_group.bootstrap[0].id
  ingress {
    protocol  = "TCP"
    ports     = ["6443", "1936", "9000-9999", "10250-10259", "22623", "30000-32767"]
    cidr_list = ["0.0.0.0/0"]
  }
  ingress {
    protocol  = "UDP"
    ports     = ["4789", "6081", "9000-9999", "30000-32767"]
    cidr_list = ["0.0.0.0/0"]
  }
}

resource "exoscale_compute" "bootstrap" {
  count      = var.bootstrap_enabled ? 1 : 0
  depends_on = [terraform_data.create_assets, exoscale_security_group_rules.bootstrap]
  zone       = var.zone

  display_name = "bootstrap"
  template_id  = var.bootstrap_node_config.template_id
  size         = replace(var.bootstrap_node_config.instance_type, "/^.*\\./", "")
  disk_size    = var.bootstrap_node_config.disk_size

  user_data = file("${local.assets_dir}/bootstrap.remote.ign")
  //  user_data = data.ignition_config.remote_ignition[0].rendered
  //  user_data = jsonencode({
  //    version = "3.2.0"
  //    ignition = {
  //      config = {
  //        replace = {
  //          source = trimspace(file("${local.assets_dir}/bootstrap.src"))
  //        }
  //      }
  //    }
  //  })

  reverse_dns        = "bootstrap.${var.cluster_name}.${var.base_domain.name}."
  security_group_ids = [var.default_security_group_id, exoscale_security_group.bootstrap[0].id]
  key_pair           = var.ssh_key_pair
  lifecycle {
    ignore_changes = [user_data]
  }
}

resource "terraform_data" "wait_for_cluster" {
  count = var.bootstrap_enabled ? 1 : 0
  provisioner "local-exec" {
    command = "until curl -ks https://${exoscale_compute.bootstrap[0].ip_address}:6443/readyz; do sleep 5s; done"
  }
}

resource "exoscale_domain_record" "bootstrap" {
  count       = var.bootstrap_enabled ? 1 : 0
  name        = "bootstrap.${var.cluster_name}"
  domain      = var.base_domain.id
  record_type = "A"
  ttl         = 60
  content     = exoscale_compute.bootstrap[0].ip_address
}

resource "exoscale_domain_record" "api" {
  count       = var.bootstrap_enabled ? 1 : 0
  name        = "api.${var.cluster_name}"
  domain      = var.base_domain.id
  record_type = "A"
  ttl         = 60
  content     = exoscale_compute.bootstrap[0].ip_address
}

resource "exoscale_domain_record" "api_int" {
  count       = var.bootstrap_enabled ? 1 : 0
  name        = "api-int.${var.cluster_name}"
  domain      = var.base_domain.id
  record_type = "A"
  ttl         = 60
  content     = exoscale_compute.bootstrap[0].ip_address
}
