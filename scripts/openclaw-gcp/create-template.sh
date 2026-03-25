#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BOOTSTRAP_SCRIPT_TEMPLATE="${SCRIPT_DIR}/bootstrap-openclaw.sh"

PROJECT_ID=""
TEMPLATE_NAME="oc-template"
REGION="asia-southeast1"
ZONE="asia-southeast1-a"
MACHINE_TYPE="e2-standard-2"
DISK_TYPE="pd-balanced"
DISK_SIZE_GB="30"
IMAGE_PROJECT="debian-cloud"
IMAGE_FAMILY="debian-12"
IMAGE_NAME=""
OPENCLAW_IMAGE="ghcr.io/openclawai/gateway"
OPENCLAW_TAG="pin-me"
STARTUP_SCRIPT_FILE=""
STARTUP_SCRIPT_URL=""
STARTUP_SCRIPT_SHA256=""
STARTUP_SCRIPT_MODE="embedded"
SERVICE_ACCOUNT=""
SCOPES=""
NO_SERVICE_ACCOUNT="false"
NO_ADDRESS="false"
RESOLUTION_RECORD="${REPO_ROOT}/.khuym/runtime/openclaw-gcp/resolved-debian-image.txt"
REPLACE_EXISTING="false"
DRY_RUN="false"
EXPLICIT_TEMPLATE_INPUTS=()

print_help() {
  cat <<EOF
Usage: $(basename "$0") [options]

Create a deterministic OpenClaw baseline instance template.

Defaults:
  machine type: ${MACHINE_TYPE}
  disk type:    ${DISK_TYPE}
  disk size:    ${DISK_SIZE_GB} GiB
  region:       ${REGION}
  zone:         ${ZONE}
  image family: ${IMAGE_FAMILY} (project ${IMAGE_PROJECT})
  OpenClaw image: ${OPENCLAW_IMAGE}
  OpenClaw tag:   ${OPENCLAW_TAG} (must be overridden)

Options:
  --project-id <id>             GCP project ID (required)
  --template-name <name>        Instance template name (default: ${TEMPLATE_NAME})
  --region <region>             Region (default: ${REGION})
  --zone <zone>                 Zone for regional context (default: ${ZONE})
  --machine-type <type>         Machine type (default: ${MACHINE_TYPE})
  --disk-type <type>            Boot disk type (default: ${DISK_TYPE})
  --disk-size-gb <size>         Boot disk size in GiB (default: ${DISK_SIZE_GB})
  --image-project <project>     Image project (default: ${IMAGE_PROJECT})
  --image-family <family>       Image family to resolve (default: ${IMAGE_FAMILY})
  --image-name <name>           Explicit image name (overrides family resolution)
  --openclaw-image <image>      OpenClaw container image (default: ${OPENCLAW_IMAGE})
  --openclaw-tag <tag>          OpenClaw image tag (required; no secrets)
  --startup-script-file <path>  Local startup script source
  --startup-script-url <url>    Remote startup script source
  --startup-script-sha256 <hex> Required SHA-256 when using --startup-script-url
  --service-account <email>     Service account to attach to the template
  --scopes <csv>                OAuth scopes for the service account
  --no-service-account          Create the template without any attached service account
  --no-address                  Create the template without an external IPv4 address
  --resolution-record <path>    File to record resolved image details (default: ${RESOLUTION_RECORD})
  --replace-existing            Delete and recreate the template if it already exists
  --dry-run                     Print resolved configuration and gcloud command only
  -h, --help                    Show help
EOF
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: required command not found: $1" >&2
    exit 1
  fi
}

die() {
  echo "Error: $*" >&2
  exit 1
}

record_explicit_template_input() {
  EXPLICIT_TEMPLATE_INPUTS+=("$1")
}

resolve_image_name() {
  if [[ -n "${IMAGE_NAME}" ]]; then
    gcloud compute images describe "${IMAGE_NAME}" \
      --project "${IMAGE_PROJECT}" \
      --format='value(name)'
    return
  fi

  gcloud compute images describe-from-family "${IMAGE_FAMILY}" \
    --project "${IMAGE_PROJECT}" \
    --format='value(name)'
}

resolve_image_self_link() {
  local resolved_name="$1"
  gcloud compute images describe "${resolved_name}" \
    --project "${IMAGE_PROJECT}" \
    --format='value(selfLink)'
}

template_exists() {
  gcloud compute instance-templates describe "${TEMPLATE_NAME}" \
    --project "${PROJECT_ID}" \
    --region "${REGION}" \
    --format='value(name)' >/dev/null 2>&1
}

write_reuse_record() {
  mkdir -p "$(dirname "${RESOLUTION_RECORD}")"
  cat >"${RESOLUTION_RECORD}" <<EOF
resolved_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
template_name=${TEMPLATE_NAME}
mode=reused-existing-template
project_id=${PROJECT_ID}
EOF
}

sha256_of_file() {
  local path="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${path}" | awk '{print $1}'
    return
  fi
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "${path}" | awk '{print $1}'
    return
  fi
  if command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "${path}" | awk '{print $NF}'
    return
  fi
  die "no SHA-256 tool available (need sha256sum, shasum, or openssl)"
}

validate_zone_region_pair() {
  [[ "${ZONE}" == "${REGION}"-* ]] || die "--zone must belong to --region (got zone=${ZONE}, region=${REGION})"
}

validate_metadata_value() {
  local field_name="$1"
  local field_value="$2"
  [[ "${field_value}" != *","* ]] || die "${field_name} must not contain ',' because it is persisted in metadata"
  [[ "${field_value}" != *"="* ]] || die "${field_name} must not contain '=' because it is persisted in metadata"
  [[ "${field_value}" != *$'\n'* ]] || die "${field_name} must not contain newlines"
}

write_embedded_startup_script() {
  local target="$1"
  [[ -f "${BOOTSTRAP_SCRIPT_TEMPLATE}" ]] || die "missing embedded bootstrap script template: ${BOOTSTRAP_SCRIPT_TEMPLATE}"
  cp "${BOOTSTRAP_SCRIPT_TEMPLATE}" "${target}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-id) PROJECT_ID="${2:-}"; shift 2 ;;
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
    --service-account) SERVICE_ACCOUNT="${2:-}"; record_explicit_template_input "--service-account"; shift 2 ;;
    --scopes) SCOPES="${2:-}"; record_explicit_template_input "--scopes"; shift 2 ;;
    --no-service-account) NO_SERVICE_ACCOUNT="true"; record_explicit_template_input "--no-service-account"; shift ;;
    --no-address) NO_ADDRESS="true"; record_explicit_template_input "--no-address"; shift ;;
    --resolution-record) RESOLUTION_RECORD="${2:-}"; shift 2 ;;
    --replace-existing) REPLACE_EXISTING="true"; shift ;;
    --dry-run) DRY_RUN="true"; shift ;;
    -h|--help) print_help; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

[[ -n "${PROJECT_ID}" ]] || die "--project-id is required"
[[ "${DISK_SIZE_GB}" =~ ^[0-9]+$ ]] || die "--disk-size-gb must be an integer"
[[ -n "${OPENCLAW_IMAGE}" ]] || die "--openclaw-image cannot be empty"
validate_zone_region_pair

if [[ -n "${STARTUP_SCRIPT_FILE}" && -n "${STARTUP_SCRIPT_URL}" ]]; then
  die "set only one of --startup-script-file or --startup-script-url"
fi

if [[ -n "${STARTUP_SCRIPT_URL}" ]]; then
  [[ "${STARTUP_SCRIPT_SHA256}" =~ ^[A-Fa-f0-9]{64}$ ]] || die "--startup-script-sha256 must be a 64-character hex digest when using --startup-script-url"
fi

if [[ "${DRY_RUN}" != "true" ]]; then
  require_command gcloud
fi

if [[ "${DRY_RUN}" != "true" ]] && template_exists; then
  if [[ "${REPLACE_EXISTING}" == "true" ]]; then
    echo "Template exists; recreating: ${TEMPLATE_NAME}"
    gcloud compute instance-templates delete "${TEMPLATE_NAME}" \
      --project "${PROJECT_ID}" \
      --region "${REGION}" \
      --quiet
  else
    if (( ${#EXPLICIT_TEMPLATE_INPUTS[@]} > 0 )); then
      die "template already exists and these explicit template-shaping flags would be ignored: ${EXPLICIT_TEMPLATE_INPUTS[*]}; rerun with --replace-existing or remove those flags"
    fi
    echo "Template already exists; reusing existing template: ${TEMPLATE_NAME}"
    echo "Pass --replace-existing to recreate it with current flags."
    write_reuse_record
    exit 0
  fi
fi

[[ -n "${OPENCLAW_TAG}" ]] || die "--openclaw-tag cannot be empty when creating or replacing a template"
[[ "${OPENCLAW_TAG}" != "pin-me" ]] || die "--openclaw-tag must be explicitly set when creating or replacing a template (avoid drifting defaults)"
if [[ "${NO_SERVICE_ACCOUNT}" == "true" ]]; then
  [[ -z "${SERVICE_ACCOUNT}" ]] || die "--no-service-account cannot be combined with --service-account"
  [[ -z "${SCOPES}" ]] || die "--no-service-account cannot be combined with --scopes"
else
  [[ -n "${SERVICE_ACCOUNT}" ]] || die "choose an identity mode: pass --service-account with --scopes, or pass --no-service-account"
  [[ -n "${SCOPES}" ]] || die "--scopes is required when using --service-account"
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT
STARTUP_SCRIPT_PATH="${WORK_DIR}/startup-script.sh"
STARTUP_SCRIPT_SOURCE="embedded-openclaw-bootstrap-v10"
STARTUP_SCRIPT_DIGEST=""

if [[ -n "${STARTUP_SCRIPT_FILE}" ]]; then
  [[ -f "${STARTUP_SCRIPT_FILE}" ]] || die "startup script not found: ${STARTUP_SCRIPT_FILE}"
  cp "${STARTUP_SCRIPT_FILE}" "${STARTUP_SCRIPT_PATH}"
  STARTUP_SCRIPT_DIGEST="$(sha256_of_file "${STARTUP_SCRIPT_PATH}")"
  STARTUP_SCRIPT_MODE="file"
  STARTUP_SCRIPT_SOURCE="file-sha256:${STARTUP_SCRIPT_DIGEST,,}"
elif [[ -n "${STARTUP_SCRIPT_URL}" ]]; then
  if [[ "${DRY_RUN}" == "true" ]]; then
    STARTUP_SCRIPT_MODE="url"
    STARTUP_SCRIPT_DIGEST="${STARTUP_SCRIPT_SHA256,,}"
    STARTUP_SCRIPT_SOURCE="url-sha256:${STARTUP_SCRIPT_DIGEST}"
    write_embedded_startup_script "${STARTUP_SCRIPT_PATH}"
  else
    require_command curl
    curl -fsSL "${STARTUP_SCRIPT_URL}" -o "${STARTUP_SCRIPT_PATH}"
    ACTUAL_STARTUP_SHA256="$(sha256_of_file "${STARTUP_SCRIPT_PATH}")"
    [[ "${ACTUAL_STARTUP_SHA256,,}" == "${STARTUP_SCRIPT_SHA256,,}" ]] || die "startup script SHA-256 mismatch for ${STARTUP_SCRIPT_URL}"
    STARTUP_SCRIPT_MODE="url"
    STARTUP_SCRIPT_DIGEST="${STARTUP_SCRIPT_SHA256,,}"
    STARTUP_SCRIPT_SOURCE="url-sha256:${STARTUP_SCRIPT_DIGEST}"
  fi
else
  write_embedded_startup_script "${STARTUP_SCRIPT_PATH}"
fi

if [[ "${DRY_RUN}" == "true" ]]; then
  RESOLVED_IMAGE_NAME="${IMAGE_NAME:-<resolved-from-${IMAGE_FAMILY}>}"
  RESOLVED_IMAGE_LINK="<resolved-self-link>"
else
  RESOLVED_IMAGE_NAME="$(resolve_image_name)"
  [[ -n "${RESOLVED_IMAGE_NAME}" ]] || die "unable to resolve Debian image name"
  RESOLVED_IMAGE_LINK="$(resolve_image_self_link "${RESOLVED_IMAGE_NAME}")"
  [[ -n "${RESOLVED_IMAGE_LINK}" ]] || die "unable to resolve Debian image selfLink"
fi

mkdir -p "$(dirname "${RESOLUTION_RECORD}")"
validate_metadata_value "openclaw_image" "${OPENCLAW_IMAGE}"
validate_metadata_value "openclaw_tag" "${OPENCLAW_TAG}"
validate_metadata_value "startup_script_source" "${STARTUP_SCRIPT_SOURCE}"
validate_metadata_value "debian_image_resolved" "${RESOLVED_IMAGE_NAME}"
if [[ -n "${SERVICE_ACCOUNT}" ]]; then
  validate_metadata_value "service_account" "${SERVICE_ACCOUNT}"
  validate_metadata_value "scopes" "${SCOPES}"
fi
cat >"${RESOLUTION_RECORD}" <<EOF
resolved_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
image_project=${IMAGE_PROJECT}
image_family=${IMAGE_FAMILY}
image_name=${RESOLVED_IMAGE_NAME}
image_self_link=${RESOLVED_IMAGE_LINK}
template_name=${TEMPLATE_NAME}
openclaw_image=${OPENCLAW_IMAGE}
openclaw_tag=${OPENCLAW_TAG}
startup_script_mode=${STARTUP_SCRIPT_MODE}
startup_script_source=${STARTUP_SCRIPT_SOURCE}
startup_script_sha256=${STARTUP_SCRIPT_DIGEST}
identity_mode=$([[ "${NO_SERVICE_ACCOUNT}" == "true" ]] && echo "no-service-account" || echo "service-account")
service_account=${SERVICE_ACCOUNT}
scopes=${SCOPES}
EOF

CMD=(
  gcloud compute instance-templates create "${TEMPLATE_NAME}"
  --project "${PROJECT_ID}"
  --machine-type "${MACHINE_TYPE}"
  --instance-template-region "${REGION}"
  --boot-disk-type "${DISK_TYPE}"
  --boot-disk-size "${DISK_SIZE_GB}GB"
  --image "${RESOLVED_IMAGE_NAME}"
  --image-project "${IMAGE_PROJECT}"
  --metadata "openclaw_image=${OPENCLAW_IMAGE},openclaw_tag=${OPENCLAW_TAG},startup_script_source=${STARTUP_SCRIPT_SOURCE},debian_image_resolved=${RESOLVED_IMAGE_NAME}"
  --metadata-from-file "startup-script=${STARTUP_SCRIPT_PATH}"
)

if [[ "${NO_SERVICE_ACCOUNT}" == "true" ]]; then
  CMD+=(--no-service-account --no-scopes)
else
  CMD+=(--service-account "${SERVICE_ACCOUNT}" --scopes "${SCOPES}")
fi
if [[ "${NO_ADDRESS}" == "true" ]]; then
  CMD+=(--no-address)
fi

echo "Deterministic inputs:"
echo "  template_name: ${TEMPLATE_NAME}"
echo "  region: ${REGION}"
echo "  zone: ${ZONE}"
echo "  machine_type: ${MACHINE_TYPE}"
echo "  disk: ${DISK_TYPE} ${DISK_SIZE_GB} GiB"
echo "  image_name: ${RESOLVED_IMAGE_NAME}"
echo "  image_self_link: ${RESOLVED_IMAGE_LINK}"
echo "  startup_script_source: ${STARTUP_SCRIPT_SOURCE}"
echo "  openclaw_image: ${OPENCLAW_IMAGE}"
echo "  openclaw_tag: ${OPENCLAW_TAG}"
echo "  identity_mode: $([[ "${NO_SERVICE_ACCOUNT}" == "true" ]] && echo "no-service-account" || echo "service-account")"
echo "  external_ipv4: $([[ "${NO_ADDRESS}" == "true" ]] && echo "disabled" || echo "ephemeral-default")"
if [[ -n "${SERVICE_ACCOUNT}" ]]; then
  echo "  service_account: ${SERVICE_ACCOUNT}"
  echo "  scopes: ${SCOPES}"
fi
echo "  resolution_record: ${RESOLUTION_RECORD}"
echo "  replace_existing: ${REPLACE_EXISTING}"
echo "  startup_script_mode: ${STARTUP_SCRIPT_MODE}"
if [[ -n "${STARTUP_SCRIPT_SHA256}" ]]; then
  echo "  startup_script_sha256: ${STARTUP_SCRIPT_SHA256,,}"
fi

if [[ "${DRY_RUN}" == "true" ]]; then
  if [[ "${REPLACE_EXISTING}" == "true" ]]; then
    echo "Dry-run command (replace existing template if present):"
    printf ' %q' gcloud compute instance-templates delete "${TEMPLATE_NAME}" --project "${PROJECT_ID}" --region "${REGION}" --quiet
    echo
  else
    echo "Dry-run note: template creation uses create-if-missing semantics."
  fi
  echo "Dry-run command:"
  printf ' %q' "${CMD[@]}"
  echo
  exit 0
fi

"${CMD[@]}"
echo "Template created: ${TEMPLATE_NAME}"
