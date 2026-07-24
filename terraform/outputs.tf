output "vm_ip_address" {
  description = "IP estático configurado para a VM"
  value       = var.vm_ip_address
}

output "vm_name" {
  description = "Nome da VM criada"
  value       = ovirt_vm.vm.name
}
