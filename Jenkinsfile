pipeline {
    agent any

    triggers {
        githubPush()
    }

    environment {
        TF_VAR_tenancy_ocid                = credentials('oci-tenancy-ocid')
        TF_VAR_user_ocid                   = credentials('oci-user-ocid')
        TF_VAR_fingerprint                 = credentials('oci-fingerprint')
        TF_VAR_private_key_path            = credentials('oci-api-private-key')
        TF_VAR_my_ssh_public_key_path      = credentials('mvrc-ssh-public-key-path')
        TF_VAR_jenkins_ssh_public_key_path = credentials('jenkins-ssh-public-key-path')
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

        stage('Capturar IP público da VM') {
            steps {
                dir('terraform') {
                    script {
                        env.VM_IP = sh(
                            script: 'terraform output -raw vm_public_ip',
                            returnStdout: true
                        ).trim()
                        echo "IP público da VM: ${env.VM_IP}"
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

        stage('Ansible - Provisionar VM OCI') {
            steps {
                sh '''
                    echo "[oci_servers]" > ansible/inventory/hosts.ini
                    echo "''' + env.VM_IP + ''' ansible_user=opc ansible_ssh_private_key_file=/var/lib/jenkins/.ssh/ansible_key ansible_ssh_common_args='-o StrictHostKeyChecking=no'" >> ansible/inventory/hosts.ini
                '''

                sh '''
                    cd ansible
                    ansible-playbook \
                      -i inventory/hosts.ini \
                      playbooks/provision-oci-vm.yml
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
            echo "Pipeline falhou. Destruindo VM se existir."
            dir('terraform') {
                sh 'terraform destroy -auto-approve || true'
            }
        }
    }
}
