#!/bin/bash
# migrate.sh
# Pulls container images and Helm charts from public/Bitnami registries
# and pushes them to the internal Harbor registry.
#
# Usage:
#   ./migrate.sh                  # Run full migration (images + charts)
#   ./migrate.sh --images-only    # Migrate container images only
#   ./migrate.sh --charts-only    # Migrate Helm charts only

set -uo pipefail

# ─── Configuration ─────────────────────────────────────────────────────────────
HARBOR_REGISTRY="harbor-test.dns.com"
HARBOR_PROJECT="harbor"
HARBOR_TARGET="oci://${HARBOR_REGISTRY}/${HARBOR_PROJECT}"
BITNAMI_HELM_REPO="https://charts.bitnami.com/bitnami"

# ─── Logging ───────────────────────────────────────────────────────────────────
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_DIR="./migration-logs/${TIMESTAMP}"
mkdir -p "${LOG_DIR}"

SUCCESS_IMAGES="${LOG_DIR}/success_images.txt"
FAILED_IMAGES="${LOG_DIR}/failed_images.txt"
SUCCESS_CHARTS="${LOG_DIR}/success_charts.txt"
FAILED_CHARTS="${LOG_DIR}/failed_charts.txt"
SUMMARY_REPORT="${LOG_DIR}/migration_report.txt"

> "${SUCCESS_IMAGES}"
> "${FAILED_IMAGES}"
> "${SUCCESS_CHARTS}"
> "${FAILED_CHARTS}"

# ─── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()     { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()   { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()  { echo -e "${RED}[ERROR]${NC} $*"; }
header() { echo -e "\n${CYAN}══════════════════════════════════════════${NC}"; echo -e "${CYAN}  $*${NC}"; echo -e "${CYAN}══════════════════════════════════════════${NC}"; }

# ─── Images List ───────────────────────────────────────────────────────────────
# Format: "source_image|harbor_tag"
# source_image = public image (bitnami or other)
# harbor_tag   = image:tag pushed to Harbor
IMAGES=(
  "docker.io/bitnami/postgresql:17.6.0-debian-12-r4|postgresql:17.6.0-debian-12-r4"
  "docker.io/bitnami/os-shell:12-debian-12-r51|os-shell:12-debian-12-r51"
  "docker.io/bitnami/os-shell:12-debian-12-r48|os-shell:12-debian-12-r48"
  "docker.io/bitnami/postgres-exporter:0.17.1-debian-12-r16|postgres-exporter:0.17.1-debian-12-r16"
  "docker.io/bitnami/redis:8.0.3-debian-12-r1|redis:8.0.3-debian-12-r1"
  "docker.io/bitnami/redis-sentinel:8.0.3-debian-12-r1|redis-sentinel:8.0.3-debian-12-r1"
  "docker.io/bitnami/redis-exporter:1.74.0-debian-12-r2|redis-exporter:1.74.0-debian-12-r2"
  "docker.io/bitnami/kubectl:1.33.3-debian-12-r0|kubectl:1.33.3-debian-12-r0"
  "docker.io/bitnami/kubectl:1.33.4-debian-12-r0|kubectl:1.33.4-debian-12-r0"
  "docker.io/bitnami/mongodb:8.0.13-debian-12-r0|mongodb:8.0.13-debian-12-r0"
  "docker.io/bitnami/nginx:1.29.1-debian-12-r0|nginx:1.29.1-debian-12-r0"
  "docker.io/bitnami/mongodb-exporter:0.47.0-debian-12-r1|mongodb-exporter:0.47.0-debian-12-r1"
  "docker.io/bitnami/bitnami-shell:12.9.4-debian-12-r0|bitnami-shell:12.9.4-debian-12-r0"
)

# ─── Helm Charts List ──────────────────────────────────────────────────────────
# Format: "chart_name|version"
HELM_CHARTS=(
  "mongodb|16.5.45"
  "postgresql|16.7.27"
  "redis|21.2.13"
)

HELM_CHARTS_DIR="./helm-charts"
mkdir -p "${HELM_CHARTS_DIR}"

# ─── Prerequisites ─────────────────────────────────────────────────────────────
check_prerequisites() {
  header "Checking Prerequisites"
  local failed=0

  if ! docker info >/dev/null 2>&1; then
    error "Docker daemon is not running. Please start Docker and retry."
    ((failed++))
  else
    ok "Docker is running"
  fi

  if ! command -v helm >/dev/null 2>&1; then
    error "Helm is not installed or not in PATH."
    ((failed++))
  else
    ok "Helm $(helm version --short 2>/dev/null) found"
  fi

  if ! command -v jq >/dev/null 2>&1; then
    warn "jq not found — Harbor API checks in verify.sh will be skipped."
  else
    ok "jq found"
  fi

  if [[ $failed -gt 0 ]]; then
    error "Prerequisites not met. Aborting."
    exit 1
  fi
}

# ─── Harbor Login ──────────────────────────────────────────────────────────────
harbor_login() {
  header "Authenticating with Harbor"
  log "Registry: ${HARBOR_REGISTRY}"

  if docker login "${HARBOR_REGISTRY}" ; then
    ok "Docker login successful"
  else
    error "Docker login failed. Ensure credentials are correct."
    exit 1
  fi

  if helm registry login "${HARBOR_REGISTRY}" ; then
    ok "Helm registry login successful"
  else
    error "Helm registry login failed."
    exit 1
  fi
}

# ─── Migrate Container Images ──────────────────────────────────────────────────
migrate_images() {
  header "Migrating Container Images  (${#IMAGES[@]} total)"
  local success=0 failed=0 total=${#IMAGES[@]}

  for entry in "${IMAGES[@]}"; do
    local src="${entry%%|*}"
    local tag="${entry##*|}"
    local dst="${HARBOR_REGISTRY}/${HARBOR_PROJECT}/${tag}"

    echo
    log "[${src}]"
    log "→ Target: ${dst}"

    # Pull from source
    if docker pull "${src}" 2>&1; then
      ok "Pulled: ${src}"
    else
      error "Failed to pull: ${src}"
      error "NOTE: This image may have moved to a private/EOL registry."
      echo "PULL_FAILED | ${src} | ${dst}" >> "${FAILED_IMAGES}"
      ((failed++))
      continue
    fi

    # Tag for Harbor
    if docker tag "${src}" "${dst}" 2>&1; then
      ok "Tagged: ${dst}"
    else
      error "Failed to tag: ${src} → ${dst}"
      echo "TAG_FAILED | ${src} | ${dst}" >> "${FAILED_IMAGES}"
      ((failed++))
      continue
    fi

    # Push to Harbor
    if docker push "${dst}" 2>&1; then
      ok "Pushed: ${dst}"
      echo "${dst}" >> "${SUCCESS_IMAGES}"
      ((success++))
    else
      error "Failed to push: ${dst}"
      echo "PUSH_FAILED | ${src} | ${dst}" >> "${FAILED_IMAGES}"
      ((failed++))
    fi

    # Clean up local image to save space
    docker rmi "${src}" "${dst}" >/dev/null 2>&1 || true
  done

  echo
  log "Images — Success: ${success}/${total}  |  Failed: ${failed}/${total}"
}

# ─── Migrate Helm Charts ───────────────────────────────────────────────────────
migrate_helm_charts() {
  header "Migrating Helm Charts  (${#HELM_CHARTS[@]} total)"
  local success=0 failed=0 total=${#HELM_CHARTS[@]}

  # Add Bitnami repo
  log "Adding Bitnami Helm repository..."
  if helm repo add bitnami "${BITNAMI_HELM_REPO}" 2>/dev/null || helm repo update bitnami 2>/dev/null; then
    ok "Bitnami repo ready"
  else
    warn "Bitnami repo add/update had issues — some charts may fail."
  fi
  helm repo update >/dev/null 2>&1

  for entry in "${HELM_CHARTS[@]}"; do
    local chart_name="${entry%%|*}"
    local chart_version="${entry##*|}"

    echo
    log "Chart: bitnami/${chart_name} @ v${chart_version}"

    # Pull chart from Bitnami
    if helm pull "bitnami/${chart_name}" \
        --version "${chart_version}" \
        --destination "${HELM_CHARTS_DIR}" 2>&1; then
      ok "Downloaded: ${chart_name}-${chart_version}.tgz"
    else
      error "Failed to download chart: bitnami/${chart_name} v${chart_version}"
      error "NOTE: This chart may be end-of-life or moved to a private registry."
      echo "DOWNLOAD_FAILED | bitnami/${chart_name} | v${chart_version}" >> "${FAILED_CHARTS}"
      ((failed++))
      continue
    fi

    local chart_file
    chart_file=$(ls "${HELM_CHARTS_DIR}/${chart_name}-${chart_version}.tgz" 2>/dev/null | head -1)

    if [[ -z "${chart_file}" ]]; then
      error "Chart file not found after download: ${chart_name}-${chart_version}.tgz"
      echo "FILE_MISSING | bitnami/${chart_name} | v${chart_version}" >> "${FAILED_CHARTS}"
      ((failed++))
      continue
    fi

    # Push to Harbor OCI
    if helm push "${chart_file}" "${HARBOR_TARGET}" 2>&1; then
      ok "Pushed: ${chart_name}-${chart_version} → ${HARBOR_TARGET}"
      echo "${HARBOR_REGISTRY}/${HARBOR_PROJECT}/${chart_name}:${chart_version}" >> "${SUCCESS_CHARTS}"
      ((success++))
    else
      error "Failed to push chart: ${chart_file} → ${HARBOR_TARGET}"
      echo "PUSH_FAILED | ${chart_name} | v${chart_version} | ${chart_file}" >> "${FAILED_CHARTS}"
      ((failed++))
    fi
  done

  echo
  log "Charts — Success: ${success}/${total}  |  Failed: ${failed}/${total}"
}

# ─── Summary Report ────────────────────────────────────────────────────────────
generate_report() {
  header "Migration Summary Report"

  local img_ok chart_ok img_fail chart_fail
  img_ok=$(wc -l < "${SUCCESS_IMAGES}" 2>/dev/null || echo 0)
  img_fail=$(wc -l < "${FAILED_IMAGES}" 2>/dev/null || echo 0)
  chart_ok=$(wc -l < "${SUCCESS_CHARTS}" 2>/dev/null || echo 0)
  chart_fail=$(wc -l < "${FAILED_CHARTS}" 2>/dev/null || echo 0)

  {
    echo "=========================================="
    echo "  Harbor Migration Report — ${TIMESTAMP}"
    echo "  Registry: ${HARBOR_REGISTRY}/${HARBOR_PROJECT}"
    echo "=========================================="
    echo ""
    echo "Container Images:"
    echo "  Succeeded : ${img_ok}"
    echo "  Failed    : ${img_fail}"
    if [[ ${img_ok} -gt 0 ]]; then
      echo ""
      echo "  Migrated images:"
      sed 's/^/    ✓ /' "${SUCCESS_IMAGES}"
    fi
    if [[ ${img_fail} -gt 0 ]]; then
      echo ""
      echo "  Failed images (reason | source | target):"
      sed 's/^/    ✗ /' "${FAILED_IMAGES}"
    fi
    echo ""
    echo "Helm Charts:"
    echo "  Succeeded : ${chart_ok}"
    echo "  Failed    : ${chart_fail}"
    if [[ ${chart_ok} -gt 0 ]]; then
      echo ""
      echo "  Migrated charts:"
      sed 's/^/    ✓ /' "${SUCCESS_CHARTS}"
    fi
    if [[ ${chart_fail} -gt 0 ]]; then
      echo ""
      echo "  Failed charts (reason | chart | version):"
      sed 's/^/    ✗ /' "${FAILED_CHARTS}"
    fi
    echo ""
    echo "=========================================="
    echo "  Logs saved to: ${LOG_DIR}"
    echo "  Harbor UI: https://${HARBOR_REGISTRY}"
    echo "=========================================="
  } | tee "${SUMMARY_REPORT}"

  echo
  if [[ ${img_fail} -gt 0 || ${chart_fail} -gt 0 ]]; then
    warn "Migration completed with failures. Review: ${SUMMARY_REPORT}"
  else
    ok "All artifacts migrated successfully!"
  fi
}

# ─── Main ──────────────────────────────────────────────────────────────────────
main() {
  local mode="all"
  [[ "${1:-}" == "--images-only" ]] && mode="images"
  [[ "${1:-}" == "--charts-only" ]] && mode="charts"

  echo
  log "Harbor Migration Script"
  log "Registry : ${HARBOR_REGISTRY}/${HARBOR_PROJECT}"
  log "Mode     : ${mode}"
  log "Logs     : ${LOG_DIR}"

  check_prerequisites
  harbor_login

  [[ "${mode}" == "all" || "${mode}" == "images" ]] && migrate_images
  [[ "${mode}" == "all" || "${mode}" == "charts" ]] && migrate_helm_charts

  generate_report
}

main "$@"
