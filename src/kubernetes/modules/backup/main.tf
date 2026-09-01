########################################################################################################################
# Backup
########################################################################################################################
resource "aws_s3_bucket" "serenditree_backup" {
  for_each = var.backup_buckets
  bucket   = each.key

  object_lock_enabled = true
  force_destroy       = false
}

resource "aws_s3_bucket_object_lock_configuration" "serenditree_backup_object_lock" {
  for_each = var.backup_buckets
  bucket   = aws_s3_bucket.serenditree_backup[each.key].id

  rule {
    default_retention {
      mode = "GOVERNANCE"
      days = 3
    }
  }
}

resource "aws_s3_bucket_versioning" "serenditree_backup_versioning" {
  for_each = var.backup_buckets
  bucket   = aws_s3_bucket.serenditree_backup[each.key].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "serenditree_backup_lifecycle" {
  for_each = var.backup_lifecycle ? var.backup_buckets : []
  bucket   = aws_s3_bucket.serenditree_backup[each.key].id

  rule {
    id     = "delete-expired"
    status = "Enabled"

    filter {
      prefix = ""
    }

    noncurrent_version_expiration {
      noncurrent_days = 3
    }

    expiration {
      expired_object_delete_marker = true
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

