
########################################################################################################################
# Storage
########################################################################################################################
variable "backup_buckets" {
  description = "Buckets for backups."
  type        = set(string)
}

variable "backup_lifecycle" {
  description = "Enable bucket lifecycle."
  type        = bool
}
