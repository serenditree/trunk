########################################################################################################################
# Load Balancer
########################################################################################################################
resource "exoscale_nlb" "serenditree" {
  zone = var.zone
  name = var.name
}
########################################################################################################################
# Domain
########################################################################################################################
data "exoscale_domain" "serenditree" {
  name = var.host
}
########################################################################################################################
# Domain Records
########################################################################################################################
resource "exoscale_domain_record" "serenditree" {
  domain      = data.exoscale_domain.serenditree.id
  name        = ""
  record_type = "A"
  content     = exoscale_nlb.serenditree.ip_address
  ttl         = var.issuer == "staging" ? 60 : 3600
}

resource "exoscale_domain_record" "www" {
  domain      = data.exoscale_domain.serenditree.id
  name        = "www"
  record_type = "CNAME"
  content     = data.exoscale_domain.serenditree.name
  ttl         = var.issuer == "staging" ? 60 : 3600
}
