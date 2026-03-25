#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID=""
INSTANCE_NAME=""
MACHINE_IMAGE=""
ZONE="asia-southeast1-a"
MACHINE_TYPE=""
SUBNET=""
SERVICE_ACCOUNT=""
SCOPES=""
DRY_RUN="false"

print_help() {
  cat <<EOF
Usage: $(basename "$0") [options]

Spawn a persistent OpenClaw clone from a machine image.

Defaults:
  zone: ${ZONE}

Options:
  --project-id <id>             GCP project ID (required)
  --instance-name <name>        New instance name (required)
  --machine-image <name-or-url> Source machine image name or self-link (required)
  --zone <zone>                 Target zone (default: ${ZONE})
  --machine-type <type>         Optional machine type override
  --subnet <subnet>             Optional subnet self-link or name
  --service-account <email>     Optional service account for secret access
  --scopes <csv>                Optional OAuth scopes (comma-separated)
  --dry-run                     Print command only
  -h, --help                    Show help

Security notes:
  - Do not assume provider credentials are safe to inherit from source images.
  - Re-auth or reinject credentials after clone creation.
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
    --machine-image) MACHINE_IMAGE="${2:-}"; shift 2 ;;
    --zone) ZONE="${2:-}"; shift 2 ;;
    --machine-type) MACHINE_TYPE="${2:-}"; shift 2 ;;
    --subnet) SUBNET="${2:-}"; shift 2 ;;
    --service-account) SERVICE_ACCOUNT="${2:-}"; shift 2 ;;
    --scopes) SCOPES="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN="true"; shift ;;
    -h|--help) print_help; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

[[ -n "${PROJECT_ID}" ]] || die "--project-id is required"
[[ -n "${INSTANCE_NAME}" ]] || die "--instance-name is required"
[[ -n "${MACHINE_IMAGE}" ]] || die "--machine-image is required"
[[ -n "${ZONE}" ]] || die "--zone cannot be empty"

if [[ "${DRY_RUN}" != "true" ]]; then
  require_command gcloud
fi

CMD=(
  gcloud compute instances create "${INSTANCE_NAME}"
  --project "${PROJECT_ID}"
  --zone "${ZONE}"
  --source-machine-image "${MACHINE_IMAGE}"
)

if [[ -n "${MACHINE_TYPE}" ]]; then
  CMD+=(--machine-type "${MACHINE_TYPE}")
fi
if [[ -n "${SUBNET}" ]]; then
  CMD+=(--subnet "${SUBNET}")
fi
if [[ -n "${SERVICE_ACCOUNT}" ]]; then
  CMD+=(--service-account "${SERVICE_ACCOUNT}")
fi
if [[ -n "${SCOPES}" ]]; then
  CMD+=(--scopes "${SCOPES}")
fi

echo "Clone inputs:"
echo "  project_id: ${PROJECT_ID}"
echo "  instance_name: ${INSTANCE_NAME}"
echo "  machine_image: ${MACHINE_IMAGE}"
echo "  zone: ${ZONE}"
if [[ -n "${MACHINE_TYPE}" ]]; then
  echo "  machine_type_override: ${MACHINE_TYPE}"
fi
if [[ -n "${SUBNET}" ]]; then
  echo "  subnet: ${SUBNET}"
fi
if [[ -n "${SERVICE_ACCOUNT}" ]]; then
  echo "  service_account: ${SERVICE_ACCOUNT}"
fi

if [[ "${DRY_RUN}" == "true" ]]; then
  echo "Dry-run command:"
  printf ' %q' "${CMD[@]}"
  echo
  exit 0
fi

"${CMD[@]}"
echo "Clone instance created: ${INSTANCE_NAME}"
echo "Required next step: perform post-clone credential reinjection or re-auth."
