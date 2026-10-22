output "nlb_ip_address" {
  description = "Address *.apps resolves to when this group is the ingress group."
  value       = exoscale_nlb.compute.ip_address
}

output "instance_pool_id" {
  value = exoscale_instance_pool.compute.id
}

output "instance_ids" {
  description = "Current pool members. Changes whenever a node is replaced, which has to re-trigger CSR approval."
  value       = [for instance in exoscale_instance_pool.compute.instances : instance.id]
}
