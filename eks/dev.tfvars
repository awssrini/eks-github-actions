env                   = "dev"
aws-region            = "ap-southeast-1"
vpc-cidr-block        = "10.16.0.0/16"
vpc-name              = "vpc"
igw-name              = "igw"
pub-subnet-count      = 3
pub-cidr-block        = ["10.16.0.0/20", "10.16.16.0/20", "10.16.32.0/20"]
pub-availability-zone = ["ap-southeast-1a", "ap-southeast-1b", "ap-southeast-1c"]
pub-sub-name          = "subnet-public"
pri-subnet-count      = 3
pri-cidr-block        = ["10.16.128.0/20", "10.16.144.0/20", "10.16.160.0/20"]
pri-availability-zone = ["ap-southeast-1a", "ap-southeast-1b", "ap-southeast-1c"]
pri-sub-name          = "subnet-private"
public-rt-name        = "public-route-table"
private-rt-name       = "private-route-table"
eip-name              = "elasticip-ngw"
ngw-name              = "ngw"
eks-sg                = "eks-sg"

# EKS
is-eks-cluster-enabled     = true
cluster-version            = "1.32"
cluster-name               = "eks-cluster"
endpoint-private-access    = true
endpoint-public-access     = true
ondemand_instance_types    = ["c5.4xlarge"]
spot_instance_types        = ["c5a.xlarge", "m5a.large", "m5a.xlarge", "c5.large", "m5.large", "t3a.large", "t3a.xlarge", "t3a.medium"]
desired_capacity_on_demand = "1"
min_capacity_on_demand     = "1"
max_capacity_on_demand     = "5"
desired_capacity_spot      = "1"
min_capacity_spot          = "1"
max_capacity_spot          = "10"
addons = [
  {
    name    = "vpc-cni",
    version = "v1.19.6-eksbuild.1" # Update this
  },
  {
    name    = "coredns"
    version = "v1.11.4-eksbuild.14" # Update this
  },
  {
    name    = "kube-proxy"
    version = "v1.32.5-eksbuild.2" # Update this
  },
  {
    name    = "aws-ebs-csi-driver"
    version = "v1.45.0-eksbuild.2" # Update this
  }
  # Add more addons as needed
]
