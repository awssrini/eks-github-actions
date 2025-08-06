# Confluent for Kubernetes (CFK) CI/CD Pipeline

This repository provides a complete CI/CD pipeline for deploying Confluent for Kubernetes (CFK) to AWS EKS, following enterprise-grade security and deployment practices.

## 🏗️ Architecture Overview

The pipeline follows the architecture shown in the diagram with these key stages:

1. **Image Discovery** - Automatically pulls latest Confluent images from Docker Hub
2. **Security Scanning** - Scans images with Trivy for vulnerabilities 
3. **ECR Push** - Tags and pushes images to AWS ECR with proper versioning
4. **Staging Deployment** - Deploys to staging environment for testing
5. **Integration Testing** - Runs connectivity and functional tests
6. **DAST Scanning** - Performs dynamic application security testing with OWASP ZAP
7. **Production Deployment** - Deploys to production with manual approval gates
8. **Cleanup** - Manages image lifecycle and cleanup

## 📋 Prerequisites

### AWS Resources
- EKS cluster running Kubernetes 1.24+
- ECR repositories for Confluent images
- S3 buckets for tiered storage
- IAM roles with appropriate permissions
- ALB/NLB for ingress and load balancing
- ACM certificates for HTTPS

### Tools Required
- AWS CLI v2
- kubectl
- Helm 3.x
- Docker

### GitHub Secrets
Configure the following secrets in your GitHub repository:

```
AWS_ACCESS_KEY_ID         # AWS access key for CI/CD
AWS_SECRET_ACCESS_KEY     # AWS secret key for CI/CD  
AWS_ACCOUNT_ID            # Your AWS account ID
EKS_CLUSTER_NAME          # Name of your EKS cluster
```

## 🚀 Quick Start

### 1. Environment Setup

Run the setup script to create required AWS resources:

```bash
# Set environment variables
export AWS_ACCOUNT_ID="your-account-id"
export AWS_REGION="ap-southeast-1"
export ENVIRONMENT="staging"

# Run setup script
chmod +x scripts/setup-environment.sh
./scripts/setup-environment.sh
```

This will create:
- ECR repositories for all Confluent images
- S3 buckets for Kafka tiered storage
- IAM roles and policies

### 2. Update Configuration

Update the following files with your specific values:

**k8s/production/control-center.yaml:**
```yaml
# Update certificate ARN
service.beta.kubernetes.io/aws-load-balancer-ssl-cert: arn:aws:acm:ap-southeast-1:YOUR-ACCOUNT:certificate/YOUR-CERT-ID

# Update WAF ACL (optional)
alb.ingress.kubernetes.io/wafv2-acl-arn: arn:aws:wafv2:ap-southeast-1:YOUR-ACCOUNT:regional/webacl/confluent-production-waf/YOUR-WAF-ID
```

**Update domain names:**
- Replace `confluent.production.example.com` with your actual domain
- Replace `confluent-staging.internal.example.com` with your staging domain

### 3. Trigger the Pipeline

The pipeline can be triggered in several ways:

**Manual Trigger:**
```bash
# Go to GitHub Actions -> Confluent CI/CD Pipeline -> Run workflow
# Select environment: staging or production
```

**Automatic Triggers:**
- Push to `main` branch (triggers staging deployment)
- Schedule: Daily at 2 AM UTC (checks for image updates)
- Changes to Kubernetes manifests

## 📊 Pipeline Stages

### Stage 1: Image Discovery
- Discovers latest Confluent image versions
- Checks for updates compared to current ECR tags
- Determines if pipeline should proceed

### Stage 2: Security Scanning
```yaml
Images Scanned:
- confluentinc/cp-server:7.7.1
- confluentinc/confluent-init-container:2.9.3  
- confluentinc/cp-enterprise-control-center:7.7.1
- confluentinc/confluent-operator:0.1033.87
```

**Security Tools:**
- **Trivy**: Container vulnerability scanning
- **SARIF**: Security results uploaded to GitHub Security tab
- **Fail on**: HIGH/CRITICAL vulnerabilities

### Stage 3: ECR Management
- Creates ECR repositories if they don't exist
- Tags images with environment-specific tags:
  - `staging-latest`, `production-latest`
  - `staging-{build-number}`, `prod-{build-number}`
- Implements lifecycle policies for cleanup

### Stage 4: Staging Deployment
- Deploys to `confluent-staging` namespace
- Uses Helm for CFK operator installation
- Applies Kafka cluster and Control Center manifests
- Waits for all pods to be ready

### Stage 5: Integration Testing
```bash
Tests performed:
✓ Kafka broker connectivity
✓ Topic creation and management
✓ Producer/Consumer functionality  
✓ Control Center UI accessibility
```

### Stage 6: DAST Scanning
- OWASP ZAP baseline scan on Control Center UI
- Checks for common web vulnerabilities
- Custom rules configuration in `.zap/rules.tsv`

### Stage 7: Production Deployment
- **Manual approval required** via GitHub Environments
- Promotes staging images to production tags
- Deploys to `confluent-production` namespace  
- Production-grade configuration:
  - 5 Kafka brokers with anti-affinity
  - 500Gi storage per broker
  - Cross-zone load balancing
  - Pod disruption budgets

### Stage 8: Cleanup
- Removes old ECR image tags (keeps latest 10)
- Cleans up Docker build cache
- Optimizes storage usage

## 🔧 Configuration Details

### Kafka Configuration

**Staging Environment:**
- 3 replicas
- 100Gi storage per broker
- Basic resource allocation
- 3-day data retention

**Production Environment:**
- 5 replicas with anti-affinity
- 500Gi storage per broker  
- High resource allocation (4 CPU, 8Gi RAM)
- 30-day data retention
- Tiered storage to S3
- Cross-zone deployment

### Security Features

**Image Security:**
- Trivy vulnerability scanning
- Container image signing (optional)
- Non-root container execution
- Security contexts enforced

**Network Security:**
- Internal load balancers for staging
- WAF protection for production
- HTTPS termination with ACM certificates
- Network policies (recommended)

**Access Control:**
- RBAC with service accounts
- IAM roles for AWS service access
- Secret management for credentials

## 📈 Monitoring and Observability

### Metrics Collection
```yaml
# Control Center JMX metrics
- Port: 9999
- Prometheus ServiceMonitor included
- Custom dashboards available
```

### Logging
- Confluent components log to stdout
- Structured logging format
- Log aggregation via Fluent Bit (recommended)

### Health Checks
- Kubernetes liveness/readiness probes
- Application-level health endpoints
- Load balancer health checks

## 🛠️ Customization

### Adding New Images
Edit `.github/workflows/confluent-cicd.yml`:

```yaml
IMAGES=$(cat << 'EOF'
[
  {
    "name": "confluentinc/new-component",
    "tag": "latest"
  }
]
EOF
)
```

### Environment-Specific Configuration
- **Staging**: `k8s/staging/`
- **Production**: `k8s/production/`

### Resource Scaling
Modify resource requests/limits in manifest files:

```yaml
resources:
  requests:
    cpu: "2000m"      # Adjust CPU
    memory: "4Gi"     # Adjust memory
  limits:
    cpu: "4000m"
    memory: "8Gi"
```

## 🔐 Security Best Practices

### Image Security
1. **Scan on Push**: ECR scanning enabled
2. **Vulnerability Management**: Trivy integration
3. **Base Image Updates**: Automated through pipeline
4. **Image Signing**: Configure with Cosign (optional)

### Runtime Security
1. **Non-root Execution**: All containers run as non-root
2. **Security Contexts**: Pod and container security contexts
3. **Network Policies**: Restrict pod-to-pod communication
4. **Secrets Management**: Use AWS Secrets Manager or External Secrets

### Access Control
1. **RBAC**: Fine-grained Kubernetes permissions
2. **IAM Integration**: AWS IAM roles for service accounts
3. **Environment Isolation**: Separate namespaces and access
4. **Audit Logging**: Enable EKS audit logs

## 🚨 Troubleshooting

### Common Issues

**Pipeline Fails at Image Scan:**
```bash
# Check image availability
docker pull confluentinc/cp-server:7.7.1

# Manual Trivy scan
trivy image confluentinc/cp-server:7.7.1
```

**Deployment Timeout:**
```bash
# Check pod status
kubectl get pods -n confluent-staging

# Check events
kubectl get events -n confluent-staging --sort-by='.lastTimestamp'

# Check logs
kubectl logs -f kafka-0 -n confluent-staging
```

**ECR Push Failures:**
```bash
# Verify AWS credentials
aws sts get-caller-identity

# Check ECR login
aws ecr get-login-password --region ap-southeast-1
```

### Debug Commands

```bash
# Port forward to Control Center
kubectl port-forward svc/controlcenter 9021:9021 -n confluent-staging

# Access Kafka directly
kubectl exec -it kafka-0 -n confluent-staging -- bash

# Check operator logs
kubectl logs -f deployment/confluent-operator -n confluent-staging
```

## 📚 Additional Resources

- [Confluent for Kubernetes Documentation](https://docs.confluent.io/operator/current/overview.html)
- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Trivy Security Scanner](https://trivy.dev/)
- [OWASP ZAP](https://www.zaproxy.org/)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Test changes in staging environment
4. Submit pull request with detailed description
5. Ensure all security scans pass

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🔄 Pipeline Status

| Environment | Status | Last Deployed | Version |
|-------------|--------|---------------|---------|
| Staging     | [![Staging](https://github.com/your-org/repo/workflows/Confluent%20CI%2FCD/badge.svg?branch=main)](https://github.com/your-org/repo/actions) | `2024-01-15` | `7.7.1-staging-123` |
| Production  | [![Production](https://github.com/your-org/repo/workflows/Confluent%20CI%2FCD/badge.svg?branch=production)](https://github.com/your-org/repo/actions) | `2024-01-10` | `7.7.1-prod-120` |

---

For questions or support, please open an issue or contact the platform team.