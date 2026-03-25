#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID=""
POLICY_NAME="oc-daily-snapshots"
REGION="asia-southeast1"
ZONE="asia-southeast1-a"
START_HOUR_UTC="18"
MAX_RETENTION_DAYS="14"
ON_SOURCE_DISK_DELETE="KEEP_AUTO_SNAPSHOTS"
TARGET_DISK=""
TARGET_DISK_ZONE=""
DRY_RUN="false"
ZONE_WAS_SET="false"

print_help() {
  cat <<EOF
Usage: $(basename "$0") [options]

Create a standard snapshot schedule resource policy and optionally attach it to a disk.

Defaults:
  policy name:         ${POLICY_NAME}
  region:              ${REGION}
  zone:                ${ZONE}
  start hour (UTC):    ${START_HOUR_UTC}:00
  retention (days):    ${MAX_RETENTION_DAYS}
  on-source-disk-delete: ${ON_SOURCE_DISK_DELETE}

Options:
  --project-id <id>             GCP project ID (required)
  --policy-name <name>          Snapshot policy name (default: ${POLICY_NAME})
  --region <region>             Policy region (default: ${REGION})
  --zone <zone>                 Default zone for disk attachment (default: ${ZONE})
  --start-hour-utc <0-23>       UTC hour for daily schedule (default: ${START_HOUR_UTC})
  --max-retention-days <days>   Retention in days (default: ${MAX_RETENTION_DAYS})
  --on-source-disk-delete <mode>
                                KEEP_AUTO_SNAPSHOTS | APPLY_RETENTION_POLICY (default: ${ON_SOURCE_DISK_DELETE})
  --target-disk <name>          Attach policy to this disk after creation
  --target-disk-zone <zone>     Zone of target disk (default: --zone value)
  --dry-run                     Print gcloud commands only
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

validate_zone_region_pair() {
  local zone="$1"
  [[ "${zone}" == "${REGION}"-* ]] || die "zone must belong to --region (got zone=${zone}, region=${REGION})"
}

policy_exists() {
  gcloud compute resource-policies describe "${POLICY_NAME}" \
    --project "${PROJECT_ID}" \
    --region "${REGION}" \
    --format='value(name)' >/dev/null 2>&1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-id) PROJECT_ID="${2:-}"; shift 2 ;;
    --policy-name) POLICY_NAME="${2:-}"; shift 2 ;;
    --region) REGION="${2:-}"; shift 2 ;;
    --zone) ZONE="${2:-}"; ZONE_WAS_SET="true"; shift 2 ;;
    --start-hour-utc) START_HOUR_UTC="${2:-}"; shift 2 ;;
    --max-retention-days) MAX_RETENTION_DAYS="${2:-}"; shift 2 ;;
    --on-source-disk-delete) ON_SOURCE_DISK_DELETE="${2:-}"; shift 2 ;;
    --target-disk) TARGET_DISK="${2:-}"; shift 2 ;;
    --target-disk-zone) TARGET_DISK_ZONE="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN="true"; shift ;;
    -h|--help) print_help; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

[[ -n "${PROJECT_ID}" ]] || die "--project-id is required"
[[ "${START_HOUR_UTC}" =~ ^([0-9]|1[0-9]|2[0-3])$ ]] || die "--start-hour-utc must be 0..23"
[[ "${MAX_RETENTION_DAYS}" =~ ^[0-9]+$ ]] || die "--max-retention-days must be an integer"
if [[ "${ZONE_WAS_SET}" != "true" && "${REGION}" != "asia-southeast1" ]]; then
  ZONE="${REGION}-a"
fi
validate_zone_region_pair "${ZONE}"

if [[ -n "${TARGET_DISK}" ]]; then
  [[ -n "${TARGET_DISK_ZONE}" ]] || TARGET_DISK_ZONE="${ZONE}"
  validate_zone_region_pair "${TARGET_DISK_ZONE}"
fi

case "${ON_SOURCE_DISK_DELETE}" in
  KEEP_AUTO_SNAPSHOTS|APPLY_RETENTION_POLICY) ;;
  *) die "--on-source-disk-delete must be KEEP_AUTO_SNAPSHOTS or APPLY_RETENTION_POLICY" ;;
esac

if [[ "${DRY_RUN}" != "true" ]]; then
  require_command gcloud
fi

CREATE_CMD=(
  gcloud compute resource-policies create snapshot-schedule "${POLICY_NAME}"
  --project "${PROJECT_ID}"
  --region "${REGION}"
  --max-retention-days "${MAX_RETENTION_DAYS}"
  --on-source-disk-delete "${ON_SOURCE_DISK_DELETE}"
  --daily-schedule
  --start-time "${START_HOUR_UTC}:00"
)

echo "Snapshot schedule defaults:"
echo "  policy_name: ${POLICY_NAME}"
echo "  region: ${REGION}"
echo "  default_zone: ${ZONE}"
echo "  start_time_utc: ${START_HOUR_UTC}:00"
echo "  retention_days: ${MAX_RETENTION_DAYS}"
echo "  on_source_disk_delete: ${ON_SOURCE_DISK_DELETE}"
if [[ -n "${TARGET_DISK}" ]]; then
  echo "  target_disk: ${TARGET_DISK}"
  echo "  target_disk_zone: ${TARGET_DISK_ZONE}"
fi

if [[ "${DRY_RUN}" == "true" ]]; then
  echo "Dry-run note: policy creation uses create-if-missing semantics."
  echo "Dry-run command (create policy):"
  printf ' %q' "${CREATE_CMD[@]}"
  echo
else
  if policy_exists; then
    echo "Snapshot policy already exists; reusing: ${POLICY_NAME}"
  else
    "${CREATE_CMD[@]}"
  fi
fi

if [[ -n "${TARGET_DISK}" ]]; then
  ATTACH_CMD=(
    gcloud compute disks add-resource-policies "${TARGET_DISK}"
    --project "${PROJECT_ID}"
    --zone "${TARGET_DISK_ZONE}"
    --resource-policies "${POLICY_NAME}"
  )

  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "Dry-run command (attach policy):"
    printf ' %q' "${ATTACH_CMD[@]}"
    echo
  else
    "${ATTACH_CMD[@]}"
  fi
fi

echo "Snapshot policy flow complete."
