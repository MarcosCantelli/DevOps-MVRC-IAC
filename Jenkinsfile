pipeline {
    agent any

    triggers {
        githubPush()
    }

    environment {
        TF_VAR_ovirt_url                   = credentials('olvm-url')
        TF_VAR_ovirt_username              = credentials('olvm-username')
        TF_VAR_ovirt_password              = credentials('olvm-password')
        TF_VAR_cluster_id                  = credentials('olvm-cluster-id')
        TF_VAR_vnic_profile_id             = credentials('olvm-vnic-profile-id')

        // Chaves SSH na home do usuário "jenkins" (ele não lê /home/mvrc/.ssh).
        // São só CAMINHOS, não segredos (já documentados no README), então
        // ficam aqui direto em vez de em credenciais do Jenkins.
        TF_VAR_my_ssh_public_key_path      = '/var/lib/jenkins/.ssh/mvrc-pc.pub'
        TF_VAR_jenkins_ssh_public_key_path = '/var/lib/jenkins/.ssh/ansible_key.pub'
        ANSIBLE_SSH_PRIVATE_KEY            = '/var/lib/jenkins/.ssh/ansible_key'
    }

    stages {

        stage('Checkout') {
            steps {
                echo "Branch: ${env.GIT_BRANCH}"
                echo "Commit: ${env.GIT_COMMIT}"
            }
        }

        // O Jenkins não exporta variável com valor vazio: uma credencial
        // salva com o Secret em branco faz o Terraform reclamar de
        // "No value for required variable" sem dizer qual credencial é.
        // Aqui o erro aponta o ID da credencial, sem imprimir valores.
        stage('Validar credenciais') {
            steps {
                sh '''
                    falhou=0
                    for par in TF_VAR_ovirt_url:olvm-url \
                               TF_VAR_ovirt_username:olvm-username \
                               TF_VAR_ovirt_password:olvm-password \
                               TF_VAR_cluster_id:olvm-cluster-id \
                               TF_VAR_vnic_profile_id:olvm-vnic-profile-id; do
                        var=${par%%:*}; id=${par#*:}
                        if [ -z "$(printenv "$var")" ]; then
                            echo "ERRO: credencial '$id' está VAZIA no Jenkins (preencha o Secret de novo)."
                            falhou=1
                        fi
                    done
                    for f in "$TF_VAR_my_ssh_public_key_path" "$TF_VAR_jenkins_ssh_public_key_path" "$ANSIBLE_SSH_PRIVATE_KEY"; do
                        if [ ! -r "$f" ]; then
                            echo "ERRO: arquivo de chave '$f' não existe ou não é legível pelo usuário $(id -un)."
                            falhou=1
                        elif [ ! -s "$f" ]; then
                            echo "ERRO: arquivo de chave '$f' está VAZIO."
                            falhou=1
                        fi
                    done
                    # As públicas vão para o authorized_keys do mvrc: um .pub
                    # inválido sobe a VM sem aquela chave, sem erro nenhum.
                    for f in "$TF_VAR_my_ssh_public_key_path" "$TF_VAR_jenkins_ssh_public_key_path"; do
                        if [ -s "$f" ] && ! ssh-keygen -lf "$f" >/dev/null 2>&1; then
                            echo "ERRO: '$f' não é uma chave pública SSH válida."
                            falhou=1
                        fi
                    done
                    [ "$falhou" -eq 0 ] && echo "Credenciais e chaves OK."
                    exit "$falhou"
                '''
            }
        }

        stage('Limpar state anterior') {
            steps {
                dir('terraform') {
                    sh 'rm -f terraform.tfstate terraform.tfstate.backup tfplan'
                }
            }
        }

        stage('Terraform Init') {
            steps {
                dir('terraform') {
                    sh 'terraform init'
                }
            }
        }

        stage('Terraform Plan') {
            steps {
                dir('terraform') {
                    sh 'terraform plan -input=false -out=tfplan'
                }
            }
        }

        stage('Terraform Apply') {
            steps {
                dir('terraform') {
                    sh 'terraform apply -auto-approve tfplan'
                }
            }
        }

        stage('Capturar IP da VM') {
            steps {
                dir('terraform') {
                    script {
                        env.VM_IP = sh(
                            script: 'terraform output -raw vm_ip_address',
                            returnStdout: true
                        ).trim()
                        echo "IP estático da VM: ${env.VM_IP}"
                    }
                }
            }
        }

        stage('Aguardar VM inicializar') {
            steps {
                script {
                    echo "Aguardando SSH em ${env.VM_IP}..."
                    sh """
                        for i in \$(seq 1 30); do
                            if nc -zw5 ${env.VM_IP} 22 2>/dev/null; then
                                echo "SSH disponível após \$((i*10)) segundos"
                                exit 0
                            fi
                            echo "Tentativa \$i/30 — aguardando 10s..."
                            sleep 10
                        done
                        echo "Timeout: SSH não disponível"
                        exit 1
                    """
                }
            }
        }

        stage('Ansible - Provisionar VM OLVM') {
            steps {
                sh '''
                    echo "[olvm_servers]" > ansible/inventory/hosts.ini
                    echo "''' + env.VM_IP + ''' ansible_user=mvrc ansible_ssh_private_key_file=$ANSIBLE_SSH_PRIVATE_KEY ansible_ssh_common_args='-o StrictHostKeyChecking=no'" >> ansible/inventory/hosts.ini
                '''

                sh '''
                    cd ansible
                    ansible-playbook \
                      -i inventory/hosts.ini \
                      playbooks/provision-olvm-vm.yml
                '''
            }
        }

    }

    post {
        success {
            echo "Pipeline finalizado com sucesso."
            echo "VM disponível no IP: ${env.VM_IP}"
        }
        failure {
            script {
                // Se a falha acontecer antes de algum stage (ex: credencial
                // inexistente no bloco environment), o post roda sem node e
                // sem workspace: não há nada a destruir, e o dir() lançaria
                // MissingContextVariableException, escondendo o erro real.
                try {
                    dir('terraform') {
                        echo "Pipeline falhou. Destruindo VM se existir."
                        sh 'terraform destroy -input=false -auto-approve || true'
                    }
                } catch (org.jenkinsci.plugins.workflow.steps.MissingContextVariableException e) {
                    echo "Pipeline falhou antes de alocar o workspace (ex: credencial ausente) - nada para destruir. Veja o erro no fim do log."
                }
            }
        }
    }
}
