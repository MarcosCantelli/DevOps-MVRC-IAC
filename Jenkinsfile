pipeline {
    agent any

    triggers {
        githubPush()
    }

    stages {
        stage('Verificar conexao') {
            steps {
                echo "Pipeline disparado com sucesso!"
                echo "Branch: ${env.GIT_BRANCH}"
                echo "Commit: ${env.GIT_COMMIT}"
                sh 'echo "Servidor: $(hostname)"'
                sh 'date'
            }
        }
    }

    post {
        success {
            echo "Tudo certo. Pipeline funcionando."
        }
        failure {
            echo "Algo falhou. Verifique os logs acima."
        }
    }
}