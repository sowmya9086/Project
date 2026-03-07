#!/bin/bash
# verify.sh
# Verifies that all expected container images and Helm charts have been
# successfully migrated to the Harbor registry.
# Generates a timestamped failure report for anything missing or inaccessible.
#
# Usage:
#   ./verify.sh                             # Verify everything
#   ./verify.sh --images-only               # Verify images only
#   ./verify.sh --charts-only               # Verify Helm charts only
#   HARBOR_USER=admin HARBOR_PASS=xxx ./verify.sh   # Pass credentials via env

set -uo pipefail

# ─── Configuration ─────────────────────────────────────────────────────────────
HARBOR_REGISTRY="harbor-test.dns.com"
HARBOR_PROJECT="harbor"
HARBOR_API="https://${HARBOR_REGISTRY}/api/v2.0"

# Credentials (can be overridden via env vars)
HARBOR_USER="${HARBOR_USER:-admin}"
HARBOR_PASS="${HARBOR_PASS:-}"

# ─── Logging ───────────────────────────────────────────────────────────────────
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_DIR="./verify-logs/${TIMESTAMP}"
mkdir -p "${LOG_DIR}"

PASS_IMAGES="${LOG_DIR}/pass_images.txt"
FAIL_IMAGES="${LOG_DIR}/fail_images.txt"
PASS_CHARTS="${LOG_DIR}/pass_charts.txt"
FAIL_CHARTS="${LOG_DIR}/fail_charts.txt"
FAILURE_REPORT="${LOG_DIR}/failure_report.txt"

> "${PASS_IMAGES}"
> "${FAIL_IMAGES}"
> "${PASS_CHARTS}"
> "${FAIL_CHARTS}"

# ─── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()     { echo -e "${GREEN}[PASS]${NC}  $*"; }
warn()   { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail()   { echo -e "${RED}[FAIL]${NC}  $*"; }
header() { echo -e "\n${CYAN}══════════════════════════════════════════${NC}"; echo -e "${CYAN}  $*${NC}"; echo -e "${CYAN}══════════════════════════════════════════${NC}"; }

# ─── Expected Images ───────────────────────────────────────────────────────────
# Format: "image:tag"  (within the harbor project)
EXPECTED_IMAGES=(
  "postgresql:17.6.0-debian-12-r4"
  "os-shell:12-debian-12-r51"
  "os-shell:12-debian-12-r48"
  "postgres-exporter:0.17.1-debian-12-r16"
  "redis:8.0.3-debian-12-r1"
  "redis-sentinel:8.0.3-debian-12-r1"
  "redis-exporter:1.74.0-debian-12-r2"
  "kubectl:1.33.3-debian-12-r0"
  "kubectl:1.33.4-debian-12-r0"
  "mongodb:8.0.13-debian-12-r0"
  "nginx:1.29.1-debian-12-r0"
  "mongodb-exporter:0.47.0-debian-12-r1"
  "bitnami-shell:12.9.4-debian-12-r0"
)

# ─── Expected Helm Charts ──────────────────────────────────────────────────────
# Format: "chart_name|version"
EXPECTED_CHARTS=(
  "mongodb|16.5.45"
  "postgresql|16.7.27"
  "redis|21.2.13"
)

# ─── Prerequisites ─────────────────────────────────────────────────────────────
check_prerequisites() {
  header "Checking Prerequisites"
  local failed=0

  if ! docker info >/dev/null 2>&1; then
    fail "Docker daemon is not running."
    ((failed++))
  else
    ok "Docker is running"
  fi

  if ! command -v helm >/dev/null 2>&1; then
    fail "Helm is not installed or not in PATH."
    ((failed++))
  else
    ok "Helm found"
  fi

  if ! command -v curl >/dev/null 2>&1; then
    warn "curl not found — Harbor API verification will be skipped."
  else
    ok "curl found"
  fi

  if ! command -v jq >/dev/null 2>&1; then
    warn "jq not found — Harbor API response parsing will be skipped."
  else
    ok "jq found"
  fi

  if [[ $failed -gt 0 ]]; then
    fail "Prerequisites not met. Aborting."
    exit 1
  fi
}

# ─── Harbor Login ──────────────────────────────────────────────────────────────
harbor_login() {
  header "Authenticating with Harbor"

  if [[ -z "${HARBOR_PASS}" ]]; then
    log "No HARBOR_PASS set. Prompting for credentials..."
  fi

  if docker login "${HARBOR_REGISTRY}" ${HARBOR_PASS:+-u "${HARBOR_USER}" -p "${HARBOR_PASS}"} ; then
    ok "Docker login to ${HARBOR_REGISTRY} successful"
  else
    fail "Docker login failed. Set HARBOR_USER and HARBOR_PASS env vars or login manually."
    exit 1
  fi

  if helm registry login "${HARBOR_REGISTRY}" ${HARBOR_PASS:+-u "${HARBOR_USER}" -p "${HARBOR_PASS}"} ; then
    ok "Helm registry login successful"
  else
    warn "Helm registry login failed — chart OCI pull verification may fail."
  fi
}

# ─── Verify via Harbor API ─────────────────────────────────────────────────────
# Returns 0 if image tag exists in Harbor API, 1 otherwise
check_harbor_api() {
  local image_name="$1"   # e.g. "redis"
  local image_tag="$2"    # e.g. "8.0.3-debian-12-r1"

  if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    return 2  # skip API check
  fi

  local repo_encoded
  repo_encoded=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${HARBOR_PROJECT}/${image_name}', safe=''))" 2>/dev/null \
    || echo "${HARBOR_PROJECT}%2F${image_name}")

  local url="${HARBOR_API}/projects/${HARBOR_PROJECT}/repositories/${image_name}/artifacts?q=tags%3D${image_tag}&page_size=1"
  local http_code
  http_code=$(curl -sk -o /dev/null -w "%{http_code}" \
    -u "${HARBOR_USER}:${HARBOR_PASS}" \
    "${url}" 2>/dev/null)

  if [[ "${http_code}" == "200" ]]; then
    local count
    count=$(curl -sk \
      -u "${HARBOR_USER}:${HARBOR_PASS}" \
      "${url}" 2>/dev/null | jq '. | length' 2>/dev/null || echo 0)
    [[ "${count}" -gt 0 ]] && return 0 || return 1
  fi
  return 1
}

# ─── Verify Container Images ───────────────────────────────────────────────────
verify_images() {
  header "Verifying Container Images  (${#EXPECTED_IMAGES[@]} expected)"
  local pass=0 fail_count=0 total=${#EXPECTED_IMAGES[@]}

  for entry in "${EXPECTED_IMAGES[@]}"; do
    local image_name="${entry%%:*}"
    local image_tag="${entry##*:}"
    local full_image="${HARBOR_REGISTRY}/${HARBOR_PROJECT}/${entry}"

    echo
    log "Checking: ${full_image}"

    local verified=false

    # Method 1: Harbor API check
    local api_result
    check_harbor_api "${image_name}" "${image_tag}"
    api_result=$?

    if [[ ${api_result} -eq 0 ]]; then
      ok "Harbor API: tag '${image_tag}' found for '${image_name}'"
      verified=true
    elif [[ ${api_result} -eq 2 ]]; then
      warn "Harbor API check skipped (curl/jq not available)"
    else
      warn "Harbor API: tag not found — falling back to docker manifest inspect"
    fi

    # Method 2: docker manifest inspect (fallback or additional check)
    if [[ "${verified}" == false ]]; then
      if docker manifest inspect "${full_image}" >/dev/null 2>&1; then
        ok "docker manifest: ${full_image} is accessible"
        verified=true
      else
        fail "Image NOT found or not accessible: ${full_image}"
        echo "${full_image}" >> "${FAIL_IMAGES}"
        ((fail_count++))
        continue
      fi
    fi

    echo "${full_image}" >> "${PASS_IMAGES}"
    ((pass++))
  done

  echo
  log "Images — Pass: ${pass}/${total}  |  Fail: ${fail_count}/${total}"
}

# ─── Verify Helm Charts ────────────────────────────────────────────────────────
verify_charts() {
  header "Verifying Helm Charts  (${#EXPECTED_CHARTS[@]} expected)"
  local pass=0 fail_count=0 total=${#EXPECTED_CHARTS[@]}
  local tmp_dir
  tmp_dir=$(mktemp -d)

  for entry in "${EXPECTED_CHARTS[@]}"; do
    local chart_name="${entry%%|*}"
    local chart_version="${entry##*|}"
    local oci_ref="oci://${HARBOR_REGISTRY}/${HARBOR_PROJECT}/${chart_name}"

    echo
    log "Checking: ${oci_ref} @ v${chart_version}"

    if helm pull "${oci_ref}" \
        --version "${chart_version}" \
        --destination "${tmp_dir}" >/dev/null 2>&1; then
      ok "Chart accessible: ${chart_name} v${chart_version}"
      echo "${HARBOR_REGISTRY}/${HARBOR_PROJECT}/${chart_name}:${chart_version}" >> "${PASS_CHARTS}"
      ((pass++))
    else
      fail "Chart NOT found or not accessible: ${chart_name} v${chart_version}"
      echo "${HARBOR_REGISTRY}/${HARBOR_PROJECT}/${chart_name}:${chart_version}" >> "${FAIL_CHARTS}"
      ((fail_count++))
    fi
  done

  rm -rf "${tmp_dir}"
  echo
  log "Charts — Pass: ${pass}/${total}  |  Fail: ${fail_count}/${total}"
}

# ─── Failure Report ────────────────────────────────────────────────────────────
generate_failure_report() {
  header "Verification Report"

  local img_pass img_fail chart_pass chart_fail
  img_pass=$(wc -l < "${PASS_IMAGES}" 2>/dev/null | tr -d ' ' || echo 0)
  img_fail=$(wc -l < "${FAIL_IMAGES}" 2>/dev/null | tr -d ' ' || echo 0)
  chart_pass=$(wc -l < "${PASS_CHARTS}" 2>/dev/null | tr -d ' ' || echo 0)
  chart_fail=$(wc -l < "${FAIL_CHARTS}" 2>/dev/null | tr -d ' ' || echo 0)

  local total_fail=$(( img_fail + chart_fail ))

  {
    echo "=========================================="
    echo "  Harbor Verification Report — ${TIMESTAMP}"
    echo "  Registry: ${HARBOR_REGISTRY}/${HARBOR_PROJECT}"
    echo "=========================================="
    echo ""
    echo "Container Images:"
    echo "  Total    : ${#EXPECTED_IMAGES[@]}"
    echo "  Passed   : ${img_pass}"
    echo "  Failed   : ${img_fail}"
    if [[ ${img_pass} -gt 0 ]]; then
      echo ""
      echo "  Verified images:"
      sed 's/^/    ✓ /' "${PASS_IMAGES}"
    fi
    if [[ ${img_fail} -gt 0 ]]; then
      echo ""
      echo "  MISSING / INACCESSIBLE images:"
      sed 's/^/    ✗ /' "${FAIL_IMAGES}"
    fi
    echo ""
    echo "Helm Charts:"
    echo "  Total    : ${#EXPECTED_CHARTS[@]}"
    echo "  Passed   : ${chart_pass}"
    echo "  Failed   : ${chart_fail}"
    if [[ ${chart_pass} -gt 0 ]]; then
      echo ""
      echo "  Verified charts:"
      sed 's/^/    ✓ /' "${PASS_CHARTS}"
    fi
    if [[ ${chart_fail} -gt 0 ]]; then
      echo ""
      echo "  MISSING / INACCESSIBLE charts:"
      sed 's/^/    ✗ /' "${FAIL_CHARTS}"
    fi
    echo ""
    echo "=========================================="
    if [[ ${total_fail} -gt 0 ]]; then
      echo "  STATUS: INCOMPLETE — ${total_fail} artifact(s) missing"
      echo "  Action: Re-run ./migrate.sh for the failed items above"
    else
      echo "  STATUS: ALL ARTIFACTS VERIFIED SUCCESSFULLY"
    fi
    echo "  Report saved to: ${FAILURE_REPORT}"
    echo "  Harbor UI: https://${HARBOR_REGISTRY}"
    echo "=========================================="
  } | tee "${FAILURE_REPORT}"

  echo
  if [[ ${total_fail} -gt 0 ]]; then
    warn "Verification FAILED for ${total_fail} artifact(s). See: ${FAILURE_REPORT}"
    exit 1
  else
    ok "All artifacts verified in Harbor!"
  fi
}

# ─── Main ──────────────────────────────────────────────────────────────────────
main() {
  local mode="all"
  [[ "${1:-}" == "--images-only" ]] && mode="images"
  [[ "${1:-}" == "--charts-only" ]] && mode="charts"

  echo
  log "Harbor Verification Script"
  log "Registry : ${HARBOR_REGISTRY}/${HARBOR_PROJECT}"
  log "Mode     : ${mode}"
  log "Logs     : ${LOG_DIR}"

  check_prerequisites
  harbor_login

  [[ "${mode}" == "all" || "${mode}" == "images" ]] && verify_images
  [[ "${mode}" == "all" || "${mode}" == "charts" ]] && verify_charts

  generate_failure_report
}

main "$@"
