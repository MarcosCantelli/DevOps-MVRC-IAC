pipeline {
    agent any

    triggers {
        githubPush()
    }

    environment {
        TF_VAR_vsphere_user     = credentials('vsphere-user')
        TF_VAR_vsphere_password = credentials('vsphere-password')
        TRUENAS_SERVER          = credentials('truenas-server')
        TRUENAS_SHARE           = credentials('truenas-share')
        TRUENAS_USER            = credentials('truenas-smb-user')
        TRUENAS_PASS            = credentials('truenas-smb-pass')
    }

    stages {

        stage('Checkout') {
            steps {
                echo "Branch: ${env.GIT_BRANCH}"
                echo "Commit: ${env.GIT_COMMIT}"
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

        stage('Capturar IP da VM') {
            steps {
                dir('terraform') {
                    script {
                        env.VM_IP = sh(
                            script: 'terraform output -raw vm_ip_address',
                            returnStdout: true
                        ).trim()
                        echo "IP da VM provisionada: ${env.VM_IP}"
                    }
                }
            }
        }

        stage('Ansible - Configurar VM') {
            steps {
                sh """
                    echo "[app_servers]" > ansible/inventory/hosts.ini
                    echo "${env.VM_IP} ansible_user=mvrc ansible_ssh_private_key_file=/var/lib/jenkins/.ssh/ansible_key ansible_ssh_common_args='-o StrictHostKeyChecking=no'" >> ansible/inventory/hosts.ini
                """

                sh """
                    ansible-playbook \
                      -i ansible/inventory/hosts.ini \
                      ansible/playbooks/configure-vm.yml \
                      --extra-vars "truenas_server=${TRUENAS_SERVER} truenas_share=${TRUENAS_SHARE} truenas_user=${TRUENAS_USER} truenas_pass=${TRUENAS_PASS}"
                """
            }
        }

    }

    post {
        success {
            echo "VM provisionada e configurada com sucesso."
            echo "IP: ${env.VM_IP}"
        }
        failure {
            echo "Pipeline falhou. Iniciando destruição da VM."
            dir('terraform') {
                sh 'terraform destroy -auto-approve || true'
            }
        }
    }
}