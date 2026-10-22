########################################################################################################################
# Platform
########################################################################################################################
variable "zone" {
  type = string
}

variable "api_key" {
  type      = string
  sensitive = true
}

variable "api_secret" {
  type      = string
  sensitive = true
}

variable "ssh_public_key_file" {
  type = string
}

variable "pull_secret_file" {
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

variable "cluster_network" {
  type = string
}

variable "cluster_network_host_prefix" {
  type = number
}

variable "service_network" {
  type = string
}

variable "network_type" {
  type = string
}

variable "fips" {
  type = bool
}
########################################################################################################################
# Nodes
########################################################################################################################
variable "control_nodes_config" {
  type = object({
    name           = string
    replicas       = number
    hyperthreading = string
    architecture   = string
  })
}

variable "compute_nodes_enabled" {
  type = bool
}

variable "compute_nodes_config" {
  type = list(object({
    name           = string
    replicas       = number
    hyperthreading = string
    architecture   = string
  }))
}

variable "ingress_replicas" {
  description = "Router replicas. Matches the size of the group whose load balancer serves *.apps."
  type        = number
}
########################################################################################################################
# Ignition delivery
########################################################################################################################
variable "ignition_bucket" {
  type = string
}

variable "ignition_url_ttl" {
  type = string
}
