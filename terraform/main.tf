provider "vsphere" {
    user           = var.vsphere_user          # Username for vSphere authentication
    password       = var.vsphere_password      # Password for vSphere authentication
    vsphere_server = var.vsphere_server        # vSphere server address

    allow_unverified_ssl = true                # Allow insecure SSL connections (useful for self-signed certificates)
}

# Fetch the datacenter information
data "vsphere_datacenter" "dc" {
    name = var.datacenter                      # Name of the datacenter to use
}

# Fetch the datastore information
data "vsphere_datastore" "datastore" {
    name          = var.datastore              # Name of the datastore to use
    datacenter_id = data.vsphere_datacenter.dc.id # Datacenter ID fetched from the datacenter data source
}

# Fetch the compute cluster information
data "vsphere_compute_cluster" "cluster" {
    name          = var.cluster                # Name of the compute cluster to use
    datacenter_id = data.vsphere_datacenter.dc.id # Datacenter ID fetched from the datacenter data source
}

# Fetch the virtual machine template information
data "vsphere_virtual_machine" "template" {
    name          = var.template_name          # Name of the VM template to use
    datacenter_id = data.vsphere_datacenter.dc.id # Datacenter ID fetched from the datacenter data source
}

# Fetch the network information
data "vsphere_network" "network" {
    name          = var.network                # Name of the network to use
    datacenter_id = data.vsphere_datacenter.dc.id # Datacenter ID fetched from the datacenter data source
}

# Define the virtual machine resource
resource "vsphere_virtual_machine" "vm" {
  name             = var.vm_name
  resource_pool_id = data.vsphere_compute_cluster.cluster.resource_pool_id
  datastore_id     = data.vsphere_datastore.datastore.id

  num_cpus                   = var.num_cpus
  memory                     = var.memory_mb
  guest_id                   = data.vsphere_virtual_machine.template.guest_id
  wait_for_guest_net_timeout = 60
  wait_for_guest_ip_timeout  = 60

  network_interface {
    network_id   = data.vsphere_network.network.id
    adapter_type = data.vsphere_virtual_machine.template.network_interface_types[0]
  }

  disk {
    label            = "disk0"
    size             = data.vsphere_virtual_machine.template.disks.0.size
    eagerly_scrub    = data.vsphere_virtual_machine.template.disks.0.eagerly_scrub
    thin_provisioned = data.vsphere_virtual_machine.template.disks.0.thin_provisioned
  }

  clone {
    template_uuid = data.vsphere_virtual_machine.template.id
  }
}