########################################################################################################################
# Scaler
########################################################################################################################
resource "exoscale_iam_role" "serenditree_scaler" {
  count = var.auto_scaler == "autoscaler" ? 1 : 0

  name        = "serenditree-scaler"
  description = "Role that allows SKS autoscaling."
  editable    = false

  policy = {
    default_service_strategy = "deny"
    services = {
      compute = {
        type = "rules"
        rules = [
          {
            expression = "operation in ['get-instance', 'get-instance-pool']"
            action     = "allow"
          },
          {
            expression = "operation in ['list-sks-clusters', 'scale-sks-nodepool', 'evict-sks-nodepool-members']"
            action     = "allow"
          },
          {
            expression = "operation == 'get-quota'"
            action     = "allow"
          }
        ]
      }
    }
  }
}

resource "exoscale_iam_api_key" "serenditree_scaler" {
  count = var.auto_scaler == "autoscaler" ? 1 : 0

  name    = "serenditree-scaler"
  role_id = exoscale_iam_role.serenditree_scaler[count.index].id
}

resource "terraform_data" "serenditree_scaler" {
  count = var.auto_scaler == "autoscaler" ? 1 : 0

  provisioner "local-exec" {
    command = "./src/post-iam.sh"
    environment = {
      ACCESS = exoscale_iam_api_key.serenditree_scaler[count.index].key
      SECRET = exoscale_iam_api_key.serenditree_scaler[count.index].secret
      PREFIX = "serenditree/iam/scaler"
    }
  }
}
