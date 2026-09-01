########################################################################################################################
# Platform
########################################################################################################################
variable "api_key" {
  description = "Exoscale api key."
  type        = string
}

variable "api_secret" {
  description = "Exoscale api secret."
  type        = string
}

variable "ssh_key_pair" {
  description = "Identifier of the ssh public key available at Exoscale."
  type        = string
  default     = "tanwald1"
}
########################################################################################################################
# Cluster
########################################################################################################################
variable "zone" {
  description = "Target zone."
  type        = string
  default     = "at-vie-1"
}

variable "base_domain" {
  description = "Base domain."
  type        = string
  default     = "serenditree.io"
}

variable "cluster_name" {
  description = "Cluster name."
  type        = string
  default     = "dev"
}
########################################################################################################################
# Nodes
########################################################################################################################
variable "bootstrap_enabled" {
  description = "Flag to set bootstrap mode."
  type        = bool
  default     = true
}

variable "worker_nodes_enabled" {
  description = "Flag to enable worker nodes."
  type        = bool
  default     = false
}

variable "master_nodes" {
  description = "The master nodes to create."
  type = object({
    name           = string
    replicas       = number
    hyperthreading = string
    template_id    = string
    instance_type  = string
    disk_size      = number
  })
  default = {
    name           = "master"
    replicas       = 3
    hyperthreading = "Enabled"
    template_id    = "1be5888e-8bbb-43b5-85c2-1c1ef796965d"
    instance_type  = "standard.extra-large"
    disk_size      = 120
  }
}

variable "worker_nodes" {
  description = "The worker nodes to create."
  type = list(object({
    name           = string
    replicas       = number
    hyperthreading = string
    template_id    = string
    instance_type  = string
    disk_size      = number
  }))
  default = [
    {
      name           = "apps"
      replicas       = 3
      hyperthreading = "Enabled"
      template_id    = "1be5888e-8bbb-43b5-85c2-1c1ef796965d"
      instance_type  = "standard.large"
      disk_size      = 120
    }
  ]
}
