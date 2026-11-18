# Autenticação no OLVM (ovirt_url, ovirt_username, ovirt_password), o
# cluster_id, o vnic_profile_id e os caminhos das chaves SSH (my_ssh_public_key_path,
# jenkins_ssh_public_key_path) são injetados pelo Jenkins via variáveis
# TF_VAR_ - NUNCA preencha aqui (repo público).

# Lab on-premises com certificado self-signed no Engine
ovirt_tls_insecure = true

# Template (nome não é sensível - é só um rótulo dado por você no OLVM)
template_name = "Ubuntu-Terraform"

# VM
vm_name     = "olvm-app-server"
cpu_cores   = 2
cpu_sockets = 1
cpu_threads = 1
memory_gb   = 2

# Rede - primeira VM em DHCP (vm_ip_address não preenchido). Quando migrar
# para IP fixo, defina vm_ip_address e ajuste netmask/gateway se preciso.
nic_name      = "enp1s0"
dns_primary   = "192.168.31.10"
dns_secondary = "8.8.8.8"

# Gameserver (ver gameserver.tf). DESLIGADO no pipeline: a VM é criada
# manualmente com -var gameserver_enabled=true (ver README).
gameserver_enabled       = false
gameserver_template_name = "Ubuntu-Terraform"
gameserver_vm_name       = "gameserver"
gameserver_cpu_sockets   = 1
gameserver_cpu_cores     = 8
gameserver_cpu_threads   = 1
gameserver_memory_gb     = 8
gameserver_disk_size_gb  = 60
gameserver_nic_name      = "enp1s0"
