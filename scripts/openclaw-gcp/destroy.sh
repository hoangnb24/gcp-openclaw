#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID=""
INSTANCE_NAME="oc-main"
TEMPLATE_NAME="oc-template"
REGION="asia-southeast1"
ZONE="asia-southeast1-a"
NETWORK="default"
ROUTER_NAME="oc-router"
NAT_NAME="oc-nat"
DRY_RUN="false"
ASSUME_YES="false"
NON_INTERACTIVE_MODE="auto"
INTERACTIVE_MODE="false"
CONFIRM_TOKEN="DESTROY"
STARTUP_SOURCE_EXPECTED="embedded-vm-prereqs-v1"
STARTUP_PROFILE_EXPECTED="vm-prereqs-v1"
STARTUP_CONTRACT_VERSION_EXPECTED="startup-ready-v1"
STARTUP_READY_SENTINEL_EXPECTED="/var/lib/openclaw/startup-ready-v1"

print_help() {
  cat <<EOF
Usage: $(basename "$0") [options]

Destroy the standard OpenClaw GCP deployment by exact resource names.

Phase 1 scope:
  - Compute instance
  - Instance template
  - Cloud NAT
  - Cloud Router

Safety contract:
  - Exact-name only (no broad discovery)
  - --dry-run prints plan and commands without mutating resources
  - Interactive real runs require a typed confirmation token

Options:
  --project-id <id>        GCP project ID (defaults from gcloud config when available)
  --instance-name <name>   Instance name (default: ${INSTANCE_NAME})
  --template-name <name>   Instance template name (default: ${TEMPLATE_NAME})
  --region <region>        Region for template/router/NAT (default: ${REGION})
  --zone <zone>            Zone for instance deletion (default: ${ZONE})
  --network <name>         VPC network expected for router ownership checks (default: ${NETWORK})
  --router-name <name>     Cloud Router name (default: ${ROUTER_NAME})
  --nat-name <name>        Cloud NAT name (default: ${NAT_NAME})
  --dry-run                Print planned delete actions without mutating infrastructure
  --yes                    Skip typed confirmation (for automation only)
  --interactive            Force interactive prompts when required
  --non-interactive        Disable prompts; require explicit inputs
  -h, --help               Show help
EOF
}

die() {
  echo "Error: $*" >&2
  exit 1
}

fail_qualification() {
  local predicate="$1"
  local detail="$2"
  local manual_guidance="$3"
  echo "Qualification failed [${predicate}]: ${detail}" >&2
  echo "Manual guidance: ${manual_guidance}" >&2
  exit 1
}

require_option_value() {
  local flag="$1"
  local value="${2-}"
  [[ -n "${value}" ]] && [[ "${value}" != --* ]] || die "missing value for ${flag}"
}

is_interactive_session() {
  [[ -t 0 && -t 1 ]]
}

resolve_interactive_mode() {
  case "${NON_INTERACTIVE_MODE}" in
    auto)
      if is_interactive_session; then
        INTERACTIVE_MODE="true"
      else
        INTERACTIVE_MODE="false"
      fi
      ;;
    true)
      INTERACTIVE_MODE="false"
      ;;
    false)
      INTERACTIVE_MODE="true"
      ;;
    *)
      die "invalid interactive mode toggle: ${NON_INTERACTIVE_MODE}"
      ;;
  esac
}

prompt_required() {
  local var_name="$1"
  local prompt_text="$2"
  local current_value="$3"
  local input_value=""

  if [[ -n "${current_value}" ]]; then
    printf -v "${var_name}" '%s' "${current_value}"
    return
  fi

  if [[ "${INTERACTIVE_MODE}" != "true" ]]; then
    die "missing required input ${var_name} in non-interactive mode"
  fi

  read -r -p "${prompt_text}" input_value
  [[ -n "${input_value}" ]] || die "missing required input ${var_name}"
  printf -v "${var_name}" '%s' "${input_value}"
}

resolve_project_id() {
  if [[ -z "${PROJECT_ID}" ]] && command -v gcloud >/dev/null 2>&1; then
    PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
    if [[ "${PROJECT_ID}" == "(unset)" ]]; then
      PROJECT_ID=""
    fi
  fi
  prompt_required PROJECT_ID "GCP project ID: " "${PROJECT_ID}"
}

validate_zone_region_pair() {
  [[ "${ZONE}" == "${REGION}"-* ]] || die "--zone must belong to --region (got zone=${ZONE}, region=${REGION})"
}

print_plan_summary() {
  echo "Destroy plan inputs:"
  echo "  project_id: ${PROJECT_ID}"
  echo "  instance_name: ${INSTANCE_NAME}"
  echo "  template_name: ${TEMPLATE_NAME}"
  echo "  region: ${REGION}"
  echo "  zone: ${ZONE}"
  echo "  network: ${NETWORK}"
  echo "  router_name: ${ROUTER_NAME}"
  echo "  nat_name: ${NAT_NAME}"
  echo "  dry_run: ${DRY_RUN}"
  echo "  assume_yes: ${ASSUME_YES}"
  echo "  interactive_mode: ${INTERACTIVE_MODE}"
  echo
  echo "Phase 1 target order:"
  echo "  1) instance: ${INSTANCE_NAME}"
  echo "  2) template: ${TEMPLATE_NAME}"
  echo "  3) nat: ${NAT_NAME}"
  echo "  4) router: ${ROUTER_NAME}"
}

print_planned_commands() {
  local instance_cmd=(
    gcloud compute instances delete "${INSTANCE_NAME}"
    --project "${PROJECT_ID}"
    --zone "${ZONE}"
    --quiet
  )
  local template_cmd=(
    gcloud compute instance-templates delete "${TEMPLATE_NAME}"
    --project "${PROJECT_ID}"
    --region "${REGION}"
    --quiet
  )
  local nat_cmd=(
    gcloud compute routers nats delete "${NAT_NAME}"
    --project "${PROJECT_ID}"
    --router "${ROUTER_NAME}"
    --region "${REGION}"
    --quiet
  )
  local router_cmd=(
    gcloud compute routers delete "${ROUTER_NAME}"
    --project "${PROJECT_ID}"
    --region "${REGION}"
    --quiet
  )

  echo "Planned delete commands:"
  printf ' %q' "${instance_cmd[@]}"
  echo
  printf ' %q' "${template_cmd[@]}"
  echo
  printf ' %q' "${nat_cmd[@]}"
  echo
  printf ' %q' "${router_cmd[@]}"
  echo
}

normalize_lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

trim_space() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

ensure_gcloud_available() {
  command -v gcloud >/dev/null 2>&1 || fail_qualification \
    "gcloud-availability" \
    "gcloud CLI is not installed or not on PATH" \
    "install Google Cloud CLI and authenticate, then rerun destroy.sh"
}

qualify_instance_disk_gate() {
  local output=""
  local row_count=0
  local row=""
  local boot=""
  local auto_delete=""
  local rest=""

  if ! output="$(
    gcloud compute instances describe "${INSTANCE_NAME}" \
      --project "${PROJECT_ID}" \
      --zone "${ZONE}" \
      --flatten='disks[]' \
      --format='value(disks.boot,disks.autoDelete)' 2>/dev/null
  )"; then
    fail_qualification \
      "instance-disk-safety" \
      "unable to describe instance ${INSTANCE_NAME} in ${ZONE}" \
      "verify instance name/zone/project and rerun after confirming instance access"
  fi

  while IFS= read -r row; do
    [[ -n "$(trim_space "${row}")" ]] || continue
    row_count=$((row_count + 1))
    if (( row_count > 1 )); then
      fail_qualification \
        "instance-disk-safety" \
        "expected exactly one attached disk row, got ${row_count}" \
        "ensure instance has only one attached disk and retry"
    fi
    IFS=$'\t ' read -r boot auto_delete rest <<<"${row}"
    [[ -z "${rest}" ]] || fail_qualification \
      "instance-disk-safety" \
      "ambiguous attached disk row format: ${row}" \
      "inspect instance disks and ensure describe output is a single boot/autoDelete row"
  done <<<"${output}"

  (( row_count == 1 )) || fail_qualification \
    "instance-disk-safety" \
    "expected exactly one attached disk row, got ${row_count}" \
    "ensure instance exists and has one attached boot disk with autoDelete enabled"

  boot="$(normalize_lower "$(trim_space "${boot}")")"
  auto_delete="$(normalize_lower "$(trim_space "${auto_delete}")")"
  [[ "${boot}" == "true" && "${auto_delete}" == "true" ]] || fail_qualification \
    "instance-disk-safety" \
    "disk predicate mismatch (boot=${boot:-unset}, autoDelete=${auto_delete:-unset})" \
    "set instance to one attached disk with boot=true and autoDelete=true before rerunning destroy"
}

qualify_template_metadata_gate() {
  local output=""
  local row=""
  local key=""
  local value=""
  local rest=""
  local expected=""
  declare -A required_pairs=(
    [startup_script_source]="${STARTUP_SOURCE_EXPECTED}"
    [startup_profile]="${STARTUP_PROFILE_EXPECTED}"
    [startup_contract_version]="${STARTUP_CONTRACT_VERSION_EXPECTED}"
    [startup_ready_sentinel]="${STARTUP_READY_SENTINEL_EXPECTED}"
  )
  declare -A seen_pairs=()

  if ! output="$(
    gcloud compute instance-templates describe "${TEMPLATE_NAME}" \
      --project "${PROJECT_ID}" \
      --region "${REGION}" \
      --flatten='properties.metadata.items[]' \
      --format='value(properties.metadata.items.key,properties.metadata.items.value)' 2>/dev/null
  )"; then
    fail_qualification \
      "template-startup-contract" \
      "unable to describe template ${TEMPLATE_NAME} in ${REGION}" \
      "verify template name/region/project and rerun"
  fi

  [[ -n "$(trim_space "${output}")" ]] || fail_qualification \
    "template-startup-contract" \
    "template metadata output is empty" \
    "verify template metadata includes the required startup contract keys"

  while IFS= read -r row; do
    [[ -n "$(trim_space "${row}")" ]] || continue
    IFS=$'\t' read -r key value rest <<<"${row}"
    [[ -n "${key}" ]] || continue

    if [[ -v "required_pairs[${key}]" ]]; then
      [[ -z "${rest}" ]] || fail_qualification \
        "template-startup-contract" \
        "ambiguous metadata row for ${key}: ${row}" \
        "ensure required metadata keys have a single exact value"
      if [[ -v "seen_pairs[${key}]" ]]; then
        fail_qualification \
          "template-startup-contract" \
          "duplicate metadata key detected: ${key}" \
          "remove duplicate startup metadata entries and retry"
      fi
      expected="${required_pairs[${key}]}"
      [[ "${value}" == "${expected}" ]] || fail_qualification \
        "template-startup-contract" \
        "metadata mismatch for ${key} (expected=${expected}, actual=${value:-unset})" \
        "update template metadata to match the OpenClaw startup contract and retry"
      seen_pairs["${key}"]="true"
    fi
  done <<<"${output}"

  for key in "${!required_pairs[@]}"; do
    [[ -v "seen_pairs[${key}]" ]] || fail_qualification \
      "template-startup-contract" \
      "required metadata key missing: ${key}" \
      "recreate or repair template metadata with the required startup contract keys"
  done
}

qualify_router_network_gate() {
  local output=""
  local row_count=0
  local row=""
  local router_network=""

  if ! output="$(
    gcloud compute routers describe "${ROUTER_NAME}" \
      --project "${PROJECT_ID}" \
      --region "${REGION}" \
      --format='value(network.basename())' 2>/dev/null
  )"; then
    fail_qualification \
      "router-network-ownership" \
      "unable to describe router ${ROUTER_NAME} in ${REGION}" \
      "verify router name/region/project and retry"
  fi

  while IFS= read -r row; do
    row="$(trim_space "${row}")"
    [[ -n "${row}" ]] || continue
    row_count=$((row_count + 1))
    router_network="${row}"
  done <<<"${output}"

  (( row_count == 1 )) || fail_qualification \
    "router-network-ownership" \
    "expected exactly one router network value, got ${row_count}" \
    "ensure router resolves to one network and rerun"

  [[ "${router_network}" == "${NETWORK}" ]] || fail_qualification \
    "router-network-ownership" \
    "router network mismatch (expected=${NETWORK}, actual=${router_network})" \
    "target the correct router/network pair or update --network for the intended stack"
}

qualify_nat_mode_gate() {
  local output=""
  local row_count=0
  local row=""
  local nat_ip_allocate_option=""
  local nat_source_ranges=""
  local rest=""

  if ! output="$(
    gcloud compute routers nats describe "${NAT_NAME}" \
      --project "${PROJECT_ID}" \
      --router "${ROUTER_NAME}" \
      --region "${REGION}" \
      --format='value(natIpAllocateOption,sourceSubnetworkIpRangesToNat)' 2>/dev/null
  )"; then
    fail_qualification \
      "nat-parent-and-mode" \
      "unable to describe NAT ${NAT_NAME} under router ${ROUTER_NAME} in ${REGION}" \
      "verify NAT name/router/region and rerun"
  fi

  while IFS= read -r row; do
    [[ -n "$(trim_space "${row}")" ]] || continue
    row_count=$((row_count + 1))
    (( row_count == 1 )) || fail_qualification \
      "nat-parent-and-mode" \
      "expected exactly one NAT mode row, got ${row_count}" \
      "ensure NAT describe output is singular and rerun"
    IFS=$'\t ' read -r nat_ip_allocate_option nat_source_ranges rest <<<"${row}"
    [[ -z "${rest}" ]] || fail_qualification \
      "nat-parent-and-mode" \
      "ambiguous NAT mode row format: ${row}" \
      "ensure NAT describe output includes only allocation mode and source range mode"
  done <<<"${output}"

  (( row_count == 1 )) || fail_qualification \
    "nat-parent-and-mode" \
    "expected exactly one NAT mode row, got ${row_count}" \
    "ensure NAT exists under the named router and retry"

  nat_ip_allocate_option="$(trim_space "${nat_ip_allocate_option}")"
  nat_source_ranges="$(trim_space "${nat_source_ranges}")"
  [[ "${nat_ip_allocate_option}" == "AUTO_ONLY" ]] || fail_qualification \
    "nat-parent-and-mode" \
    "natIpAllocateOption mismatch (expected=AUTO_ONLY, actual=${nat_ip_allocate_option:-unset})" \
    "set NAT to auto-allocate external IPs and rerun"
  [[ "${nat_source_ranges}" == "ALL_SUBNETWORKS_ALL_IP_RANGES" ]] || fail_qualification \
    "nat-parent-and-mode" \
    "sourceSubnetworkIpRangesToNat mismatch (expected=ALL_SUBNETWORKS_ALL_IP_RANGES, actual=${nat_source_ranges:-unset})" \
    "set NAT to all-subnet ranges mode and rerun"
}

run_phase1_qualification_checks() {
  echo "Running Phase 1 qualification checks..."
  ensure_gcloud_available
  qualify_instance_disk_gate
  qualify_template_metadata_gate
  qualify_router_network_gate
  qualify_nat_mode_gate
  echo "Qualification checks passed."
}

require_typed_confirmation() {
  local response=""
  local expected="${CONFIRM_TOKEN} ${PROJECT_ID}/${INSTANCE_NAME}"

  if [[ "${ASSUME_YES}" == "true" ]]; then
    echo "Confirmation bypassed with --yes."
    return
  fi

  if [[ "${INTERACTIVE_MODE}" != "true" ]]; then
    die "refusing destructive run in non-interactive mode without --yes"
  fi

  echo
  echo "Destructive action requested."
  echo "Type exactly: ${expected}"
  read -r -p "> " response
  [[ "${response}" == "${expected}" ]] || die "typed confirmation did not match; aborting"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-id) require_option_value "$1" "${2-}"; PROJECT_ID="${2}"; shift 2 ;;
    --instance-name) require_option_value "$1" "${2-}"; INSTANCE_NAME="${2}"; shift 2 ;;
    --template-name) require_option_value "$1" "${2-}"; TEMPLATE_NAME="${2}"; shift 2 ;;
    --region) require_option_value "$1" "${2-}"; REGION="${2}"; shift 2 ;;
    --zone) require_option_value "$1" "${2-}"; ZONE="${2}"; shift 2 ;;
    --network) require_option_value "$1" "${2-}"; NETWORK="${2}"; shift 2 ;;
    --router-name) require_option_value "$1" "${2-}"; ROUTER_NAME="${2}"; shift 2 ;;
    --nat-name) require_option_value "$1" "${2-}"; NAT_NAME="${2}"; shift 2 ;;
    --dry-run) DRY_RUN="true"; shift ;;
    --yes) ASSUME_YES="true"; shift ;;
    --interactive) NON_INTERACTIVE_MODE="false"; shift ;;
    --non-interactive) NON_INTERACTIVE_MODE="true"; shift ;;
    -h|--help) print_help; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

resolve_interactive_mode
resolve_project_id
validate_zone_region_pair

print_plan_summary
print_planned_commands

if [[ "${DRY_RUN}" == "true" ]]; then
  echo
  echo "Dry-run mode: no resources were modified."
  exit 0
fi

run_phase1_qualification_checks
require_typed_confirmation

echo
echo "Confirmation gate passed."
echo "Phase 1 scaffold complete: qualification and teardown execution are handled in subsequent stories."
