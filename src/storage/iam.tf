########################################################################################################################
# IAM roles/keys
########################################################################################################################
locals {
  backup_roles = toset(["user", "seed"])
}
########################################################################################################################
# Backup
########################################################################################################################
resource "exoscale_iam_role" "serenditree_backup" {
  for_each    = local.backup_roles
  name        = "serenditree-backup-${each.key}"
  description = "Role that allows backup and restore of databases to and from a single SOS bucket."
  editable    = false

  policy = {
    default_service_strategy = "deny"
    services = {
      sos = {
        type = "rules"
        rules = [
          {
            expression = "parameters.bucket != 'serenditree-backup-${each.key}'"
            action     = "deny"
          },
          {
            expression = "operation.matches('^[^-]+-object.*')"
            action     = "allow"
          }
        ]
      }
    }
  }
}

resource "exoscale_iam_api_key" "serenditree_backup" {
  for_each = local.backup_roles
  name     = "serenditree-backup-${each.key}"
  role_id  = exoscale_iam_role.serenditree_backup[each.key].id
}

resource "terraform_data" "serenditree_backup" {
  for_each = local.backup_roles

  provisioner "local-exec" {
    command = "./src/post-iam.sh"
    environment = {
      ACCESS = exoscale_iam_api_key.serenditree_backup[each.key].key
      SECRET = exoscale_iam_api_key.serenditree_backup[each.key].secret
      PREFIX = "serenditree/iam/backup-${each.key}"
    }
  }
}
########################################################################################################################
# Replication
########################################################################################################################
resource "exoscale_iam_role" "serenditree-replication" {
  name        = "serenditree-replication"
  description = "Rule that allows arbitrary SOS bucket replication."
  editable    = false

  policy = {
    default_service_strategy = "deny"
    services = {
      sos = {
        type = "allow"
      }
    }
  }
}
########################################################################################################################
# Data
########################################################################################################################
resource "exoscale_iam_role" "serenditree_data" {
  name        = "serenditree-data"
  description = "Role that allows retrieval of data from a single SOS bucket."
  editable    = false

  policy = {
    default_service_strategy = "deny"
    services = {
      sos = {
        type = "rules"
        rules = [
          {
            expression = "parameters.bucket != 'serenditree-data'"
            action     = "deny"
          },
          {
            expression = "operation in ['head-object', 'get-object']"
            action     = "allow"
          }
        ]
      }
    }
  }
}

resource "exoscale_iam_api_key" "serenditree_data" {
  name    = "serenditree-data"
  role_id = exoscale_iam_role.serenditree_data.id
}

resource "terraform_data" "serenditree_data" {
  provisioner "local-exec" {
    command = "./src/post-iam.sh"
    environment = {
      ACCESS = exoscale_iam_api_key.serenditree_data.key
      SECRET = exoscale_iam_api_key.serenditree_data.secret
      PREFIX = "serenditree/iam/data"
    }
  }
}
