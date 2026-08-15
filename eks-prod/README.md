# eks-prod — Production EKS Cluster (Terraform)

Provisions a production-grade Amazon EKS cluster with a dedicated VPC on AWS using Terraform.

---

## What Gets Created

**VPC (`vpc.tf`)**
- VPC: `10.0.0.0/16`
- 2 Public subnets (`10.0.0.0/20`, `10.0.16.0/20`) across `us-west-2a` / `us-west-2b`
- 2 Private subnets (`10.0.128.0/20`, `10.0.144.0/20`) across `us-west-2a` / `us-west-2b`
- Internet Gateway + NAT Gateway per AZ (HA)
- Public & private route tables
- S3 VPC Gateway Endpoint

**EKS (`eks.tf`)**
- EKS Cluster (`project-eks`, Kubernetes `1.34`)
- IAM roles for cluster + node group
- Security groups for control plane ↔ nodes
- OIDC provider (for IRSA)
- Managed Node Group (private subnets, `t3.small`, desired: 3, min: 2, max: 10)
- Launch template with IMDSv2, encrypted gp3 EBS, detailed monitoring
- Add-ons: `vpc-cni`, `coredns`, `kube-proxy`, `aws-ebs-csi-driver`
- IRSA role for EBS CSI driver

---

## Files

| File | Purpose |
|------|---------|
| `vpc.tf` | VPC, subnets, IGW, NAT, route tables, S3 endpoint |
| `eks.tf` | EKS cluster, node group, IAM, OIDC, add-ons |
| `variables.tf` | All input variables with defaults |
| `terraform.tfvars` | Actual values used for deployment |
| `outputs.tf` | Useful outputs (cluster endpoint, kubeconfig command, etc.) |
| `versions.tf` | Provider versions and Terraform version constraint |

---

## Usage

```bash
cd eks-prod

# Initialize
terraform init

# Preview
terraform plan

# Apply
terraform apply
```

After apply, configure kubectl:

```bash
aws eks update-kubeconfig --region us-west-2 --name project-eks
```

---

## Key Variables (`terraform.tfvars`)

| Variable | Value |
|----------|-------|
| `region` | `us-west-2` |
| `cluster_name` | `project-eks` |
| `cluster_version` | `1.34` |
| `node_instance_types` | `t3.small` |
| `node_desired` | `3` |
| `node_min / max` | `2 / 10` |
| `node_disk_size` | `50 GiB` |

---

## Outputs

| Output | Description |
|--------|-------------|
| `vpc_id` | VPC ID |
| `cluster_name` | EKS cluster name |
| `cluster_endpoint` | API server endpoint |
| `oidc_provider_arn` | Use for IRSA role creation |
| `kubeconfig_command` | Run to update local kubeconfig |

---

## AWS Load Balancer Controller — IRSA + Ingress Setup

The cluster uses IRSA (IAM Roles for Service Accounts) so the AWS Load Balancer Controller can manage ALBs/NLBs without node-level IAM permissions.

### Step 1 — Download the IAM Policy

```bash
curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.2/docs/install/iam_policy.json
```

### Step 2 — Create the IAM Policy

```bash
aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam_policy.json
```

### Step 3 — Create the Service Account (IRSA)

```bash
eksctl create iamserviceaccount \
  --cluster=project-eks \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --role-name AmazonEKSLoadBalancerControllerRole \
  --attach-policy-arn=arn:aws:iam::<ACCOUNT_ID>:policy/AWSLoadBalancerControllerIAMPolicy \
  --approve \
  --region us-west-2
```

> Replace `<ACCOUNT_ID>` with your AWS account ID.

### Step 4 — Install the Controller via Helm

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=project-eks \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=us-west-2 \
  --set vpcId=<VPC_ID>
```

> Get `<VPC_ID>` from Terraform output: `terraform output vpc_id`

### Step 5 — Create an Ingress Resource

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-ingress
  namespace: default
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
spec:
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: my-service
                port:
                  number: 80
```

```bash
kubectl apply -f ingress.yaml
kubectl get ingress -n default   # shows the ALB DNS after ~2 min
```

---

## Official AWS Links

| Topic | Link |
|-------|------|
| EKS User Guide | https://docs.aws.amazon.com/eks/latest/userguide/what-is-eks.html |
| AWS Load Balancer Controller | https://kubernetes-sigs.github.io/aws-load-balancer-controller/ |
| LBC IAM Policy Install Guide | https://docs.aws.amazon.com/eks/latest/userguide/lbc-helm.html |
| IRSA (IAM Roles for Service Accounts) | https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html |
| EKS Managed Node Groups | https://docs.aws.amazon.com/eks/latest/userguide/managed-node-groups.html |
| EKS Add-ons | https://docs.aws.amazon.com/eks/latest/userguide/eks-add-ons.html |
| EBS CSI Driver | https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html |
| eksctl CLI | https://eksctl.io/ |
| Helm | https://helm.sh/docs/intro/install/ |

---

## Requirements

- Terraform `>= 1.0.0`
- AWS provider `~> 5.40`
- TLS provider `~> 4.0`
- AWS credentials configured (`aws configure` or IAM role)
