########################################################################################################################
# Platform
########################################################################################################################
variable "zone" {
  type = string
}

variable "security_group_ids" {
  type = list(string)
}

variable "template_id" {
  type = string
}
########################################################################################################################
# Cluster
########################################################################################################################
variable "cluster_name" {
  type = string
}

variable "base_domain" {
  type = string
}
########################################################################################################################
# Node
########################################################################################################################
variable "bootstrap_enabled" {
  type = bool
}

variable "bootstrap_node_config" {
  type = object({
    instance_type = string
    disk_size     = number
  })
}

variable "user_data" {
  description = "Stub ignition config pointing at the pre-signed bootstrap.ign."
  type        = string
}
