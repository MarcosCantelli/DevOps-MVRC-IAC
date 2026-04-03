# Infraestrutura vSphere
vsphere_server = "192.168.31.13"       # IP ou hostname do seu vCenter
datacenter     = "MVRC-DC"
cluster        = "Xeon"
datastore      = "VS2_HD1_1TB"
network        = "VM Network"

# Template e VM
template_name  = "Ubuntu-Terraform"
vm_name        = "JavaAppTerraform"
num_cpus       = 2
memory_mb      = 4096