# DEVOPS-MVRC-IAC (branch `oci`)

> Pipeline de Infraestrutura como Código — provisionamento, configuração e deploy de aplicações containerizadas em uma VM Always Free da Oracle Cloud Infrastructure (OCI), usando Jenkins, Terraform e Ansible.

> Esta branch é dedicada à Oracle Cloud. A versão original para vSphere/ESXi on-premise continua disponível nas branches `main` e `vcenter`.

---

## Overview

Este projeto implementa um pipeline DevOps completo para uma VM na Oracle Cloud (Always Free Tier). Toda a etapa — da criação da instância até a configuração do servidor de aplicação — é automatizada e disparada por merge de Pull Request na branch `main` (ou execução manual do job Jenkins).

O pipeline provisiona uma instância `VM.Standard.E2.1.Micro` (Always Free, AMD, 1 OCPU / 1GB RAM) rodando Oracle Linux 9 via Terraform, e então repassa para o Ansible, que cria o usuário de operação, configura swap, abre o firewall e instala Docker + Traefik para hospedar aplicações em containers.

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
        ├── Stage 1 → Terraform   →  Provisiona VCN, subnet e instância na OCI
        │
        ├── Stage 2 → Ansible     →  Configura a VM (usuário mvrc, swap, firewalld, Docker, Traefik)
        │
        └── Post Actions          →  Reporta sucesso ou destrói a VM em caso de falha
```

---

## Infraestrutura

| Componente      | Detalhes                                              |
|------------------|--------------------------------------------------------|
| Cloud            | Oracle Cloud Infrastructure (OCI) — Always Free Tier   |
| Shape            | `VM.Standard.E2.1.Micro` (AMD, 1 OCPU / 1GB RAM)       |
| CI/CD            | Jenkins (self-hosted)                                  |
| Tunnel           | ngrok (expõe o Jenkins para webhooks do GitHub)        |
| IaC              | Terraform com provider `oracle/oci`                    |
| Configuração     | Ansible                                                 |
| SO               | Oracle Linux 9 (última build 9.x, hoje 9.7)             |
| Swap             | Swapfile de 4GB                                         |
| Reverse Proxy    | Traefik (Docker-native, roteamento por path)            |
| Runtime          | Docker CE + Compose plugin                              |

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
│   ├── main.tf                        # VCN, subnet, security list e instância OCI
│   ├── variables.tf                   # Variable declarations
│   ├── outputs.tf                     # IP público da VM
│   ├── versions.tf                    # Provider version lock
│   └── terraform.tfvars               # Valores não sensíveis (region, compartment, shape...)
│
└── ansible/
    ├── ansible.cfg                    # Ansible configuration
    ├── inventory/
    │   └── hosts.ini                  # Gerado dinamicamente pelo Jenkins
    ├── playbooks/
    │   └── provision-oci-vm.yml       # Playbook principal (OCI)
    └── roles/
        ├── mvrc-user/                 # Cria o usuário mvrc + autoriza as chaves SSH + sudo
        ├── swap/                      # Swapfile de 4GB
        ├── base/                      # Pacotes essenciais (dnf)
        ├── firewalld/                 # Abre as portas 80/443 para o Traefik
        ├── docker/                    # Docker CE via repositório compatível RHEL/CentOS
        ├── traefik/                   # Reverse proxy compartilhado (Docker, roteamento por path)
        │
        ├── java/                      # [legado vSphere/Ubuntu - não usado nesta branch]
        ├── nodejs/                    # [legado vSphere/Ubuntu - não usado nesta branch]
        └── app-user/                  # [legado vSphere/Ubuntu - não usado nesta branch]
```

> As roles `java`, `nodejs` e `app-user` são resquício da versão vSphere/Ubuntu (apt-based) e não são chamadas pelo playbook `provision-oci-vm.yml`. Ficam preservadas apenas como referência para uma eventual adaptação futura, caso a VM da OCI passe a rodar runtimes nativos além dos containers Docker.

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
Inicializa o provider `oracle/oci`, gera o plano e provisiona: VCN, internet gateway, route table, security list (portas 22/80/443) e a instância Oracle Linux 9.

### 4. Capturar IP público da VM
Extrai o IP público da instância a partir do output `vm_public_ip` do Terraform.

### 5. Aguardar VM inicializar
Faz polling na porta 22 a cada 10s (até 5 minutos) antes de repassar para o Ansible.

### 6. Ansible — Provisionar VM OCI
Conecta como `opc` (usuário padrão das imagens Oracle Linux) e executa, em ordem:

| Role         | O que faz                                                              |
|--------------|--------------------------------------------------------------------------|
| `mvrc-user`  | Cria o usuário `mvrc`, autoriza as chaves SSH (pessoal + Jenkins) e concede sudo sem senha |
| `swap`       | Cria e ativa um swapfile de 4GB, persistido em `/etc/fstab`             |
| `base`       | Instala pacotes essenciais via `dnf` (curl, wget, git, unzip...)        |
| `firewalld`  | Libera as portas 80 e 443 no firewall local da instância                |
| `docker`     | Instala Docker CE + Compose plugin, adiciona `mvrc` ao grupo `docker`   |
| `traefik`    | Sobe o Traefik compartilhado (Docker, roteamento por path)              |

### Post Actions
- **Sucesso**: loga o IP público da VM.
- **Falha**: executa `terraform destroy` automaticamente para não deixar recursos órfãos.

---

## Fluxo de autenticação SSH

1. O Terraform lê duas chaves públicas locais (a sua e a do Jenkins) e as autoriza no usuário padrão `opc`, via `metadata.ssh_authorized_keys`, no primeiro boot da instância.
2. O Jenkins conecta via Ansible como `opc`, usando a chave do Jenkins.
3. A role `mvrc-user` cria o usuário `mvrc` e replica as **mesmas duas chaves** para ele, além de conceder sudo sem senha.
4. A partir daí, tanto você quanto o Jenkins podem acessar a VM diretamente como `mvrc` (autenticação só por chave, sem senha).

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

### Oracle Cloud Infrastructure
- Conta OCI com Always Free Tier disponível na região escolhida
- Um **compartment** criado para os recursos deste projeto (anote o OCID)
- Um **API Key** gerado para o seu usuário OCI (`Profile → My Profile → API Keys → Add API Key`), com:
  - `tenancy_ocid`
  - `user_ocid`
  - `fingerprint`
  - chave privada (`.pem`) disponível no servidor Jenkins

### Jenkins Credentials (configuradas via Manage Jenkins → Credentials)

| Credential ID                  | Type        | Description                                        |
|---------------------------------|-------------|------------------------------------------------------|
| `oci-tenancy-ocid`              | Secret text | OCID da tenancy OCI                                  |
| `oci-user-ocid`                 | Secret text | OCID do usuário OCI                                  |
| `oci-fingerprint`                | Secret text | Fingerprint da API Key                              |
| `oci-api-private-key`           | Secret file | Chave privada (`.pem`) da API Key OCI                |
| `mvrc-ssh-public-key-path`      | Secret text | Caminho local (no agente Jenkins) para a chave pública SSH pessoal |
| `jenkins-ssh-public-key-path`   | Secret text | Caminho local para a chave pública SSH do Jenkins (`ansible_key.pub`) |
| `github-pat`                    | Secret text | GitHub Personal Access Token                         |

---

## Setup Guide

### 1. Clone este repositório e mude para a branch `oci`

```bash
git clone https://github.com/your-username/DEVOPS-MVRC-IAC.git
cd DEVOPS-MVRC-IAC
git checkout oci
```

### 2. Configure `terraform/terraform.tfvars`

```hcl
region            = "sa-saopaulo-1"
compartment_ocid  = "ocid1.compartment.oc1..xxxxxxxx"

vm_name             = "oci-app-server"
shape               = "VM.Standard.E2.1.Micro"
boot_volume_size_gb = 50
```

> `tenancy_ocid`, `user_ocid`, `fingerprint`, `private_key_path`, `my_ssh_public_key_path` e `jenkins_ssh_public_key_path` **nunca** são armazenados neste arquivo — este repositório é público. Todos são injetados pelo Jenkins em tempo de execução via variáveis `TF_VAR_`.

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

Adicione as 6 credenciais OCI/SSH + o PAT do GitHub listadas na tabela acima em `Manage Jenkins → Credentials`.

### 6. Crie o job do pipeline no Jenkins

- New Item → Pipeline
- Build Triggers: `GitHub hook trigger for GITScm polling`
- Pipeline: `Pipeline script from SCM` → Git → URL do seu repo → branch `*/oci`
- Script Path: `Jenkinsfile`

### 7. Dispare o pipeline

Push de qualquer commit na branch configurada (ou execute manualmente pelo Jenkins).

---

## Security Considerations

- Credenciais OCI (tenancy, user, fingerprint, chave privada) ficam nos Secrets do Jenkins e são injetadas como variáveis `TF_VAR_` — nunca aparecem em código ou logs.
- O `.gitignore` exclui todos os arquivos de state do Terraform (`*.tfstate`), planos (`*.tfplan`) e o cache `.terraform/`.
- Acesso SSH às VMs provisionadas usa apenas autenticação por chave.
- O usuário `mvrc` é criado com sudo sem senha apenas para simplificar a automação em ambiente de laboratório — avalie restringir isso em produção.
- A Security List da OCI libera as portas 22/80/443 para `0.0.0.0/0` por padrão de laboratório; restrinja o CIDR de origem em um ambiente real.
- O túnel ngrok é usado apenas para fins de laboratório local. Em produção, deve ser substituído por uma regra de firewall adequada ou um reverse proxy dedicado com TLS.

---

## Technologies Used

| Tool          | Version   | Purpose                                    |
|----------------|-----------|----------------------------------------------|
| Jenkins        | 2.x LTS   | Orquestração CI/CD                           |
| Terraform      | >= 1.5.0  | Provisionamento de infraestrutura (IaC)      |
| OCI Provider   | >= 5.0.0  | Provider Terraform para Oracle Cloud         |
| Ansible        | 2.16+     | Gerenciamento de configuração                |
| Oracle Cloud   | Always Free | Plataforma de virtualização (shape E2.1.Micro) |
| ngrok          | 3.x       | Túnel de webhook para Jenkins local          |
| Docker CE      | latest    | Runtime de containers para as aplicações     |
| Traefik        | v3.7      | Reverse proxy compartilhado (roteamento por path) |
| Oracle Linux   | 9.x (9.7) | SO das instâncias provisionadas              |

---

## Author

**Marcos Cantelli**
DevOps & Infrastructure Engineer

[GitHub](https://github.com/MarcosCantelli) · [LinkedIn](www.linkedin.com/in/marcos-cantelli-a450bb169)

---

## License

This project is intended for learning and portfolio purposes.
