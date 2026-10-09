########################################################################################################################
# Platform
########################################################################################################################
variable "api_key" {
  description = "Exoscale api key."
  type        = string
  sensitive   = true
}

variable "api_secret" {
  description = "Exoscale api secret."
  type        = string
  sensitive   = true
}
########################################################################################################################
# Zones
########################################################################################################################
variable "zone_storage_1" {
  description = "Primary zone for storage."
  type        = string
}

variable "zone_storage_2" {
  description = "Secondary zone for storage."
  type        = string
}
########################################################################################################################
# Storage
########################################################################################################################
variable "storage_data" {
  description = "Bucket for application assets."
  type        = string
  default     = "serenditree-data"
}

variable "storage_backup" {
  description = "Buckets for backups."
  type        = set(string)
  default     = ["serenditree-backup-seed", "serenditree-backup-user"]
}

variable "storage_backup_lifecycle" {
  description = "Enable bucket lifecycle."
  type        = bool
  default     = true
}
