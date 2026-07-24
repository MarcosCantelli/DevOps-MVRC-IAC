provider "ovirt" {
  url          = var.ovirt_url
  username     = var.ovirt_username
  password     = var.ovirt_password
  tls_insecure = var.ovirt_tls_insecure
}

# Template Oracle Linux 9 preparado manualmente no OLVM (cloud-init instalado
# e selado com virt-sysprep / "Make Template"). O provider não expõe um
# catálogo de imagens como a OCI - o template precisa existir de antemão.
data "ovirt_templates" "oracle_linux" {
  name          = var.template_name
  fail_on_empty = true
}

# Cloud-init: cria o usuário mvrc já no primeiro boot (sem estágio
# intermediário via um usuário padrão da imagem, diferente do fluxo da OCI)
# e autoriza as duas chaves SSH (pessoal + Jenkins).
locals {
  cloud_init = templatefile("${path.module}/templates/cloud-init.yaml.tpl", {
    dns_primary   = var.dns_primary
    dns_secondary = var.dns_secondary
    ssh_keys = [
      trimspace(file(pathexpand(var.my_ssh_public_key_path))),
      trimspace(file(pathexpand(var.jenkins_ssh_public_key_path))),
    ]
  })
}

resource "ovirt_vm" "vm" {
  name        = var.vm_name
  cluster_id  = var.cluster_id
  template_id = tolist(data.ovirt_templates.oracle_linux.templates)[0].id
  clone       = true

  cpu_cores   = var.cpu_cores
  cpu_sockets = var.cpu_sockets
  cpu_threads = var.cpu_threads
  memory      = var.memory_gb * 1024 * 1024 * 1024

  initialization_hostname      = var.vm_name
  initialization_custom_script = local.cloud_init

  initialization_nic {
    name = var.nic_name
    ipv4 {
      address = var.vm_ip_address
      netmask = var.vm_netmask
      gateway = var.vm_gateway
    }
  }
}

# A criação da VM não a liga automaticamente no OLVM - precisa deste
# resource separado para ligá-la (e desligá-la no destroy).
resource "ovirt_vm_start" "vm" {
  vm_id = ovirt_vm.vm.id
}
