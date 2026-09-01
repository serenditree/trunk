########################################################################################################################
# Platform
########################################################################################################################
variable "ssh_key_pair" {
  type = string
}

variable "default_security_group_id" {
  type = string
}
########################################################################################################################
# Cluster
########################################################################################################################
variable "zone" {
  type = string
}

variable "base_domain" {
  type = object({
    id   = string
    name = string
  })
}

variable "cluster_name" {
  type = string
}
########################################################################################################################
# Nodes
########################################################################################################################
variable "bootstrap_enabled" {
  type = bool
}

variable "assets_dir" {
  type = string
}

variable "worker_nodes_enabled" {
  type = bool
}

variable "master_nodes_config" {
  description = "The master nodes to create."
  type = object({
    name           = string
    replicas       = number
    hyperthreading = string
    template_id    = string
    instance_type  = string
    disk_size      = number
  })
}

variable "user_data" {
  type = string
}
