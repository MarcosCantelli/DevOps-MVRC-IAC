output "vm_public_ip" {
  description = "IP público da VM criada na OCI"
  value       = oci_core_instance.vm.public_ip
}

output "vm_name" {
  description = "Nome da VM criada"
  value       = oci_core_instance.vm.display_name
}
