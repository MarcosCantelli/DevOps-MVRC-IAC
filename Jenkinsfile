pipeline {
    agent any

    triggers {
        githubPush()
    }

    environment {
        TF_VAR_vsphere_user     = credentials('vsphere-user')
        TF_VAR_vsphere_password = credentials('vsphere-password')
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

        stage('Validar VM') {
            steps {
                dir('terraform') {
                    sh 'terraform output'
                }
            }
        }

    }

    post {
        success {
            echo "VM provisionada com sucesso."
        }
        failure {
            echo "Pipeline falhou. A VM pode precisar ser removida manualmente no vCenter."
            dir('terraform') {
                sh 'terraform destroy -auto-approve || true'
            }
        }
    }
}