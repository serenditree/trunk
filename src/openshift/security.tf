########################################################################################################################
# Init
########################################################################################################################
resource "exoscale_security_group" "node" {
  name        = "${var.cluster_name}-node"
  description = "Nodes of the ${local.cluster_domain} cluster."
}

locals {
  # Ports from the "Ports used for all-machine to all-machine communications" and "control plane to control plane"
  # tables of the OpenShift bare-metal installation docs.
  node_rules = {
    ping = {
      description = "path MTU discovery and liveness"
      protocol    = "ICMP"
      start_port  = null
      end_port    = null
      icmp_type   = 8
      icmp_code   = 0
    }
    fragmentation_needed = {
      description = "path MTU discovery"
      protocol    = "ICMP"
      start_port  = null
      end_port    = null
      icmp_type   = 3
      icmp_code   = 4
    }
    etcd = {
      description = "etcd peer and client traffic"
      protocol    = "TCP"
      start_port  = 2379
      end_port    = 2380
      icmp_type   = null
      icmp_code   = null
    }
    kubernetes_api = {
      description = "kube-apiserver"
      protocol    = "TCP"
      start_port  = 6443
      end_port    = 6443
      icmp_type   = null
      icmp_code   = null
    }
    machine_config_server = {
      description = "machine config server - serves the real ignition configs"
      protocol    = "TCP"
      start_port  = 22623
      end_port    = 22623
      icmp_type   = null
      icmp_code   = null
    }
    router_stats = {
      description = "router health and metrics"
      protocol    = "TCP"
      start_port  = 1936
      end_port    = 1936
      icmp_type   = null
      icmp_code   = null
    }
    host_services_tcp = {
      description = "host level services including the node exporter"
      protocol    = "TCP"
      start_port  = 9000
      end_port    = 9999
      icmp_type   = null
      icmp_code   = null
    }
    host_services_udp = {
      description = "host level services"
      protocol    = "UDP"
      start_port  = 9000
      end_port    = 9999
      icmp_type   = null
      icmp_code   = null
    }
    kubelet = {
      description = "kubelet and the Kubernetes reserved range"
      protocol    = "TCP"
      start_port  = 10250
      end_port    = 10259
      icmp_type   = null
      icmp_code   = null
    }
    node_ports_tcp = {
      description = "NodePort services"
      protocol    = "TCP"
      start_port  = 30000
      end_port    = 32767
      icmp_type   = null
      icmp_code   = null
    }
    node_ports_udp = {
      description = "NodePort services"
      protocol    = "UDP"
      start_port  = 30000
      end_port    = 32767
      icmp_type   = null
      icmp_code   = null
    }
    geneve = {
      description = "OVN-Kubernetes overlay"
      protocol    = "UDP"
      start_port  = 6081
      end_port    = 6081
      icmp_type   = null
      icmp_code   = null
    }
    ntp = {
      description = "chrony"
      protocol    = "UDP"
      start_port  = 123
      end_port    = 123
      icmp_type   = null
      icmp_code   = null
    }
    ipsec_ike = {
      description = "IPsec IKE - only used when east-west encryption is enabled"
      protocol    = "UDP"
      start_port  = 500
      end_port    = 500
      icmp_type   = null
      icmp_code   = null
    }
    ipsec_nat_traversal = {
      description = "IPsec NAT traversal - only used when east-west encryption is enabled"
      protocol    = "UDP"
      start_port  = 4500
      end_port    = 4500
      icmp_type   = null
      icmp_code   = null
    }
    ipsec_esp = {
      description = "IPsec ESP - only used when east-west encryption is enabled"
      protocol    = "ESP"
      start_port  = null
      end_port    = null
      icmp_type   = null
      icmp_code   = null
    }
  }
}
########################################################################################################################
# Intra-cluster
########################################################################################################################
resource "exoscale_security_group_rule" "node" {
  for_each = local.node_rules

  security_group_id      = exoscale_security_group.node.id
  user_security_group_id = exoscale_security_group.node.id
  description            = each.value.description
  type                   = "INGRESS"
  protocol               = each.value.protocol
  start_port             = each.value.start_port
  end_port               = each.value.end_port
  icmp_type              = each.value.icmp_type
  icmp_code              = each.value.icmp_code
}
########################################################################################################################
# Public
########################################################################################################################
resource "exoscale_security_group_rule" "ssh" {
  for_each = toset(var.ssh_cidr)

  security_group_id = exoscale_security_group.node.id
  description       = "SSH as the core user"
  type              = "INGRESS"
  protocol          = "TCP"
  cidr              = each.value
  start_port        = 22
  end_port          = 22
}

resource "exoscale_security_group_rule" "kubernetes_api" {
  for_each = toset(var.api_cidr)

  security_group_id = exoscale_security_group.node.id
  description       = "kube-apiserver"
  type              = "INGRESS"
  protocol          = "TCP"
  cidr              = each.value
  start_port        = 6443
  end_port          = 6443
}

resource "exoscale_security_group_rule" "http" {
  for_each = toset(var.ingress_cidr)

  security_group_id = exoscale_security_group.node.id
  description       = "router"
  type              = "INGRESS"
  protocol          = "TCP"
  cidr              = each.value
  start_port        = 80
  end_port          = 80
}

resource "exoscale_security_group_rule" "https" {
  for_each = toset(var.ingress_cidr)

  security_group_id = exoscale_security_group.node.id
  description       = "router"
  type              = "INGRESS"
  protocol          = "TCP"
  cidr              = each.value
  start_port        = 443
  end_port          = 443
}
