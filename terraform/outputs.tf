output "vm_ip_address" {
  description = "IP da VM criada"
  value       = vsphere_virtual_machine.vm.guest_ip_addresses
}

output "vm_name" {
  description = "JavaAppTerraform"
  value       = vsphere_virtual_machine.vm.name
}