########################################################################################################################
# Security group
########################################################################################################################
resource "exoscale_security_group" "serenditree" {
  name = "serenditree"
}

resource "exoscale_security_group_rule" "node_port_service" {
  security_group_id = exoscale_security_group.serenditree.id
  type              = "INGRESS"
  protocol          = "TCP"
  cidr              = "0.0.0.0/0"
  start_port        = 30000
  end_port          = 32767
}

resource "exoscale_security_group_rule" "kubelet" {
  security_group_id      = exoscale_security_group.serenditree.id
  user_security_group_id = exoscale_security_group.serenditree.id
  type                   = "INGRESS"
  protocol               = "TCP"
  start_port             = 10250
  end_port               = 10250
}

resource "exoscale_security_group_rule" "calico_traffic" {
  count                  = var.cni == "calico" ? 1 : 0
  security_group_id      = exoscale_security_group.serenditree.id
  user_security_group_id = exoscale_security_group.serenditree.id
  type                   = "INGRESS"
  protocol               = "UDP"
  start_port             = 4789
  end_port               = 4789
}

resource "exoscale_security_group_rule" "cilium_healthcheck_tcp" {
  count                  = var.cni == "cilium" || var.cni == "" ? 1 : 0
  security_group_id      = exoscale_security_group.serenditree.id
  user_security_group_id = exoscale_security_group.serenditree.id
  type                   = "INGRESS"
  protocol               = "TCP"
  start_port             = 4240
  end_port               = 4240
}

resource "exoscale_security_group_rule" "cilium_healthcheck_icmp" {
  count                  = var.cni == "cilium" || var.cni == "" ? 1 : 0
  security_group_id      = exoscale_security_group.serenditree.id
  user_security_group_id = exoscale_security_group.serenditree.id
  type                   = "INGRESS"
  protocol               = "ICMP"
  icmp_type              = 8
  icmp_code              = 0
}

resource "exoscale_security_group_rule" "cilium_vxlan" {
  count                  = var.cni == "cilium" || var.cni == "" ? 1 : 0
  security_group_id      = exoscale_security_group.serenditree.id
  user_security_group_id = exoscale_security_group.serenditree.id
  type                   = "INGRESS"
  protocol               = "UDP"
  start_port             = 8472
  end_port               = 8472
}

resource "exoscale_security_group_rule" "cilium_wireguard" {
  count                  = var.cni == "cilium" || var.cni == "" ? 1 : 0
  security_group_id      = exoscale_security_group.serenditree.id
  user_security_group_id = exoscale_security_group.serenditree.id
  type                   = "INGRESS"
  protocol               = "UDP"
  start_port             = 51871
  end_port               = 51871
}

resource "exoscale_security_group_rule" "cilium_hubble" {
  count                  = var.cni == "cilium" || var.cni == "" ? 1 : 0
  security_group_id      = exoscale_security_group.serenditree.id
  user_security_group_id = exoscale_security_group.serenditree.id
  type                   = "INGRESS"
  protocol               = "TCP"
  start_port             = 4244
  end_port               = 4244
}

resource "exoscale_security_group_rule" "prometheus" {
  count                  = var.cni == "cilium" || var.cni == "" ? 1 : 0
  security_group_id      = exoscale_security_group.serenditree.id
  user_security_group_id = exoscale_security_group.serenditree.id
  type                   = "INGRESS"
  protocol               = "TCP"
  start_port             = 9962
  end_port               = 9965
}

resource "exoscale_security_group_rule" "prometheus_node_exporter" {
  count                  = var.cni == "cilium" || var.cni == "" ? 1 : 0
  security_group_id      = exoscale_security_group.serenditree.id
  user_security_group_id = exoscale_security_group.serenditree.id
  type                   = "INGRESS"
  protocol               = "TCP"
  start_port             = 9100
  end_port               = 9100
}
