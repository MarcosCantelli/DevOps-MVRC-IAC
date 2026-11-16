# VM dedicada a servidores de jogos (Project Zomboid B42 em Docker, depois
# outros jogos). Fica num arquivo separado para não tocar na VM de aplicação
# (ovirt_vm.vm em main.tf) - os dois recursos são totalmente independentes.

# Template Ubuntu já existente no OLVM (firmware BIOS, 2 vCPU / 2 GiB e SEM
# interface de rede). Precisa ter cloud-init e qemu-guest-agent instalados,
# como o template Oracle Linux (ver README).
data "ovirt_templates" "ubuntu" {
  name          = var.gameserver_template_name
  fail_on_empty = true
}

resource "ovirt_vm" "gameserver" {
  name        = var.gameserver_vm_name
  cluster_id  = var.cluster_id
  template_id = tolist(data.ovirt_templates.ubuntu.templates)[0].id
  clone       = true

  # Mesmo padrão da VM de aplicação: 1 socket x N cores x 1 thread
  # (8 vCPUs). O provider exige que os três campos sejam informados juntos.
  cpu_sockets = var.gameserver_cpu_sockets
  cpu_cores   = var.gameserver_cpu_cores
  cpu_threads = var.gameserver_cpu_threads

  # Memória: memory e maximum_memory iguais (8 GiB). Sem isso o OLVM usa
  # maximum = 4x memory, reservado para hotplug, que aqui não faz sentido.
  #
  # O provider 2.2.0 NÃO expõe a "guaranteed memory" da memory policy, então
  # o valor pode vir do template (2 GiB). Com ballooning ligado, o host
  # poderia tomar memória da VM até esse piso, o que derrubaria um servidor
  # de jogo com heap Java grande. Desligar o ballooning mantém os 8 GiB
  # inteiros para o guest. Se quiser fixar a guaranteed em 8 GiB, ajuste no
  # Engine (Edit VM > System > Physical Memory Guaranteed) ou via API/Ansible.
  memory            = var.gameserver_memory_gb * 1024 * 1024 * 1024
  maximum_memory    = var.gameserver_memory_gb * 1024 * 1024 * 1024
  memory_ballooning = false

  initialization_hostname = var.gameserver_vm_name
  # Mesmo cloud-config da VM de aplicação: cria o mvrc com as duas chaves
  # SSH. No Ubuntu o grupo "wheel" não existe. O cloud-init cria esse grupo,
  # e o sudo vem da linha NOPASSWD, então funciona sem alterar o template
  # compartilhado (alterá-lo geraria diff na VM de aplicação).
  initialization_custom_script = local.cloud_init

  # IP fixo opcional, mesmo padrão de main.tf. Para servidor de jogo (port
  # forward no roteador) vale a pena fixar o IP via gameserver_ip_address.
  dynamic "initialization_nic" {
    for_each = var.gameserver_ip_address != null ? [1] : []
    content {
      name = var.gameserver_nic_name
      ipv4 {
        address = var.gameserver_ip_address
        netmask = var.vm_netmask
        gateway = var.vm_gateway
      }
    }
  }

  # GPU passthrough: o provider oVirt 2.2.0 não tem resource de host device.
  # Por enquanto existe só a variável gameserver_gpu_passthrough (ver
  # variables.tf). Quando for implementar, o caminho provável é: IOMMU
  # habilitado no host, VM fixada no host (placement_policy_affinity =
  # "pinned" + placement_policy_host_ids), cpu_mode = "host_passthrough" e
  # anexar o host device via API do Engine ou ovirt.ovirt (Ansible).
}

# O template não tem NIC, então ela é criada explicitamente, no mesmo vNIC
# profile usado pelas outras VMs (ID injetado via TF_VAR_vnic_profile_id).
resource "ovirt_nic" "gameserver" {
  vm_id           = ovirt_vm.gameserver.id
  name            = "nic1"
  vnic_profile_id = var.vnic_profile_id
}

# Aumenta o disco clonado do template para 60 GiB antes do primeiro boot.
# O growpart do cloud-init do Ubuntu expande a partição raiz automaticamente.
# Atenção: este resource redimensiona TODOS os discos da VM (o template tem
# só o disco do SO) e só aumenta - nunca reduz.
resource "ovirt_vm_disks_resize" "gameserver" {
  vm_id = ovirt_vm.gameserver.id
  size  = var.gameserver_disk_size_gb * 1024 * 1024 * 1024
}

# Liga a VM só depois da NIC e do resize, para o cloud-init já encontrar a
# placa de rede e o disco no tamanho final no primeiro boot.
resource "ovirt_vm_start" "gameserver" {
  vm_id = ovirt_vm.gameserver.id

  depends_on = [
    ovirt_nic.gameserver,
    ovirt_vm_disks_resize.gameserver,
  ]
}

# Mesmo mecanismo da VM de aplicação: sem IP fixo, descobre o IP do DHCP via
# guest agent (qemu-guest-agent precisa estar ativo no template Ubuntu).
data "ovirt_wait_for_ip" "gameserver" {
  count = var.gameserver_ip_address == null ? 1 : 0
  vm_id = ovirt_vm_start.gameserver.vm_id
}

locals {
  gameserver_dhcp_ip = try(
    [
      for iface in tolist(one(data.ovirt_wait_for_ip.gameserver).interfaces) : tolist(iface.ipv4_addresses)[0]
      if iface.name == var.gameserver_nic_name && length(iface.ipv4_addresses) > 0
    ][0],
    null
  )
}
