#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID=""
REGION="asia-southeast1"
NETWORK="default"
ROUTER_NAME="oc-router"
NAT_NAME="oc-nat"
DRY_RUN="false"

print_help() {
  cat <<EOF
Usage: $(basename "$0") [options]

Create an idempotent Cloud Router + Cloud NAT for internal-only OpenClaw VMs.

Defaults:
  region:      ${REGION}
  network:     ${NETWORK}
  router name: ${ROUTER_NAME}
  nat name:    ${NAT_NAME}

Options:
  --project-id <id>      GCP project ID (required)
  --region <region>      Region for the router and NAT (default: ${REGION})
  --network <name>       VPC network name (default: ${NETWORK})
  --router-name <name>   Cloud Router name (default: ${ROUTER_NAME})
  --nat-name <name>      Cloud NAT name (default: ${NAT_NAME})
  --dry-run              Print commands only
  -h, --help             Show help
EOF
}

die() {
  echo "Error: $*" >&2
  exit 1
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    die "required command not found: $1"
  fi
}

router_exists() {
  gcloud compute routers describe "${ROUTER_NAME}" \
    --project "${PROJECT_ID}" \
    --region "${REGION}" \
    --format='value(name)' >/dev/null 2>&1
}

nat_exists() {
  gcloud compute routers nats describe "${NAT_NAME}" \
    --project "${PROJECT_ID}" \
    --router "${ROUTER_NAME}" \
    --region "${REGION}" \
    --format='value(name)' >/dev/null 2>&1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-id) PROJECT_ID="${2:-}"; shift 2 ;;
    --region) REGION="${2:-}"; shift 2 ;;
    --network) NETWORK="${2:-}"; shift 2 ;;
    --router-name) ROUTER_NAME="${2:-}"; shift 2 ;;
    --nat-name) NAT_NAME="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN="true"; shift ;;
    -h|--help) print_help; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

[[ -n "${PROJECT_ID}" ]] || die "--project-id is required"

if [[ "${DRY_RUN}" != "true" ]]; then
  require_command gcloud
fi

ROUTER_CMD=(
  gcloud compute routers create "${ROUTER_NAME}"
  --project "${PROJECT_ID}"
  --region "${REGION}"
  --network "${NETWORK}"
)

NAT_CMD=(
  gcloud compute routers nats create "${NAT_NAME}"
  --project "${PROJECT_ID}"
  --router "${ROUTER_NAME}"
  --region "${REGION}"
  --auto-allocate-nat-external-ips
  --nat-all-subnet-ip-ranges
)

echo "Cloud NAT inputs:"
echo "  project_id: ${PROJECT_ID}"
echo "  region: ${REGION}"
echo "  network: ${NETWORK}"
echo "  router_name: ${ROUTER_NAME}"
echo "  nat_name: ${NAT_NAME}"

if [[ "${DRY_RUN}" == "true" ]]; then
  echo "Dry-run note: router and NAT both use create-if-missing semantics."
  echo "Dry-run command (create router):"
  printf ' %q' "${ROUTER_CMD[@]}"
  echo
  echo "Dry-run command (create NAT):"
  printf ' %q' "${NAT_CMD[@]}"
  echo
  exit 0
fi

if router_exists; then
  echo "Cloud Router already exists; reusing: ${ROUTER_NAME}"
else
  "${ROUTER_CMD[@]}"
fi

if nat_exists; then
  echo "Cloud NAT already exists; reusing: ${NAT_NAME}"
else
  "${NAT_CMD[@]}"
fi

echo "Cloud NAT flow complete."
