# k8s-helm-deployments

A collection of Kubernetes tooling deployments using Helm charts and automation scripts, designed for AWS EKS environments.

---

## 📂 Repository Structure

```
k8s-helm-deployments/
├── README.md                   # This documentation
├── ingress-nginx/              # Ingress-NGINX Helm deployment
│   ├── README.md
│   └── values.yaml
├── karpenter-scripts/          # Karpenter automation scripts
│   ├── README.md
│   ├── main.sh
│   ├── deployment/
│   ├── iam/
│   ├── network/
│   ├── provisioners/
│   └── utils/
├── keda/                       # KEDA Helm deployment & ScaledObjects
│   ├── README.md
│   ├── keda.sh
│   ├── keda-affinity.yaml
│   └── scaled-object.yaml
└── linkerd/                    # Linkerd service mesh installation
    └── README.md
```

---

## 🔧 Components

### 1. [Ingress-NGINX](./ingress-nginx/README.md)
Helm-based deployment of the NGINX Ingress Controller for AWS EKS with:
- AWS NLB (Network Load Balancer) integration
- Custom controller image and NGINX snippets
- Secure source-IP preservation via `externalTrafficPolicy: Local`
- Docker registry secret support for private image pulls

### 2. [Karpenter Scripts](./karpenter-scripts/README.md)
Modular shell scripts for automating Karpenter installation and management on EKS:
- IAM role and policy setup
- Network configuration (subnets, security groups)
- Karpenter Helm deployment (v0.33.1)
- NodePool and provisioner management (v1beta1 API)

### 3. [KEDA](./keda/README.md)
Kubernetes Event-Driven Autoscaler deployment using Helm with:
- RabbitMQ-based event triggers
- Node affinity configuration
- ScaledObject definitions for HPA integration
- Secret-based authentication support

### 4. [Linkerd](./linkerd/README.md)
Service mesh installation guide for EKS with:
- Default and custom certificate setup
- mTLS between services
- Namespace-level sidecar injection
- Helm-based installation (legacy and latest 1.16.x)

---

## 🔑 Prerequisites

All components require:
- An existing **AWS EKS cluster**
- **kubectl** configured with cluster access
- **Helm 3.x** installed
- **AWS CLI** configured with appropriate IAM permissions

Refer to each component's README for component-specific prerequisites.

---

## 🚀 Quick Start

Navigate to the relevant component folder and follow its README:

```bash
# Ingress-NGINX
cd ingress-nginx && helm install -f values.yaml ingress-nginx ingress-nginx/ingress-nginx --version 4.12.1 -n ingress-nginx

# Karpenter
cd karpenter-scripts && bash main.sh --install

# KEDA
cd keda && bash keda.sh

# Linkerd
linkerd install | kubectl apply -f -
```

---

## 📚 Useful Links

- [Helm Documentation](https://helm.sh/docs/)
- [AWS EKS Documentation](https://docs.aws.amazon.com/eks/)
- [Karpenter Documentation](https://karpenter.sh/)
- [KEDA Documentation](https://keda.sh/)
- [Linkerd Documentation](https://linkerd.io/docs/)
