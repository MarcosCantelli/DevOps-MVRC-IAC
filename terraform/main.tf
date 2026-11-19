provider "ovirt" {
  url          = var.ovirt_url
  username     = var.ovirt_username
  password     = var.ovirt_password
  tls_insecure = var.ovirt_tls_insecure
}

# Template Ubuntu preparado manualmente no OLVM (o mesmo do gameserver:
# cloud-init e qemu-guest-agent instalados, SEM interface de rede). O provider
# não expõe um catálogo de imagens como a OCI - o template precisa existir de
# antemão. O disco do template NÃO pode ficar no hosted_storage: só SuperUser
# cria disco no storage do Hosted Engine (ver README).
data "ovirt_templates" "app" {
  count = var.app_vm_enabled ? 1 : 0

  name          = var.template_name
  fail_on_empty = true
}

# Cloud-init: cria o usuário mvrc já no primeiro boot (sem estágio
# intermediário via um usuário padrão da imagem, diferente do fluxo da OCI)
# e autoriza as duas chaves SSH (pessoal + Jenkins).
locals {
  ssh_keys = [
    trimspace(file(pathexpand(var.my_ssh_public_key_path))),
    trimspace(file(pathexpand(var.jenkins_ssh_public_key_path))),
  ]

  # Um .pub vazio vira um item vazio em ssh_authorized_keys: a VM sobe, mas
  # sem aquela chave (e o cloud-init só avisa de "schema validation").
  ssh_keys_ok = alltrue([for k in local.ssh_keys : can(regex("^(ssh-|ecdsa-|sk-)", k))])

  cloud_init = templatefile("${path.module}/templates/cloud-init.yaml.tpl", {
    dns_primary   = var.dns_primary
    dns_secondary = var.dns_secondary
    ssh_keys      = local.ssh_keys
  })
}

# VM de aplicação (Docker + Traefik). Desligada neste ambiente
# (app_vm_enabled = false no terraform.tfvars): aqui o pipeline cria só o
# gameserver. O código fica para quem usar o repo como modelo.
resource "ovirt_vm" "vm" {
  count = var.app_vm_enabled ? 1 : 0

  name        = var.vm_name
  cluster_id  = var.cluster_id
  template_id = tolist(data.ovirt_templates.app[0].templates)[0].id
  clone       = true

  cpu_cores   = var.cpu_cores
  cpu_sockets = var.cpu_sockets
  cpu_threads = var.cpu_threads
  memory      = var.memory_gb * 1024 * 1024 * 1024

  initialization_hostname      = var.vm_name
  initialization_custom_script = local.cloud_init

  lifecycle {
    precondition {
      condition     = local.ssh_keys_ok
      error_message = "Uma das chaves públicas SSH (my_ssh_public_key_path / jenkins_ssh_public_key_path) está vazia ou não é uma chave pública."
    }
  }

  # Só configura IP estático via cloud-init quando vm_ip_address é
  # preenchido. Deixando null, a NIC não é tocada e o template segue com o
  # comportamento padrão dele (DHCP).
  dynamic "initialization_nic" {
    for_each = var.vm_ip_address != null ? [1] : []
    content {
      name = var.nic_name
      ipv4 {
        address = var.vm_ip_address
        netmask = var.vm_netmask
        gateway = var.vm_gateway
      }
    }
  }
}

# O template Ubuntu não tem NIC, então ela é criada explicitamente, no vNIC
# profile da rede das outras VMs (ID injetado via TF_VAR_vnic_profile_id).
resource "ovirt_nic" "vm" {
  count = var.app_vm_enabled ? 1 : 0

  vm_id           = ovirt_vm.vm[0].id
  name            = "nic1"
  vnic_profile_id = var.vnic_profile_id
}

# A criação da VM não a liga automaticamente no OLVM - precisa deste
# resource separado para ligá-la (e desligá-la no destroy). Só liga depois
# da NIC existir, para o cloud-init já encontrar a placa no primeiro boot.
resource "ovirt_vm_start" "vm" {
  count = var.app_vm_enabled ? 1 : 0

  vm_id = ovirt_vm.vm[0].id

  depends_on = [ovirt_nic.vm]
}

# Quando não há IP fixo, descobrimos o IP atribuído por DHCP através do
# guest agent (qemu-guest-agent precisa estar instalado e habilitado no
# template - ver README). Sem isso, este data source fica esperando pra sempre.
data "ovirt_wait_for_ip" "vm" {
  count = var.app_vm_enabled && var.vm_ip_address == null ? 1 : 0
  vm_id = ovirt_vm_start.vm[0].vm_id
}

# Prefere a NIC chamada var.nic_name; se o guest der outro nome à placa
# (ex: ens3 em vez de enp1s0, conforme o chipset), usa a primeira interface
# não-loopback com IPv4, em vez de deixar o pipeline sem IP.
locals {
  vm_guest_ifaces = try(tolist(one(data.ovirt_wait_for_ip.vm).interfaces), [])
  vm_dhcp_ip = try(
    concat(
      [for iface in local.vm_guest_ifaces : tolist(iface.ipv4_addresses)[0] if iface.name == var.nic_name && length(iface.ipv4_addresses) > 0],
      [for iface in local.vm_guest_ifaces : tolist(iface.ipv4_addresses)[0] if iface.name != "lo" && length(iface.ipv4_addresses) > 0],
    )[0],
    null
  )
}
