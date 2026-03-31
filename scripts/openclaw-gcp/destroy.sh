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
SNAPSHOT_POLICY_NAME=""
SNAPSHOT_POLICY_DISK=""
SNAPSHOT_POLICY_DISK_ZONE=""
MACHINE_IMAGE_NAME=""
CLONE_INSTANCE_NAME=""
CLONE_ZONE=""
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

Phase 2 optional extras (exact-name only when explicitly provided):
  - Snapshot policy (with optional disk context for future detach checks)
  - Clone instance
  - Machine image

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
  --snapshot-policy-name <name>
                            Optional snapshot policy to include in destroy flow
  --snapshot-policy-disk <name>
                            Optional disk context for snapshot policy handling
  --snapshot-policy-disk-zone <zone>
                            Zone for --snapshot-policy-disk (defaults to --zone)
  --clone-instance-name <name>
                            Optional clone instance to include in destroy flow
  --clone-zone <zone>      Zone for --clone-instance-name (defaults to --zone)
  --machine-image-name <name>
                            Optional machine image to include in destroy flow
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

has_explicit_extra_targets() {
  [[ -n "${SNAPSHOT_POLICY_NAME}" || -n "${CLONE_INSTANCE_NAME}" || -n "${MACHINE_IMAGE_NAME}" ]]
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
  if has_explicit_extra_targets; then
    echo "Phase 2 explicit extra targets:"
    [[ -n "${SNAPSHOT_POLICY_NAME}" ]] && echo "  snapshot_policy_name: ${SNAPSHOT_POLICY_NAME}"
    if [[ -n "${SNAPSHOT_POLICY_DISK}" ]]; then
      echo "  snapshot_policy_disk: ${SNAPSHOT_POLICY_DISK}"
      echo "  snapshot_policy_disk_zone: ${SNAPSHOT_POLICY_DISK_ZONE}"
    fi
    [[ -n "${CLONE_INSTANCE_NAME}" ]] && echo "  clone_instance_name: ${CLONE_INSTANCE_NAME}"
    [[ -n "${CLONE_INSTANCE_NAME}" ]] && echo "  clone_zone: ${CLONE_ZONE}"
    [[ -n "${MACHINE_IMAGE_NAME}" ]] && echo "  machine_image_name: ${MACHINE_IMAGE_NAME}"
    echo
    echo "Deterministic extra-resource order:"
    echo "  0) snapshot-policy: ${SNAPSHOT_POLICY_NAME:-not requested}"
    echo "  5) clone-instance: ${CLONE_INSTANCE_NAME:-not requested}"
    echo "  6) machine-image: ${MACHINE_IMAGE_NAME:-not requested}"
    echo
  fi
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
  local snapshot_policy_delete_cmd=(
    gcloud compute resource-policies delete "${SNAPSHOT_POLICY_NAME}"
    --project "${PROJECT_ID}"
    --region "${REGION}"
    --quiet
  )
  local clone_cmd=(
    gcloud compute instances delete "${CLONE_INSTANCE_NAME}"
    --project "${PROJECT_ID}"
    --zone "${CLONE_ZONE}"
    --quiet
  )
  local machine_image_cmd=(
    gcloud compute machine-images delete "${MACHINE_IMAGE_NAME}"
    --project "${PROJECT_ID}"
    --quiet
  )

  echo "Planned delete commands:"
  if [[ -n "${SNAPSHOT_POLICY_NAME}" && -n "${SNAPSHOT_POLICY_DISK}" ]]; then
    printf ' %q' \
      gcloud compute disks describe "${SNAPSHOT_POLICY_DISK}" \
      --project "${PROJECT_ID}" \
      --zone "${SNAPSHOT_POLICY_DISK_ZONE}" \
      --flatten='resourcePolicies[]' \
      --format='value(resourcePolicies.basename())'
    echo
    printf ' %q' \
      gcloud compute disks remove-resource-policies "${SNAPSHOT_POLICY_DISK}" \
      --project "${PROJECT_ID}" \
      --zone "${SNAPSHOT_POLICY_DISK_ZONE}" \
      --resource-policies "${SNAPSHOT_POLICY_NAME}"
    echo
  fi
  if [[ -n "${SNAPSHOT_POLICY_NAME}" ]]; then
    printf ' %q' "${snapshot_policy_delete_cmd[@]}"
    echo
  fi
  printf ' %q' "${instance_cmd[@]}"
  echo
  printf ' %q' "${template_cmd[@]}"
  echo
  printf ' %q' "${nat_cmd[@]}"
  echo
  printf ' %q' "${router_cmd[@]}"
  echo
  if [[ -n "${CLONE_INSTANCE_NAME}" ]]; then
    printf ' %q' \
      gcloud compute instances describe "${CLONE_INSTANCE_NAME}" \
      --project "${PROJECT_ID}" \
      --zone "${CLONE_ZONE}" \
      --flatten='disks[]' \
      --format='value(disks.boot,disks.autoDelete)'
    echo
    printf ' %q' "${clone_cmd[@]}"
    echo
  fi
  if [[ -n "${MACHINE_IMAGE_NAME}" ]]; then
    printf ' %q' \
      gcloud compute machine-images describe "${MACHINE_IMAGE_NAME}" \
      --project "${PROJECT_ID}" \
      --format='value(name)'
    echo
    printf ' %q' "${machine_image_cmd[@]}"
    echo
  fi
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
  local i=0
  local matched_index=-1
  local expected=""
  local required_keys=(
    "startup_script_source"
    "startup_profile"
    "startup_contract_version"
    "startup_ready_sentinel"
  )
  local required_values=(
    "${STARTUP_SOURCE_EXPECTED}"
    "${STARTUP_PROFILE_EXPECTED}"
    "${STARTUP_CONTRACT_VERSION_EXPECTED}"
    "${STARTUP_READY_SENTINEL_EXPECTED}"
  )
  local seen_flags=("false" "false" "false" "false")

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

    matched_index=-1
    i=0
    while (( i < ${#required_keys[@]} )); do
      if [[ "${required_keys[i]}" == "${key}" ]]; then
        matched_index="${i}"
        break
      fi
      i=$((i + 1))
    done

    if (( matched_index >= 0 )); then
      [[ -z "${rest}" ]] || fail_qualification \
        "template-startup-contract" \
        "ambiguous metadata row for ${key}: ${row}" \
        "ensure required metadata keys have a single exact value"
      if [[ "${seen_flags[matched_index]}" == "true" ]]; then
        fail_qualification \
          "template-startup-contract" \
          "duplicate metadata key detected: ${key}" \
          "remove duplicate startup metadata entries and retry"
      fi
      expected="${required_values[matched_index]}"
      [[ "${value}" == "${expected}" ]] || fail_qualification \
        "template-startup-contract" \
        "metadata mismatch for ${key} (expected=${expected}, actual=${value:-unset})" \
        "update template metadata to match the OpenClaw startup contract and retry"
      seen_flags[matched_index]="true"
    fi
  done <<<"${output}"

  i=0
  while (( i < ${#required_keys[@]} )); do
    [[ "${seen_flags[i]}" == "true" ]] || fail_qualification \
      "template-startup-contract" \
      "required metadata key missing: ${required_keys[i]}" \
      "recreate or repair template metadata with the required startup contract keys"
    i=$((i + 1))
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

qualify_snapshot_policy_attachment_gate() {
  local output=""
  local row=""
  local policy_name=""
  local rest=""
  local row_count=0
  local seen_names=""
  local matched="false"

  [[ -n "${SNAPSHOT_POLICY_NAME}" ]] || return 0
  [[ -n "${SNAPSHOT_POLICY_DISK}" ]] || return 0

  if ! output="$(
    gcloud compute disks describe "${SNAPSHOT_POLICY_DISK}" \
      --project "${PROJECT_ID}" \
      --zone "${SNAPSHOT_POLICY_DISK_ZONE}" \
      --flatten='resourcePolicies[]' \
      --format='value(resourcePolicies.basename())' 2>/dev/null
  )"; then
    fail_qualification \
      "snapshot-policy-attachment" \
      "unable to describe disk ${SNAPSHOT_POLICY_DISK} in ${SNAPSHOT_POLICY_DISK_ZONE}" \
      "verify snapshot disk name/zone/project and rerun"
  fi

  while IFS= read -r row; do
    row="$(trim_space "${row}")"
    [[ -n "${row}" ]] || continue
    row_count=$((row_count + 1))

    IFS=$'\t ' read -r policy_name rest <<<"${row}"
    [[ -n "${policy_name}" ]] || fail_qualification \
      "snapshot-policy-attachment" \
      "empty policy row from disk describe output" \
      "inspect resource policy attachment output and retry"
    [[ -z "${rest}" ]] || fail_qualification \
      "snapshot-policy-attachment" \
      "ambiguous policy row format: ${row}" \
      "inspect disk policy attachments and ensure the output is one policy name per row"

    if [[ "${seen_names}" == *$'\n'"${policy_name}"$'\n'* ]]; then
      fail_qualification \
        "snapshot-policy-attachment" \
        "duplicate policy row detected for ${policy_name}" \
        "inspect disk resource policy attachments and remove ambiguous duplicates"
    fi
    seen_names+=$'\n'"${policy_name}"$'\n'
    if [[ "${policy_name}" == "${SNAPSHOT_POLICY_NAME}" ]]; then
      matched="true"
    fi
  done <<<"${output}"

  (( row_count > 0 )) || fail_qualification \
    "snapshot-policy-attachment" \
    "disk describe output for resource policies is empty" \
    "confirm the policy is attached to the named disk or rerun without disk context for delete-only mode"

  [[ "${matched}" == "true" ]] || fail_qualification \
    "snapshot-policy-attachment" \
    "named policy ${SNAPSHOT_POLICY_NAME} is not attached to disk ${SNAPSHOT_POLICY_DISK}" \
    "attach the policy to the named disk or use the intended policy/disk pair and rerun"
}

run_phase1_qualification_checks() {
  echo "Running Phase 1 qualification checks..."
  ensure_gcloud_available
  qualify_instance_disk_gate
  qualify_template_metadata_gate
  qualify_router_network_gate
  qualify_nat_mode_gate
  qualify_snapshot_policy_attachment_gate
  echo "Qualification checks passed."
}

render_command_string() {
  local out=""
  local token=""
  for token in "$@"; do
    printf -v out '%s %q' "${out}" "${token}"
  done
  echo "${out# }"
}

run_delete_step() {
  local resource_label="$1"
  local retry_command="$2"
  shift 2
  local exit_code=0
  local index="${DELETE_STEP_INDEX}"

  printf 'Deleting %s...\n' "${resource_label}"
  if "$@"; then
    DELETE_STATUS[index]="succeeded"
    DELETE_DETAIL[index]="deleted successfully"
    DELETE_RETRY[index]="${retry_command}"
  else
    exit_code=$?
    DELETE_STATUS[index]="failed"
    DELETE_DETAIL[index]="delete command exited with status ${exit_code}"
    DELETE_RETRY[index]="${retry_command}"
    DELETE_ANY_FAILURE="true"
  fi
  DELETE_STEP_INDEX=$((DELETE_STEP_INDEX + 1))
}

execute_snapshot_policy_cleanup() {
  local detach_cmd=()
  local delete_cmd=()
  local index="${DELETE_STEP_INDEX}"
  local exit_code=0

  [[ -n "${SNAPSHOT_POLICY_NAME}" ]] || return 0

  delete_cmd=(
    gcloud compute resource-policies delete "${SNAPSHOT_POLICY_NAME}"
    --project "${PROJECT_ID}"
    --region "${REGION}"
    --quiet
  )
  detach_cmd=(
    gcloud compute disks remove-resource-policies "${SNAPSHOT_POLICY_DISK}"
    --project "${PROJECT_ID}"
    --zone "${SNAPSHOT_POLICY_DISK_ZONE}"
    --resource-policies "${SNAPSHOT_POLICY_NAME}"
  )

  printf 'Deleting %s...\n' "snapshot-policy:${SNAPSHOT_POLICY_NAME}"

  if [[ -n "${SNAPSHOT_POLICY_DISK}" ]]; then
    echo "Detaching snapshot policy ${SNAPSHOT_POLICY_NAME} from disk ${SNAPSHOT_POLICY_DISK}..."
    if "${detach_cmd[@]}"; then
      :
    else
      exit_code=$?
      DELETE_STATUS[index]="failed"
      DELETE_DETAIL[index]="detach command exited with status ${exit_code}"
      DELETE_RETRY[index]="$(render_command_string "${detach_cmd[@]}")"
      DELETE_ANY_FAILURE="true"
      DELETE_STEP_INDEX=$((DELETE_STEP_INDEX + 1))
      return
    fi
  fi

  if "${delete_cmd[@]}"; then
    DELETE_STATUS[index]="succeeded"
    DELETE_DETAIL[index]="deleted successfully"
    DELETE_RETRY[index]="$(render_command_string "${delete_cmd[@]}")"
  else
    exit_code=$?
    DELETE_STATUS[index]="failed"
    DELETE_DETAIL[index]="delete command exited with status ${exit_code}"
    DELETE_RETRY[index]="$(render_command_string "${delete_cmd[@]}")"
    DELETE_ANY_FAILURE="true"
  fi
  DELETE_STEP_INDEX=$((DELETE_STEP_INDEX + 1))
}

execute_clone_instance_cleanup() {
  local describe_cmd=()
  local delete_cmd=()
  local output=""
  local row_count=0
  local row=""
  local boot=""
  local auto_delete=""
  local rest=""
  local index="${DELETE_STEP_INDEX}"
  local exit_code=0

  [[ -n "${CLONE_INSTANCE_NAME}" ]] || return 0

  describe_cmd=(
    gcloud compute instances describe "${CLONE_INSTANCE_NAME}"
    --project "${PROJECT_ID}"
    --zone "${CLONE_ZONE}"
    --flatten='disks[]'
    --format='value(disks.boot,disks.autoDelete)'
  )
  delete_cmd=(
    gcloud compute instances delete "${CLONE_INSTANCE_NAME}"
    --project "${PROJECT_ID}"
    --zone "${CLONE_ZONE}"
    --quiet
  )

  printf 'Deleting %s...\n' "clone-instance:${CLONE_INSTANCE_NAME}"
  if ! output="$("${describe_cmd[@]}" 2>/dev/null)"; then
    DELETE_STATUS[index]="failed"
    DELETE_DETAIL[index]="unable to describe clone instance in ${CLONE_ZONE}"
    DELETE_RETRY[index]="$(render_command_string "${describe_cmd[@]}")"
    DELETE_ANY_FAILURE="true"
    DELETE_STEP_INDEX=$((DELETE_STEP_INDEX + 1))
    return
  fi

  while IFS= read -r row; do
    [[ -n "$(trim_space "${row}")" ]] || continue
    row_count=$((row_count + 1))
    if (( row_count > 1 )); then
      DELETE_STATUS[index]="failed"
      DELETE_DETAIL[index]="expected exactly one attached disk row, got ${row_count}"
      DELETE_RETRY[index]="$(render_command_string "${describe_cmd[@]}")"
      DELETE_ANY_FAILURE="true"
      DELETE_STEP_INDEX=$((DELETE_STEP_INDEX + 1))
      return
    fi
    IFS=$'\t ' read -r boot auto_delete rest <<<"${row}"
    if [[ -n "${rest}" ]]; then
      DELETE_STATUS[index]="failed"
      DELETE_DETAIL[index]="ambiguous attached disk row format"
      DELETE_RETRY[index]="$(render_command_string "${describe_cmd[@]}")"
      DELETE_ANY_FAILURE="true"
      DELETE_STEP_INDEX=$((DELETE_STEP_INDEX + 1))
      return
    fi
  done <<<"${output}"

  if (( row_count != 1 )); then
    DELETE_STATUS[index]="failed"
    DELETE_DETAIL[index]="expected exactly one attached disk row, got ${row_count}"
    DELETE_RETRY[index]="$(render_command_string "${describe_cmd[@]}")"
    DELETE_ANY_FAILURE="true"
    DELETE_STEP_INDEX=$((DELETE_STEP_INDEX + 1))
    return
  fi

  boot="$(normalize_lower "$(trim_space "${boot}")")"
  auto_delete="$(normalize_lower "$(trim_space "${auto_delete}")")"
  if [[ "${boot}" != "true" || "${auto_delete}" != "true" ]]; then
    DELETE_STATUS[index]="failed"
    DELETE_DETAIL[index]="disk predicate mismatch (boot=${boot:-unset}, autoDelete=${auto_delete:-unset})"
    DELETE_RETRY[index]="$(render_command_string "${describe_cmd[@]}")"
    DELETE_ANY_FAILURE="true"
    DELETE_STEP_INDEX=$((DELETE_STEP_INDEX + 1))
    return
  fi

  if "${delete_cmd[@]}"; then
    DELETE_STATUS[index]="succeeded"
    DELETE_DETAIL[index]="deleted successfully"
    DELETE_RETRY[index]="$(render_command_string "${delete_cmd[@]}")"
  else
    exit_code=$?
    DELETE_STATUS[index]="failed"
    DELETE_DETAIL[index]="delete command exited with status ${exit_code}"
    DELETE_RETRY[index]="$(render_command_string "${delete_cmd[@]}")"
    DELETE_ANY_FAILURE="true"
  fi
  DELETE_STEP_INDEX=$((DELETE_STEP_INDEX + 1))
}

execute_machine_image_cleanup() {
  local describe_cmd=()
  local delete_cmd=()
  local output=""
  local row=""
  local row_count=0
  local described_name=""
  local index="${DELETE_STEP_INDEX}"
  local exit_code=0

  [[ -n "${MACHINE_IMAGE_NAME}" ]] || return 0

  describe_cmd=(
    gcloud compute machine-images describe "${MACHINE_IMAGE_NAME}"
    --project "${PROJECT_ID}"
    --format='value(name)'
  )
  delete_cmd=(
    gcloud compute machine-images delete "${MACHINE_IMAGE_NAME}"
    --project "${PROJECT_ID}"
    --quiet
  )

  printf 'Deleting %s...\n' "machine-image:${MACHINE_IMAGE_NAME}"
  if ! output="$("${describe_cmd[@]}" 2>/dev/null)"; then
    DELETE_STATUS[index]="failed"
    DELETE_DETAIL[index]="unable to describe machine image ${MACHINE_IMAGE_NAME}"
    DELETE_RETRY[index]="$(render_command_string "${describe_cmd[@]}")"
    DELETE_ANY_FAILURE="true"
    DELETE_STEP_INDEX=$((DELETE_STEP_INDEX + 1))
    return
  fi

  while IFS= read -r row; do
    row="$(trim_space "${row}")"
    [[ -n "${row}" ]] || continue
    row_count=$((row_count + 1))
    described_name="${row}"
  done <<<"${output}"

  if (( row_count != 1 )) || [[ "${described_name}" != "${MACHINE_IMAGE_NAME}" ]]; then
    DELETE_STATUS[index]="failed"
    DELETE_DETAIL[index]="machine image describe output mismatch"
    DELETE_RETRY[index]="$(render_command_string "${describe_cmd[@]}")"
    DELETE_ANY_FAILURE="true"
    DELETE_STEP_INDEX=$((DELETE_STEP_INDEX + 1))
    return
  fi

  if "${delete_cmd[@]}"; then
    DELETE_STATUS[index]="succeeded"
    DELETE_DETAIL[index]="deleted successfully"
    DELETE_RETRY[index]="$(render_command_string "${delete_cmd[@]}")"
  else
    exit_code=$?
    DELETE_STATUS[index]="failed"
    DELETE_DETAIL[index]="delete command exited with status ${exit_code}"
    DELETE_RETRY[index]="$(render_command_string "${delete_cmd[@]}")"
    DELETE_ANY_FAILURE="true"
  fi
  DELETE_STEP_INDEX=$((DELETE_STEP_INDEX + 1))
}

execute_phase1_teardown() {
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

  echo
  echo "Starting Phase 1 teardown..."
  run_delete_step "instance:${INSTANCE_NAME}" "$(render_command_string "${instance_cmd[@]}")" "${instance_cmd[@]}"
  run_delete_step "template:${TEMPLATE_NAME}" "$(render_command_string "${template_cmd[@]}")" "${template_cmd[@]}"
  run_delete_step "nat:${NAT_NAME}" "$(render_command_string "${nat_cmd[@]}")" "${nat_cmd[@]}"
  run_delete_step "router:${ROUTER_NAME}" "$(render_command_string "${router_cmd[@]}")" "${router_cmd[@]}"
}

print_teardown_summary() {
  local i=0
  local failed_count=0

  echo
  if has_explicit_extra_targets; then
    echo "Teardown summary:"
  else
    echo "Phase 1 teardown summary:"
  fi
  while (( i < ${#DELETE_RESOURCE[@]} )); do
    echo "  - ${DELETE_RESOURCE[i]} => ${DELETE_STATUS[i]} (${DELETE_DETAIL[i]})"
    if [[ "${DELETE_STATUS[i]}" == "failed" ]]; then
      failed_count=$((failed_count + 1))
      echo "    manual cleanup hint: ${DELETE_RETRY[i]}"
    fi
    i=$((i + 1))
  done

  if (( failed_count > 0 )); then
    echo
    echo "Manual cleanup is required for ${failed_count} failed resource(s)."
  fi
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
    --snapshot-policy-name) require_option_value "$1" "${2-}"; SNAPSHOT_POLICY_NAME="${2}"; shift 2 ;;
    --snapshot-policy-disk) require_option_value "$1" "${2-}"; SNAPSHOT_POLICY_DISK="${2}"; shift 2 ;;
    --snapshot-policy-disk-zone) require_option_value "$1" "${2-}"; SNAPSHOT_POLICY_DISK_ZONE="${2}"; shift 2 ;;
    --clone-instance-name) require_option_value "$1" "${2-}"; CLONE_INSTANCE_NAME="${2}"; shift 2 ;;
    --clone-zone) require_option_value "$1" "${2-}"; CLONE_ZONE="${2}"; shift 2 ;;
    --machine-image-name) require_option_value "$1" "${2-}"; MACHINE_IMAGE_NAME="${2}"; shift 2 ;;
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
if [[ -n "${SNAPSHOT_POLICY_DISK}" && -z "${SNAPSHOT_POLICY_NAME}" ]]; then
  die "--snapshot-policy-disk requires --snapshot-policy-name"
fi
if [[ -n "${SNAPSHOT_POLICY_DISK_ZONE}" && -z "${SNAPSHOT_POLICY_DISK}" ]]; then
  die "--snapshot-policy-disk-zone requires --snapshot-policy-disk"
fi
if [[ -n "${SNAPSHOT_POLICY_DISK}" && -z "${SNAPSHOT_POLICY_DISK_ZONE}" ]]; then
  SNAPSHOT_POLICY_DISK_ZONE="${ZONE}"
fi
if [[ -n "${CLONE_ZONE}" && -z "${CLONE_INSTANCE_NAME}" ]]; then
  die "--clone-zone requires --clone-instance-name"
fi
if [[ -n "${CLONE_INSTANCE_NAME}" && -z "${CLONE_ZONE}" ]]; then
  CLONE_ZONE="${ZONE}"
fi
DELETE_RESOURCE=(
)
if [[ -n "${SNAPSHOT_POLICY_NAME}" ]]; then
  DELETE_RESOURCE+=("snapshot-policy:${SNAPSHOT_POLICY_NAME}")
fi
DELETE_RESOURCE+=(
  "instance:${INSTANCE_NAME}"
  "template:${TEMPLATE_NAME}"
  "nat:${NAT_NAME}"
  "router:${ROUTER_NAME}"
)
if [[ -n "${CLONE_INSTANCE_NAME}" ]]; then
  DELETE_RESOURCE+=("clone-instance:${CLONE_INSTANCE_NAME}")
fi
if [[ -n "${MACHINE_IMAGE_NAME}" ]]; then
  DELETE_RESOURCE+=("machine-image:${MACHINE_IMAGE_NAME}")
fi
DELETE_STATUS=()
DELETE_DETAIL=()
DELETE_RETRY=()
for _ in "${DELETE_RESOURCE[@]}"; do
  DELETE_STATUS+=("skipped")
  DELETE_DETAIL+=("not attempted")
  DELETE_RETRY+=("")
done
DELETE_ANY_FAILURE="false"
DELETE_STEP_INDEX=0

print_plan_summary
print_planned_commands

if [[ "${DRY_RUN}" == "true" ]]; then
  echo
  echo "Dry-run mode: no resources were modified."
  exit 0
fi

run_phase1_qualification_checks
require_typed_confirmation
execute_snapshot_policy_cleanup
execute_phase1_teardown
execute_clone_instance_cleanup
execute_machine_image_cleanup
print_teardown_summary

echo
if [[ "${DELETE_ANY_FAILURE}" == "true" ]]; then
  echo "Destroy completed with failures."
  exit 1
fi
echo "Destroy completed successfully."
