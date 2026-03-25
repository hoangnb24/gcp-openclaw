#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID=""
SOURCE_INSTANCE="oc-main"
SOURCE_ZONE="asia-southeast1-a"
IMAGE_NAME=""
IMAGE_FAMILY=""
DESCRIPTION="OpenClaw persistent clone source image"
STORAGE_LOCATION=""
DRY_RUN="false"

print_help() {
  cat <<EOF
Usage: $(basename "$0") [options]

Create a machine image from a known-good OpenClaw VM for persistent cloning.

Defaults:
  source instance: ${SOURCE_INSTANCE}
  source zone:     ${SOURCE_ZONE}
  image family:    (none)

Options:
  --project-id <id>          GCP project ID (required)
  --source-instance <name>   Source VM name (default: ${SOURCE_INSTANCE})
  --source-zone <zone>       Source VM zone (default: ${SOURCE_ZONE})
  --image-name <name>        Machine image name (default: oc-image-<utc-timestamp>)
  --image-family <name>      Optional machine image family (for latest-in-family workflows)
  --description <text>       Image description
  --storage-location <loc>   Optional storage location/region override
  --dry-run                  Print command only
  -h, --help                 Show help

Safety notes:
  - This captures VM and disk state for persistent clones.
  - Scrub sensitive credentials on the source VM before capture.
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
    --source-instance) SOURCE_INSTANCE="${2:-}"; shift 2 ;;
    --source-zone) SOURCE_ZONE="${2:-}"; shift 2 ;;
    --image-name) IMAGE_NAME="${2:-}"; shift 2 ;;
    --image-family) IMAGE_FAMILY="${2:-}"; shift 2 ;;
    --description) DESCRIPTION="${2:-}"; shift 2 ;;
    --storage-location) STORAGE_LOCATION="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN="true"; shift ;;
    -h|--help) print_help; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

[[ -n "${PROJECT_ID}" ]] || die "--project-id is required"
[[ -n "${SOURCE_INSTANCE}" ]] || die "--source-instance cannot be empty"
[[ -n "${SOURCE_ZONE}" ]] || die "--source-zone cannot be empty"

if [[ -z "${IMAGE_NAME}" ]]; then
  IMAGE_NAME="oc-image-$(date -u +%Y%m%d-%H%M%S)"
fi

if [[ "${DRY_RUN}" != "true" ]]; then
  require_command gcloud
fi

CMD=(
  gcloud compute machine-images create "${IMAGE_NAME}"
  --project "${PROJECT_ID}"
  --source-instance "${SOURCE_INSTANCE}"
  --source-instance-zone "${SOURCE_ZONE}"
  --description "${DESCRIPTION}"
)

if [[ -n "${STORAGE_LOCATION}" ]]; then
  CMD+=(--storage-location "${STORAGE_LOCATION}")
fi
if [[ -n "${IMAGE_FAMILY}" ]]; then
  CMD+=(--labels "openclaw-family=${IMAGE_FAMILY}")
fi

echo "Machine image inputs:"
echo "  project_id: ${PROJECT_ID}"
echo "  source_instance: ${SOURCE_INSTANCE}"
echo "  source_zone: ${SOURCE_ZONE}"
echo "  image_name: ${IMAGE_NAME}"
if [[ -n "${IMAGE_FAMILY}" ]]; then
  echo "  image_family(label): ${IMAGE_FAMILY}"
fi
if [[ -n "${STORAGE_LOCATION}" ]]; then
  echo "  storage_location: ${STORAGE_LOCATION}"
fi

if [[ "${DRY_RUN}" == "true" ]]; then
  echo "Dry-run command:"
  printf ' %q' "${CMD[@]}"
  echo
  exit 0
fi

"${CMD[@]}"
echo "Machine image created: ${IMAGE_NAME}"
echo "Next: spawn a clone and reinject credentials or re-auth on the new VM."
