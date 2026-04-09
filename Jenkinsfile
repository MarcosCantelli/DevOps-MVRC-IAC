pipeline {
    agent any

    triggers {
        githubPush()
    }

    environment {
        TF_VAR_vsphere_user     = credentials('vsphere-user')
        TF_VAR_vsphere_password = credentials('vsphere-password')
        STATIC_VM_IP            = '192.168.31.50'
    }

    stages {

        stage('Checkout') {
            steps {
                echo "Branch: ${env.GIT_BRANCH}"
                echo "Commit: ${env.GIT_COMMIT}"
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
                    sh 'terraform plan -out=tfplan'
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

        stage('Capturar IP DHCP da VM') {
            steps {
                dir('terraform') {
                    script {
                        env.VM_IP = sh(
                            script: 'terraform output -raw vm_ip_address',
                            returnStdout: true
                        ).trim()
                        echo "IP DHCP da VM: ${env.VM_IP}"
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

        stage('Ansible - Configurar VM') {
            steps {
                sh '''
                    echo "[app_servers]" > ansible/inventory/hosts.ini
                    echo "''' + env.VM_IP + ''' ansible_user=mvrc ansible_ssh_private_key_file=/var/lib/jenkins/.ssh/ansible_key ansible_ssh_common_args='-o StrictHostKeyChecking=no'" >> ansible/inventory/hosts.ini
                '''

                sh '''
                    cd ansible
                    ansible-playbook \
                      -i inventory/hosts.ini \
                      playbooks/configure-vm.yml
                '''
            }
        }

        stage('Verificar IP estático') {
            steps {
                script {
                    echo "Verificando se a VM está acessível no IP fixo ${STATIC_VM_IP}..."
                    sh """
                        for i in \$(seq 1 18); do
                            if ping -c 1 -W 3 ${STATIC_VM_IP} 2>/dev/null; then
                                echo "VM respondendo no IP fixo ${STATIC_VM_IP}"
                                exit 0
                            fi
                            echo "Tentativa \$i/18 — aguardando 10s..."
                            sleep 10
                        done
                        echo "Timeout: VM não responde no IP ${STATIC_VM_IP}"
                        exit 1
                    """
                    sh "nc -zw5 ${STATIC_VM_IP} 22 && echo 'SSH disponível no IP fixo'"
                }
            }
        }

    }

    post {
        success {
            echo "Pipeline finalizado com sucesso."
            echo "VM disponível no IP fixo: ${STATIC_VM_IP}"
        }
        failure {
            echo "Pipeline falhou. Destruindo VM se existir."
            dir('terraform') {
                sh 'terraform destroy -auto-approve || true'
            }
        }
    }
}