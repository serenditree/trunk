########################################################################################################################
# Cluster
########################################################################################################################
variable "name" {
  description = "Project name"
  type        = string
}

variable "zone" {
  description = "Primary zone for compute."
  type        = string
}
########################################################################################################################
# Global
########################################################################################################################
variable "host" {
  description = "Hostname for endpoints."
  type        = string
}

variable "issuer" {
  description = "Let's encrypt issuer type."
  type        = string
  validation {
    condition     = contains(["staging", "prod"], var.issuer)
    error_message = "Valid values for issuer: {staging, prod}."
  }
}
