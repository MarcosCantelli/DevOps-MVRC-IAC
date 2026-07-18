# Autenticação OCI (API Key) - injetada via TF_VAR_ pelo Jenkins, nunca commitada
variable "tenancy_ocid" {
  description = "OCID da tenancy OCI"
  type        = string
  sensitive   = true
}

variable "user_ocid" {
  description = "OCID do usuário OCI usado para autenticação via API Key"
  type        = string
  sensitive   = true
}

variable "fingerprint" {
  description = "Fingerprint da chave de API OCI"
  type        = string
  sensitive   = true
}

variable "private_key_path" {
  description = "Caminho local para a chave privada da API OCI (PEM)"
  type        = string
  sensitive   = true
}

# Região e compartment
variable "region" {
  description = "Região OCI (ex: sa-saopaulo-1)"
  type        = string
}

variable "compartment_ocid" {
  description = "OCID do compartment onde os recursos serão criados"
  type        = string
}

# VM
variable "vm_name" {
  description = "Nome da instância"
  type        = string
  default     = "oci-app-server"
}

variable "shape" {
  description = "Shape da instância (Always Free AMD = VM.Standard.E2.1.Micro: 1 OCPU / 1GB RAM)"
  type        = string
  default     = "VM.Standard.E2.1.Micro"
}

variable "boot_volume_size_gb" {
  description = "Tamanho do boot volume em GB (Always Free permite até 200GB somados entre volumes)"
  type        = number
  default     = 50
}

# Rede
variable "vcn_cidr" {
  description = "CIDR da VCN"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR da subnet pública"
  type        = string
  default     = "10.0.1.0/24"
}

# SSH - chaves autorizadas na VM (usuário opc no primeiro boot, depois mvrc).
# Caminhos injetados via TF_VAR_ pelo Jenkins (repo é público - sem paths
# pessoais commitados), mesmo padrão das credenciais OCI acima.
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
