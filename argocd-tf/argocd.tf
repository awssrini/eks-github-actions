# Configure the AWS provider
provider "aws" {
  region = "ap-southeast-1" # Ensure this matches your EKS cluster's region
}

# Data source to retrieve EKS cluster details
# Replace 'your-eks-cluster-name' with the actual name of your EKS cluster
data "aws_eks_cluster" "eks_cluster" {
  name = "dev-medium-eks-cluster" # IMPORTANT: Replace with your EKS cluster name
}

# Data source to retrieve EKS cluster authentication token
data "aws_eks_cluster_auth" "eks_cluster_auth" {
  name = data.aws_eks_cluster.eks_cluster.name
}

# Configure the Kubernetes provider
# This provider uses the output from the EKS cluster data sources to authenticate
provider "kubernetes" {
  host                   = data.aws_eks_cluster.eks_cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks_cluster.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.eks_cluster_auth.token
}

# Configure the Helm provider
# This provider also uses the Kubernetes provider's configuration
provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.eks_cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks_cluster.certificate_authority.0.data)
    token                  = data.aws_eks_cluster_auth.eks_cluster_auth.token
  }
}

# Create the namespace for ArgoCD if it doesn't exist
resource "kubernetes_namespace" "argocd_namespace" {
  metadata {
    name = "argocd"
  }
}

# Deploy ArgoCD using the Helm chart
# This uses the official ArgoCD Helm chart: https://argo-cd.readthedocs.io/en/stable/getting_started/#helm
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = kubernetes_namespace.argocd_namespace.metadata[0].name
  version    = "5.55.0" # IMPORTANT: Specify a compatible chart version. Check ArgoCD Helm chart releases.

  # Values to customize the ArgoCD installation
  # These are common customizations; adjust as per your needs.
  values = [
    # You can externalize these values into a separate YAML file and reference it
    # using 'value_files = ["./values.yaml"]' if the values become extensive.
    # For simplicity, they are inline here.
    yamlencode({
      installCRDs = true # Install ArgoCD Custom Resource Definitions
      server = {
        service = {
          type = "LoadBalancer" # Expose ArgoCD UI via AWS Load Balancer
          # If you want to use an Ingress, set type to ClusterIP and configure ingress below
        }
        # If using Ingress instead of LoadBalancer:
        # ingress = {
        #   enabled = true
        #   ingressClassName = "nginx" # Or your specific ingress controller class
        #   hostname = "argocd.yourdomain.com" # Replace with your desired hostname
        #   annotations = {
        #     "kubernetes.io/ingress.class" = "nginx"
        #     "nginx.ingress.kubernetes.io/backend-protocol" = "HTTPS"
        #     # Add AWS ALB specific annotations if using ALB Ingress Controller
        #     # "alb.ingress.kubernetes.io/scheme" = "internet-facing"
        #     # "alb.ingress.kubernetes.io/target-type" = "ip"
        #   }
        #   tls = [{
        #     hosts = ["argocd.yourdomain.com"]
        #     secretName = "argocd-tls" # Kubernetes secret containing your TLS cert
        #   }]
        # }
      }
      # Define resource limits and requests for better stability
      # Adjust these based on your cluster size and expected load
      defaultResourceLimits = {
        cpu    = "100m"
        memory = "128Mi"
      }
      defaultResourceRequests = {
        cpu    = "50m"
        memory = "64Mi"
      }
    })
  ]

  # Ensure the namespace is created before the helm release
  depends_on = [
    kubernetes_namespace.argocd_namespace
  ]
}

# Output the ArgoCD server URL (if using LoadBalancer)
output "argocd_server_url" {
  description = "The URL to access the ArgoCD UI (if LoadBalancer type is used)"
  value = one(
    [for ingress in helm_release.argocd.status.first_deployed.resources.items :
      "http://${ingress.status.loadBalancer.ingress[0].hostname}"
      if ingress.kind == "Service" && ingress.metadata.name == "argocd-server" && ingress.status.loadBalancer.ingress[0].hostname != null
    ]
  )
  sensitive = false # Not sensitive, as it's a URL
}

# Instructions to get the initial admin password
# This will be printed to the console after a successful apply
output "argocd_initial_password_instructions" {
  description = "Instructions to retrieve the initial ArgoCD admin password"
  value = <<EOT
To get the initial admin password for ArgoCD:
1. Ensure kubectl is configured to connect to your EKS cluster.
2. Run the following command:
   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
EOT
  sensitive = true # Mark as sensitive as it contains instructions to get a password
}