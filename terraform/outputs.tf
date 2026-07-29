output "vm_ip_address" {
  description = "IP da VM: o estático configurado, ou o obtido via DHCP/guest agent"
  value       = coalesce(var.vm_ip_address, local.vm_dhcp_ip)
}

output "vm_name" {
  description = "Nome da VM criada"
  value       = ovirt_vm.vm.name
}
