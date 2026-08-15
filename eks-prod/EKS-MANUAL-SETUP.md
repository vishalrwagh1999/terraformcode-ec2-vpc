# EKS Cluster — Manual Setup Guide (Beginner Friendly)

This guide walks you through creating an EKS cluster **manually using AWS Console + CLI**.
It covers every IAM role, what it does, OIDC identity provider, service accounts, and the Ingress Controller setup — explained simply.

---

## Big Picture — What Are We Building?

```
Your App (Pod)
     |
  Ingress  <-- AWS Load Balancer Controller manages this ALB
     |
  Service Account  <-- has an IAM Role attached (IRSA)
     |
  OIDC Provider  <-- trust bridge between Kubernetes and AWS IAM
     |
  IAM Role + Policy  <-- actual AWS permissions
```

> Think of it like this:
> - **IAM Role** = a set of AWS permissions
> - **Service Account** = a Kubernetes identity for a pod
> - **OIDC** = the trust bridge that links the two together
> - **Ingress Controller** = the thing that creates an AWS Load Balancer for your app

---

## Prerequisites

- AWS CLI installed and configured (`aws configure`)
- `kubectl` installed
- `eksctl` installed → https://eksctl.io/
- `helm` installed → https://helm.sh/docs/intro/install/

---

## Part 1 — IAM Roles Explained

EKS needs multiple IAM roles. Here is each one, what it is, and why it exists.

---

### Role 1 — EKS Cluster Role

**What it is:** An IAM role that the EKS control plane (master nodes managed by AWS) uses.

**Why it exists:** AWS needs permission to manage networking, load balancers, and EC2 resources on your behalf to run the cluster.

**Policy to attach:**
| Policy | Why |
|--------|-----|
| `AmazonEKSClusterPolicy` | Lets EKS manage EC2, networking, and autoscaling for the cluster |
| `AmazonEKSVPCResourceController` | Lets EKS manage security groups for pods (required for VPC CNI) |

**How to create (Console):**
1. Go to **IAM → Roles → Create Role**
2. Trusted entity: `AWS Service` → `EKS` → `EKS - Cluster`
3. Attach: `AmazonEKSClusterPolicy`
4. Name it: `eks-cluster-role`

**How to create (CLI):**
```bash
# 1. Create trust policy file
cat > eks-cluster-trust.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "eks.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}
EOF

# 2. Create the role
aws iam create-role \
  --role-name eks-cluster-role \
  --assume-role-policy-document file://eks-cluster-trust.json

# 3. Attach policies
aws iam attach-role-policy \
  --role-name eks-cluster-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy

aws iam attach-role-policy \
  --role-name eks-cluster-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSVPCResourceController
```

---

### Role 2 — EKS Node Group Role (Worker Node Role)

**What it is:** An IAM role attached to every EC2 worker node in your cluster.

**Why it exists:** Worker nodes (EC2 instances) need AWS permissions to join the cluster, pull container images from ECR, and set up pod networking.

**Policies to attach:**
| Policy | Why |
|--------|-----|
| `AmazonEKSWorkerNodePolicy` | Lets the node register itself with the EKS cluster |
| `AmazonEKS_CNI_Policy` | Lets the VPC CNI plugin assign IP addresses to pods |
| `AmazonEC2ContainerRegistryReadOnly` | Lets nodes pull Docker images from ECR |
| `AmazonSSMManagedInstanceCore` | Lets you SSH into nodes via Session Manager (no bastion needed) |

**How to create (CLI):**
```bash
# 1. Trust policy for EC2
cat > ec2-trust.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "ec2.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}
EOF

# 2. Create the role
aws iam create-role \
  --role-name eks-node-role \
  --assume-role-policy-document file://ec2-trust.json

# 3. Attach all 4 policies
aws iam attach-role-policy --role-name eks-node-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy

aws iam attach-role-policy --role-name eks-node-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy

aws iam attach-role-policy --role-name eks-node-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly

aws iam attach-role-policy --role-name eks-node-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
```

---

### Role 3 — AWS Load Balancer Controller Role (IRSA Role)

**What it is:** An IAM role for the **Load Balancer Controller pod** running inside Kubernetes.

**Why it exists:** The Load Balancer Controller needs to create/manage ALBs and NLBs in your AWS account. Instead of giving the whole node permission, we give only this specific pod the permission it needs — this is called **IRSA (IAM Roles for Service Accounts)**.

> This role is linked to a Kubernetes Service Account via OIDC (explained in Part 2).

**How to create:** Covered in Part 3 below.

---

### Role 4 — EBS CSI Driver Role (IRSA Role)

**What it is:** An IAM role for the EBS CSI Driver pod.

**Why it exists:** When a pod requests a PersistentVolume (disk storage), the EBS CSI driver creates an EBS volume in AWS. It needs IAM permission to do that.

**Policy to attach:** `AmazonEBSCSIDriverPolicy`

> Also linked via IRSA + OIDC like the Load Balancer Controller role.

---

## Part 2 — Create the EKS Cluster

### Step 1 — Create the Cluster (Console)

1. Go to **EKS → Create Cluster**
2. Name: `project-eks`
3. Kubernetes version: `1.34`
4. Cluster service role: select `eks-cluster-role` (created above)
5. VPC: select your VPC, choose private + public subnets
6. Click **Create** (takes ~10 min)

### Step 1 — Create the Cluster (CLI)

```bash
aws eks create-cluster \
  --name project-eks \
  --kubernetes-version 1.34 \
  --role-arn arn:aws:iam::<ACCOUNT_ID>:role/eks-cluster-role \
  --resources-vpc-config \
    subnetIds=<SUBNET_1>,<SUBNET_2>,<SUBNET_3>,<SUBNET_4>,\
    securityGroupIds=<SG_ID>,\
    endpointPublicAccess=true,\
    endpointPrivateAccess=true

# Wait for cluster to become ACTIVE
aws eks wait cluster-active --name project-eks
```

### Step 2 — Add Worker Nodes (Node Group)

```bash
aws eks create-nodegroup \
  --cluster-name project-eks \
  --nodegroup-name project-eks-ng \
  --node-role arn:aws:iam::<ACCOUNT_ID>:role/eks-node-role \
  --subnets <PRIVATE_SUBNET_1> <PRIVATE_SUBNET_2> \
  --instance-types t3.small \
  --scaling-config minSize=2,maxSize=10,desiredSize=3 \
  --disk-size 50

# Wait for nodes to be ready
aws eks wait nodegroup-active \
  --cluster-name project-eks \
  --nodegroup-name project-eks-ng
```

### Step 3 — Configure kubectl

```bash
aws eks update-kubeconfig --region us-west-2 --name project-eks

# Verify nodes are ready
kubectl get nodes
```

---

## Part 3 — OIDC Identity Provider (The Trust Bridge)

### What is OIDC and why do we need it?

By default, AWS IAM has no idea what is happening inside your Kubernetes cluster. It cannot tell which pod is which.

**OIDC (OpenID Connect)** is a standard that lets Kubernetes prove to AWS:
> "This pod is running as Service Account X in namespace Y — trust it."

Without OIDC, you would have to give the entire EC2 node full IAM permissions, which is a security risk. With OIDC, only the specific pod/service account gets the permissions it needs.

```
Pod uses Service Account
        |
        | (token)
        v
   OIDC Provider  -->  AWS IAM verifies the token
        |
        v
   IAM Role is assumed  -->  Pod gets AWS permissions
```

### Step 1 — Get the OIDC Issuer URL

```bash
aws eks describe-cluster \
  --name project-eks \
  --query "cluster.identity.oidc.issuer" \
  --output text
```

Output looks like:
```
https://oidc.eks.us-west-2.amazonaws.com/id/EXAMPLED539D4633E53DE1B716D3041E
```

### Step 2 — Create the OIDC Provider in IAM

```bash
eksctl utils associate-iam-oidc-provider \
  --cluster project-eks \
  --region us-west-2 \
  --approve
```

> This registers the OIDC URL from your cluster into AWS IAM so that IAM can trust tokens issued by your cluster.

**Verify it was created:**
```bash
aws iam list-open-id-connect-providers
```

---

## Part 4 — Service Account + Ingress Controller Setup

### What is a Service Account?

A **Service Account** is a Kubernetes identity assigned to a pod. Think of it like a username for a pod.

When combined with OIDC + an IAM Role, the pod can make AWS API calls using that role's permissions — without any hardcoded credentials.

```
Pod  -->  Service Account  -->  IAM Role (via OIDC)  -->  AWS API
```

---

### Step 1 — Download the Load Balancer Controller IAM Policy

```bash
curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.2/docs/install/iam_policy.json
```

### Step 2 — Create the IAM Policy in AWS

```bash
aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam_policy.json
```

Note down the policy ARN from the output:
```
arn:aws:iam::<ACCOUNT_ID>:policy/AWSLoadBalancerControllerIAMPolicy
```

### Step 3 — Create the Service Account + IAM Role (IRSA)

This single command does 3 things at once:
1. Creates an IAM role with the correct OIDC trust policy
2. Attaches the policy to the role
3. Creates a Kubernetes Service Account and annotates it with the role ARN

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

**Verify the service account was created:**
```bash
kubectl get serviceaccount aws-load-balancer-controller -n kube-system -o yaml
```

You should see an annotation like:
```yaml
annotations:
  eks.amazonaws.com/role-arn: arn:aws:iam::<ACCOUNT_ID>:role/AmazonEKSLoadBalancerControllerRole
```

> This annotation is how Kubernetes tells AWS: "this service account should use this IAM role".

---

### Step 4 — Install the AWS Load Balancer Controller via Helm

```bash
# Add the EKS Helm chart repo
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Get your VPC ID
VPC_ID=$(aws eks describe-cluster \
  --name project-eks \
  --query "cluster.resourcesVpcConfig.vpcId" \
  --output text)

# Install the controller
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=project-eks \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=us-west-2 \
  --set vpcId=$VPC_ID
```

**Verify the controller is running:**
```bash
kubectl get deployment aws-load-balancer-controller -n kube-system
```

Expected output:
```
NAME                           READY   UP-TO-DATE   AVAILABLE
aws-load-balancer-controller   2/2     2            2
```

---

## Part 5 — Create an Ingress Resource

### What is Ingress?

**Ingress** is a Kubernetes object that defines HTTP/HTTPS routing rules.
The **AWS Load Balancer Controller** reads these rules and creates a real **AWS ALB (Application Load Balancer)** for you automatically.

```
Internet
   |
  ALB (created by AWS LBC)
   |
  Ingress rules (your YAML)
   |
  Kubernetes Service
   |
  Your Pod
```

### Sample Ingress YAML

```yaml
# ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app-ingress
  namespace: default
  annotations:
    kubernetes.io/ingress.class: alb                        # use ALB
    alb.ingress.kubernetes.io/scheme: internet-facing       # public ALB
    alb.ingress.kubernetes.io/target-type: ip               # route to pod IPs directly
spec:
  rules:
    - host: myapp.example.com                               # optional: your domain
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: my-service                            # your Kubernetes service name
                port:
                  number: 80
```

```bash
kubectl apply -f ingress.yaml

# Check the ALB DNS (takes ~2 min to provision)
kubectl get ingress my-app-ingress -n default
```

Output:
```
NAME             CLASS   HOSTS   ADDRESS                                          PORTS
my-app-ingress   alb     *       k8s-default-xxxx.us-west-2.elb.amazonaws.com    80
```

Open that ADDRESS in your browser — that is your app!

---

## Summary — All Roles at a Glance

| Role | Used By | Purpose |
|------|---------|---------|
| `eks-cluster-role` | EKS Control Plane (AWS managed) | Lets AWS manage networking & EC2 for the cluster |
| `eks-node-role` | EC2 Worker Nodes | Lets nodes join cluster, pull images, set up pod networking |
| `AmazonEKSLoadBalancerControllerRole` | Load Balancer Controller Pod (IRSA) | Lets the LBC pod create/manage ALBs in AWS |
| `EBS CSI Driver Role` | EBS CSI Driver Pod (IRSA) | Lets the CSI pod create/manage EBS volumes in AWS |

---

## Full Flow Recap (Simple Version)

```
1. Create EKS Cluster  -->  needs eks-cluster-role
2. Add Worker Nodes    -->  needs eks-node-role
3. Enable OIDC         -->  trust bridge between K8s and IAM
4. Create SA + Role    -->  LBC pod gets AWS permissions via IRSA
5. Install LBC         -->  controller watches for Ingress objects
6. Apply Ingress YAML  -->  ALB is created automatically in AWS
```

---

## Official AWS Docs

| Topic | Link |
|-------|------|
| EKS Getting Started | https://docs.aws.amazon.com/eks/latest/userguide/getting-started.html |
| EKS Cluster IAM Role | https://docs.aws.amazon.com/eks/latest/userguide/service_IAM_role.html |
| EKS Node IAM Role | https://docs.aws.amazon.com/eks/latest/userguide/create-node-role.html |
| OIDC Provider Setup | https://docs.aws.amazon.com/eks/latest/userguide/enable-iam-roles-for-service-accounts.html |
| IRSA (IAM Roles for Service Accounts) | https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html |
| AWS Load Balancer Controller Install | https://docs.aws.amazon.com/eks/latest/userguide/lbc-helm.html |
| AWS LBC Ingress Annotations | https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.7/guide/ingress/annotations/ |
| EBS CSI Driver | https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html |
| eksctl Docs | https://eksctl.io/usage/creating-and-managing-clusters/ |
