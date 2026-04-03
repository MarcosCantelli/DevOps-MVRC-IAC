output "vm_ip_address" {
  description = "IP principal da VM criada"
  value       = vsphere_virtual_machine.vm.default_ip_address
}

output "vm_name" {
  description = "Nome da VM criada"
  value       = vsphere_virtual_machine.vm.name
}