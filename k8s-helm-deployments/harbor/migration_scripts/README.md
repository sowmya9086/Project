# Harbor Registry Migration Scripts

Migrates end-of-life and Bitnami container images and Helm charts from public registries to the internal Harbor registry at `harbor-test.dns.com/harbor/`.

Many Bitnami images and charts have moved from Docker Hub to private repositories. This tooling pulls them while still accessible and pushes them into Harbor for continued use in EKS deployments.

---

## 📂 Structure

```
migration_scripts/
├── README.md                           # This documentation
├── migrate.sh                          # Pull from public registries → push to Harbor
├── verify.sh                           # Verify all artifacts in Harbor → failure report
├── helm-charts/                        # Downloaded Helm .tgz files (created at runtime)
├── migration-logs/<timestamp>/         # Logs created per migrate.sh run
│   ├── success_images.txt              # Successfully pushed images
│   ├── failed_images.txt               # Failed images with reason
│   ├── success_charts.txt              # Successfully pushed charts
│   ├── failed_charts.txt               # Failed charts with reason
│   └── migration_report.txt            # Full migration summary
└── verify-logs/<timestamp>/            # Logs created per verify.sh run
    ├── pass_images.txt                 # Verified images
    ├── fail_images.txt                 # Missing/inaccessible images
    ├── pass_charts.txt                 # Verified charts
    ├── fail_charts.txt                 # Missing/inaccessible charts
    └── failure_report.txt              # Full verification report
```

---

## 🔧 Prerequisites

- **Docker** running (Docker Desktop or daemon)
- **Helm 3.x** installed
- **curl** + **jq** installed (used by `verify.sh` for Harbor API checks)
- Network access to `harbor-test.dns.com` and `docker.io`

---

## 🚀 Usage

### Step 1 — Run Migration

```bash
chmod +x migrate.sh verify.sh
./migrate.sh
```

Options:
```bash
./migrate.sh                 # Migrate images + Helm charts (default)
./migrate.sh --images-only   # Container images only
./migrate.sh --charts-only   # Helm charts only
```

You will be prompted for Harbor credentials on first run. Logs are saved to `./migration-logs/<timestamp>/`.

### Step 2 — Verify Migration

```bash
./verify.sh
```

Pass credentials via environment variables to skip the interactive prompt:

```bash
HARBOR_USER=admin HARBOR_PASS=yourpassword ./verify.sh
```

Options:
```bash
./verify.sh                  # Verify images + charts (default)
./verify.sh --images-only    # Verify images only
./verify.sh --charts-only    # Verify charts only
```

`verify.sh` exits with code `1` if any artifact is missing — CI/CD friendly.

---

## 📦 What Gets Migrated

### Container Images (13) — pulled from `docker.io/bitnami/`

| Image | Tag |
|---|---|
| postgresql | 17.6.0-debian-12-r4 |
| os-shell | 12-debian-12-r51, 12-debian-12-r48 |
| postgres-exporter | 0.17.1-debian-12-r16 |
| redis | 8.0.3-debian-12-r1 |
| redis-sentinel | 8.0.3-debian-12-r1 |
| redis-exporter | 1.74.0-debian-12-r2 |
| kubectl | 1.33.3-debian-12-r0, 1.33.4-debian-12-r0 |
| mongodb | 8.0.13-debian-12-r0 |
| nginx | 1.29.1-debian-12-r0 |
| mongodb-exporter | 0.47.0-debian-12-r1 |
| bitnami-shell | 12.9.4-debian-12-r0 |

### Helm Charts (3) — pulled from Bitnami Helm repo

| Chart | Version |
|---|---|
| mongodb | 16.5.45 |
| postgresql | 16.7.27 |
| redis | 21.2.13 |

All artifacts are pushed to: **`harbor-test.dns.com/harbor/`**

---

## ⚠️ Handling Failures

If `verify.sh` reports failures:
1. Check `./verify-logs/<timestamp>/failure_report.txt` for the exact list of missing artifacts
2. Re-run `./migrate.sh` — it will retry all items and update the logs
3. If an image/chart is no longer publicly available (EOL or moved to private), update the `IMAGES` or `HELM_CHARTS` arrays in `migrate.sh` with an alternative source or newer version

---

## 🔍 Troubleshooting

### Docker not running
```bash
# macOS
open -a Docker
# Linux
sudo systemctl start docker
```

### Harbor login fails
```bash
docker login harbor-test.dns.com
helm registry login harbor-test.dns.com
```

### Bitnami image pull fails (EOL or moved to private)
Some Bitnami image versions have been removed from Docker Hub as they reach end-of-life. The script logs these as `PULL_FAILED` with the reason. Update the version in `migrate.sh` or source from an alternative mirror.

### Helm chart download fails
Bitnami may remove older chart versions from the public repo. Check available versions and update `migrate.sh`:
```bash
helm search repo bitnami/mongodb --versions | head -5
helm search repo bitnami/postgresql --versions | head -5
helm search repo bitnami/redis --versions | head -5
```
