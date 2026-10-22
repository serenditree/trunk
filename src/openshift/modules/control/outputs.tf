output "nlb_ip_address" {
  description = "Address api and api-int resolve to once the bootstrap node is gone."
  value       = exoscale_nlb.control.ip_address
}

output "instance_pool_id" {
  value = exoscale_instance_pool.control.id
}

output "instance_ids" {
  description = "Current pool members. Changes whenever a node is replaced, which has to re-trigger CSR approval."
  value       = [for instance in exoscale_instance_pool.control.instances : instance.id]
}
