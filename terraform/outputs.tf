output "vm_ip_address" {
  description = "IP da VM: o estático configurado, ou o obtido via DHCP/guest agent"
  value       = coalesce(var.vm_ip_address, local.vm_dhcp_ip)
}

output "vm_name" {
  description = "Nome da VM criada"
  value       = ovirt_vm.vm.name
}

output "gameserver_ip_address" {
  description = "IP do gameserver: o estático configurado, ou o obtido via DHCP/guest agent"
  value       = coalesce(var.gameserver_ip_address, local.gameserver_dhcp_ip)
}

output "gameserver_vm_name" {
  description = "Nome da VM de servidor de jogos"
  value       = ovirt_vm.gameserver.name
}
