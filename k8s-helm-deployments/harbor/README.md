# Harbor - Container Registry Deployment

This project deploys **Harbor**, an open-source cloud native container registry, on Kubernetes (AWS EKS) using a customized Helm chart sourced from [goharbor/harbor-helm](https://github.com/goharbor/harbor-helm). It includes a custom company logo, Kubernetes secrets for S3 storage, Prometheus monitoring integration, and migration scripts for moving images between EKS clusters.

---

## 📂 Repository Structure

```
harbor/
├── README.md                        # This documentation
├── harbor-helm/                     # Customized Harbor Helm chart
│   ├── Chart.yaml                   # Chart metadata (Harbor v1.4.0)
│   ├── values.yaml                  # Helm values (ingress, S3, TLS, Trivy)
│   ├── secrets.yaml                 # Kubernetes Secret for S3 credentials
│   ├── prometheus.yaml              # Prometheus CR for Harbor metrics scraping
│   ├── customize/
│   │   ├── harborlogo.png           # Custom company logo (replaces Harbor default)
│   │   └── setting.json             # Harbor UI customization config
│   ├── templates/                   # Helm chart templates
│   └── docs/                        # Additional documentation
└── migration_scripts/               # Scripts to migrate EOL/Bitnami images & charts to Harbor
    ├── README.md                    # Migration guide
    ├── migrate.sh                   # Pull from public registries → push to Harbor
    └── verify.sh                    # Verify all artifacts exist in Harbor + failure report
```

---

## 🎨 Custom Logo Customization

The default Harbor logo in the top-left corner of the UI has been replaced with a custom company logo:

- **`customize/harborlogo.png`** — the company logo image file
- **`customize/setting.json`** — Harbor UI customization config that references the logo:

```json
{
  "product": {
    "logo": "harborlogo.png"
  }
}
```

This is applied at deploy time so the Harbor portal displays company branding instead of the default Harbor logo.

---

## ⚙️ Key Configurations

### Ingress & TLS
- Exposed via **NGINX Ingress** with TLS enabled
- Host: `harbor-test.dns.com`
- TLS certificate managed by **cert-manager** (`letsencrypt-prod`)
- IP allowlist enforced via NGINX server snippet

### S3 Image Storage
Container images are stored in **AWS S3** instead of a local filesystem:

```yaml
persistence:
  imageChartStorage:
    type: s3
    s3:
      existingSecret: "harbor-secret-s3"
      region: us-east-1
      bucket: qa-terraform-state
      secure: true
```

S3 credentials are stored in a Kubernetes Secret (`secrets.yaml`):

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: harbor-secret-s3
  namespace: harbor
type: Opaque
data:
  REGISTRY_STORAGE_S3_ACCESSKEY: <base64-encoded>
  REGISTRY_STORAGE_S3_SECRETKEY: <base64-encoded>
```

### Image Vulnerability Scanning (Trivy)
- **Trivy** is enabled for scanning container images
- Scans for `UNKNOWN`, `LOW`, `MEDIUM`, `HIGH`, and `CRITICAL` vulnerabilities
- Scans both OS packages and libraries

### Prometheus Monitoring
- `prometheus.yaml` contains a Prometheus CR configured to scrape Harbor metrics
- ServiceMonitor selector targets `release: harbor-poc`

---

## 🔧 Prerequisites

- AWS EKS cluster
- **Helm 3.x** installed
- **kubectl** configured with cluster access
- **cert-manager** installed in the cluster (for TLS)
- **NGINX Ingress Controller** deployed
- AWS S3 bucket created (`qa-terraform-state`)
- AWS IAM credentials with S3 read/write access

---

## 🚀 Deployment Steps

### 1. Create Namespace

```bash
kubectl create namespace harbor
```

### 2. Apply S3 Secret

> Update the base64-encoded values in `secrets.yaml` before applying.

```bash
kubectl apply -f harbor-helm/secrets.yaml
```

### 3. Apply Custom Logo ConfigMap

```bash
kubectl create configmap harbor-customize \
  --from-file=harborlogo.png=harbor-helm/customize/harborlogo.png \
  --from-file=setting.json=harbor-helm/customize/setting.json \
  -n harbor
```

### 4. Deploy Harbor with Custom Values

```bash
helm install harbor ./harbor-helm \
  -f harbor-helm/values.yaml \
  -n harbor
```

### 5. Verify Installation

```bash
kubectl get pods -n harbor
kubectl get svc -n harbor
kubectl get ingress -n harbor
```

---

## 🔍 Troubleshooting

### Check pod status
```bash
kubectl get pods -n harbor
kubectl describe pod <pod-name> -n harbor
```

### View Harbor core logs
```bash
kubectl logs -f deployment/harbor-core -n harbor
```

### Check S3 connectivity
```bash
kubectl exec -it deployment/harbor-registry -n harbor -- env | grep AWS
```

### Check Trivy scanner
```bash
kubectl get pods -n harbor | grep trivy
kubectl logs deployment/harbor-trivy -n harbor
```

---

## 🚚 Migration Scripts

The `migration_scripts/` folder migrates end-of-life and Bitnami images/Helm charts from public registries into this Harbor instance, since many Bitnami projects have moved from Docker Hub to private repositories.

See [`migration_scripts/README.md`](./migration_scripts/README.md) for full details.

| Script | Purpose |
|---|---|
| `migrate.sh` | Pull images & charts from public registries → push to `harbor-test.dns.com/harbor/` |
| `verify.sh` | Verify all artifacts exist in Harbor → generate timestamped failure report |

**Quick start:**
```bash
cd migration_scripts
chmod +x migrate.sh verify.sh
./migrate.sh          # migrate images + helm charts
./verify.sh           # verify and generate failure report
```

---

## 📚 Useful Links

- [Harbor Official Documentation](https://goharbor.io/docs/)
- [Harbor Helm Chart (GitHub)](https://github.com/goharbor/harbor-helm)
- [Harbor S3 Storage Configuration](https://goharbor.io/docs/latest/install-config/configure-storage-backend/)
- [Trivy Scanner](https://trivy.dev/)
- [cert-manager](https://cert-manager.io/docs/)
