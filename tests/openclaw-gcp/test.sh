#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

TESTS_RUN=0
TESTS_FAILED=0
RUN_OUTPUT=""
RUN_STATUS=0

fail() {
  local message="$1"
  echo "not ok - ${message}"
  TESTS_FAILED=$((TESTS_FAILED + 1))
}

pass() {
  local message="$1"
  echo "ok - ${message}"
}

run_capture() {
  set +e
  RUN_OUTPUT="$("$@" 2>&1)"
  RUN_STATUS=$?
  set -e
}

assert_status() {
  local expected="$1"
  local message="$2"
  if [[ "${RUN_STATUS}" == "${expected}" ]]; then
    pass "${message}"
  else
    fail "${message} (expected status ${expected}, got ${RUN_STATUS})"
    printf '%s\n' "${RUN_OUTPUT}"
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"
  if [[ "${haystack}" == *"${needle}"* ]]; then
    pass "${message}"
  else
    fail "${message} (missing: ${needle})"
    printf '%s\n' "${haystack}"
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"
  if [[ "${haystack}" == *"${needle}"* ]]; then
    fail "${message} (unexpected: ${needle})"
    printf '%s\n' "${haystack}"
  else
    pass "${message}"
  fi
}

new_mock_env() {
  local name="$1"
  local dir="${TMP_DIR}/${name}"
  mkdir -p "${dir}/bin"
  cat >"${dir}/bin/gcloud" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
LOG_FILE="${MOCK_GCLOUD_LOG:?}"
METADATA_STATE_FILE="${MOCK_METADATA_STATE_FILE:-${LOG_FILE}.metadata}"
printf 'GCLOUD %s\n' "$*" >>"${LOG_FILE}"

metadata_default_value() {
  case "$1" in
    startup_script_source) printf '%s\n' "${MOCK_STARTUP_SCRIPT_SOURCE:-embedded-vm-prereqs-v1}" ;;
    startup_profile) printf '%s\n' "${MOCK_STARTUP_PROFILE:-vm-prereqs-v1}" ;;
    startup_contract_version) printf '%s\n' "${MOCK_STARTUP_CONTRACT_VERSION:-startup-ready-v1}" ;;
    startup_ready_sentinel) printf '%s\n' "${MOCK_STARTUP_READY_SENTINEL:-/var/lib/openclaw/startup-ready-v1}" ;;
    readiness_log_path) printf '%s\n' "${MOCK_READINESS_LOG_PATH:-/var/log/openclaw/readiness-gate.log}" ;;
    openclaw_image) printf '%s\n' "${MOCK_OPENCLAW_IMAGE:-ghcr.io/openclawai/gateway}" ;;
    openclaw_tag) printf '%s\n' "${MOCK_OPENCLAW_TAG:-2026.3.23}" ;;
    legacy_openclaw_image) printf '%s\n' "${MOCK_LEGACY_OPENCLAW_IMAGE:-}" ;;
    legacy_openclaw_tag) printf '%s\n' "${MOCK_LEGACY_OPENCLAW_TAG:-}" ;;
    *) printf '%s\n' "" ;;
  esac
}

metadata_current_value() {
  local key="$1"
  if [[ -f "${METADATA_STATE_FILE}" ]]; then
    local line
    line="$(awk -F '\t' -v key="${key}" '$1 == key { print $2; exit }' "${METADATA_STATE_FILE}")"
    if [[ -n "${line}" ]]; then
      printf '%s\n' "${line}"
      return
    fi
  fi
  metadata_default_value "${key}"
}

write_metadata_state() {
  local metadata_string="$1"
  : >"${METADATA_STATE_FILE}"
  local pair key value
  IFS=',' read -r -a metadata_pairs <<<"${metadata_string}"
  for pair in "${metadata_pairs[@]}"; do
    key="${pair%%=*}"
    value="${pair#*=}"
    printf '%s\t%s\n' "${key}" "${value}" >>"${METADATA_STATE_FILE}"
  done
}

if [[ "$*" == *"compute images describe-from-family"* ]]; then
  printf '%s\n' "${MOCK_IMAGE_NAME:-debian-12-bookworm-v20260310}"
  exit 0
fi

if [[ "$*" == *"config get-value project"* ]]; then
  printf '%s\n' "${MOCK_PROJECT_ID:-hoangnb-openclaw}"
  exit 0
fi

if [[ "$*" == *"auth list"* && "$*" == *"--filter=status:ACTIVE"* ]]; then
  printf '%s\n' "${MOCK_ACTIVE_ACCOUNT:-operator@example.com}"
  exit 0
fi

if [[ "$*" == *"projects describe"* && "$*" == *"--format=value(projectId)"* ]]; then
  for ((i=1; i <= $#; i++)); do
    if [[ "${!i}" == "describe" ]]; then
      next=$((i + 1))
      printf '%s\n' "${!next}"
      exit 0
    fi
  done
  printf '%s\n' "${MOCK_PROJECT_ID:-hoangnb-openclaw}"
  exit 0
fi

if [[ "$*" == *"services list"* && "$*" == *"config.name=compute.googleapis.com"* ]]; then
  printf '%s\n' "compute.googleapis.com"
  exit 0
fi

if [[ "$*" == *"services list"* && "$*" == *"config.name=iap.googleapis.com"* ]]; then
  printf '%s\n' "iap.googleapis.com"
  exit 0
fi

if [[ "$*" == *"compute zones describe"* && "$*" == *"--format=value(region.basename())"* ]]; then
  zone=""
  for ((i=1; i <= $#; i++)); do
    if [[ "${!i}" == "describe" ]]; then
      next=$((i + 1))
      zone="${!next}"
      break
    fi
  done
  if [[ -z "${zone}" ]]; then
    printf '%s\n' "${MOCK_ZONE_REGION:-asia-southeast1}"
    exit 0
  fi
  printf '%s\n' "${zone%-*}"
  exit 0
fi

if [[ "$*" == *"compute firewall-rules list"* ]]; then
  if [[ -n "${MOCK_FIREWALL_RULE_LINES:-}" ]]; then
    printf '%b\n' "${MOCK_FIREWALL_RULE_LINES}"
    exit 0
  fi
  printf '%b\n' "allow-iap-ssh\tINGRESS\tFalse\t35.235.240.0/20\ttcp:22"
  exit 0
fi

if [[ "$*" == *"compute ssh"* ]] && [[ "${MOCK_SSH_FAIL:-false}" == "true" ]]; then
  echo "mocked ssh failure" >&2
  exit 73
fi

if [[ "$*" == *"compute ssh"* ]] && [[ "${MOCK_SSH_FAIL_HANDOFF:-false}" == "true" ]] && [[ "$*" == *"openclaw.ai/install.sh"* ]]; then
  echo "mocked ssh failure" >&2
  exit 73
fi

if [[ "$*" == *"compute instances list"* && "$*" == *"--format=value(zone.basename())"* ]]; then
  if [[ -n "${MOCK_INSTANCE_EXISTING_ZONE:-}" ]]; then
    printf '%s\n' "${MOCK_INSTANCE_EXISTING_ZONE}"
    exit 0
  fi
  if [[ "${MOCK_INSTANCE_EXISTS:-false}" == "true" ]]; then
    printf '%s\n' "${MOCK_INSTANCE_ZONE:-asia-southeast1-a}"
    exit 0
  fi
  exit 0
fi

if [[ "$*" == *"compute images describe"* && "$*" == *"--format=value(name)"* ]]; then
  for arg in "$@"; do
    if [[ "${arg}" != --* && "${arg}" != "compute" && "${arg}" != "images" && "${arg}" != "describe" ]]; then
      printf '%s\n' "${arg}"
      exit 0
    fi
  done
fi

if [[ "$*" == *"compute images describe"* && "$*" == *"--format=value(selfLink)"* ]]; then
  image_name=""
  for arg in "$@"; do
    if [[ "${arg}" != --* && "${arg}" != "compute" && "${arg}" != "images" && "${arg}" != "describe" ]]; then
      image_name="${arg}"
      break
    fi
  done
  printf 'https://example.invalid/projects/mock/global/images/%s\n' "${image_name}"
  exit 0
fi

if [[ "$*" == *"compute instance-templates describe"* ]]; then
  if [[ "$*" == *"accessConfigs"* ]]; then
    if [[ "${MOCK_TEMPLATE_HAS_EXTERNAL_IP:-false}" == "true" ]]; then
      printf '%s\n' "External NAT"
      exit 0
    fi
    exit 0
  fi
  if [[ "${MOCK_TEMPLATE_EXISTS:-false}" == "true" ]]; then
    printf '%s\n' "${MOCK_TEMPLATE_NAME:-oc-template}"
    exit 0
  fi
  exit 1
fi

if [[ "$*" == *"compute instances describe"* && "$*" == *"--format=value(name)"* ]]; then
  if [[ "${MOCK_INSTANCE_EXISTS:-false}" == "true" ]]; then
    for ((i=1; i <= $#; i++)); do
      if [[ "${!i}" == "describe" ]]; then
        next=$((i + 1))
        printf '%s\n' "${!next}"
        exit 0
      fi
    done
    printf '%s\n' "${MOCK_INSTANCE_NAME:-oc-main}"
    exit 0
  fi
  exit 1
fi

if [[ "$*" == *"compute instances describe"* && "$*" == *"--flatten=metadata.items[]"* && "$*" == *"--format=value(metadata.items.key,metadata.items.value)"* ]]; then
  for metadata_key in \
    startup_script_source \
    startup_profile \
    startup_contract_version \
    startup_ready_sentinel \
    readiness_log_path \
    openclaw_image \
    openclaw_tag \
    legacy_openclaw_image \
    legacy_openclaw_tag; do
    printf '%s\t%s\n' "${metadata_key}" "$(metadata_current_value "${metadata_key}")"
  done
  exit 0
fi

if [[ "$*" == *"compute instances add-metadata"* ]]; then
  metadata_string=""
  for ((i=1; i <= $#; i++)); do
    if [[ "${!i}" == "--metadata" ]]; then
      next=$((i + 1))
      metadata_string="${!next}"
      break
    fi
  done
  if [[ -n "${metadata_string}" ]]; then
    write_metadata_state "${metadata_string}"
  fi
  printf 'Updated [%s]\n' "https://www.googleapis.com/compute/v1/projects/${MOCK_PROJECT_ID:-hoangnb-openclaw}/zones/${MOCK_INSTANCE_ZONE:-asia-southeast1-a}/instances/${MOCK_INSTANCE_NAME:-oc-main}"
  exit 0
fi

if [[ "$*" == *"compute resource-policies describe"* ]]; then
  if [[ "${MOCK_POLICY_EXISTS:-false}" == "true" ]]; then
    printf '%s\n' "${MOCK_POLICY_NAME:-oc-daily-snapshots}"
    exit 0
  fi
  exit 1
fi

if [[ "$*" == *"compute routers describe"* ]]; then
  if [[ "${MOCK_ROUTER_EXISTS:-false}" == "true" ]]; then
    printf '%s\n' "${MOCK_ROUTER_NAME:-oc-router}"
    exit 0
  fi
  exit 1
fi

if [[ "$*" == *"compute routers nats describe"* ]]; then
  if [[ "${MOCK_NAT_EXISTS:-false}" == "true" ]]; then
    printf '%s\n' "${MOCK_NAT_NAME:-oc-nat}"
    exit 0
  fi
  exit 1
fi

for arg in "$@"; do
  if [[ "${arg}" == startup-script=* ]]; then
    startup_path="${arg#startup-script=}"
    printf 'STARTUP_SCRIPT_BEGIN\n' >>"${LOG_FILE}"
    cat "${startup_path}" >>"${LOG_FILE}"
    printf '\nSTARTUP_SCRIPT_END\n' >>"${LOG_FILE}"
  fi
done
EOF
  chmod +x "${dir}/bin/gcloud"
  printf '%s\n' "${dir}"
}

run_with_mock() {
  local mock_dir="$1"
  shift
  local -a env_args=()
  while [[ $# -gt 0 && "$1" == *=* ]]; do
    env_args+=("$1")
    shift
  done
  env "${env_args[@]}" PATH="${mock_dir}/bin:${PATH}" MOCK_GCLOUD_LOG="${mock_dir}/gcloud.log" "$@"
}

test_create_template_command_and_startup_script() {
  local mock_dir
  mock_dir="$(new_mock_env template-create)"
  TESTS_RUN=$((TESTS_RUN + 1))

  run_capture run_with_mock "${mock_dir}" \
    bash "${ROOT_DIR}/scripts/openclaw-gcp/create-template.sh" \
    --project-id hoangnb-openclaw \
    --openclaw-tag v1.2.3 \
    --no-service-account \
    --no-address

  assert_status 0 "create-template succeeds with explicit no-service-account mode"
  assert_contains "${RUN_OUTPUT}" "identity_mode: no-service-account" "create-template reports explicit identity mode"
  assert_contains "${RUN_OUTPUT}" "external_ipv4: disabled" "create-template reports internal-only networking mode"

  local log_content
  log_content="$(cat "${mock_dir}/gcloud.log")"
  assert_contains "${log_content}" "--instance-template-region asia-southeast1" "create-template uses regional template flag"
  assert_contains "${log_content}" "--no-service-account" "create-template passes no-service-account to gcloud"
  assert_contains "${log_content}" "--no-scopes" "create-template disables scopes when no service account is attached"
  assert_contains "${log_content}" "--no-address" "create-template disables external IPv4 when requested"
  assert_contains "${RUN_OUTPUT}" "startup_script_source: embedded-vm-prereqs-v1" "create-template reports new startup script source"
  assert_contains "${RUN_OUTPUT}" "startup_profile: vm-prereqs-v1" "create-template reports startup profile"
  assert_contains "${RUN_OUTPUT}" "startup_contract_version: startup-ready-v1" "create-template reports startup contract version"
  assert_contains "${RUN_OUTPUT}" "startup_ready_sentinel: /var/lib/openclaw/startup-ready-v1" "create-template reports readiness sentinel"
  assert_contains "${log_content}" "startup_script_source=embedded-vm-prereqs-v1" "template metadata uses vm prereqs source contract"
  assert_contains "${log_content}" "startup_profile=vm-prereqs-v1" "template metadata records startup profile"
  assert_contains "${log_content}" "startup_contract_version=startup-ready-v1" "template metadata records startup contract version"
  assert_contains "${log_content}" "startup_ready_sentinel=/var/lib/openclaw/startup-ready-v1" "template metadata records readiness sentinel"
  assert_contains "${log_content}" "apt-get install -y ca-certificates curl" "embedded startup script installs only baseline VM prerequisites"
  assert_contains "${log_content}" "STARTUP_READY_SENTINEL=\"/var/lib/openclaw/startup-ready-v1\"" "embedded startup script defines the readiness sentinel"
  assert_contains "${log_content}" "cat >\"\${STARTUP_READY_SENTINEL}\"" "embedded startup script writes readiness sentinel"
  assert_not_contains "${log_content}" "docker.io" "embedded startup script does not install Docker"
  assert_not_contains "${log_content}" "docker compose" "embedded startup script does not invoke Docker Compose"
  assert_not_contains "${log_content}" "openclaw-docker-setup" "embedded startup script does not install OpenClaw wrappers"
  assert_not_contains "${log_content}" "git clone --depth 1 https://github.com/openclaw/openclaw.git" "embedded startup script does not clone OpenClaw repo"
}

test_create_instance_first_run_flow() {
  local mock_dir
  mock_dir="$(new_mock_env instance-first-run)"
  TESTS_RUN=$((TESTS_RUN + 1))

  run_capture run_with_mock "${mock_dir}" \
    bash "${ROOT_DIR}/scripts/openclaw-gcp/create-instance.sh" \
    --project-id hoangnb-openclaw \
    --instance-name oc-main \
    --openclaw-tag v1.2.3 \
    --no-service-account \
    --no-address

  assert_status 0 "create-instance can ensure template and create instance on first run"

  local log_content
  log_content="$(cat "${mock_dir}/gcloud.log")"
  assert_contains "${RUN_OUTPUT}" "Ensuring Cloud NAT exists for internal-only egress..." "create-instance auto-ensures Cloud NAT for internal-only templates"
  assert_contains "${log_content}" "GCLOUD compute instance-templates create oc-template" "create-instance ensured template creation"
  assert_contains "${log_content}" "GCLOUD compute routers create oc-router --project hoangnb-openclaw --region asia-southeast1 --network default" "create-instance ensures Cloud Router before internal-only instance creation"
  assert_contains "${log_content}" "GCLOUD compute routers nats create oc-nat --project hoangnb-openclaw --router oc-router --region asia-southeast1 --auto-allocate-nat-external-ips --nat-all-subnet-ip-ranges" "create-instance ensures Cloud NAT before internal-only instance creation"
  assert_contains "${log_content}" "GCLOUD compute instances create oc-main" "create-instance created the VM"
  assert_contains "${log_content}" "--source-instance-template projects/hoangnb-openclaw/regions/asia-southeast1/instanceTemplates/oc-template" "create-instance uses regional template resource path"
  assert_contains "${log_content}" "--no-address" "create-instance forwards internal-only networking when creating the template"
}

test_create_instance_existing_internal_template_auto_nat() {
  local mock_dir
  mock_dir="$(new_mock_env existing-internal-template)"
  TESTS_RUN=$((TESTS_RUN + 1))

  run_capture run_with_mock "${mock_dir}" MOCK_TEMPLATE_HAS_EXTERNAL_IP=false \
    bash "${ROOT_DIR}/scripts/openclaw-gcp/create-instance.sh" \
    --project-id hoangnb-openclaw \
    --instance-name oc-main \
    --no-create-template

  assert_status 0 "create-instance auto-ensures Cloud NAT when reusing an internal-only template"
  assert_contains "${RUN_OUTPUT}" "Ensuring Cloud NAT exists for internal-only egress..." "create-instance announces Cloud NAT auto-ensure for reused internal-only templates"

  local log_content
  log_content="$(cat "${mock_dir}/gcloud.log")"
  assert_contains "${log_content}" "GCLOUD compute instance-templates describe oc-template --project hoangnb-openclaw --region asia-southeast1 --format=value(properties.networkInterfaces[0].accessConfigs[0].name)" "create-instance inspects template networking when reusing a template"
  assert_contains "${log_content}" "GCLOUD compute routers create oc-router --project hoangnb-openclaw --region asia-southeast1 --network default" "create-instance auto-creates Cloud Router for reused internal-only template"
  assert_contains "${log_content}" "GCLOUD compute routers nats create oc-nat --project hoangnb-openclaw --router oc-router --region asia-southeast1 --auto-allocate-nat-external-ips --nat-all-subnet-ip-ranges" "create-instance auto-creates Cloud NAT for reused internal-only template"
}

test_template_reuse_rejects_explicit_drift_inputs() {
  local mock_dir
  mock_dir="$(new_mock_env template-reuse-drift)"
  TESTS_RUN=$((TESTS_RUN + 1))

  run_capture run_with_mock "${mock_dir}" MOCK_TEMPLATE_EXISTS=true \
    bash "${ROOT_DIR}/scripts/openclaw-gcp/create-template.sh" \
    --project-id hoangnb-openclaw \
    --machine-type e2-standard-4

  assert_status 1 "create-template rejects explicit template-shaping flags during reuse"
  assert_contains "${RUN_OUTPUT}" "would be ignored" "create-template explains drift rejection on reuse"
}

test_snapshot_policy_reuse_and_region_default_zone() {
  local mock_dir
  mock_dir="$(new_mock_env snapshot-reuse)"
  TESTS_RUN=$((TESTS_RUN + 1))

  run_capture run_with_mock "${mock_dir}" MOCK_POLICY_EXISTS=true \
    bash "${ROOT_DIR}/scripts/openclaw-gcp/create-snapshot-policy.sh" \
    --project-id hoangnb-openclaw \
    --region us-central1 \
    --target-disk oc-main

  assert_status 0 "create-snapshot-policy reuses existing policy and attaches disk"
  assert_contains "${RUN_OUTPUT}" "target_disk_zone: us-central1-a" "snapshot policy derives region-matching default attachment zone"

  local log_content
  log_content="$(cat "${mock_dir}/gcloud.log")"
  assert_contains "${log_content}" "GCLOUD compute disks add-resource-policies oc-main --project hoangnb-openclaw --zone us-central1-a --resource-policies oc-daily-snapshots" "snapshot attach uses derived us-central1-a zone"
}

test_docs_smoke_commands() {
  TESTS_RUN=$((TESTS_RUN + 1))

  run_capture bash "${ROOT_DIR}/scripts/openclaw-gcp/create-template.sh" \
    --project-id hoangnb-openclaw \
    --no-service-account \
    --no-address \
    --openclaw-tag vX.Y.Z \
    --dry-run
  assert_status 0 "README create-template example parses in dry-run mode"
  assert_contains "${RUN_OUTPUT}" "--no-service-account" "README create-template example keeps explicit identity choice"

  run_capture bash "${ROOT_DIR}/scripts/openclaw-gcp/create-instance.sh" \
    --project-id hoangnb-openclaw \
    --instance-name oc-main \
    --no-address \
    --no-create-template \
    --dry-run
  assert_status 0 "README create-instance example parses in dry-run mode"
  assert_contains "${RUN_OUTPUT}" "--source-instance-template" "README create-instance example emits instance-template source"

  run_capture bash "${ROOT_DIR}/scripts/openclaw-gcp/create-machine-image.sh" \
    --project-id hoangnb-openclaw \
    --source-instance oc-main \
    --source-zone asia-southeast1-a \
    --image-name oc-image-20260324-001 \
    --dry-run
  assert_status 0 "README machine-image capture example parses in dry-run mode"

  run_capture bash "${ROOT_DIR}/scripts/openclaw-gcp/spawn-from-image.sh" \
    --project-id hoangnb-openclaw \
    --instance-name oc-clone-a \
    --machine-image oc-image-20260324-001 \
    --zone us-central1-a \
    --dry-run
  assert_status 0 "README clone spawn example parses in dry-run mode"

  run_capture bash "${ROOT_DIR}/scripts/openclaw-gcp/create-snapshot-policy.sh" \
    --project-id hoangnb-openclaw \
    --policy-name oc-daily-snapshots \
    --region asia-southeast1 \
    --start-hour-utc 18 \
    --max-retention-days 14 \
    --dry-run
  assert_status 0 "backup runbook snapshot create example parses in dry-run mode"

  run_capture bash "${ROOT_DIR}/scripts/openclaw-gcp/create-snapshot-policy.sh" \
    --project-id hoangnb-openclaw \
    --policy-name oc-daily-snapshots \
    --region asia-southeast1 \
    --target-disk oc-main \
    --target-disk-zone asia-southeast1-a \
    --dry-run
  assert_status 0 "backup runbook snapshot attach example parses in dry-run mode"

  run_capture bash "${ROOT_DIR}/scripts/openclaw-gcp/create-cloud-nat.sh" \
    --project-id hoangnb-openclaw \
    --region asia-southeast1 \
    --dry-run
  assert_status 0 "README Cloud NAT example parses in dry-run mode"

  run_capture bash "${ROOT_DIR}/scripts/openclaw-gcp/repair-instance-bootstrap.sh" \
    --project-id hoangnb-openclaw \
    --instance-name oc-main \
    --openclaw-tag vX.Y.Z \
    --run-now \
    --dry-run
  assert_status 0 "repair-instance-bootstrap example parses in dry-run mode"
}

test_install_help_and_noninteractive_gcloud_guard() {
  TESTS_RUN=$((TESTS_RUN + 1))

  run_capture bash "${ROOT_DIR}/scripts/openclaw-gcp/install.sh" --help
  assert_status 0 "install.sh --help renders usage"
  assert_contains "${RUN_OUTPUT}" "Create or reuse an OpenClaw VM through the template-backed provisioning flow." "install.sh help describes primary flow"

  run_capture bash -c "env PATH=\"/usr/bin:/bin\" bash \"${ROOT_DIR}/scripts/openclaw-gcp/install.sh\" --project-id test-project --instance-name test-vm --zone asia-southeast1-a </dev/null"
  assert_status 1 "install.sh fails before provisioning when gcloud is missing"
  assert_contains "${RUN_OUTPUT}" "Preflight failed: gcloud CLI is not installed or not on PATH" "install.sh reports missing gcloud preflight failure"
  assert_contains "${RUN_OUTPUT}" "Recovery: install Google Cloud CLI, then run: gcloud init" "install.sh prints exact gcloud recovery command"
  assert_not_contains "${RUN_OUTPUT}" "Provisioning instance through template-backed flow..." "install.sh does not reach provisioning after preflight failure"
}

test_install_parser_missing_value_guard() {
  TESTS_RUN=$((TESTS_RUN + 1))

  run_capture bash "${ROOT_DIR}/scripts/openclaw-gcp/install.sh" --project-id
  assert_status 1 "install.sh rejects missing values for value-taking flags"
  assert_contains "${RUN_OUTPUT}" "Error: missing value for --project-id" "install.sh reports a controlled missing-value parser error"
  assert_not_contains "${RUN_OUTPUT}" "shift count out of range" "install.sh avoids raw shell shift failures for missing option values"
}

test_install_prompt_and_nonprompt_behavior() {
  local mock_dir
  mock_dir="$(new_mock_env install-prompt-nonprompt)"
  TESTS_RUN=$((TESTS_RUN + 1))

  run_capture run_with_mock "${mock_dir}" MOCK_PROJECT_ID="(unset)" \
    bash "${ROOT_DIR}/scripts/openclaw-gcp/install.sh" \
    --instance-name oc-main \
    --zone asia-southeast1-a \
    --non-interactive \
    --dry-run

  assert_status 1 "install.sh non-interactive mode rejects missing required project input"
  assert_contains "${RUN_OUTPUT}" "missing required input PROJECT_ID in non-interactive mode" "install.sh explains non-interactive missing input failure"

  run_capture bash -c "printf 'hoangnb-openclaw\n' | env PATH=\"${mock_dir}/bin:\${PATH}\" MOCK_GCLOUD_LOG=\"${mock_dir}/gcloud.log\" MOCK_PROJECT_ID=\"(unset)\" MOCK_INSTANCE_EXISTS=true bash \"${ROOT_DIR}/scripts/openclaw-gcp/install.sh\" --interactive --instance-name oc-main --zone asia-southeast1-a --dry-run"

  assert_status 0 "install.sh interactive mode prompts and accepts missing project input"
  assert_contains "${RUN_OUTPUT}" "Preflight checks passed." "install.sh interactive prompt path completes preflight"
}

test_install_readiness_gate_dry_run_contract() {
  local mock_dir
  mock_dir="$(new_mock_env install-readiness-dry-run)"
  TESTS_RUN=$((TESTS_RUN + 1))

  run_capture run_with_mock "${mock_dir}" MOCK_INSTANCE_EXISTS=true \
    bash "${ROOT_DIR}/scripts/openclaw-gcp/install.sh" \
    --project-id hoangnb-openclaw \
    --instance-name oc-main \
    --zone asia-southeast1-a \
    --dry-run

  assert_status 0 "install.sh dry-run prints readiness gate contract before SSH handoff"
  assert_contains "${RUN_OUTPUT}" "Readiness gate: probing VM startup contract and host readiness." "install.sh dry-run announces readiness stage"
  assert_contains "${RUN_OUTPUT}" "Readiness log contract: \$HOME/.openclaw-gcp/install-logs/readiness-gate.log" "install.sh dry-run prints readiness log path contract"
  assert_not_contains "${RUN_OUTPUT}" "/var/log/openclaw/readiness-gate.log" "install.sh readiness contract avoids root-owned log path"
  assert_contains "${RUN_OUTPUT}" "Dry-run command (readiness probe):" "install.sh dry-run prints readiness probe command"
  assert_contains "${RUN_OUTPUT}" "fuser" "install.sh readiness probe uses lock-based package-manager detection"
  assert_contains "${RUN_OUTPUT}" "/var/lib/dpkg/lock-frontend" "install.sh readiness probe checks dpkg lock files"
  assert_not_contains "${RUN_OUTPUT}" "pgrep\\ -f\\ \"apt-get\\|apt.systemd.daily\\|unattended-upgrade\\|dpkg\"" "install.sh readiness probe no longer uses broad process-name matching"
}

test_install_firewall_preflight_predicate() {
  local mock_dir
  mock_dir="$(new_mock_env install-firewall-predicate)"
  TESTS_RUN=$((TESTS_RUN + 1))

  run_capture run_with_mock "${mock_dir}" \
    MOCK_INSTANCE_EXISTS=true \
    MOCK_FIREWALL_RULE_LINES=$'allow-http\tINGRESS\tFalse\t35.235.240.0/20\ttcp:80' \
    bash "${ROOT_DIR}/scripts/openclaw-gcp/install.sh" \
    --project-id hoangnb-openclaw \
    --instance-name oc-main \
    --zone asia-southeast1-a

  assert_status 1 "install.sh rejects firewall false-positive rules that do not allow SSH"
  assert_contains "${RUN_OUTPUT}" "no ingress firewall rule allows TCP 22 from 35.235.240.0/20" "install.sh reports missing SSH/IAP ingress when only tcp:80 rule exists"

  run_capture run_with_mock "${mock_dir}" \
    MOCK_INSTANCE_EXISTS=true \
    MOCK_FIREWALL_RULE_LINES=$'allow-http\tINGRESS\tFalse\t35.235.240.0/20\ttcp:80\nallow-iap-ssh\tINGRESS\tFalse\t35.235.240.0/20\ttcp:22' \
    bash "${ROOT_DIR}/scripts/openclaw-gcp/install.sh" \
    --project-id hoangnb-openclaw \
    --instance-name oc-main \
    --zone asia-southeast1-a

  assert_status 0 "install.sh accepts a valid SSH/IAP firewall rule"
  assert_contains "${RUN_OUTPUT}" "Preflight checks passed." "install.sh preflight proceeds when a valid rule is present"
  assert_contains "${RUN_OUTPUT}" "Readiness gate passed." "install.sh continues past preflight after matching a valid rule"
}

test_install_cross_zone_existing_instance_guard() {
  local mock_dir
  mock_dir="$(new_mock_env install-cross-zone-existing)"
  TESTS_RUN=$((TESTS_RUN + 1))

  run_capture run_with_mock "${mock_dir}" \
    MOCK_INSTANCE_EXISTING_ZONE=asia-southeast1-b \
    bash "${ROOT_DIR}/scripts/openclaw-gcp/install.sh" \
    --project-id hoangnb-openclaw \
    --instance-name oc-main \
    --zone asia-southeast1-a \
    --dry-run

  assert_status 1 "install.sh fails fast when instance exists in a different zone"
  assert_contains "${RUN_OUTPUT}" "instance 'oc-main' already exists in zone 'asia-southeast1-b', not requested zone 'asia-southeast1-a'" "install.sh reports cross-zone mismatch before provisioning"
  assert_not_contains "${RUN_OUTPUT}" "Provisioning instance through template-backed flow..." "install.sh does not enter create path for cross-zone existing instance"

  local log_content
  log_content="$(cat "${mock_dir}/gcloud.log")"
  assert_not_contains "${log_content}" "GCLOUD compute instances create oc-main" "install.sh does not emit create command for cross-zone existing instance"
}

test_install_reuse_eligibility_guardrails() {
  local mock_dir
  mock_dir="$(new_mock_env install-reuse-eligibility)"
  TESTS_RUN=$((TESTS_RUN + 1))

  run_capture run_with_mock "${mock_dir}" \
    MOCK_INSTANCE_EXISTS=true \
    MOCK_STARTUP_PROFILE=custom-startup-script \
    MOCK_STARTUP_SCRIPT_SOURCE=file-sha256:deadbeef \
    bash "${ROOT_DIR}/scripts/openclaw-gcp/install.sh" \
    --project-id hoangnb-openclaw \
    --instance-name oc-main \
    --zone asia-southeast1-a

  assert_status 1 "install.sh rejects reused instances with custom startup contracts"
  assert_contains "${RUN_OUTPUT}" "uses a custom startup contract that this installer will not auto-repair" "install.sh explains custom-contract rejection"
  assert_not_contains "${RUN_OUTPUT}" "Interactive SSH handoff stage: launching upstream installer." "install.sh stops before SSH handoff when reuse eligibility fails"
}

test_install_repairable_reuse_contract_auto_repairs() {
  local mock_dir
  mock_dir="$(new_mock_env install-repairable-reuse)"
  TESTS_RUN=$((TESTS_RUN + 1))

  run_capture run_with_mock "${mock_dir}" \
    MOCK_INSTANCE_EXISTS=true \
    MOCK_STARTUP_PROFILE=legacy-bootstrap-v10 \
    MOCK_STARTUP_SCRIPT_SOURCE=embedded-openclaw-bootstrap-v10 \
    MOCK_STARTUP_CONTRACT_VERSION=legacy-bootstrap-v10 \
    MOCK_STARTUP_READY_SENTINEL=/var/lib/openclaw/legacy-ready-v10 \
    bash "${ROOT_DIR}/scripts/openclaw-gcp/install.sh" \
    --project-id hoangnb-openclaw \
    --instance-name oc-main \
    --zone asia-southeast1-a

  assert_status 0 "install.sh auto-repairs legacy startup contracts for reused instances"
  assert_contains "${RUN_OUTPUT}" "Readiness gate: startup contract mismatch detected; attempting in-place repair." "install.sh announces in-place repair for repairable reuse contracts"
  assert_contains "${RUN_OUTPUT}" "Readiness gate passed." "install.sh revalidates successfully after repair"
  assert_contains "${RUN_OUTPUT}" "Interactive SSH handoff stage: launching upstream installer." "install.sh continues to the SSH handoff after successful repair"

  local log_content
  log_content="$(cat "${mock_dir}/gcloud.log")"
  assert_contains "${log_content}" "GCLOUD compute instances add-metadata oc-main --project hoangnb-openclaw --zone asia-southeast1-a" "install.sh repair path updates instance metadata before revalidation"
}

test_install_ssh_handoff_contract_and_failure_summary() {
  local mock_dir
  mock_dir="$(new_mock_env install-ssh-handoff)"
  TESTS_RUN=$((TESTS_RUN + 1))

  run_capture run_with_mock "${mock_dir}" MOCK_INSTANCE_EXISTS=true \
    bash "${ROOT_DIR}/scripts/openclaw-gcp/install.sh" \
    --project-id hoangnb-openclaw \
    --instance-name oc-main \
    --zone asia-southeast1-a \
    --dry-run

  assert_status 0 "install.sh dry-run prints interactive SSH handoff command contract"
  assert_contains "${RUN_OUTPUT}" "Dry-run command (interactive SSH handoff):" "install.sh dry-run prints handoff command"
  assert_contains "${RUN_OUTPUT}" "--tunnel-through-iap" "install.sh handoff command preserves IAP SSH posture"
  assert_contains "${RUN_OUTPUT}" "curl -fsSL https://openclaw.ai/install.sh | bash" "install.sh handoff command includes upstream installer"
  assert_contains "${RUN_OUTPUT}" "umask\\ 077" "install.sh handoff command hardens transcript umask"
  assert_contains "${RUN_OUTPUT}" "mkdir\\ -m\\ 700\\ -p" "install.sh handoff command creates transcript directory with private permissions"
  assert_contains "${RUN_OUTPUT}" "chmod\\ 600\\ " "install.sh handoff command hardens transcript file permissions"
  assert_contains "${RUN_OUTPUT}" " -- -t" "install.sh handoff command requests interactive TTY"

  run_capture run_with_mock "${mock_dir}" MOCK_INSTANCE_EXISTS=true MOCK_SSH_FAIL_HANDOFF=true \
    bash "${ROOT_DIR}/scripts/openclaw-gcp/install.sh" \
    --project-id hoangnb-openclaw \
    --instance-name oc-main \
    --zone asia-southeast1-a

  assert_status 1 "install.sh prints local failure summary when SSH handoff fails"
  assert_contains "${RUN_OUTPUT}" "Install handoff failed: upstream installer exited non-zero or SSH handoff could not be completed" "install.sh prints install handoff failure summary"
  assert_contains "${RUN_OUTPUT}" "Remote installer log hint: \$HOME/.openclaw-gcp/install-logs/latest.log" "install.sh prints remote installer log hint on failure"
}

test_cloud_nat_idempotent_flow() {
  local mock_dir
  mock_dir="$(new_mock_env cloud-nat)"
  TESTS_RUN=$((TESTS_RUN + 1))

  run_capture run_with_mock "${mock_dir}" MOCK_ROUTER_EXISTS=true MOCK_NAT_EXISTS=true \
    bash "${ROOT_DIR}/scripts/openclaw-gcp/create-cloud-nat.sh" \
    --project-id hoangnb-openclaw \
    --region asia-southeast1

  assert_status 0 "create-cloud-nat reuses existing router and NAT"
  assert_contains "${RUN_OUTPUT}" "Cloud Router already exists; reusing: oc-router" "create-cloud-nat reports router reuse"
  assert_contains "${RUN_OUTPUT}" "Cloud NAT already exists; reusing: oc-nat" "create-cloud-nat reports NAT reuse"
}

test_repair_instance_bootstrap_flow() {
  local mock_dir
  mock_dir="$(new_mock_env repair-bootstrap)"
  TESTS_RUN=$((TESTS_RUN + 1))

  run_capture run_with_mock "${mock_dir}" \
    bash "${ROOT_DIR}/scripts/openclaw-gcp/repair-instance-bootstrap.sh" \
    --project-id hoangnb-openclaw \
    --instance-name oc-main \
    --zone asia-southeast1-a \
    --openclaw-tag 2026.3.23 \
    --run-now

  assert_status 0 "repair-instance-bootstrap updates metadata and reruns startup"

  local log_content
  log_content="$(cat "${mock_dir}/gcloud.log")"
  assert_contains "${log_content}" "GCLOUD compute instances add-metadata oc-main --project hoangnb-openclaw --zone asia-southeast1-a" "repair-instance-bootstrap updates instance metadata"
  assert_contains "${log_content}" "startup_script_source=embedded-vm-prereqs-v1" "repair-instance-bootstrap marks the refreshed startup profile"
  assert_contains "${log_content}" "startup_contract_version=startup-ready-v1" "repair-instance-bootstrap persists startup contract version"
  assert_contains "${log_content}" "startup_ready_sentinel=/var/lib/openclaw/startup-ready-v1" "repair-instance-bootstrap persists readiness sentinel metadata"
  assert_contains "${log_content}" "readiness_log_path=/var/log/openclaw/readiness-gate.log" "repair-instance-bootstrap persists readiness log path metadata"
  assert_contains "${log_content}" "GCLOUD compute ssh oc-main --project hoangnb-openclaw --zone asia-southeast1-a --tunnel-through-iap --command sudo google_metadata_script_runner startup" "repair-instance-bootstrap reruns startup over IAP by default"
}

test_repair_instance_bootstrap_rejects_invalid_metadata_values() {
  TESTS_RUN=$((TESTS_RUN + 1))

  run_capture bash "${ROOT_DIR}/scripts/openclaw-gcp/repair-instance-bootstrap.sh" \
    --project-id hoangnb-openclaw \
    --instance-name oc-main \
    --openclaw-image "bad,image" \
    --dry-run
  assert_status 1 "repair-instance-bootstrap rejects openclaw-image values with commas"
  assert_contains "${RUN_OUTPUT}" "openclaw_image must not contain ',' because it is persisted in metadata" "repair-instance-bootstrap explains comma metadata guard"

  run_capture bash "${ROOT_DIR}/scripts/openclaw-gcp/repair-instance-bootstrap.sh" \
    --project-id hoangnb-openclaw \
    --instance-name oc-main \
    --openclaw-image "bad=value" \
    --dry-run
  assert_status 1 "repair-instance-bootstrap rejects openclaw-image values with equals signs"
  assert_contains "${RUN_OUTPUT}" "openclaw_image must not contain '=' because it is persisted in metadata" "repair-instance-bootstrap explains equals metadata guard"

  run_capture bash "${ROOT_DIR}/scripts/openclaw-gcp/repair-instance-bootstrap.sh" \
    --project-id hoangnb-openclaw \
    --instance-name oc-main \
    --openclaw-tag $'bad\ntag' \
    --dry-run
  assert_status 1 "repair-instance-bootstrap rejects openclaw-tag values with newlines"
  assert_contains "${RUN_OUTPUT}" "openclaw_tag must not contain newlines" "repair-instance-bootstrap explains newline metadata guard"

  run_capture bash "${ROOT_DIR}/scripts/openclaw-gcp/repair-instance-bootstrap.sh" \
    --project-id hoangnb-openclaw \
    --instance-name oc-main \
    --openclaw-image "" \
    --dry-run
  assert_status 1 "repair-instance-bootstrap rejects empty openclaw-image values"
  assert_contains "${RUN_OUTPUT}" "--openclaw-image cannot be empty" "repair-instance-bootstrap explains empty openclaw-image guard"
}

test_negative_guards() {
  local startup_file="${TMP_DIR}/startup.sh"
  TESTS_RUN=$((TESTS_RUN + 1))

  printf '#!/usr/bin/env bash\necho ok\n' >"${startup_file}"

  run_capture bash "${ROOT_DIR}/scripts/openclaw-gcp/create-template.sh" \
    --project-id hoangnb-openclaw \
    --openclaw-tag v1.2.3 \
    --no-service-account \
    --startup-script-url https://example.invalid/script.sh \
    --dry-run
  assert_status 1 "create-template rejects unpinned startup-script-url"
  assert_contains "${RUN_OUTPUT}" "--startup-script-sha256 must be a 64-character hex digest" "create-template explains missing startup-script digest"

  run_capture bash "${ROOT_DIR}/scripts/openclaw-gcp/create-template.sh" \
    --project-id hoangnb-openclaw \
    --openclaw-tag v1.2.3 \
    --no-service-account \
    --startup-script-file "${startup_file}" \
    --startup-script-url https://example.invalid/script.sh \
    --startup-script-sha256 1111111111111111111111111111111111111111111111111111111111111111 \
    --dry-run
  assert_status 1 "create-template rejects simultaneous local and remote startup script sources"
  assert_contains "${RUN_OUTPUT}" "set only one of --startup-script-file or --startup-script-url" "create-template explains mutually exclusive startup-script sources"

  run_capture bash "${ROOT_DIR}/scripts/openclaw-gcp/create-template.sh" \
    --project-id hoangnb-openclaw \
    --openclaw-tag pin-me \
    --no-service-account \
    --dry-run
  assert_status 1 "create-template rejects pin-me tag sentinel"
  assert_contains "${RUN_OUTPUT}" "must be explicitly set" "create-template explains tag pin guard"

  run_capture bash "${ROOT_DIR}/scripts/openclaw-gcp/create-template.sh" \
    --project-id hoangnb-openclaw \
    --region us-central1 \
    --zone asia-southeast1-a \
    --openclaw-tag v1.2.3 \
    --no-service-account \
    --dry-run
  assert_status 1 "create-template rejects mismatched region and zone"
  assert_contains "${RUN_OUTPUT}" "--zone must belong to --region" "create-template explains zone mismatch"

  run_capture bash "${ROOT_DIR}/scripts/openclaw-gcp/create-snapshot-policy.sh" \
    --project-id hoangnb-openclaw \
    --start-hour-utc 24 \
    --dry-run
  assert_status 1 "create-snapshot-policy rejects invalid UTC hour"
  assert_contains "${RUN_OUTPUT}" "--start-hour-utc must be 0..23" "create-snapshot-policy explains invalid UTC hour"

  run_capture bash "${ROOT_DIR}/scripts/openclaw-gcp/create-snapshot-policy.sh" \
    --project-id hoangnb-openclaw \
    --on-source-disk-delete DELETE_NOW \
    --dry-run
  assert_status 1 "create-snapshot-policy rejects invalid delete mode"
  assert_contains "${RUN_OUTPUT}" "--on-source-disk-delete must be KEEP_AUTO_SNAPSHOTS or APPLY_RETENTION_POLICY" "create-snapshot-policy explains invalid delete mode"

  run_capture bash "${ROOT_DIR}/scripts/openclaw-gcp/create-template.sh" \
    --project-id hoangnb-openclaw \
    --openclaw-tag v1.2.3 \
    --dry-run
  assert_status 1 "create-template requires explicit identity mode"
  assert_contains "${RUN_OUTPUT}" "choose an identity mode" "create-template explains missing identity selection"
}

main() {
  test_create_template_command_and_startup_script
  test_create_instance_first_run_flow
  test_create_instance_existing_internal_template_auto_nat
  test_template_reuse_rejects_explicit_drift_inputs
  test_snapshot_policy_reuse_and_region_default_zone
  test_docs_smoke_commands
  test_install_help_and_noninteractive_gcloud_guard
  test_install_parser_missing_value_guard
  test_install_prompt_and_nonprompt_behavior
  test_install_readiness_gate_dry_run_contract
  test_install_firewall_preflight_predicate
  test_install_cross_zone_existing_instance_guard
  test_install_reuse_eligibility_guardrails
  test_install_repairable_reuse_contract_auto_repairs
  test_install_ssh_handoff_contract_and_failure_summary
  test_cloud_nat_idempotent_flow
  test_repair_instance_bootstrap_flow
  test_repair_instance_bootstrap_rejects_invalid_metadata_values
  test_negative_guards

  if (( TESTS_FAILED > 0 )); then
    echo
    echo "FAIL ${TESTS_FAILED}/${TESTS_RUN} test groups failed"
    exit 1
  fi

  echo
  echo "PASS ${TESTS_RUN} test groups"
}

main "$@"
