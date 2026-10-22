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

variable "zone" {
  description = "Target zone."
  type        = string
  default     = "at-vie-2"
}

variable "ssh_public_key_file" {
  description = "Public key for ssh access (security group needed)."
  type        = string
  default     = "~/.ssh/default@exoscale.com.pub"
}

variable "pull_secret_file" {
  description = "Pull secret for openshift releases."
  type        = string
  default     = "~/.config/openshift/pull-secret.json"
}
########################################################################################################################
# Cluster
########################################################################################################################
variable "base_domain" {
  description = "Base domain."
  type        = string
  default     = "serenditree.io"
}

variable "cluster_name" {
  description = "Cluster name. The cluster domain becomes <cluster_name>.<base_domain>."
  type        = string
  default     = "ocp"
}

variable "cluster_network" {
  description = "Pod network CIDR."
  type        = string
  default     = "10.128.0.0/14"
}

variable "cluster_network_host_prefix" {
  description = "Size of the per-node pod subnet carved out of `cluster_network`."
  type        = number
  default     = 23
}

variable "service_network" {
  description = "Service network CIDR."
  type        = string
  default     = "172.30.0.0/16"
}

variable "network_type" {
  description = "Cluster network plugin. OVNKubernetes is the only option."
  type        = string
  default     = "OVNKubernetes"

  validation {
    condition     = var.network_type == "OVNKubernetes"
    error_message = "Only OVNKubernetes is supported."
  }
}

variable "fips" {
  description = "Enable FIPS mode."
  type        = bool
  default     = false
}
########################################################################################################################
# Image
########################################################################################################################
variable "manage_template" {
  description = "Register or reuse the RHCOS template"
  type        = bool
  default     = true
}

variable "template_name" {
  description = "Name of the RHCOS template. Defaults to rhcos-<release> as reported by `openshift-install`."
  type        = string
  default     = ""
}

variable "template_bucket" {
  description = "Name of the bucket where template images are stored."
  type        = string
  default     = "serenditree-templates"
}

variable "template_disk_size" {
  description = "Disk size in GB the RHCOS image is resized to before registration. Node disks cannot be smaller."
  type        = number
  default     = 128
}
########################################################################################################################
# Ignition delivery
########################################################################################################################
variable "ignition_bucket" {
  description = "SOS bucket holding bootstrap.ign."
  type        = string
  default     = "serenditree-ignition"
}

variable "ignition_url_ttl" {
  description = "Lifetime of the pre-signed bootstrap.ign URL."
  type        = string
  default     = "1h"
}
########################################################################################################################
# Access
########################################################################################################################
variable "ssh_cidr" {
  description = "Networks allowed to ssh into the nodes."
  type        = list(string)
  default     = []
}

variable "api_cidr" {
  description = "Networks allowed to reach the Kubernetes API on 6443."
  type        = list(string)
  default     = []
}

variable "ingress_cidr" {
  description = "Networks allowed to reach the router on 80/443."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
########################################################################################################################
# Nodes
########################################################################################################################
variable "bootstrap_enabled" {
  description = <<-EOT
    Phase switch. True provisions the bootstrap node and points api/api-int at it. False tears it down and repoints
    api/api-int at the control plane load balancer. Both phases need to run sequentially.
  EOT
  type        = bool
  default     = true
}

variable "compute_nodes_enabled" {
  description = "Create dedicated compute nodes. When false the control plane is made schedulable."
  type        = bool
  default     = true
}

variable "bootstrap_node" {
  description = "The bootstrap node to create."
  type = object({
    instance_type = string
    disk_size     = number
  })
  default = {
    instance_type = "standard.extra-large"
    disk_size     = 128
  }
}

variable "control_nodes" {
  description = "The control plane nodes to create."
  type = object({
    name           = string
    replicas       = number
    hyperthreading = string
    architecture   = string
    instance_type  = string
    disk_size      = number
  })
  default = {
    name           = "control"
    replicas       = 3
    hyperthreading = "Enabled"
    architecture   = "amd64"
    instance_type  = "standard.extra-large"
    disk_size      = 128
  }
}

variable "compute_nodes" {
  description = "The compute node groups to create."
  type = list(object({
    name           = string
    replicas       = number
    hyperthreading = string
    architecture   = string
    instance_type  = string
    disk_size      = number
  }))
  default = [
    {
      name           = "compute"
      replicas       = 3
      hyperthreading = "Enabled"
      architecture   = "amd64"
      instance_type  = "standard.large"
      disk_size      = 128
    }
  ]

  validation {
    condition     = !var.compute_nodes_enabled || length(var.compute_nodes) > 0
    error_message = "compute_nodes must define at least one group unless `compute_nodes_enabled` is false."
  }
}

variable "ingress_node_group" {
  description = "Compute group whose load balancer *.apps points at. Defaults to the first entry of `compute_nodes`."
  type        = string
  default     = ""
}
########################################################################################################################
# Storage
########################################################################################################################
variable "csi_driver" {
  description = "Exoscale Block Storage CSI driver."
  type = object({
    enabled       = optional(bool, true)
    storage_class = optional(string, "exoscale-sbs")
    default_class = optional(bool, true)
  })
  default = {}
}
########################################################################################################################
# Operators
########################################################################################################################
variable "operators" {
  description = "OLM operator subscriptions. Empty disables the step entirely."
  type = list(object({
    package   = string
    channel   = optional(string, "")
    namespace = optional(string, "openshift-operators")
    catalog   = optional(string, "redhat-operators")
    operand = optional(object({
      resource  = string
      name      = string
      namespace = optional(string, "")
      jsonpath  = string
      value     = string
    }))
  }))
  default = [
    {
      package   = "openshift-gitops-operator"
      channel   = "latest"
      namespace = "openshift-gitops-operator"
      operand = {
        resource  = "argocd.argoproj.io"
        name      = "openshift-gitops"
        namespace = "openshift-gitops"
        jsonpath  = "{.status.phase}"
        value     = "Available"
      }
    },
    {
      package = "openshift-pipelines-operator-rh"
      channel = "latest"
      operand = {
        resource = "tektonconfig.operator.tekton.dev"
        name     = "config"
        jsonpath = "{.status.conditions[?(@.type==\"Ready\")].status}"
        value    = "True"
      }
    },
    {
      package = "strimzi-kafka-operator"
      channel = "strimzi-1.x"
      catalog = "community-operators"
    },
  ]
}
