########################################################################################################################
# Instance
########################################################################################################################
resource "exoscale_compute_instance" "bootstrap" {
  count = var.bootstrap_enabled ? 1 : 0
  zone  = var.zone

  name        = "${var.cluster_name}-bootstrap"
  template_id = var.template_id
  type        = var.bootstrap_node_config.instance_type
  disk_size   = var.bootstrap_node_config.disk_size

  user_data          = var.user_data
  reverse_dns        = "bootstrap.${var.cluster_name}.${var.base_domain}."
  security_group_ids = var.security_group_ids

  # The pre-signed URL inside the stub is rotated whenever the assets are regenerated. Reacting to that would
  # recreate the node mid-bootstrap.
  lifecycle {
    ignore_changes = [user_data]
  }
}
