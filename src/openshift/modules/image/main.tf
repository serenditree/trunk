########################################################################################################################
# Init
########################################################################################################################
data "external" "stream" {
  program = ["bash", "${path.module}/src/rhcos-stream.sh"]
}

locals {
  release = data.external.stream.result.release
  name    = var.template_name != "" ? var.template_name : "RHCOS-${local.release}"
  work    = abspath("${path.root}/.image")
}
########################################################################################################################
# Registration
########################################################################################################################
resource "terraform_data" "template" {
  triggers_replace = {
    release   = local.release
    name      = local.name
    zone      = var.zone
    disk_size = var.template_disk_size
    managed   = var.manage_template
  }

  provisioner "local-exec" {
    command = "bash ${path.module}/src/register-template.sh"
    environment = {
      EXOSCALE_ZONE      = var.zone
      TEMPLATE_NAME      = local.name
      TEMPLATE_BUCKET    = var.template_bucket
      TEMPLATE_DISK_SIZE = var.template_disk_size
      MANAGE_TEMPLATE    = var.manage_template
      RELEASE            = local.release
      IMAGE_URL          = data.external.stream.result.url
      IMAGE_SHA256       = data.external.stream.result.sha256
      DISK_SHA256        = data.external.stream.result.uncompressed_sha256
      WORK_DIR           = local.work
      ID_FILE            = "${local.work}/${local.name}.id"
    }
  }
}

data "local_file" "template_id" {
  depends_on = [terraform_data.template]
  filename   = "${local.work}/${local.name}.id"
}
