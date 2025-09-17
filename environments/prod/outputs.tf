output "resource_group_name" {
  description = "Name of the resource group"
  value       = module.vnet.resource_group_name
}

output "vnet_id" {
  description = "ID of the virtual network"
  value       = module.vnet.vnet_id
}

output "load_balancer_ip" {
  description = "Public IP of the load balancer"
  value       = azurerm_public_ip.lb_pip.ip_address
}

output "vm_private_ips" {
  description = "Private IPs of the VMs"
  value       = azurerm_network_interface.vm[*].private_ip_address
}

output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "application_url" {
  description = "URL to access the application"
  value       = "http://${azurerm_public_ip.lb_pip.ip_address}"
}