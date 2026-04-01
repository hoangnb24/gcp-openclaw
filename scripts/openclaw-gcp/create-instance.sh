#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CREATE_TEMPLATE_SCRIPT="${SCRIPT_DIR}/create-template.sh"
CREATE_CLOUD_NAT_SCRIPT="${SCRIPT_DIR}/create-cloud-nat.sh"

PROJECT_ID=""
INSTANCE_NAME="oc-main"
TEMPLATE_NAME="oc-template"
REGION="asia-southeast1"
ZONE="asia-southeast1-a"
MACHINE_TYPE="e2-standard-2"
DISK_TYPE="pd-balanced"
DISK_SIZE_GB="30"
OPENCLAW_IMAGE="ghcr.io/openclawai/gateway"
OPENCLAW_TAG=""
IMAGE_PROJECT="debian-cloud"
IMAGE_FAMILY="debian-12"
IMAGE_NAME=""
STARTUP_SCRIPT_FILE=""
STARTUP_SCRIPT_URL=""
STARTUP_SCRIPT_SHA256=""
RESOURCE_LABELS=""
SERVICE_ACCOUNT=""
SCOPES=""
NO_SERVICE_ACCOUNT="false"
NO_ADDRESS="false"
ENSURE_CLOUD_NAT="auto"
NETWORK="default"
ROUTER_NAME="oc-router"
NAT_NAME="oc-nat"
RESOLUTION_RECORD="${REPO_ROOT}/.khuym/runtime/openclaw-gcp/resolved-debian-image.txt"
ENSURE_TEMPLATE="true"
REPLACE_TEMPLATE="false"
DRY_RUN="false"
EXPLICIT_TEMPLATE_INPUTS=()

print_help() {
  cat <<EOF
Usage: $(basename "$0") [options]

Create a baseline OpenClaw VM from a deterministic instance template.

Defaults:
  machine type: ${MACHINE_TYPE}
  disk type:    ${DISK_TYPE}
  disk size:    ${DISK_SIZE_GB} GiB
  region:       ${REGION}
  zone:         ${ZONE}
  template:     ${TEMPLATE_NAME}
  instance:     ${INSTANCE_NAME}

Options:
  --project-id <id>             GCP project ID (required)
  --instance-name <name>        VM instance name (default: ${INSTANCE_NAME})
  --template-name <name>        Template name (default: ${TEMPLATE_NAME})
  --region <region>             Region (default: ${REGION})
  --zone <zone>                 Zone (default: ${ZONE})
  --machine-type <type>         Template machine type default (default: ${MACHINE_TYPE})
  --disk-type <type>            Template disk type default (default: ${DISK_TYPE})
  --disk-size-gb <size>         Template disk size default (default: ${DISK_SIZE_GB})
  --image-project <project>     Template image project (default: ${IMAGE_PROJECT})
  --image-family <family>       Template image family (default: ${IMAGE_FAMILY})
  --image-name <name>           Template explicit image name
  --openclaw-image <image>      OpenClaw container image (default: ${OPENCLAW_IMAGE})
  --openclaw-tag <tag>          OpenClaw image tag (required only when creating/replacing template)
  --startup-script-file <path>  Local startup script source for template
  --startup-script-url <url>    Remote startup script source for template
  --startup-script-sha256 <hex> Required SHA-256 when using --startup-script-url
  --resource-labels <csv>       Labels to apply to template and instance resources
  --service-account <email>     Service account for template-created VMs
  --scopes <csv>                OAuth scopes for the template service account
  --no-service-account          Create template-created VMs without any attached service account
  --no-address                  Create or replace the template without an external IPv4 address
  --ensure-cloud-nat            Ensure Cloud NAT exists when using an internal-only template
  --no-ensure-cloud-nat         Skip Cloud NAT creation even for internal-only templates
  --network <name>              Network name for Cloud NAT (default: ${NETWORK})
  --router-name <name>          Cloud Router name for NAT (default: ${ROUTER_NAME})
  --nat-name <name>             Cloud NAT name (default: ${NAT_NAME})
  --resolution-record <path>    Template image resolution record path
  --no-create-template          Skip template creation and use existing template
  --replace-template            Recreate the template before instance creation
  --dry-run                     Print commands only
  -h, --help                    Show help
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

record_explicit_template_input() {
  EXPLICIT_TEMPLATE_INPUTS+=("$1")
}

validate_zone_region_pair() {
  [[ "${ZONE}" == "${REGION}"-* ]] || die "--zone must belong to --region (got zone=${ZONE}, region=${REGION})"
}

template_is_internal_only() {
  local access_config_name
  access_config_name="$(gcloud compute instance-templates describe "${TEMPLATE_NAME}" \
    --project "${PROJECT_ID}" \
    --region "${REGION}" \
    --format='value(properties.networkInterfaces[0].accessConfigs[0].name)' 2>/dev/null || true)"
  [[ -z "${access_config_name}" ]]
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-id) PROJECT_ID="${2:-}"; shift 2 ;;
    --instance-name) INSTANCE_NAME="${2:-}"; shift 2 ;;
    --template-name) TEMPLATE_NAME="${2:-}"; shift 2 ;;
    --region) REGION="${2:-}"; shift 2 ;;
    --zone) ZONE="${2:-}"; shift 2 ;;
    --machine-type) MACHINE_TYPE="${2:-}"; record_explicit_template_input "--machine-type"; shift 2 ;;
    --disk-type) DISK_TYPE="${2:-}"; record_explicit_template_input "--disk-type"; shift 2 ;;
    --disk-size-gb) DISK_SIZE_GB="${2:-}"; record_explicit_template_input "--disk-size-gb"; shift 2 ;;
    --image-project) IMAGE_PROJECT="${2:-}"; record_explicit_template_input "--image-project"; shift 2 ;;
    --image-family) IMAGE_FAMILY="${2:-}"; record_explicit_template_input "--image-family"; shift 2 ;;
    --image-name) IMAGE_NAME="${2:-}"; record_explicit_template_input "--image-name"; shift 2 ;;
    --openclaw-image) OPENCLAW_IMAGE="${2:-}"; record_explicit_template_input "--openclaw-image"; shift 2 ;;
    --openclaw-tag) OPENCLAW_TAG="${2:-}"; record_explicit_template_input "--openclaw-tag"; shift 2 ;;
    --startup-script-file) STARTUP_SCRIPT_FILE="${2:-}"; record_explicit_template_input "--startup-script-file"; shift 2 ;;
    --startup-script-url) STARTUP_SCRIPT_URL="${2:-}"; record_explicit_template_input "--startup-script-url"; shift 2 ;;
    --startup-script-sha256) STARTUP_SCRIPT_SHA256="${2:-}"; record_explicit_template_input "--startup-script-sha256"; shift 2 ;;
    --resource-labels) RESOURCE_LABELS="${2:-}"; shift 2 ;;
    --service-account) SERVICE_ACCOUNT="${2:-}"; record_explicit_template_input "--service-account"; shift 2 ;;
    --scopes) SCOPES="${2:-}"; record_explicit_template_input "--scopes"; shift 2 ;;
    --no-service-account) NO_SERVICE_ACCOUNT="true"; record_explicit_template_input "--no-service-account"; shift ;;
    --no-address) NO_ADDRESS="true"; record_explicit_template_input "--no-address"; shift ;;
    --ensure-cloud-nat) ENSURE_CLOUD_NAT="true"; shift ;;
    --no-ensure-cloud-nat) ENSURE_CLOUD_NAT="false"; shift ;;
    --network) NETWORK="${2:-}"; shift 2 ;;
    --router-name) ROUTER_NAME="${2:-}"; shift 2 ;;
    --nat-name) NAT_NAME="${2:-}"; shift 2 ;;
    --resolution-record) RESOLUTION_RECORD="${2:-}"; shift 2 ;;
    --no-create-template) ENSURE_TEMPLATE="false"; shift ;;
    --replace-template) REPLACE_TEMPLATE="true"; shift ;;
    --dry-run) DRY_RUN="true"; shift ;;
    -h|--help) print_help; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

[[ -n "${PROJECT_ID}" ]] || die "--project-id is required"
[[ "${DISK_SIZE_GB}" =~ ^[0-9]+$ ]] || die "--disk-size-gb must be an integer"
[[ -f "${CREATE_TEMPLATE_SCRIPT}" ]] || die "missing helper script: ${CREATE_TEMPLATE_SCRIPT}"
[[ -f "${CREATE_CLOUD_NAT_SCRIPT}" ]] || die "missing helper script: ${CREATE_CLOUD_NAT_SCRIPT}"
validate_zone_region_pair

if [[ "${DRY_RUN}" != "true" ]]; then
  require_command gcloud
fi

if [[ "${ENSURE_TEMPLATE}" == "true" ]]; then
  TEMPLATE_CMD=(
    bash "${CREATE_TEMPLATE_SCRIPT}"
    --project-id "${PROJECT_ID}"
    --template-name "${TEMPLATE_NAME}"
    --region "${REGION}"
    --zone "${ZONE}"
    --resolution-record "${RESOLUTION_RECORD}"
  )

  if [[ " ${EXPLICIT_TEMPLATE_INPUTS[*]} " == *" --machine-type "* ]]; then
    TEMPLATE_CMD+=(--machine-type "${MACHINE_TYPE}")
  fi
  if [[ " ${EXPLICIT_TEMPLATE_INPUTS[*]} " == *" --disk-type "* ]]; then
    TEMPLATE_CMD+=(--disk-type "${DISK_TYPE}")
  fi
  if [[ " ${EXPLICIT_TEMPLATE_INPUTS[*]} " == *" --disk-size-gb "* ]]; then
    TEMPLATE_CMD+=(--disk-size-gb "${DISK_SIZE_GB}")
  fi
  if [[ " ${EXPLICIT_TEMPLATE_INPUTS[*]} " == *" --image-project "* ]]; then
    TEMPLATE_CMD+=(--image-project "${IMAGE_PROJECT}")
  fi
  if [[ " ${EXPLICIT_TEMPLATE_INPUTS[*]} " == *" --image-family "* ]]; then
    TEMPLATE_CMD+=(--image-family "${IMAGE_FAMILY}")
  fi
  if [[ -n "${IMAGE_NAME}" ]]; then
    TEMPLATE_CMD+=(--image-name "${IMAGE_NAME}")
  fi
  if [[ " ${EXPLICIT_TEMPLATE_INPUTS[*]} " == *" --openclaw-image "* ]]; then
    TEMPLATE_CMD+=(--openclaw-image "${OPENCLAW_IMAGE}")
  fi
  if [[ -n "${OPENCLAW_TAG}" ]]; then
    TEMPLATE_CMD+=(--openclaw-tag "${OPENCLAW_TAG}")
  fi
  if [[ -n "${STARTUP_SCRIPT_FILE}" ]]; then
    TEMPLATE_CMD+=(--startup-script-file "${STARTUP_SCRIPT_FILE}")
  fi
  if [[ -n "${STARTUP_SCRIPT_URL}" ]]; then
    TEMPLATE_CMD+=(--startup-script-url "${STARTUP_SCRIPT_URL}")
  fi
  if [[ -n "${STARTUP_SCRIPT_SHA256}" ]]; then
    TEMPLATE_CMD+=(--startup-script-sha256 "${STARTUP_SCRIPT_SHA256}")
  fi
  if [[ -n "${RESOURCE_LABELS}" ]]; then
    TEMPLATE_CMD+=(--resource-labels "${RESOURCE_LABELS}")
  fi
  if [[ -n "${SERVICE_ACCOUNT}" ]]; then
    TEMPLATE_CMD+=(--service-account "${SERVICE_ACCOUNT}")
  fi
  if [[ -n "${SCOPES}" ]]; then
    TEMPLATE_CMD+=(--scopes "${SCOPES}")
  fi
  if [[ "${NO_SERVICE_ACCOUNT}" == "true" ]]; then
    TEMPLATE_CMD+=(--no-service-account)
  fi
  if [[ "${NO_ADDRESS}" == "true" ]]; then
    TEMPLATE_CMD+=(--no-address)
  fi
  if [[ "${REPLACE_TEMPLATE}" == "true" ]]; then
    TEMPLATE_CMD+=(--replace-existing)
  fi
  if [[ "${DRY_RUN}" == "true" ]]; then
    TEMPLATE_CMD+=(--dry-run)
  fi

  echo "Ensuring deterministic template exists..."
  "${TEMPLATE_CMD[@]}"
fi

SHOULD_ENSURE_CLOUD_NAT="false"
case "${ENSURE_CLOUD_NAT}" in
  true) SHOULD_ENSURE_CLOUD_NAT="true" ;;
  false) SHOULD_ENSURE_CLOUD_NAT="false" ;;
  auto)
    if [[ "${DRY_RUN}" == "true" ]]; then
      [[ "${NO_ADDRESS}" == "true" ]] && SHOULD_ENSURE_CLOUD_NAT="true"
    else
      template_is_internal_only && SHOULD_ENSURE_CLOUD_NAT="true"
    fi
    ;;
  *) die "invalid Cloud NAT mode: ${ENSURE_CLOUD_NAT}" ;;
esac

if [[ "${SHOULD_ENSURE_CLOUD_NAT}" == "true" ]]; then
  NAT_CMD=(
    bash "${CREATE_CLOUD_NAT_SCRIPT}"
    --project-id "${PROJECT_ID}"
    --region "${REGION}"
    --network "${NETWORK}"
    --router-name "${ROUTER_NAME}"
    --nat-name "${NAT_NAME}"
  )
  if [[ "${DRY_RUN}" == "true" ]]; then
    NAT_CMD+=(--dry-run)
  fi
  echo "Ensuring Cloud NAT exists for internal-only egress..."
  "${NAT_CMD[@]}"
fi

SOURCE_TEMPLATE="projects/${PROJECT_ID}/regions/${REGION}/instanceTemplates/${TEMPLATE_NAME}"

CREATE_CMD=(
  gcloud compute instances create "${INSTANCE_NAME}"
  --project "${PROJECT_ID}"
  --zone "${ZONE}"
  --source-instance-template "${SOURCE_TEMPLATE}"
)
if [[ -n "${RESOURCE_LABELS}" ]]; then
  CREATE_CMD+=(--labels "${RESOURCE_LABELS}")
fi

echo "Instance defaults:"
echo "  instance_name: ${INSTANCE_NAME}"
echo "  template_name: ${TEMPLATE_NAME}"
echo "  source_template: ${SOURCE_TEMPLATE}"
echo "  region: ${REGION}"
echo "  zone: ${ZONE}"
echo "  machine_type(default): ${MACHINE_TYPE}"
echo "  disk(default): ${DISK_TYPE} ${DISK_SIZE_GB} GiB"
echo "  ensure_template: ${ENSURE_TEMPLATE}"
echo "  replace_template: ${REPLACE_TEMPLATE}"
echo "  ensure_cloud_nat: ${ENSURE_CLOUD_NAT}"
echo "  resource_labels: ${RESOURCE_LABELS:-<none>}"
if (( ${#EXPLICIT_TEMPLATE_INPUTS[@]} > 0 )); then
  echo "  explicit_template_inputs: ${EXPLICIT_TEMPLATE_INPUTS[*]}"
fi

if [[ "${DRY_RUN}" == "true" ]]; then
  echo "Dry-run command:"
  printf ' %q' "${CREATE_CMD[@]}"
  echo
  exit 0
fi

"${CREATE_CMD[@]}"
echo "Instance created: ${INSTANCE_NAME}"
