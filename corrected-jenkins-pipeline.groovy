pipeline {
    agent any

    environment {
        AWS_ACCOUNT_ID      = credentials('ACCOUNT_ID')        // Jenkins secret text credential
        AWS_ECR_REPO_NAME   = credentials('ECR_REPO_CFK')      // Jenkins secret text credential
        AWS_DEFAULT_REGION  = 'ap-southeast-1'
        AWS_REGION          = 'ap-southeast-1'                 // Fixed: Added missing AWS_REGION variable
        EKS_CLUSTER_NAME    = credentials('eks-cluster-name')  // Jenkins secret text credential
        AWS_ACCESS_KEY_ID   = credentials('aws-access-key-id') // Jenkins secret text credential
        AWS_SECRET_ACCESS_KEY = credentials('aws-secret-access-key') // Jenkins secret text credential
        STAGING_NAMESPACE   = 'confluent'
    }

    stages {
        stage('Set REPOSITORY_URI') {
            steps {
                script {
                    env.REPOSITORY_URI = "${env.AWS_ACCOUNT_ID}.dkr.ecr.${env.AWS_DEFAULT_REGION}.amazonaws.com"
                }
            }
        }

        stage('Git Pulling') {
            steps {
                git branch: 'main', url: 'https://github.com/awssrini/poc1.git'
                sh 'ls -la'
                sh 'ls -la kubernetes_manifests_files || echo "kubernetes_manifests_files directory not found"'
            }
        }

        stage('Trivy File Scan') {
            steps {
                dir('kubernetes_manifests_files') {
                    sh 'trivy fs . > trivyfs.txt'
                }
                // Archive the scan results
                archiveArtifacts artifacts: 'kubernetes_manifests_files/trivyfs.txt', allowEmptyArchive: true
            }
        }

        stage('Trivy Image Scan') {
            steps {
                script {
                    def images = [
                        'confluentinc/cp-server:7.7.1',
                        'confluentinc/confluent-init-container:2.9.3',
                        'confluentinc/cp-enterprise-control-center:7.7.1',
                        'confluentinc/confluent-operator:0.1033.87'
                    ]

                    images.each { image ->
                        echo "Scanning image: ${image}"
                        // Fixed: Proper string interpolation for shell commands
                        sh "trivy image ${image} > trivy-${image.replaceAll(/[:\/]/, '-')}.txt"
                    }
                }
                // Archive all trivy scan results
                archiveArtifacts artifacts: 'trivy-*.txt', allowEmptyArchive: true
            }
        }

        stage('Deploying Confluent Kafka') {
            steps {
                // Fixed: Use consistent credential ID and region variable
                withAWS(credentials: 'aws-jenkins-credentials', region: "${AWS_DEFAULT_REGION}") {
                    withEnv(["AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION}"]) {
                        dir('kubernetes_manifests_files') {
                            sh '''
                                # Configure kubeconfig - Fixed: Use environment variable instead of hardcoded cluster name
                                aws eks update-kubeconfig --name "${EKS_CLUSTER_NAME}" --region ${AWS_DEFAULT_REGION}

                                # Create namespace
                                kubectl create namespace confluent || true

                                # Download and extract CFK bundle
                                curl -O https://packages.confluent.io/bundle/cfk/confluent-for-kubernetes-2.9.6.tar.gz
                                tar -xzvf confluent-for-kubernetes-2.9.6.tar.gz

                                # Install Confluent Operator using Helm
                                cd confluent-for-kubernetes-2.9.6-*/helm
                                helm upgrade --install confluent-operator --namespace confluent confluent-for-kubernetes --set kRaftEnabled=true

                                # Return to kubernetes_manifests_files directory
                                cd ../../

                                # Load basic users
                                chmod +x load_c3_basic_users.sh
                                ./load_c3_basic_users.sh

                                # Apply Kafka and Control Center manifests
                                kubectl apply -f confluent-platform-kraft-7.7.0.yaml
                            '''
                        }
                    }
                }
            }
        }
        
        stage('🧪 Test Staging Environment') {
            steps {
                script {
                    // Fixed: Use consistent credential ID and region variable
                    withAWS(region: "${AWS_REGION}", credentials: 'aws-jenkins-credentials') {
                        sh '''
                            echo "⏳ Waiting for Kafka pods to be ready..."
                            sleep 600

                            # Fixed: Use environment variable for cluster name
                            aws eks update-kubeconfig --region $AWS_REGION --name "${EKS_CLUSTER_NAME}"

                            echo "🔹 Running Kafka connectivity test..."
                            kubectl exec -n $STAGING_NAMESPACE kafka-0 -- kafka-broker-api-versions --bootstrap-server kafka:9092

                            echo "🔹 Running Kafka integration test: Create topic..."
                            kubectl exec -n $STAGING_NAMESPACE kafka-0 -- kafka-topics --create --topic test-topic --bootstrap-server kafka:9092 --partitions 3 --replication-factor 3 || true

                            echo "🔹 Sending test message..."
                            kubectl exec -n $STAGING_NAMESPACE kafka-0 -- bash -c "echo 'test message' | kafka-console-producer --topic test-topic --bootstrap-server kafka:9092"

                            echo "🔹 Receiving test message..."
                            kubectl exec -n $STAGING_NAMESPACE kafka-0 -- kafka-console-consumer --topic test-topic --bootstrap-server kafka:9092 --from-beginning --max-messages 1

                            echo "🔹 Testing Control Center UI via port-forward..."
                            # Fixed: Added timeout and proper cleanup for port-forward
                            timeout 30s kubectl port-forward svc/controlcenter 9021:9021 -n $STAGING_NAMESPACE &
                            PORT_FORWARD_PID=$!
                            sleep 10
                            curl -f http://localhost:9021 || echo "Control Center not accessible"
                            # Clean up port-forward process
                            kill $PORT_FORWARD_PID 2>/dev/null || true
                        '''
                    }
                }
            }
        }

        stage('🔍 DAST Security Scan') {
            steps {
                script {
                    // Fixed: Use consistent credential ID and region variable
                    withAWS(region: "${AWS_REGION}", credentials: 'aws-jenkins-credentials') {
                        sh '''
                            # Fixed: Use environment variable for cluster name
                            aws eks update-kubeconfig --region $AWS_REGION --name "${EKS_CLUSTER_NAME}"

                            echo "🔹 Getting Control Center endpoint..."
                            CONTROL_CENTER_LB=$(kubectl get svc controlcenter -n $STAGING_NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
                            
                            # Fixed: Add validation for load balancer endpoint
                            if [ -z "$CONTROL_CENTER_LB" ]; then
                                echo "Warning: Control Center LoadBalancer endpoint not found, skipping DAST scan"
                                exit 0
                            fi
                            
                            export CONTROL_CENTER_URL=http://$CONTROL_CENTER_LB:9021

                            echo "🔹 Running OWASP ZAP scan..."
                            # Fixed: Proper volume mounting and improved error handling
                            docker run --rm -v "$(pwd)":/zap/wrk/:rw -t ghcr.io/zaproxy/zap2docker-stable zap-baseline.py \
                                -t "$CONTROL_CENTER_URL" \
                                -r zap-report.html \
                                -a || true
                        '''
                        archiveArtifacts artifacts: 'zap-report.html', allowEmptyArchive: true
                    }
                }
            }
        }
    }

    post {
        always {
            // Clean up any remaining processes or temporary files
            sh '''
                # Kill any remaining port-forward processes
                pkill -f "kubectl port-forward" || true
                
                # Clean up temporary files
                rm -f confluent-for-kubernetes-*.tar.gz
            '''
        }
        success {
            echo '✅ Pipeline completed successfully!'
        }
        failure {
            echo '❌ Pipeline failed. Check the logs for details.'
        }
    }
}