output "ip_address" {
  description = "Public address of the bootstrap node. Null once the bootstrap phase is over."
  value       = var.bootstrap_enabled ? exoscale_compute_instance.bootstrap[0].public_ip_address : null
}
