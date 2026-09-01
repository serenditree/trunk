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
# Cluster
########################################################################################################################
variable "name" {
  description = "Project name"
  type        = string
  default     = "serenditree"
}

variable "zone_compute_1" {
  description = "Primary zone for compute."
  type        = string
}

variable "zone_storage_1" {
  description = "Primary zone for storage."
  type        = string
}

variable "zone_storage_2" {
  description = "Secondary zone for storage."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version."
  type        = string
  default     = ""
}
variable "service_level" {
  description = "Service level."
  type        = string
  default     = "pro"
}

variable "auto_upgrade" {
  description = "Auto-upgrade Kubernetes to the latest patch release."
  type        = string
  default     = true
}

variable "auto_scaler" {
  description = "Autoscaler to use."
  type        = string
  default     = ""
  validation {
    condition     = contains(["karpenter", "karpenter-only", "autoscaler", ""], var.auto_scaler)
    error_message = "Valid values for auto_scaler: {karpenter, karpenter-only, autoscaler, \"\"}."
  }
}

variable "gateway" {
  description = "Gateway to use."
  type        = string
  validation {
    condition     = contains(["traefik", "envoy"], var.gateway)
    error_message = "Valid values for gateway: {traefik, envoy}."
  }
}

variable "cni" {
  description = "Container network interface plugin to use."
  type        = string
  default     = ""
  validation {
    condition     = contains(["cilium", "calico", ""], var.cni)
    error_message = "Valid values for cni: {cilium, calico, \"\"}."
  }
}

variable "csi" {
  description = "Enable container storage interface plugin."
  type        = bool
  default     = true
}
########################################################################################################################
# Nodes
########################################################################################################################
variable "compute_nodes" {
  description = "The node-pools to create."
  type = map(object({
    replicas      = number
    instance_type = string
    disk_size     = number
  }))
  default = {
    dev = {
      replicas      = 4
      instance_type = "standard.large"
      disk_size     = 64
    }
  }
}
########################################################################################################################
# Storage
########################################################################################################################
variable "storage_data" {
  description = "Bucket for application assets."
  type        = string
  default     = ""
  #default = "serenditree-data"
}

variable "storage_backup" {
  description = "Buckets for backups."
  type        = set(string)
  default     = []
  #default = ["serenditree-backup-seed", "serenditree-backup-user"]
}

variable "storage_backup_lifecycle" {
  description = "Enable bucket lifecycle."
  type        = bool
  default     = false
}
########################################################################################################################
# Global
########################################################################################################################
variable "context" {
  description = "Kubernetes context to use."
  type        = string
}

variable "host" {
  description = "Hostname for endpoints."
  type        = string
}

variable "cluster_domain" {
  description = "Kubernetes cluster domain."
  type        = string
  default     = "cluster.local"
}

variable "issuer" {
  description = "Let's encrypt issuer type."
  type        = string
  validation {
    condition     = contains(["staging", "prod"], var.issuer)
    error_message = "Valid values for issuer: {staging, prod}."
  }
}

variable "email" {
  description = "Email for Let's Encrypt."
  type        = string
}

variable "stage" {
  description = "Target stage."
  type        = string
  validation {
    condition     = contains(["dev", "test", "prod"], var.stage)
    error_message = "Valid values for stage: {dev, test, prod}."
  }
}

variable "wait" {
  description = "Force sequential deployment of individual apps by waiting for health."
  type        = bool
}
########################################################################################################################
# OIDC
########################################################################################################################
variable "oidc_parameters" {
  description = "OIDC parameters."
  type        = map(string)
}
########################################################################################################################
# Path
########################################################################################################################
variable "charts" {
  description = "Path to helm charts."
  type        = string
}
