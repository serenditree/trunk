########################################################################################################################
# Init
########################################################################################################################
provider "exoscale" {
  key     = var.api_key
  secret  = var.api_secret
  timeout = 240
}

locals {
  cluster_domain = "${var.cluster_name}.${var.base_domain}"

  compute_enabled           = var.compute_nodes_enabled && !var.bootstrap_enabled
  compute_replicas_by_group = { for group in var.compute_nodes : group.name => group.replicas }

  # Default ingress group is the first group of compute nodes. The number of ingress replicase is used to have one
  # ingress service per node and all health checks succeed.
  ingress_group_name = var.compute_nodes_enabled ? (var.ingress_node_group != "" ? var.ingress_node_group : var.compute_nodes[0].name) : ""
  ingress_replicas   = var.compute_nodes_enabled ? lookup(local.compute_replicas_by_group, local.ingress_group_name, var.compute_nodes[0].replicas) : var.control_nodes.replicas
  ingress_enabled    = local.compute_enabled || !var.compute_nodes_enabled
  ingress_group      = local.compute_enabled ? local.ingress_group_name : ""
  ingress_ip         = local.compute_enabled ? module.compute[local.ingress_group].nlb_ip_address : module.control.nlb_ip_address

  csi_name = replace("${var.cluster_name}-${var.base_domain}-csi", ".", "-")
  csi_operations = [
    "attach-block-storage-volume-to-instance",
    "create-block-storage-snapshot",
    "create-block-storage-volume",
    "delete-block-storage-snapshot",
    "delete-block-storage-volume",
    "detach-block-storage-volume",
    "get-block-storage-snapshot",
    "get-block-storage-volume",
    "list-block-storage-snapshots",
    "list-block-storage-volumes",
    "list-quotas",
    "list-zones",
    "resize-block-storage-volume",
    "update-block-storage-volume-labels"
  ]
}

data "exoscale_domain" "base" {
  name = var.base_domain
}
########################################################################################################################
# Image
########################################################################################################################
module "image" {
  source = "./modules/image"

  api_key    = var.api_key
  api_secret = var.api_secret
  zone       = var.zone

  manage_template    = var.manage_template
  template_name      = var.template_name
  template_bucket    = var.template_bucket
  template_disk_size = var.template_disk_size
}
########################################################################################################################
# Assets
########################################################################################################################
module "assets" {
  source = "./modules/assets"

  api_key    = var.api_key
  api_secret = var.api_secret
  zone       = var.zone

  ssh_public_key_file = var.ssh_public_key_file
  pull_secret_file    = var.pull_secret_file

  cluster_name                = var.cluster_name
  base_domain                 = var.base_domain
  cluster_network             = var.cluster_network
  cluster_network_host_prefix = var.cluster_network_host_prefix
  service_network             = var.service_network
  network_type                = var.network_type
  fips                        = var.fips

  control_nodes_config = {
    name           = var.control_nodes.name
    replicas       = var.control_nodes.replicas
    hyperthreading = var.control_nodes.hyperthreading
    architecture   = var.control_nodes.architecture
  }

  compute_nodes_enabled = var.compute_nodes_enabled
  compute_nodes_config = [
    for group in var.compute_nodes : {
      name           = group.name
      replicas       = group.replicas
      hyperthreading = group.hyperthreading
      architecture   = group.architecture
    }
  ]

  ingress_replicas = local.ingress_replicas

  ignition_bucket  = var.ignition_bucket
  ignition_url_ttl = var.ignition_url_ttl
}
########################################################################################################################
# Bootstrap
########################################################################################################################
module "bootstrap" {
  source = "./modules/bootstrap"

  zone         = var.zone
  template_id  = module.image.template_id
  cluster_name = var.cluster_name
  base_domain  = var.base_domain

  security_group_ids = [exoscale_security_group.node.id]

  bootstrap_enabled     = var.bootstrap_enabled
  bootstrap_node_config = var.bootstrap_node
  user_data             = module.assets.ignition_bootstrap
}
########################################################################################################################
# Control plane
########################################################################################################################
module "control" {
  source = "./modules/control"

  zone         = var.zone
  template_id  = module.image.template_id
  cluster_name = var.cluster_name

  security_group_ids     = [exoscale_security_group.node.id]
  node_security_group_id = exoscale_security_group.node.id

  control_nodes_config  = var.control_nodes
  compute_nodes_enabled = var.compute_nodes_enabled
  user_data             = module.assets.ignition_control
}
########################################################################################################################
# Compute
########################################################################################################################
module "compute" {
  source     = "./modules/compute"
  for_each   = local.compute_enabled ? { for group in var.compute_nodes : group.name => group } : {}
  depends_on = [exoscale_domain_record.api_int]

  zone         = var.zone
  template_id  = module.image.template_id
  cluster_name = var.cluster_name

  security_group_ids     = [exoscale_security_group.node.id]
  node_security_group_id = exoscale_security_group.node.id

  compute_nodes_config = each.value
  user_data            = module.assets.ignition_compute
}
########################################################################################################################
# Bootstrap phase
########################################################################################################################
resource "exoscale_domain_record" "bootstrap" {
  count = var.bootstrap_enabled ? 1 : 0

  name        = "bootstrap.${var.cluster_name}"
  domain      = data.exoscale_domain.base.id
  record_type = "A"
  ttl         = 60
  content     = module.bootstrap.ip_address
}

resource "terraform_data" "wait_for_handover" {
  count      = var.bootstrap_enabled ? 1 : 0
  depends_on = [module.control, exoscale_domain_record.api, exoscale_domain_record.api_int]

  provisioner "local-exec" {
    command = "bash ${path.module}/src/handover.sh"
    environment = {
      KUBECONFIG          = module.assets.kubeconfig
      EXPECTED_NODE_COUNT = var.control_nodes.replicas
      BOOTSTRAP_IP        = module.bootstrap.ip_address
    }
  }
}
########################################################################################################################
# API
########################################################################################################################
resource "exoscale_domain_record" "api" {
  name        = "api.${var.cluster_name}"
  domain      = data.exoscale_domain.base.id
  record_type = "A"
  ttl         = 300
  content     = module.control.nlb_ip_address
}

resource "exoscale_domain_record" "api_int" {
  name        = "api-int.${var.cluster_name}"
  domain      = data.exoscale_domain.base.id
  record_type = "A"
  ttl         = var.bootstrap_enabled ? 60 : 300
  content     = var.bootstrap_enabled ? module.bootstrap.ip_address : module.control.nlb_ip_address
}

resource "exoscale_domain_record" "apps" {
  count = local.ingress_enabled ? 1 : 0

  name        = "*.apps.${var.cluster_name}"
  domain      = data.exoscale_domain.base.id
  record_type = "A"
  ttl         = 300
  content     = local.ingress_ip

  lifecycle {
    precondition {
      condition     = !local.compute_enabled || contains([for group in var.compute_nodes : group.name], local.ingress_group)
      error_message = "ingress_node_group must name one of the groups in compute_nodes."
    }
  }
}
########################################################################################################################
# Completion
########################################################################################################################
resource "terraform_data" "approve_csr" {
  count      = var.bootstrap_enabled ? 0 : 1
  depends_on = [module.compute, exoscale_domain_record.api_int]

  triggers_replace = {
    control = join(",", sort(module.control.instance_ids))
    compute = join(",", sort(flatten([for group in module.compute : group.instance_ids])))
  }

  provisioner "local-exec" {
    command = "bash ${path.module}/src/csr.sh"
    environment = {
      KUBECONFIG          = module.assets.kubeconfig
      EXPECTED_NODE_COUNT = var.control_nodes.replicas + (local.compute_enabled ? sum([for group in var.compute_nodes : group.replicas]) : 0)
    }
  }
}

resource "terraform_data" "wait_for_install" {
  count      = var.bootstrap_enabled ? 0 : 1
  depends_on = [terraform_data.approve_csr, exoscale_domain_record.apps]

  provisioner "local-exec" {
    command = "openshift-install --dir='${module.assets.assets_dir}' wait-for install-complete"
  }
}

resource "terraform_data" "delete_ignition" {
  count      = var.bootstrap_enabled ? 0 : 1
  depends_on = [terraform_data.wait_for_install]

  provisioner "local-exec" {
    command = "exo storage rb --recursive --force 'sos://${var.ignition_bucket}'"
  }
}
########################################################################################################################
# Block Storage
########################################################################################################################
resource "exoscale_iam_role" "csi" {
  count = var.csi_driver.enabled ? 1 : 0

  name        = local.csi_name
  description = "Exoscale Block Storage CSI driver of the ${local.cluster_domain} cluster."

  policy = {
    default_service_strategy = "deny"
    services = {
      compute = {
        type = "rules"
        rules = [
          {
            expression = "operation in ['${join("', '", local.csi_operations)}']"
            action     = "allow"
          }
        ]
      }
    }
  }
}

resource "exoscale_iam_api_key" "csi" {
  count = var.csi_driver.enabled ? 1 : 0

  name    = local.csi_name
  role_id = exoscale_iam_role.csi[0].id
}

resource "terraform_data" "csi_driver" {
  count      = var.bootstrap_enabled || !var.csi_driver.enabled ? 0 : 1
  depends_on = [terraform_data.wait_for_install]

  triggers_replace = {
    csi_driver = jsonencode(var.csi_driver)
    api_key    = exoscale_iam_api_key.csi[0].key
  }

  provisioner "local-exec" {
    command = "bash ${path.module}/src/csi.sh"
    environment = {
      KUBECONFIG        = module.assets.kubeconfig
      CSI_STORAGE_CLASS = var.csi_driver.storage_class
      CSI_DEFAULT_CLASS = var.csi_driver.default_class
      CSI_API_KEY       = exoscale_iam_api_key.csi[0].key
      CSI_API_SECRET    = nonsensitive(exoscale_iam_api_key.csi[0].secret)
    }
  }
}
########################################################################################################################
# Operators
########################################################################################################################
resource "terraform_data" "operators" {
  count      = var.bootstrap_enabled || length(var.operators) == 0 ? 0 : 1
  depends_on = [terraform_data.wait_for_install, terraform_data.csi_driver]

  triggers_replace = {
    operators = jsonencode(var.operators)
  }

  provisioner "local-exec" {
    command = "bash ${path.module}/src/operators.sh"
    environment = {
      KUBECONFIG = module.assets.kubeconfig
      OPERATORS  = jsonencode(var.operators)
    }
  }
}
