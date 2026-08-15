region      = "us-west-2"
project     = "project"
environment = "production"

# VPC — matches CLI commands exactly
vpc_cidr = "10.0.0.0/16"
azs      = ["us-west-2a", "us-west-2b"]

public_subnet_cidrs  = ["10.0.0.0/20", "10.0.16.0/20"]
private_subnet_cidrs = ["10.0.128.0/20", "10.0.144.0/20"] # 10.0.144.0/20 in us-west-2b matches CLI

# EKS
cluster_name        = "project-eks"
cluster_version     = "1.34"
node_instance_types = ["t3.small"]
node_desired        = 3
node_min            = 2
node_max            = 10
node_disk_size      = 50
