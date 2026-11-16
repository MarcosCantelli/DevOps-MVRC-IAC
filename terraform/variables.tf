# Autenticação no OLVM (oVirt Engine API) - injetada via TF_VAR_ pelo Jenkins,
# nunca commitada (repo público).
variable "ovirt_url" {
  description = "URL da API do OLVM Engine (ex: https://olvm.mvrc.lan/ovirt-engine/api)"
  type        = string
  sensitive   = true
}

variable "ovirt_username" {
  description = "Usuário para autenticação no OLVM (ex: admin@internal)"
  type        = string
  sensitive   = true
}

variable "ovirt_password" {
  description = "Senha para autenticação no OLVM"
  type        = string
  sensitive   = true
}

# Self-signed é comum em labs on-prem - equivalente ao allow_unverified_ssl
# usado no provider vSphere original. Ajuste para false + tls_ca_files em produção.
variable "ovirt_tls_insecure" {
  description = "Desabilita a validação do certificado TLS do OLVM Engine"
  type        = bool
  default     = true
}

# Cluster (o OLVM não expõe data source de busca por nome - o ID precisa ser
# copiado do próprio Engine). Sensível e injetado via TF_VAR_ pelo Jenkins -
# é um identificador interno do ambiente, sem motivo pra ficar num repo público.
variable "cluster_id" {
  description = "ID do cluster OLVM onde a VM será criada"
  type        = string
  sensitive   = true
}

variable "template_name" {
  description = "Nome do template Oracle Linux 9 já preparado com cloud-init no OLVM"
  type        = string
}

# VM
variable "vm_name" {
  description = "Nome da instância"
  type        = string
  default     = "olvm-app-server"
}

variable "cpu_cores" {
  description = "Núcleos de CPU por socket"
  type        = number
  default     = 2
}

variable "cpu_sockets" {
  description = "Sockets de CPU"
  type        = number
  default     = 1
}

variable "cpu_threads" {
  description = "Threads por núcleo"
  type        = number
  default     = 1
}

variable "memory_gb" {
  description = "Memória RAM em GB"
  type        = number
  default     = 2
}

# Rede - se vm_ip_address for null, a VM sobe em DHCP e o IP é descoberto
# depois via guest agent (ver ovirt_wait_for_ip em main.tf). Para IP fixo,
# preencha vm_ip_address no terraform.tfvars.
variable "nic_name" {
  description = "Nome da NIC já presente no template (Oracle Linux 9 usa nomes previsíveis, ex: enp1s0, não eth0)"
  type        = string
  default     = "enp1s0"
}

variable "vm_ip_address" {
  description = "IP estático a atribuir à VM. Deixe null para usar DHCP."
  type        = string
  default     = null
}

variable "vm_netmask" {
  description = "Máscara de rede"
  type        = string
  default     = "255.255.255.0"
}

variable "vm_gateway" {
  description = "Gateway padrão da rede"
  type        = string
  default     = "192.168.31.1"
}

variable "dns_primary" {
  description = "Servidor DNS primário"
  type        = string
  default     = "192.168.31.1"
}

variable "dns_secondary" {
  description = "Servidor DNS secundário"
  type        = string
  default     = "8.8.8.8"
}

# SSH - chaves autorizadas para o usuário mvrc, criado via cloud-init no
# primeiro boot. Caminhos injetados via TF_VAR_ pelo Jenkins (repo público).
variable "my_ssh_public_key_path" {
  description = "Caminho para a chave pública SSH pessoal (mvrc)"
  type        = string
  sensitive   = true
}

variable "jenkins_ssh_public_key_path" {
  description = "Caminho para a chave pública SSH do Jenkins (usada pelo Ansible)"
  type        = string
  sensitive   = true
}

# Rede compartilhada - vNIC profile (rede lógica) das VMs. A VM de aplicação
# herda a NIC do template, mas o template Ubuntu do gameserver não tem NIC, então
# ela é criada via ovirt_nic, que exige o ID do profile (o provider não tem
# data source de busca por nome). Mesmo tratamento do cluster_id: ID interno
# do ambiente, injetado via TF_VAR_ pelo Jenkins.
variable "vnic_profile_id" {
  description = "ID do vNIC profile (mesma rede das outras VMs) usado nas NICs criadas pelo Terraform"
  type        = string
  sensitive   = true
}

# Gameserver - VM dedicada a servidores de jogos (ver gameserver.tf)
variable "gameserver_template_name" {
  description = "Nome do template Ubuntu (BIOS, sem NIC, com cloud-init e qemu-guest-agent) no OLVM"
  type        = string
  default     = "Ubuntu-Terraform"
}

variable "gameserver_vm_name" {
  description = "Nome (e hostname) da VM de servidor de jogos"
  type        = string
  default     = "gameserver"
}

variable "gameserver_cpu_sockets" {
  description = "Sockets de CPU do gameserver"
  type        = number
  default     = 1
}

variable "gameserver_cpu_cores" {
  description = "Núcleos de CPU por socket do gameserver"
  type        = number
  default     = 8
}

variable "gameserver_cpu_threads" {
  description = "Threads por núcleo do gameserver"
  type        = number
  default     = 1
}

variable "gameserver_memory_gb" {
  description = "Memória RAM do gameserver em GiB (usada em memory e maximum_memory)"
  type        = number
  default     = 8
}

variable "gameserver_disk_size_gb" {
  description = "Tamanho final do disco do gameserver em GiB (só aumenta, nunca reduz)"
  type        = number
  default     = 60
}

variable "gameserver_nic_name" {
  description = "Nome da NIC dentro do guest Ubuntu (confirme com ip -o link: enp1s0 em Q35, ens3 em i440fx)"
  type        = string
  default     = "enp1s0"
}

variable "gameserver_ip_address" {
  description = "IP estático do gameserver. Deixe null para usar DHCP (IP descoberto via guest agent)."
  type        = string
  default     = null
}

# Preparada para o futuro: o provider oVirt 2.2.0 não suporta host devices,
# então a variável ainda não tem efeito. A validação impede habilitá-la por
# engano achando que a GPU foi anexada. Ver comentário em gameserver.tf.
variable "gameserver_gpu_passthrough" {
  description = "Habilita GPU passthrough no gameserver (ainda não suportado pelo provider)"
  type        = bool
  default     = false

  validation {
    condition     = !var.gameserver_gpu_passthrough
    error_message = "gameserver_gpu_passthrough = true ainda não é suportado: o provider oVirt 2.2.0 não gerencia host devices."
  }
}
