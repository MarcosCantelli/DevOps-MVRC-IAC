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

# Cluster e template (o OLVM não expõe data source de busca de cluster por
# nome - o ID precisa ser copiado do próprio Engine)
variable "cluster_id" {
  description = "ID do cluster OLVM onde a VM será criada"
  type        = string
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

# Rede - IP estático via cloud-init (initialization_nic), sem DHCP no ambiente on-premises
variable "nic_name" {
  description = "Nome da NIC já presente no template (ex: eth0)"
  type        = string
  default     = "eth0"
}

variable "vm_ip_address" {
  description = "IP estático a atribuir à VM"
  type        = string
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
