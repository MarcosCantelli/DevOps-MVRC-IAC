# DEVOPS-MVRC-IAC (branch `olvm`)

> Pipeline de Infraestrutura como Código — provisionamento, configuração e deploy de aplicações containerizadas em uma VM Oracle Linux 9 no Oracle Linux Virtualization Manager (OLVM), on-premises, usando Jenkins, Terraform e Ansible.

> Esta branch é dedicada ao OLVM (estudo de migração do ambiente VMware/ESXi para virtualização KVM on-premises). A versão original vSphere continua nas branches `main`/`vcenter`, e a versão em nuvem (Oracle Cloud Infrastructure) está na branch `oci`.

---

## Overview

Este projeto implementa um pipeline DevOps completo para uma VM no OLVM (Oracle Linux Virtualization Manager), o hypervisor KVM on-premises da Oracle — sucessor natural do ambiente vSphere/ESXi neste laboratório. Toda a etapa — da criação da instância até a configuração do servidor de aplicação — é automatizada e disparada por merge de Pull Request (ou execução manual do job Jenkins).

O pipeline clona uma VM Oracle Linux 9 a partir de um template já preparado no OLVM via Terraform (provider `oVirt/ovirt` — o mesmo motor de API usado pelo OLVM), atribuindo IP estático e criando o usuário `mvrc` já no primeiro boot via cloud-init. Em seguida o Ansible configura swap, abre o firewall e instala Docker + Traefik para hospedar aplicações em containers — a mesma base já usada na branch `oci`.

---

## Architecture

```
GitHub (PR merged to main)
        │
        ▼
   Webhook (ngrok tunnel)
        │
        ▼
     Jenkins
        │
        ├── Stage 1 → Terraform   →  Clona a VM do template no OLVM (IP estático, cloud-init)
        │
        ├── Stage 2 → Ansible     →  Configura a VM (swap, firewalld, Docker, Traefik)
        │
        └── Post Actions          →  Reporta sucesso ou destrói a VM em caso de falha
```

---

## Infraestrutura

| Componente      | Detalhes                                              |
|------------------|--------------------------------------------------------|
| Hypervisor       | OLVM (Oracle Linux Virtualization Manager, KVM)        |
| CI/CD            | Jenkins (self-hosted)                                  |
| Tunnel           | ngrok (expõe o Jenkins para webhooks do GitHub)        |
| IaC              | Terraform com provider `oVirt/ovirt`                   |
| Configuração     | Ansible                                                |
| SO               | Oracle Linux 9 (template pré-preparado com cloud-init) |
| Rede             | IP estático via cloud-init (`initialization_nic`)      |
| Swap             | Swapfile de 4GB                                        |
| Reverse Proxy    | Traefik (Docker-native, roteamento por path)           |
| Runtime          | Docker CE + Compose plugin                             |

---

## Repository Structure

```
DEVOPS-MVRC-IAC/
│
├── Jenkinsfile                        # CI/CD pipeline definition
├── README.md
├── .gitignore
│
├── terraform/
│   ├── main.tf                        # Provider oVirt, lookup do template e clone da VM
│   ├── variables.tf                   # Variable declarations
│   ├── outputs.tf                     # IP estático da VM
│   ├── versions.tf                    # Provider version lock
│   ├── terraform.tfvars               # Valores não sensíveis (cluster, template, rede...)
│   └── templates/
│       └── cloud-init.yaml.tpl        # cloud-config: cria o mvrc + DNS no primeiro boot
│
└── ansible/
    ├── ansible.cfg                    # Ansible configuration
    ├── inventory/
    │   └── hosts.ini                  # Gerado dinamicamente pelo Jenkins
    ├── playbooks/
    │   └── provision-olvm-vm.yml      # Playbook principal (OLVM)
    └── roles/
        ├── swap/                      # Swapfile de 4GB
        ├── base/                      # Pacotes essenciais (dnf)
        ├── firewalld/                 # Abre as portas 80/443 para o Traefik
        ├── docker/                    # Docker CE via repositório compatível RHEL/CentOS
        ├── traefik/                   # Reverse proxy compartilhado (Docker, roteamento por path)
        │
        ├── mvrc-user/                 # [não usado nesta branch - ver nota abaixo]
        ├── java/                      # [legado vSphere/Ubuntu - não usado nesta branch]
        ├── nodejs/                    # [legado vSphere/Ubuntu - não usado nesta branch]
        └── app-user/                  # [legado vSphere/Ubuntu - não usado nesta branch]
```

> Diferença importante em relação à branch `oci`: lá o usuário `mvrc` era criado pelo Ansible (via role `mvrc-user`) depois de conectar como `opc`, o usuário padrão da imagem Oracle da OCI. Aqui não existe esse usuário padrão de imagem — o próprio cloud-init do OLVM (`templates/cloud-init.yaml.tpl`) já cria o `mvrc` com as chaves SSH e sudo no primeiro boot, então o Ansible conecta direto como `mvrc` e a role `mvrc-user` fica sem uso nesta branch (preservada como referência).

---

## Pipeline Stages

### 1. Checkout
Loga branch e commit para rastreabilidade.

### 2. Limpar state anterior
Remove arquivos de state do Terraform de execuções anteriores.

```bash
rm -f terraform.tfstate terraform.tfstate.backup tfplan
```

### 3. Terraform Init / Plan / Apply
Inicializa o provider `oVirt/ovirt`, localiza o template Oracle Linux 9 pelo nome e clona a VM no cluster informado, com CPU/memória, IP estático e cloud-init definidos nas variáveis. A criação da VM (`ovirt_vm`) e a ligação dela (`ovirt_vm_start`) são operações separadas no OLVM - o Terraform já cuida das duas.

### 4. Capturar IP da VM
Como o IP é estático (definido por você em `vm_ip_address`), este stage apenas lê o output `vm_ip_address` do Terraform para uso nos stages seguintes.

### 5. Aguardar VM inicializar
Faz polling na porta 22 a cada 10s (até 5 minutos) antes de repassar para o Ansible.

### 6. Ansible — Provisionar VM OLVM
Conecta diretamente como `mvrc` (criado pelo cloud-init) e executa, em ordem:

| Role         | O que faz                                                              |
|--------------|--------------------------------------------------------------------------|
| `swap`       | Cria e ativa um swapfile de 4GB, persistido em `/etc/fstab`             |
| `base`       | Instala pacotes essenciais via `dnf` (curl, wget, git, unzip...)        |
| `firewalld`  | Libera as portas 80 e 443 no firewall local da instância                |
| `docker`     | Instala Docker CE + Compose plugin, adiciona `mvrc` ao grupo `docker`   |
| `traefik`    | Sobe o Traefik compartilhado (Docker, roteamento por path)              |

### Post Actions
- **Sucesso**: loga o IP da VM.
- **Falha**: executa `terraform destroy` automaticamente para não deixar recursos órfãos.

---

## Fluxo de autenticação SSH

1. O Terraform lê duas chaves públicas locais (a sua e a do Jenkins) e monta um cloud-config (`templates/cloud-init.yaml.tpl`) que cria o usuário `mvrc`, autoriza as duas chaves e concede sudo sem senha.
2. Esse cloud-config é passado como `initialization_custom_script` da VM — executado pelo cloud-init já instalado no template, no primeiro boot.
3. O Jenkins (e você) conectam via SSH diretamente como `mvrc`, sem nenhum usuário intermediário.

---

## Pré-requisito: template Oracle Linux 9 no OLVM

O provider oVirt não tem um catálogo de imagens como a OCI — o template precisa existir de antemão no OLVM:

1. Crie uma VM no OLVM, instale Oracle Linux 9 e o pacote `cloud-init` (`dnf install cloud-init`, `systemctl enable cloud-init`).
2. Rode `virt-sysprep` (ou o processo equivalente) para generalizar a VM e remova qualquer configuração de rede fixa.
3. No OLVM, use **Make Template** para transformar a VM selada em template. Anote o **nome exato** do template — ele vai em `template_name` no `terraform.tfvars`.
4. Confirme o nome da NIC do template (geralmente `eth0`) — ele vai em `nic_name`.

---

## Traefik Configuration

A VM hospeda várias aplicações lado a lado, então em vez de cada uma reivindicar sua própria porta, o Traefik escuta na porta 80 e roteia por path, descobrindo os containers automaticamente via labels do Docker declaradas no `docker-compose.yml` de cada aplicação:

```
GET /crochejuka/*  → roteado para os containers frontend/backend do crochedajuka
GET /wr13/*        → roteado para o container frontend do wr13
```

Nenhuma configuração aqui precisa mudar quando uma nova aplicação é adicionada — ela só precisa entrar na rede Docker externa `web` e declarar seus próprios labels `traefik.*`.

---

## Prerequisites

### Jenkins Server
- Jenkins instalado e rodando na porta `8080`
- Plugins: `GitHub Integration Plugin`
- Ferramentas instaladas: `terraform`, `ansible`, `netcat`
- Par de chaves SSH gerado em `/var/lib/jenkins/.ssh/ansible_key`

### GitHub
- Webhook do repositório apontando para `https://<ngrok-url>/github-webhook/`
- Personal Access Token (PAT) com escopos `repo` e `admin:repo_hook`

### OLVM
- Engine acessível via API (`https://<olvm-engine>/ovirt-engine/api`)
- Usuário com permissão de criar/iniciar/destruir VMs no cluster de destino (ex: `admin@internal`)
- Template Oracle Linux 9 com cloud-init preparado (ver seção acima)
- ID do cluster de destino (`Compute → Clusters` no portal do OLVM)

### Jenkins Credentials (configuradas via Manage Jenkins → Credentials)

| Credential ID                  | Type        | Description                                                        |
|---------------------------------|-------------|----------------------------------------------------------------------|
| `olvm-url`                      | Secret text | URL da API do OLVM Engine                                            |
| `olvm-username`                 | Secret text | Usuário de autenticação no OLVM (ex: `admin@internal`)               |
| `olvm-password`                 | Secret text | Senha do usuário OLVM                                                |
| `mvrc-ssh-public-key-path`      | Secret text | Caminho local (no agente Jenkins) para a chave pública SSH pessoal   |
| `jenkins-ssh-public-key-path`   | Secret text | Caminho local para a chave pública SSH do Jenkins (`ansible_key.pub`) |
| `github-pat`                    | Secret text | GitHub Personal Access Token                                         |

---

## Setup Guide

### 1. Clone este repositório e mude para a branch `olvm`

```bash
git clone https://github.com/your-username/DEVOPS-MVRC-IAC.git
cd DEVOPS-MVRC-IAC
git checkout olvm
```

### 2. Configure `terraform/terraform.tfvars`

```hcl
ovirt_tls_insecure = true

cluster_id    = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
template_name = "OracleLinux9-cloudinit"

vm_name     = "olvm-app-server"
cpu_cores   = 2
cpu_sockets = 1
cpu_threads = 1
memory_gb   = 2

nic_name      = "eth0"
vm_ip_address = "192.168.31.xx"
vm_netmask    = "255.255.255.0"
vm_gateway    = "192.168.31.1"
dns_primary   = "192.168.31.1"
dns_secondary = "8.8.8.8"
```

> `ovirt_url`, `ovirt_username`, `ovirt_password`, `my_ssh_public_key_path` e `jenkins_ssh_public_key_path` **nunca** são armazenados neste arquivo — este repositório é público. Todos são injetados pelo Jenkins em tempo de execução via variáveis `TF_VAR_`.

### 3. Start ngrok no servidor Jenkins

```bash
ngrok http 8080
```

### 4. Configure o Webhook do GitHub

```
Payload URL:   https://abc123.ngrok-free.app/github-webhook/
Content type:  application/json
Events:        Just the push event
```

### 5. Configure as credenciais no Jenkins

Adicione as 5 credenciais OLVM/SSH + o PAT do GitHub listadas na tabela acima em `Manage Jenkins → Credentials`.

### 6. Crie o job do pipeline no Jenkins

- New Item → Pipeline
- Build Triggers: `GitHub hook trigger for GITScm polling`
- Pipeline: `Pipeline script from SCM` → Git → URL do seu repo → branch `*/olvm`
- Script Path: `Jenkinsfile`

### 7. Dispare o pipeline

Push de qualquer commit na branch configurada (ou execute manualmente pelo Jenkins).

---

## Security Considerations

- Credenciais OLVM (URL, usuário, senha) e os caminhos das chaves SSH ficam nos Secrets do Jenkins e são injetados como variáveis `TF_VAR_` — nunca aparecem em código ou logs.
- O `.gitignore` exclui todos os arquivos de state do Terraform (`*.tfstate`), planos (`*.tfplan`) e o cache `.terraform/`.
- Acesso SSH às VMs provisionadas usa apenas autenticação por chave.
- O usuário `mvrc` é criado com sudo sem senha apenas para simplificar a automação em ambiente de laboratório — avalie restringir isso em produção.
- `ovirt_tls_insecure = true` desabilita a validação do certificado do Engine — aceitável em lab com certificado self-signed, mas troque por `tls_ca_files` em um ambiente real.
- O túnel ngrok é usado apenas para fins de laboratório local. Em produção, deve ser substituído por uma regra de firewall adequada ou um reverse proxy dedicado com TLS.

---

## Technologies Used

| Tool           | Version     | Purpose                                           |
|-----------------|-------------|------------------------------------------------------|
| Jenkins         | 2.x LTS     | Orquestração CI/CD                                   |
| Terraform       | >= 1.5.0    | Provisionamento de infraestrutura (IaC)              |
| oVirt Provider  | >= 2.0.0    | Provider Terraform para OLVM/oVirt Engine            |
| Ansible         | 2.16+       | Gerenciamento de configuração                        |
| OLVM            | -           | Hypervisor KVM on-premises (Oracle Linux Virt. Manager) |
| ngrok           | 3.x         | Túnel de webhook para Jenkins local                  |
| Docker CE       | latest      | Runtime de containers para as aplicações             |
| Traefik         | v3.7        | Reverse proxy compartilhado (roteamento por path)    |
| Oracle Linux    | 9.x         | SO do template e das instâncias provisionadas        |

---

## Author

**Marcos Cantelli**
DevOps & Infrastructure Engineer

[GitHub](https://github.com/MarcosCantelli) · [LinkedIn](www.linkedin.com/in/marcos-cantelli-a450bb169)

---

## License

This project is intended for learning and portfolio purposes.
