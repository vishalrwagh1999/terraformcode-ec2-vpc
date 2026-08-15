# ── VPC Outputs ───────────────────────────────────────────────────────────────

output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "s3_vpc_endpoint_id" {
  value = aws_vpc_endpoint.s3.id
}

# ── EKS Outputs ───────────────────────────────────────────────────────────────

output "cluster_name" {
  value = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.main.endpoint
}

output "cluster_ca_certificate" {
  value     = aws_eks_cluster.main.certificate_authority[0].data
  sensitive = true
}

output "cluster_version" {
  value = aws_eks_cluster.main.version
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN — use this when creating IRSA roles"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "node_group_role_arn" {
  value = aws_iam_role.nodes.arn
}

output "kubeconfig_command" {
  description = "Run this to update your local kubeconfig"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${aws_eks_cluster.main.name}"
}
