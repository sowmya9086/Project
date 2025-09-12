# Ingress-NGINX Deployment using Helm

This project demonstrates a **customized Helm deployment of Ingress-NGINX** for Kubernetes clusters, designed for AWS EKS with **NLB integration**, security best practices, and extensible configuration.

---

## 📌 Features

- Helm-based deployment of [ingress-nginx](https://artifacthub.io/packages/helm/ingress-nginx/ingress-nginx)
- Custom controller image and configuration snippets
- AWS NLB integration with cross-zone load balancing
- Support for Lua and custom NGINX snippets
- Secure source-IP preservation (`externalTrafficPolicy: Local`)
- Docker registry secret (`regcred`) for private image pulls

---

## 📂 Repository Structure

```
ingress-nginx/
├── README.md           # This documentation
├── values.yaml         # Helm values configuration
```

---

## 🔧 Prerequisites

- Kubernetes cluster (EKS, GKE, AKS, or On-Prem)
- [Helm 3.x](https://helm.sh/docs/intro/install/)
- `kubectl` configured with cluster access
- AWS CLI (if using EKS with NLB)
- Docker registry secret for private image pulls

---

## 🚀 Installation Steps

### 1. Add Helm repositories

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add stable https://charts.helm.sh/stable
helm repo update
```

### 2. Create namespace

```bash
kubectl create namespace ingress-nginx
```

### 3. Create Docker registry secret

```bash
kubectl create secret generic regcred \
  --from-file=.dockerconfigjson=/root/.docker/config.json \
  --type=kubernetes.io/dockerconfigjson \
  -n ingress-nginx
```

### 4. Install ingress-nginx with custom values

```bash
helm install -f values.yaml ingress-nginx ingress-nginx/ingress-nginx \
  --version 4.12.1 -n ingress-nginx
```

### 5. Verify installation

```bash
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx
```

---

## ⚠️ Security Considerations

- **Restrict loadBalancerSourceRanges** → Avoid `0.0.0.0/0` in production
- **Enable Admission Webhooks** → For advanced security policies
- **Set allowPrivilegeEscalation: false** where possible
- **TLS termination** should be enabled at ingress or load balancer level

---

## 🔍 Troubleshooting

### Check pod status

```bash
kubectl get pods -n ingress-nginx
kubectl describe pod <pod-name> -n ingress-nginx
```

### Check service and endpoints

```bash
kubectl get svc -n ingress-nginx
kubectl get endpoints -n ingress-nginx
```

### View logs

```bash
kubectl logs -f deployment/ingress-nginx-controller -n ingress-nginx
```

---

## 📚 Useful Links

- [Ingress-NGINX Helm Chart](https://artifacthub.io/packages/helm/ingress-nginx/ingress-nginx)
- [Ingress-NGINX Documentation](https://kubernetes.github.io/ingress-nginx/)
- [Kubernetes Ingress Documentation](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)

---

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
