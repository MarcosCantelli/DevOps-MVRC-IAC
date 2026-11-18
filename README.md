# DEVOPS-MVRC-IAC

> Pipeline de Infraestrutura como Código — provisionamento, configuração e deploy de aplicações containerizadas em uma VM Ubuntu no Oracle Linux Virtualization Manager (OLVM), on-premises, usando Jenkins, Terraform e Ansible.

> A `main` é dedicada ao OLVM (estudo de migração do ambiente VMware/ESXi para virtualização KVM on-premises) e é a única branch que o pipeline executa. A versão original vSphere continua na branch `vcenter`, e a versão em nuvem (Oracle Cloud Infrastructure) está na branch `oci`.

---

## Overview

Este projeto implementa um pipeline DevOps completo para uma VM no OLVM (Oracle Linux Virtualization Manager), o hypervisor KVM on-premises da Oracle — sucessor natural do ambiente vSphere/ESXi neste laboratório. Toda a etapa — da criação da instância até a configuração do servidor de aplicação — é automatizada e disparada por merge de Pull Request (ou execução manual do job Jenkins).

O pipeline clona uma VM Ubuntu a partir de um template já preparado no OLVM via Terraform (provider `oVirt/ovirt` — o mesmo motor de API usado pelo OLVM), cria a placa de rede, atribui IP (DHCP ou estático) e cria o usuário `mvrc` já no primeiro boot via cloud-init. Em seguida o Ansible configura swap, abre o firewall e instala Docker + Traefik para hospedar aplicações em containers — a mesma base já usada na branch `oci`.

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
        ├── Stage 2 → Ansible     →  Configura a VM (swap, UFW, Docker, Traefik)
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
| SO               | Ubuntu (template `Ubuntu-Terraform` com cloud-init)    |
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
        ├── base/                      # Pacotes essenciais (apt)
        ├── ufw/                       # Firewall: libera 22/80/443 e bloqueia o resto
        ├── docker/                    # Docker CE via repositório oficial do Ubuntu
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
Inicializa o provider `oVirt/ovirt`, localiza o template Ubuntu pelo nome e clona a VM no cluster informado, com CPU/memória e cloud-init definidos nas variáveis. O template não tem placa de rede: o Terraform cria a NIC (`ovirt_nic`) no vNIC profile informado em `olvm-vnic-profile-id`. A criação da VM (`ovirt_vm`), a NIC e a ligação da VM (`ovirt_vm_start`) são operações separadas no OLVM - o Terraform cuida de todas.

### 4. Capturar IP da VM
Como o IP é estático (definido por você em `vm_ip_address`), este stage apenas lê o output `vm_ip_address` do Terraform para uso nos stages seguintes.

### 5. Aguardar VM inicializar
Faz polling na porta 22 a cada 10s (até 5 minutos) antes de repassar para o Ansible.

### 6. Ansible — Provisionar VM OLVM
Conecta diretamente como `mvrc` (criado pelo cloud-init), espera o cloud-init terminar o primeiro boot e executa, em ordem:

| Role         | O que faz                                                              |
|--------------|--------------------------------------------------------------------------|
| `swap`       | Cria e ativa um swapfile de 4GB, persistido em `/etc/fstab`             |
| `base`       | Instala pacotes essenciais via `apt` (curl, wget, git, unzip...)        |
| `ufw`        | Libera 22, 80 e 443 e ativa o UFW (bloqueia o resto da entrada)         |
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

## Pré-requisito: template Ubuntu no OLVM

O provider oVirt não tem um catálogo de imagens como a OCI — o template precisa existir de antemão no OLVM. A VM de aplicação e o gameserver usam o mesmo template (`Ubuntu-Terraform`):

1. Crie uma VM no OLVM, instale o Ubuntu Server e os pacotes `cloud-init` e `qemu-guest-agent` (o guest agent é o que informa o IP do DHCP ao Terraform).
2. Remova a placa de rede da VM: o Terraform cria a NIC de cada VM clonada.
3. Generalize a VM (`sudo cloud-init clean --logs`, `sudo truncate -s 0 /etc/machine-id`) e desligue.
4. No OLVM, use **Make Template** (marcando *Seal Template* se disponível). Anote o **nome exato** do template — ele vai em `template_name` no `terraform.tfvars`.
5. **O disco do template não pode ficar no `hosted_storage`** (o storage do Hosted Engine). Ali só SuperUser cria discos, e o clone feito pelo usuário do Jenkins falha com `Internal Engine Error` (no `engine.log`: `NON_ADMIN_USER_NOT_AUTHORIZED_TO_PERFORM_ACTION_ON_HE`). Deixe o disco só num domínio de dados comum (ex: `data_vms_hd`). Para tirar uma cópia de um domínio, use a aba **Storage** do template → domínio → disco → **Remover** (o *Remover* da tela geral de Discos apaga o template inteiro).
6. Confirme o nome da NIC com `ip -o link show` numa VM clonada (ex: `enp1s0` em Q35, `ens3` em i440fx). Esse nome vai em `nic_name`; se não bater, o Terraform usa a primeira interface com IPv4.

---

## Gameserver (VM `gameserver`, Ubuntu)

VM separada para servidores de jogos (Project Zomboid B42 em Docker). Ela é criada por `terraform/gameserver.tf` e configurada pelo playbook `ansible/playbooks/gameserver.yml` (roles `gs_*`), **fora do pipeline do Jenkins** por enquanto.

### Criação da VM (manual, com state local)

No pipeline, `gameserver_enabled = false`. O Jenkins apaga o tfstate a cada run e roda `destroy` quando falha, então ele não pode ser dono da VM de jogo. A criação é feita da sua máquina, mirando só nos recursos do gameserver:

```bash
cd terraform
# exporte as mesmas TF_VAR_ do Jenkins (ovirt_url/username/password, cluster_id, vnic_profile_id, chaves SSH) e:
terraform init
terraform plan  -var gameserver_enabled=true -target=ovirt_vm_start.gameserver -target=data.ovirt_wait_for_ip.gameserver -out=gameserver.tfplan
terraform apply gameserver.tfplan
terraform output gameserver_ip_address
```

> O `-target` evita que o Terraform tente recriar a `olvm-app-server`, que pertence ao pipeline. **Guarde o `terraform.tfstate` gerado**: ele é o único registro dessa VM. Não fica no Git e será necessário para alterar ou destruir a VM depois. Ele vai para um backend remoto quando o state do projeto for migrado.

### Configuração (Ansible)

| Role           | O que faz                                                                    |
|----------------|--------------------------------------------------------------------------------|
| `gs_base`      | apt upgrade, unattended-upgrades, fail2ban, usuário `games` sem sudo, SSH só por chave |
| `gs_firewall`  | UFW: deny incoming; SSH só da `mgmt_cidr` e da tailnet; UDP 16261-16262 só em `tailscale0` |
| `gs_tailscale` | Repositório oficial, `tailscale up` com authkey do Vault, `tag:gameserver`; IP no fact `gs_tailscale_ip` |
| `gs_docker`    | Docker CE oficial, log rotation, bind padrão em 127.0.0.1                       |
| `gs_zomboid`   | Imagem própria (steamcmd, não-root), portas publicadas **só no IP do Tailscale** |
| `gs_backup`    | Timer diário: avisa, para, `tar.gz`, sobe; 7 dias locais + rsync; libera o update |

> O Docker ignora o UFW ao publicar portas. Por isso toda porta de jogo é publicada no IP do Tailscale, nunca em `0.0.0.0`.

Segredos (`tailscale_authkey`, `zomboid_password`, `zomboid_admin_password`) ficam em `ansible/inventory/group_vars/gameservers/vault.yml`, criptografado com `ansible-vault` e **fora do Git** (`.gitignore`, porque o repo é público). Use o `vault.example.yml` como modelo.

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml
cp inventory/group_vars/gameservers/vault.example.yml inventory/group_vars/gameservers/vault.yml
ansible-vault encrypt inventory/group_vars/gameservers/vault.yml   # depois: ansible-vault edit
# preencha ansible_host em inventory/hosts.yml (terraform output gameserver_ip_address)
ansible-playbook -i inventory/hosts.yml playbooks/gameserver.yml --ask-vault-pass --check --diff
```

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
- O Jenkins roda como o usuário de sistema `jenkins` (home `/var/lib/jenkins`), que **não** lê `/home/mvrc/.ssh`. Por isso as chaves usadas pelo pipeline ficam na home dele:
  - par do Ansible: `/var/lib/jenkins/.ssh/ansible_key` (+ `.pub`), gerado como `jenkins` (`ANSIBLE_SSH_PRIVATE_KEY` no Jenkinsfile)
  - sua chave pública pessoal: cópia em `/var/lib/jenkins/.ssh/mvrc-pc.pub`

### GitHub
- Webhook do repositório apontando para `https://<ngrok-url>/github-webhook/`
- Personal Access Token (PAT) com escopos `repo` e `admin:repo_hook`

### OLVM
- Engine acessível via API (`https://<olvm-engine>/ovirt-engine/api`)
- Usuário de serviço com o papel `DataCenterAdmin` no Data Center (ex: `jenkins@mvrc.local@internalsso`, criado no Keycloak do OLVM - não usar SuperUser)
- Template Ubuntu com cloud-init e qemu-guest-agent, com o disco fora do `hosted_storage` (ver seção acima)
- ID do cluster de destino (`Compute → Clusters` no portal do OLVM)
- ID do vNIC profile da rede das VMs (ver abaixo)

### Jenkins Credentials (configuradas via Manage Jenkins → Credentials)

| Credential ID                  | Type        | Description                                                        |
|---------------------------------|-------------|----------------------------------------------------------------------|
| `olvm-url`                      | Secret text | URL da API do OLVM Engine                                            |
| `olvm-username`                 | Secret text | Usuário de autenticação no OLVM (ex: `jenkins@mvrc.local@internalsso`) |
| `olvm-password`                 | Secret text | Senha do usuário OLVM                                                |
| `olvm-cluster-id`               | Secret text | ID (UUID) do cluster OLVM onde as VMs são criadas                    |
| `olvm-vnic-profile-id`          | Secret text | ID (UUID) do vNIC profile da rede das VMs (NIC criada pelo Terraform) |
| `github-pat`                    | Secret text | GitHub Personal Access Token                                         |

**Como achar o ID do vNIC profile:** o portal não mostra o ID, então consulte a API (troque o usuário; a senha é pedida no prompt):

```bash
curl -sk -u 'jenkins@mvrc.local@internalsso' -H 'Accept: application/json' \
  https://olvm-manager.mvrc.local/ovirt-engine/api/vnicprofiles \
  | python3 -c 'import json,sys; [print(p["id"], p["name"]) for p in json.load(sys.stdin)["vnic_profile"]]'
```

Use o ID do profile da rede onde as outras VMs estão (normalmente `ovirtmgmt`).

---

## Setup Guide

### 1. Clone este repositório

```bash
git clone https://github.com/your-username/DEVOPS-MVRC-IAC.git
cd DEVOPS-MVRC-IAC
```

### 2. Configure `terraform/terraform.tfvars`

```hcl
ovirt_tls_insecure = true

template_name = "Ubuntu-Terraform"

vm_name     = "olvm-app-server"
cpu_cores   = 2
cpu_sockets = 1
cpu_threads = 1
memory_gb   = 2

# Sem vm_ip_address definido, a VM sobe em DHCP e o IP é descoberto via
# guest agent. Para IP fixo, defina vm_ip_address (+ vm_netmask/vm_gateway).
nic_name      = "enp1s0"
dns_primary   = "192.168.31.10"
dns_secondary = "8.8.8.8"
```

> `ovirt_url`, `ovirt_username`, `ovirt_password`, `cluster_id`, `vnic_profile_id`, `my_ssh_public_key_path` e `jenkins_ssh_public_key_path` **nunca** são armazenados neste arquivo. Os cinco primeiros vêm de credenciais do Jenkins (repo público), e os caminhos das chaves vêm do `environment` do Jenkinsfile — todos como variáveis `TF_VAR_`.

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

Adicione as 5 credenciais OLVM + o PAT do GitHub listadas na tabela acima em `Manage Jenkins → Credentials`.

### 6. Crie o job do pipeline no Jenkins

- New Item → Pipeline
- Build Triggers: `GitHub hook trigger for GITScm polling`
- Pipeline: `Pipeline script from SCM` → Git → URL do seu repo → branch `*/main` (o pipeline só roda na `main`)
- Script Path: `Jenkinsfile`

### 7. Dispare o pipeline

Push de qualquer commit na branch configurada (ou execute manualmente pelo Jenkins).

---

## Security Considerations

- Credenciais OLVM (URL, usuário, senha, cluster, vNIC profile) ficam nos Secrets do Jenkins e são injetadas como variáveis `TF_VAR_` — nunca aparecem em código ou logs. Os caminhos das chaves SSH públicas ficam no próprio Jenkinsfile (são caminhos, não segredos).
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
| Ubuntu Server   | 24.04+      | SO do template e das instâncias provisionadas        |

---

## Author

**Marcos Cantelli**
DevOps & Infrastructure Engineer

[GitHub](https://github.com/MarcosCantelli) · [LinkedIn](www.linkedin.com/in/marcos-cantelli-a450bb169)

---

## License

This project is intended for learning and portfolio purposes.
