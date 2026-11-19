output "vm_ip_address" {
  description = "IP da VM: o estático configurado, ou o obtido via DHCP/guest agent"
  # try(): com a VM de aplicação desligada não há IP - o output fica null.
  value = try(coalesce(var.vm_ip_address, local.vm_dhcp_ip), null)
}

output "vm_name" {
  description = "Nome da VM criada"
  value       = one(ovirt_vm.vm[*].name)
}

output "gameserver_ip_address" {
  description = "IP do gameserver: o estático configurado, ou o obtido via DHCP/guest agent"
  # try(): com o gameserver desligado não há IP, e coalesce() sem nenhum
  # valor não nulo daria erro - o output fica null.
  value = try(coalesce(var.gameserver_ip_address, local.gameserver_dhcp_ip), null)
}

output "gameserver_vm_name" {
  description = "Nome da VM de servidor de jogos"
  value       = one(ovirt_vm.gameserver[*].name)
}
