variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "project" {
  description = "Project name used in resource naming and tags"
  type        = string
  default     = "project"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

# ── VPC ──────────────────────────────────────────────────────────────────────

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability zones (must have at least 2 for EKS)"
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b"]
}

# Public subnets — one per AZ
variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.0.0/20", "10.0.16.0/20"]
}

# Private subnets — one per AZ  (matches CLI: 10.0.144.0/20 in us-west-2b)
variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.128.0/20", "10.0.144.0/20"]
}

# ── EKS ──────────────────────────────────────────────────────────────────────

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "project-eks"
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.34"
}

variable "node_instance_types" {
  description = "EC2 instance types for the managed node group"
  type        = list(string)
  default     = ["m5.xlarge"]
}

variable "node_desired" {
  type    = number
  default = 3
}

variable "node_min" {
  type    = number
  default = 2
}

variable "node_max" {
  type    = number
  default = 10
}

variable "node_disk_size" {
  description = "Root EBS volume size (GiB) per node"
  type        = number
  default     = 50
}
