# Autenticação no OLVM (ovirt_url, ovirt_username, ovirt_password) e os
# caminhos das chaves SSH (my_ssh_public_key_path, jenkins_ssh_public_key_path)
# são injetados pelo Jenkins via variáveis TF_VAR_ - NUNCA preencha aqui
# (repo público).

# Lab on-premises com certificado self-signed no Engine
ovirt_tls_insecure = true

# Cluster e template (IDs/nomes copiados do próprio OLVM Engine)
cluster_id    = "REPLACE_WITH_YOUR_CLUSTER_ID"
template_name = "OracleLinux9-cloudinit"

# VM
vm_name     = "olvm-app-server"
cpu_cores   = 2
cpu_sockets = 1
cpu_threads = 1
memory_gb   = 2

# Rede - mesma LAN usada pela VM de produção original (vSphere)
nic_name      = "eth0"
vm_ip_address = "REPLACE_WITH_A_FREE_IP_ON_YOUR_LAN"
vm_netmask    = "255.255.255.0"
vm_gateway    = "192.168.31.1"
dns_primary   = "192.168.31.1"
dns_secondary = "8.8.8.8"
