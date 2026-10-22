########################################################################################################################
# Platform
########################################################################################################################
variable "zone" {
  type = string
}

variable "security_group_ids" {
  type = list(string)
}

variable "node_security_group_id" {
  description = "Security group the load balancer rules are attached to."
  type        = string
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
########################################################################################################################
# Nodes
########################################################################################################################
variable "compute_nodes_config" {
  type = object({
    name           = string
    replicas       = number
    hyperthreading = string
    architecture   = string
    instance_type  = string
    disk_size      = number
  })
}

variable "user_data" {
  description = "The installer's worker.ign."
  type        = string
  sensitive   = true
}
