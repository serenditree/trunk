########################################################################################################################
# S3 Config
########################################################################################################################
provider "aws" {
  alias = "src"
  endpoints {
    s3 = "https://sos-${var.zone_storage_1}.exo.io"
  }
  region                      = var.zone_storage_1
  access_key                  = var.api_key
  secret_key                  = var.api_secret
  skip_credentials_validation = true
  skip_region_validation      = true
  skip_requesting_account_id  = true
}

provider "aws" {
  alias = "dest"
  endpoints {
    s3 = "https://sos-${var.zone_storage_2}.exo.io"
  }
  region                      = var.zone_storage_2
  access_key                  = var.api_key
  secret_key                  = var.api_secret
  skip_credentials_validation = true
  skip_region_validation      = true
  skip_requesting_account_id  = true
}
########################################################################################################################
# Data
########################################################################################################################
resource "aws_s3_bucket" "serenditree_data" {
  provider = aws.src
  count    = var.storage_data == "" ? 0 : 1
  bucket   = var.storage_data

  force_destroy = false
}
########################################################################################################################
# Backup
########################################################################################################################
locals {
  replica_suffix = "replica"
}

module "serenditree_backup" {
  source = "./modules/backup"
  providers = {
    aws = aws.src
  }

  backup_buckets   = var.storage_backup
  backup_lifecycle = var.storage_backup_lifecycle
}

module "serenditree_backup_replica" {
  source = "./modules/backup"
  providers = {
    aws = aws.dest
  }

  backup_buckets   = toset([for id, bucket in var.storage_backup : "${bucket}-${local.replica_suffix}"])
  backup_lifecycle = var.storage_backup_lifecycle
}

resource "aws_s3_bucket_replication_configuration" "serenditree_backup_replication" {
  provider   = aws.src
  for_each   = module.serenditree_backup.buckets
  depends_on = [module.serenditree_backup, module.serenditree_backup_replica]

  bucket = module.serenditree_backup.buckets[each.key].id
  role   = "arn:aws:iam::third-party:${exoscale_iam_role.serenditree-replication.id}"

  rule {
    id       = "${module.serenditree_backup.buckets[each.key].id}-replication"
    status   = "Enabled"
    priority = 1

    filter {
      prefix = ""
    }

    delete_marker_replication {
      status = "Enabled"
    }

    destination {
      bucket = "arn:aws:s3:::${module.serenditree_backup.buckets[each.key].id}-${local.replica_suffix}"
    }
  }
}
