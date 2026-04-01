#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CREATE_INSTANCE_SCRIPT="${SCRIPT_DIR}/create-instance.sh"
REPAIR_BOOTSTRAP_SCRIPT="${SCRIPT_DIR}/repair-instance-bootstrap.sh"

PROJECT_ID=""
INSTANCE_NAME="oc-main"
TEMPLATE_NAME="oc-template"
REGION="asia-southeast1"
ZONE="asia-southeast1-a"
OPENCLAW_IMAGE="ghcr.io/openclawai/gateway"
OPENCLAW_TAG=""
NO_SERVICE_ACCOUNT="true"
SERVICE_ACCOUNT=""
SCOPES=""
NO_ADDRESS="true"
DRY_RUN="false"
NON_INTERACTIVE_MODE="auto"
IAP_SSH_SOURCE_RANGE="35.235.240.0/20"
ROUTER_NAME="oc-router"
NAT_NAME="oc-nat"
RESOURCE_LABELS=""
STARTUP_PROFILE_EXPECTED="vm-prereqs-v1"
STARTUP_SOURCE_EXPECTED="embedded-vm-prereqs-v1"
STARTUP_CONTRACT_VERSION_EXPECTED="startup-ready-v1"
STARTUP_READY_SENTINEL_EXPECTED="/var/lib/openclaw/startup-ready-v1"
READINESS_LOG_PATH="\$HOME/.openclaw-gcp/install-logs/readiness-gate.log"
READINESS_LOG_HINT_LINES="200"
INSTALL_LOG_DIR_REMOTE="\$HOME/.openclaw-gcp/install-logs"
INSTALL_LOG_LATEST_REMOTE="${INSTALL_LOG_DIR_REMOTE}/latest.log"
INSTALL_LOG_HINT_LINES="200"
UPSTREAM_INSTALL_CMD="curl -fsSL https://openclaw.ai/install.sh | bash"
READINESS_SSH_MAX_ATTEMPTS="${OPENCLAW_READINESS_SSH_MAX_ATTEMPTS:-19}"
READINESS_SSH_RETRY_DELAY_SECONDS="${OPENCLAW_READINESS_SSH_RETRY_DELAY_SECONDS:-10}"
INSTANCE_REUSED="false"

print_help() {
  cat <<EOF
Usage: $(basename "$0") [options]

Create or reuse an OpenClaw VM through the template-backed provisioning flow.

This command runs local preflight checks before provisioning:
  - gcloud is installed and runnable
  - active gcloud auth exists
  - project is resolved and describable
  - compute.googleapis.com is enabled
  - iap.googleapis.com is enabled
  - zone belongs to region and exists
  - at least one ingress firewall candidate allows TCP 22 from ${IAP_SSH_SOURCE_RANGE}

Options:
  --project-id <id>             GCP project ID (defaults from gcloud config when available)
  --instance-name <name>        VM instance name (default: ${INSTANCE_NAME})
  --template-name <name>        Instance template name (default: ${TEMPLATE_NAME})
  --region <region>             Region (default: ${REGION})
  --zone <zone>                 Zone (default: ${ZONE})
  --router-name <name>          Cloud Router name (default: ${ROUTER_NAME})
  --nat-name <name>             Cloud NAT name (default: ${NAT_NAME})
  --resource-labels <csv>       Labels applied to labelable resources in this provisioning path
  --openclaw-image <image>      Legacy template metadata image value (default: ${OPENCLAW_IMAGE})
  --openclaw-tag <tag>          Legacy template metadata tag value (required when provisioning a new VM)
  --service-account <email>     Service account for template-created VMs
  --scopes <csv>                OAuth scopes when using --service-account
  --no-service-account          Create template-created VMs without any attached service account (default)
  --allow-external-ip           Allow external IPv4 on newly created VMs (default is internal-only)
  --dry-run                     Print provisioning commands without mutating infrastructure
  --interactive                 Force interactive prompts for missing inputs
  --non-interactive             Disable prompts; require explicit flags
  -h, --help                    Show help
EOF
}

die() {
  echo "Error: $*" >&2
  exit 1
}

require_option_value() {
  local flag="$1"
  local value="${2-}"
  [[ -n "${value}" ]] && [[ "${value}" != --* ]] || die "missing value for ${flag}"
}

fail_preflight() {
  local problem="$1"
  local recovery="$2"
  echo "Preflight failed: ${problem}" >&2
  echo "Recovery: ${recovery}" >&2
  exit 1
}

fail_readiness() {
  local reason="$1"
  local remedy="$2"
  echo "Readiness gate failed: ${reason}" >&2
  echo "Remote readiness log: ${READINESS_LOG_PATH}" >&2
  echo "Next steps: ${remedy}" >&2
  echo "Log retrieval hint: gcloud compute ssh ${INSTANCE_NAME} --project ${PROJECT_ID} --zone ${ZONE} --tunnel-through-iap --command \"bash -lc 'tail -n ${READINESS_LOG_HINT_LINES} ${READINESS_LOG_PATH}'\"" >&2
  exit 1
}

fail_install_handoff() {
  local reason="$1"
  local remedy="$2"
  echo "Install handoff failed: ${reason}" >&2
  echo "Remote installer log hint: ${INSTALL_LOG_LATEST_REMOTE}" >&2
  echo "Next steps: ${remedy}" >&2
  echo "Log retrieval hint: gcloud compute ssh ${INSTANCE_NAME} --project ${PROJECT_ID} --zone ${ZONE} --tunnel-through-iap --command \"bash -lc 'tail -n ${INSTALL_LOG_HINT_LINES} ${INSTALL_LOG_LATEST_REMOTE}'\"" >&2
  exit 1
}

readiness_ssh_error_is_retryable() {
  local output="$1"
  [[ "${output}" == *"Failed to lookup instance"* ]] ||
    [[ "${output}" == *"Error during local connection to [stdin]"* ]]
}

validate_zone_region_pair() {
  [[ "${ZONE}" == "${REGION}"-* ]] || die "--zone must belong to --region (got zone=${ZONE}, region=${REGION})"
}

is_interactive_session() {
  [[ -t 0 && -t 1 ]]
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
    fail_preflight "missing required input ${var_name} in non-interactive mode" "pass the required flag explicitly (for example: --project-id, --openclaw-tag)"
  fi

  read -r -p "${prompt_text}" input_value
  [[ -n "${input_value}" ]] || fail_preflight "missing required input ${var_name}" "rerun and provide a non-empty value"
  printf -v "${var_name}" '%s' "${input_value}"
}

require_gcloud() {
  command -v gcloud >/dev/null 2>&1 || fail_preflight \
    "gcloud CLI is not installed or not on PATH" \
    "install Google Cloud CLI, then run: gcloud init"
  gcloud --version >/dev/null 2>&1 || fail_preflight \
    "gcloud exists but is not runnable" \
    "repair your gcloud installation, then run: gcloud init"
}

resolve_project_id() {
  if [[ -z "${PROJECT_ID}" ]]; then
    PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
    if [[ "${PROJECT_ID}" == "(unset)" ]]; then
      PROJECT_ID=""
    fi
  fi
  prompt_required PROJECT_ID "GCP project ID: " "${PROJECT_ID}"
}

check_active_auth() {
  local active_account
  active_account="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | head -n1 || true)"
  [[ -n "${active_account}" ]] || fail_preflight \
    "no active gcloud account was found" \
    "run: gcloud auth login"
}

check_project_access() {
  local described_project
  described_project="$(gcloud projects describe "${PROJECT_ID}" --format='value(projectId)' 2>/dev/null || true)"
  [[ "${described_project}" == "${PROJECT_ID}" ]] || fail_preflight \
    "project '${PROJECT_ID}' is missing or inaccessible" \
    "verify access and run: gcloud projects describe ${PROJECT_ID}"
}

check_api_enabled() {
  local service_name="$1"
  local service_value
  service_value="$(gcloud services list --project "${PROJECT_ID}" --enabled --filter="config.name=${service_name}" --format='value(config.name)' 2>/dev/null || true)"
  [[ "${service_value}" == "${service_name}" ]] || fail_preflight \
    "required API is not enabled: ${service_name}" \
    "run: gcloud services enable ${service_name} --project ${PROJECT_ID}"
}

check_zone_exists_and_matches_region() {
  local zone_region
  zone_region="$(gcloud compute zones describe "${ZONE}" --project "${PROJECT_ID}" --format='value(region.basename())' 2>/dev/null || true)"
  [[ -n "${zone_region}" ]] || fail_preflight \
    "zone '${ZONE}' is invalid or inaccessible in project '${PROJECT_ID}'" \
    "list zones with: gcloud compute zones list --project ${PROJECT_ID}"
  [[ "${zone_region}" == "${REGION}" ]] || fail_preflight \
    "zone '${ZONE}' belongs to region '${zone_region}', not '${REGION}'" \
    "pick a zone in '${REGION}' with: gcloud compute zones list --project ${PROJECT_ID} --filter=\"region:(${REGION})\""
}

has_iap_ssh_firewall_candidate() {
  local rule_name direction disabled source_ranges allowed_rules disabled_lower
  while IFS=$'\t' read -r rule_name direction disabled source_ranges allowed_rules; do
    [[ -n "${rule_name}" ]] || continue

    disabled_lower="${disabled,,}"
    [[ "${direction}" == "INGRESS" ]] || continue
    [[ "${disabled_lower}" != "true" ]] || continue
    [[ "${source_ranges}" == *"${IAP_SSH_SOURCE_RANGE}"* ]] || continue

    if [[ "${allowed_rules}" =~ (^|[[:space:],;])all($|[[:space:],;]) ]] || [[ "${allowed_rules}" =~ tcp:22($|[^0-9]) ]]; then
      return 0
    fi
  done < <(
    gcloud compute firewall-rules list \
      --project "${PROJECT_ID}" \
      --format='value(name,direction,disabled,sourceRanges.list(),allowed[].map().firewall_rule().list())' 2>/dev/null || true
  )
  return 1
}

check_iap_firewall_candidate() {
  has_iap_ssh_firewall_candidate || fail_preflight \
    "no ingress firewall rule allows TCP 22 from ${IAP_SSH_SOURCE_RANGE}" \
    "create/update a rule, for example: gcloud compute firewall-rules create allow-iap-ssh --project ${PROJECT_ID} --direction=INGRESS --action=ALLOW --rules=tcp:22 --source-ranges=${IAP_SSH_SOURCE_RANGE} --target-tags=<vm-tag>"
}

read_instance_zone() {
  gcloud compute instances list \
    --project "${PROJECT_ID}" \
    --filter="name=('${INSTANCE_NAME}')" \
    --format='value(zone.basename())' 2>/dev/null | head -n1 || true
}

read_instance_metadata_value() {
  local metadata_key="$1"
  gcloud compute instances describe "${INSTANCE_NAME}" \
    --project "${PROJECT_ID}" \
    --zone "${ZONE}" \
    --flatten='metadata.items[]' \
    --format='value(metadata.items.key,metadata.items.value)' 2>/dev/null |
    awk -F $'\t' -v metadata_key="${metadata_key}" '$1 == metadata_key { print $2; exit }' || true
}

check_existing_instance_eligibility() {
  local startup_source
  local startup_profile
  local startup_contract_version
  local startup_ready_sentinel
  local instance_zone

  instance_zone="$(read_instance_zone)"
  if [[ -n "${instance_zone}" ]] && [[ "${instance_zone}" != "${ZONE}" ]]; then
    fail_preflight \
      "instance '${INSTANCE_NAME}' already exists in zone '${instance_zone}', not requested zone '${ZONE}'" \
      "rerun with --zone ${instance_zone} or choose a different --instance-name"
  fi

  startup_source="$(read_instance_metadata_value startup_script_source)"
  startup_profile="$(read_instance_metadata_value startup_profile)"
  startup_contract_version="$(read_instance_metadata_value startup_contract_version)"
  startup_ready_sentinel="$(read_instance_metadata_value startup_ready_sentinel)"

  if [[ "${startup_profile}" == "custom-startup-script" ]] || [[ "${startup_source}" == file-sha256:* ]] || [[ "${startup_source}" == url-sha256:* ]]; then
    fail_preflight \
      "instance '${INSTANCE_NAME}' uses a custom startup contract that this installer will not auto-repair (${startup_profile:-unset} / ${startup_source:-unset})" \
      "use a different instance name or migrate this VM to startup_profile=${STARTUP_PROFILE_EXPECTED} with startup_script_source=${STARTUP_SOURCE_EXPECTED}"
  fi

  # Legacy built-in startup contracts are allowed to continue so the readiness
  # gate can repair them in-place. Only custom contracts are rejected here.
}

get_instance_contract_field() {
  local key="$1"
  read_instance_metadata_value "${key}"
}

instance_contract_matches_expected() {
  local startup_source
  local startup_profile
  local startup_contract_version
  local startup_ready_sentinel
  startup_source="$(get_instance_contract_field startup_script_source)"
  startup_profile="$(get_instance_contract_field startup_profile)"
  startup_contract_version="$(get_instance_contract_field startup_contract_version)"
  startup_ready_sentinel="$(get_instance_contract_field startup_ready_sentinel)"
  [[ "${startup_source}" == "${STARTUP_SOURCE_EXPECTED}" ]] &&
    [[ "${startup_profile}" == "${STARTUP_PROFILE_EXPECTED}" ]] &&
    [[ "${startup_contract_version}" == "${STARTUP_CONTRACT_VERSION_EXPECTED}" ]] &&
    [[ "${startup_ready_sentinel}" == "${STARTUP_READY_SENTINEL_EXPECTED}" ]]
}

instance_contract_is_repairable() {
  local startup_source
  local startup_profile
  startup_source="$(get_instance_contract_field startup_script_source)"
  startup_profile="$(get_instance_contract_field startup_profile)"
  [[ "${startup_profile}" != "custom-startup-script" ]] &&
    [[ "${startup_source}" != file-sha256:* ]] &&
    [[ "${startup_source}" != url-sha256:* ]]
}

build_repair_cmd() {
  REPAIR_CMD=(
    bash "${REPAIR_BOOTSTRAP_SCRIPT}"
    --project-id "${PROJECT_ID}"
    --instance-name "${INSTANCE_NAME}"
    --zone "${ZONE}"
    --run-now
  )
  if [[ -n "${OPENCLAW_TAG}" ]]; then
    REPAIR_CMD+=(--openclaw-tag "${OPENCLAW_TAG}")
  fi
  if [[ "${DRY_RUN}" == "true" ]]; then
    REPAIR_CMD+=(--dry-run)
  fi
}

maybe_auto_repair_contract() {
  if instance_contract_matches_expected; then
    return 0
  fi

  if ! instance_contract_is_repairable; then
    fail_readiness \
      "instance contract is legacy/unknown and not safe to auto-repair in place" \
      "choose a different instance name or migrate this VM manually with ${REPAIR_BOOTSTRAP_SCRIPT}"
  fi

  build_repair_cmd
  echo "Readiness gate: startup contract mismatch detected; attempting in-place repair."
  printf 'Repair command:'
  printf ' %q' "${REPAIR_CMD[@]}"
  echo
  "${REPAIR_CMD[@]}" || fail_readiness \
    "automatic startup contract repair failed" \
    "rerun the printed repair command manually, then retry install.sh"

  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "Dry-run: startup contract revalidation would run after repair."
    return 0
  fi

  instance_contract_matches_expected || fail_readiness \
    "startup contract still mismatched after repair" \
    "inspect metadata and rerun ${REPAIR_BOOTSTRAP_SCRIPT} before retrying install.sh"
}

build_readiness_ssh_cmd() {
  local readiness_check
  read -r -d '' readiness_check <<EOF || true
set -euo pipefail
LOG_PATH="${READINESS_LOG_PATH}"
SENTINEL_PATH="${STARTUP_READY_SENTINEL_EXPECTED}"
APT_LOCK_FILES=(
  /var/lib/dpkg/lock-frontend
  /var/lib/dpkg/lock
  /var/lib/apt/lists/lock
  /var/cache/apt/archives/lock
)
mkdir -p "\$(dirname "\${LOG_PATH}")"
{
  echo "[readiness] started_at_utc=\$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if [[ ! -f "\${SENTINEL_PATH}" ]]; then
    echo "[readiness] missing sentinel: \${SENTINEL_PATH}"
    exit 20
  fi
  LOCK_CHECK_CMD=(fuser)
  if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
    LOCK_CHECK_CMD=(sudo -n fuser)
  fi
  for lock_file in "\${APT_LOCK_FILES[@]}"; do
    if "\${LOCK_CHECK_CMD[@]}" "\${lock_file}" >/dev/null 2>&1; then
      echo "[readiness] package-manager lock still held: \${lock_file}"
      exit 21
    fi
  done
  echo "[readiness] sentinel present and no package-manager activity detected"
  echo "[readiness] status=ready"
} 2>&1 | tee -a "\${LOG_PATH}"
EOF

  READINESS_SSH_CMD=(
    gcloud compute ssh "${INSTANCE_NAME}"
    --project "${PROJECT_ID}"
    --zone "${ZONE}"
    --tunnel-through-iap
    --command "bash -lc $(printf '%q' "${readiness_check}")"
  )
}

run_readiness_probe() {
  local probe_output=""
  local exit_code=0
  local attempt=1

  build_readiness_ssh_cmd
  echo "Readiness gate: probing VM startup contract and host readiness."
  echo "Readiness log contract: ${READINESS_LOG_PATH}"
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "Dry-run command (readiness probe):"
    printf ' %q' "${READINESS_SSH_CMD[@]}"
    echo
    return 0
  fi

  while true; do
    set +e
    probe_output="$("${READINESS_SSH_CMD[@]}" 2>&1)"
    exit_code=$?
    set -e

    if [[ "${exit_code}" == "0" ]]; then
      [[ -n "${probe_output}" ]] && printf '%s\n' "${probe_output}"
      return 0
    fi

    if ! readiness_ssh_error_is_retryable "${probe_output}"; then
      [[ -n "${probe_output}" ]] && printf '%s\n' "${probe_output}" >&2
      fail_readiness \
        "remote readiness probe failed" \
        "wait for startup to finish and rerun install.sh; if needed rerun ${REPAIR_BOOTSTRAP_SCRIPT} --run-now"
    fi

    if (( attempt >= READINESS_SSH_MAX_ATTEMPTS )); then
      [[ -n "${probe_output}" ]] && printf '%s\n' "${probe_output}" >&2
      fail_readiness \
        "remote readiness probe did not become reachable via IAP before timeout" \
        "wait for IAP instance propagation to finish and rerun install.sh; if needed rerun ${REPAIR_BOOTSTRAP_SCRIPT} --run-now"
    fi

    echo "Readiness gate: instance not yet reachable through IAP SSH (attempt ${attempt}/${READINESS_SSH_MAX_ATTEMPTS}); retrying in ${READINESS_SSH_RETRY_DELAY_SECONDS}s."
    attempt=$((attempt + 1))
    sleep "${READINESS_SSH_RETRY_DELAY_SECONDS}"
  done
}

run_readiness_gate() {
  if [[ "${INSTANCE_REUSED}" == "true" ]]; then
    maybe_auto_repair_contract
  else
    echo "Readiness gate: target path is create/new; reuse-repair branch skipped."
  fi
  run_readiness_probe
  echo "Readiness gate passed."
}

build_install_handoff_ssh_cmd() {
  local remote_install_script
  read -r -d '' remote_install_script <<EOF || true
set -euo pipefail
LOG_DIR="${INSTALL_LOG_DIR_REMOTE}"
LATEST_LOG="${INSTALL_LOG_LATEST_REMOTE}"
INSTALLER_CMD="${UPSTREAM_INSTALL_CMD}"
umask 077
mkdir -m 700 -p "\${LOG_DIR}"
chmod 700 "\${LOG_DIR}"
RUN_LOG="\${LOG_DIR}/install-\$(date -u +%Y%m%dT%H%M%SZ).log"
touch "\${RUN_LOG}"
chmod 600 "\${RUN_LOG}"
echo "[handoff] launching upstream installer with PTY transcript capture"
echo "[handoff] run log: \${RUN_LOG}"
if ! command -v script >/dev/null 2>&1; then
  echo "[handoff] missing required 'script' command for PTY-preserving capture" >&2
  exit 42
fi
if script -qefc "\${INSTALLER_CMD}" "\${RUN_LOG}"; then
  ln -sfn "\${RUN_LOG}" "\${LATEST_LOG}"
  echo "[handoff] upstream installer completed successfully"
  echo "[handoff] latest log symlink: \${LATEST_LOG}"
  exec bash -il
fi
installer_rc=\$?
ln -sfn "\${RUN_LOG}" "\${LATEST_LOG}"
echo "[handoff] upstream installer exited with code \${installer_rc}" >&2
echo "[handoff] latest log symlink: \${LATEST_LOG}" >&2
exit "\${installer_rc}"
EOF

  INSTALL_HANDOFF_SSH_CMD=(
    gcloud compute ssh "${INSTANCE_NAME}"
    --project "${PROJECT_ID}"
    --zone "${ZONE}"
    --tunnel-through-iap
    --command "bash -lc $(printf '%q' "${remote_install_script}")"
    --
    -t
  )
}

run_install_handoff() {
  build_install_handoff_ssh_cmd
  echo "Interactive SSH handoff stage: launching upstream installer."
  echo "Handoff installer command: ${UPSTREAM_INSTALL_CMD}"
  echo "Remote installer log contract: ${INSTALL_LOG_LATEST_REMOTE}"

  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "Dry-run command (interactive SSH handoff):"
    printf ' %q' "${INSTALL_HANDOFF_SSH_CMD[@]}"
    echo
    return 0
  fi

  "${INSTALL_HANDOFF_SSH_CMD[@]}" || fail_install_handoff \
    "upstream installer exited non-zero or SSH handoff could not be completed" \
    "inspect the remote installer log, resolve the issue, and rerun install.sh"
}

run_preflight() {
  echo "Running local preflight checks..."
  require_gcloud
  resolve_project_id
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "Dry-run: skipping live auth/project/API/firewall validations."
    validate_zone_region_pair
    echo "Preflight checks passed."
    echo "Note: IAM effectiveness and guest-level reachability are validated in later readiness/SSH stages."
    return
  fi
  check_active_auth
  check_project_access
  check_api_enabled compute.googleapis.com
  check_api_enabled iap.googleapis.com
  validate_zone_region_pair
  check_zone_exists_and_matches_region
  check_iap_firewall_candidate
  echo "Preflight checks passed."
  echo "Note: IAM effectiveness and guest-level reachability are validated in later readiness/SSH stages."
}

build_create_instance_cmd() {
  CREATE_INSTANCE_CMD=(
    bash "${CREATE_INSTANCE_SCRIPT}"
    --project-id "${PROJECT_ID}"
    --instance-name "${INSTANCE_NAME}"
    --template-name "${TEMPLATE_NAME}"
    --region "${REGION}"
    --zone "${ZONE}"
    --router-name "${ROUTER_NAME}"
    --nat-name "${NAT_NAME}"
  )

  [[ -n "${OPENCLAW_IMAGE}" ]] && CREATE_INSTANCE_CMD+=(--openclaw-image "${OPENCLAW_IMAGE}")
  [[ -n "${OPENCLAW_TAG}" ]] && CREATE_INSTANCE_CMD+=(--openclaw-tag "${OPENCLAW_TAG}")
  [[ -n "${RESOURCE_LABELS}" ]] && CREATE_INSTANCE_CMD+=(--resource-labels "${RESOURCE_LABELS}")

  if [[ "${NO_SERVICE_ACCOUNT}" == "true" ]]; then
    CREATE_INSTANCE_CMD+=(--no-service-account)
  else
    [[ -n "${SERVICE_ACCOUNT}" ]] || fail_preflight "missing --service-account value" "pass --service-account <email> with --scopes <csv>, or use --no-service-account"
    [[ -n "${SCOPES}" ]] || fail_preflight "missing --scopes value" "pass --scopes <csv> with --service-account, or use --no-service-account"
    CREATE_INSTANCE_CMD+=(--service-account "${SERVICE_ACCOUNT}" --scopes "${SCOPES}")
  fi

  if [[ "${NO_ADDRESS}" == "true" ]]; then
    CREATE_INSTANCE_CMD+=(--no-address)
  fi

  if [[ "${DRY_RUN}" == "true" ]]; then
    CREATE_INSTANCE_CMD+=(--dry-run)
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-id) require_option_value "--project-id" "${2-}"; PROJECT_ID="$2"; shift 2 ;;
    --instance-name) require_option_value "--instance-name" "${2-}"; INSTANCE_NAME="$2"; shift 2 ;;
    --template-name) require_option_value "--template-name" "${2-}"; TEMPLATE_NAME="$2"; shift 2 ;;
    --region) require_option_value "--region" "${2-}"; REGION="$2"; shift 2 ;;
    --zone) require_option_value "--zone" "${2-}"; ZONE="$2"; shift 2 ;;
    --router-name) require_option_value "--router-name" "${2-}"; ROUTER_NAME="$2"; shift 2 ;;
    --nat-name) require_option_value "--nat-name" "${2-}"; NAT_NAME="$2"; shift 2 ;;
    --resource-labels) require_option_value "--resource-labels" "${2-}"; RESOURCE_LABELS="$2"; shift 2 ;;
    --openclaw-image) require_option_value "--openclaw-image" "${2-}"; OPENCLAW_IMAGE="$2"; shift 2 ;;
    --openclaw-tag) require_option_value "--openclaw-tag" "${2-}"; OPENCLAW_TAG="$2"; shift 2 ;;
    --service-account) require_option_value "--service-account" "${2-}"; SERVICE_ACCOUNT="$2"; NO_SERVICE_ACCOUNT="false"; shift 2 ;;
    --scopes) require_option_value "--scopes" "${2-}"; SCOPES="$2"; shift 2 ;;
    --no-service-account) NO_SERVICE_ACCOUNT="true"; SERVICE_ACCOUNT=""; SCOPES=""; shift ;;
    --allow-external-ip) NO_ADDRESS="false"; shift ;;
    --dry-run) DRY_RUN="true"; shift ;;
    --interactive) NON_INTERACTIVE_MODE="false"; shift ;;
    --non-interactive) NON_INTERACTIVE_MODE="true"; shift ;;
    -h|--help) print_help; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

[[ -n "${INSTANCE_NAME}" ]] || die "--instance-name cannot be empty"
[[ -n "${TEMPLATE_NAME}" ]] || die "--template-name cannot be empty"
[[ -f "${CREATE_INSTANCE_SCRIPT}" ]] || die "missing helper script: ${CREATE_INSTANCE_SCRIPT}"
[[ -f "${REPAIR_BOOTSTRAP_SCRIPT}" ]] || die "missing helper script: ${REPAIR_BOOTSTRAP_SCRIPT}"
validate_zone_region_pair

if [[ "${NON_INTERACTIVE_MODE}" == "auto" ]]; then
  if is_interactive_session; then
    INTERACTIVE_MODE="true"
  else
    INTERACTIVE_MODE="false"
  fi
elif [[ "${NON_INTERACTIVE_MODE}" == "false" ]]; then
  INTERACTIVE_MODE="true"
else
  INTERACTIVE_MODE="false"
fi

run_preflight

INSTANCE_DISCOVERED_ZONE="$(read_instance_zone)"
if [[ -n "${INSTANCE_DISCOVERED_ZONE}" ]]; then
  if [[ "${INSTANCE_DISCOVERED_ZONE}" != "${ZONE}" ]]; then
    fail_preflight \
      "instance '${INSTANCE_NAME}' already exists in zone '${INSTANCE_DISCOVERED_ZONE}', not requested zone '${ZONE}'" \
      "rerun with --zone ${INSTANCE_DISCOVERED_ZONE} or choose a different --instance-name"
  fi
  INSTANCE_REUSED="true"
  check_existing_instance_eligibility
  echo "Reusing existing instance: ${INSTANCE_NAME}"
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "Dry-run: instance exists; no provisioning command will be executed."
  fi
else
  if [[ -z "${OPENCLAW_TAG}" ]]; then
    if [[ "${DRY_RUN}" == "true" ]]; then
      OPENCLAW_TAG="dry-run-placeholder"
      echo "Dry-run: using placeholder --openclaw-tag ${OPENCLAW_TAG} for command rendering."
    else
      prompt_required OPENCLAW_TAG "OpenClaw tag for template metadata: " "${OPENCLAW_TAG}"
    fi
  fi

  build_create_instance_cmd
  echo "Provisioning instance through template-backed flow..."
  "${CREATE_INSTANCE_CMD[@]}"
fi

echo "Install preflight + provisioning stage complete."
run_readiness_gate
run_install_handoff
