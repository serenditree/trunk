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

variable "kubeconfig" {
  type = string
}
########################################################################################################################
# Nodes
########################################################################################################################
variable "worker_nodes_enabled" {
  type = bool
}

variable "worker_nodes_config" {
  type = object({
    name          = string
    replicas      = number
    template_id   = string
    instance_type = string
    disk_size     = number
  })
}

variable "user_data" {
  type = string
}
