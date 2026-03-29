#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_SCRIPT="${SCRIPT_DIR}/bootstrap-vm-prereqs.sh"
STARTUP_SCRIPT_SOURCE="embedded-vm-prereqs-v1"
STARTUP_PROFILE="vm-prereqs-v1"
STARTUP_CONTRACT_VERSION="startup-ready-v1"
STARTUP_READY_SENTINEL="/var/lib/openclaw/startup-ready-v1"

PROJECT_ID=""
INSTANCE_NAME=""
ZONE="asia-southeast1-a"
OPENCLAW_IMAGE="ghcr.io/openclaw/openclaw"
OPENCLAW_TAG=""
RUN_NOW="false"
TUNNEL_THROUGH_IAP="true"
DRY_RUN="false"

print_help() {
  cat <<EOF
Usage: $(basename "$0") [options]

Update an existing VM's startup metadata to the current VM prerequisites bootstrap and optionally rerun it immediately.

Options:
  --project-id <id>        GCP project ID (required)
  --instance-name <name>   VM instance name (required)
  --zone <zone>            VM zone (default: ${ZONE})
  --openclaw-image <img>   Legacy metadata compatibility value (default: ${OPENCLAW_IMAGE})
  --openclaw-tag <tag>     Legacy metadata compatibility value (optional)
  --run-now                Rerun the startup script immediately over SSH
  --no-tunnel-through-iap  Do not use IAP when rerunning remotely
  --dry-run                Print commands only
  -h, --help               Show help
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

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-id) PROJECT_ID="${2:-}"; shift 2 ;;
    --instance-name) INSTANCE_NAME="${2:-}"; shift 2 ;;
    --zone) ZONE="${2:-}"; shift 2 ;;
    --openclaw-image) OPENCLAW_IMAGE="${2:-}"; shift 2 ;;
    --openclaw-tag) OPENCLAW_TAG="${2:-}"; shift 2 ;;
    --run-now) RUN_NOW="true"; shift ;;
    --no-tunnel-through-iap) TUNNEL_THROUGH_IAP="false"; shift ;;
    --dry-run) DRY_RUN="true"; shift ;;
    -h|--help) print_help; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

[[ -n "${PROJECT_ID}" ]] || die "--project-id is required"
[[ -n "${INSTANCE_NAME}" ]] || die "--instance-name is required"
[[ -f "${BOOTSTRAP_SCRIPT}" ]] || die "missing bootstrap script: ${BOOTSTRAP_SCRIPT}"

if [[ "${DRY_RUN}" != "true" ]]; then
  require_command gcloud
fi

METADATA_ENTRIES=(
  "startup_script_source=${STARTUP_SCRIPT_SOURCE}"
  "startup_profile=${STARTUP_PROFILE}"
  "startup_contract_version=${STARTUP_CONTRACT_VERSION}"
  "startup_ready_sentinel=${STARTUP_READY_SENTINEL}"
)
if [[ -n "${OPENCLAW_IMAGE}" ]]; then
  METADATA_ENTRIES+=("legacy_openclaw_image=${OPENCLAW_IMAGE}")
fi
if [[ -n "${OPENCLAW_TAG}" ]]; then
  METADATA_ENTRIES+=("legacy_openclaw_tag=${OPENCLAW_TAG}")
fi
METADATA_STRING="$(IFS=,; printf '%s' "${METADATA_ENTRIES[*]}")"

METADATA_CMD=(
  gcloud compute instances add-metadata "${INSTANCE_NAME}"
  --project "${PROJECT_ID}"
  --zone "${ZONE}"
  --metadata "${METADATA_STRING}"
  --metadata-from-file "startup-script=${BOOTSTRAP_SCRIPT}"
)

SSH_CMD=(
  gcloud compute ssh "${INSTANCE_NAME}"
  --project "${PROJECT_ID}"
  --zone "${ZONE}"
)

if [[ "${TUNNEL_THROUGH_IAP}" == "true" ]]; then
  SSH_CMD+=(--tunnel-through-iap)
fi

SSH_CMD+=(--command "sudo google_metadata_script_runner startup")

echo "Repair inputs:"
echo "  project_id: ${PROJECT_ID}"
echo "  instance_name: ${INSTANCE_NAME}"
echo "  zone: ${ZONE}"
echo "  startup_script_source: ${STARTUP_SCRIPT_SOURCE}"
echo "  startup_profile: ${STARTUP_PROFILE}"
echo "  startup_contract_version: ${STARTUP_CONTRACT_VERSION}"
echo "  startup_ready_sentinel: ${STARTUP_READY_SENTINEL}"
echo "  openclaw_image: ${OPENCLAW_IMAGE}"
echo "  openclaw_tag: ${OPENCLAW_TAG}"
echo "  run_now: ${RUN_NOW}"
echo "  tunnel_through_iap: ${TUNNEL_THROUGH_IAP}"

if [[ "${DRY_RUN}" == "true" ]]; then
  echo "Dry-run command (update metadata):"
  printf ' %q' "${METADATA_CMD[@]}"
  echo
  if [[ "${RUN_NOW}" == "true" ]]; then
    echo "Dry-run command (rerun startup):"
    printf ' %q' "${SSH_CMD[@]}"
    echo
  fi
  exit 0
fi

"${METADATA_CMD[@]}"
echo "Updated startup metadata on ${INSTANCE_NAME}."

if [[ "${RUN_NOW}" == "true" ]]; then
  "${SSH_CMD[@]}"
fi

echo "Repair flow complete."
