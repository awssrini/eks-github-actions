pipeline {
    agent any
    parameters {
        string(name: 'Environment', defaultValue: 'dev')
        choice(name: 'Terraform_Action', choices: ['plan', 'apply', 'destroy'])
    }
    stages {
        stage('Preparing') {
            steps {
                sh 'echo Preparing started'
                sh 'whoami'
                sh 'pwd'
                sh 'ls -la'
            }
        }
        stage('Git Pulling') {
            steps {
                git branch: 'main', url: 'https://github.com/awssrini/eks-github-actions.git'
                sh 'ls -la'
                sh 'ls -la eks || echo eks directory not found'
            }
        }
        stage('Init') {
            steps {
                withAWS(credentials: 'aws-creds', region: 'ap-southeast-1') {
                    sh 'terraform version || echo Terraform not installed'
                    sh 'terraform -chdir=eks/ init'
                }
            }
        }
        stage('Validate') {
            steps {
                withAWS(credentials: 'aws-creds', region: 'ap-southeast-1') {
                    sh 'terraform -chdir=eks/ validate'
                }
            }
        }
        stage('Action') {
            steps {
                withAWS(credentials: 'aws-creds', region: 'ap-southeast-1') {
                    script {
                        if (params.Terraform_Action == 'plan') {
                            sh "terraform -chdir=eks/ plan -var-file=${params.Environment}.tfvars"
                        } else if (params.Terraform_Action == 'apply') {
                            sh "terraform -chdir=eks/ apply -var-file=${params.Environment}.tfvars -auto-approve"
                        } else if (params.Terraform_Action == 'destroy') {
                            sh "terraform -chdir=eks/ destroy -var-file=${params.Environment}.tfvars -auto-approve"
                        } else {
                            error "Invalid value for Terraform_Action: ${params.Terraform_Action}"
                        }
                    }
                }
            }
        }
    }
    post {
        always {
            echo "Build finished with status: ${currentBuild.currentResult}"
            sh 'ls -R'
        }
        failure {
            echo "Build failed. Check logs above."
        }
    }
}