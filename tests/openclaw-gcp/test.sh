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

assert_ordered_line_patterns() {
  local text="$1"
  local first_pattern="$2"
  local second_pattern="$3"
  local message="$4"
  local first_line=""
  local second_line=""

  first_line="$(printf '%s\n' "${text}" | grep -n "${first_pattern}" | head -n1 | cut -d: -f1 || true)"
  second_line="$(printf '%s\n' "${text}" | grep -n "${second_pattern}" | head -n1 | cut -d: -f1 || true)"

  if [[ -z "${first_line}" || -z "${second_line}" ]]; then
    fail "${message} (missing pattern)"
    printf '%s\n' "${text}"
    return
  fi

  if (( first_line < second_line )); then
    pass "${message}"
  else
    fail "${message} (order mismatch: ${first_pattern} should precede ${second_pattern})"
    printf '%s\n' "${text}"
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
SSH_ATTEMPT_STATE_FILE="${MOCK_SSH_ATTEMPT_STATE_FILE:-${LOG_FILE}.ssh_attempts}"
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

derive_stack_id_from_resource_name() {
  local resource_name="$1"
  case "${resource_name}" in
    oc-*-template)
      printf '%s\n' "${resource_name#oc-}" | sed 's/-template$//'
      ;;
    oc-*)
      printf '%s\n' "${resource_name#oc-}"
      ;;
    *)
      printf '%s\n' "${MOCK_STACK_ID_DEFAULT:-unknown-stack}"
      ;;
  esac
}

label_default_value() {
  local resource_name="$1"
  local key="$2"
  case "${key}" in
    openclaw_managed) printf '%s\n' "true" ;;
    openclaw_stack_id) derive_stack_id_from_resource_name "${resource_name}" ;;
    openclaw_tool) printf '%s\n' "openclaw-gcp" ;;
    openclaw_lifecycle) printf '%s\n' "${MOCK_LABEL_LIFECYCLE:-persistent}" ;;
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

if [[ "$*" == *"compute ssh"* ]] && [[ "$*" == *"readiness-gate.log"* ]] && [[ -n "${MOCK_READINESS_SSH_FAIL_COUNT:-}" ]]; then
  attempt_count="0"
  if [[ -f "${SSH_ATTEMPT_STATE_FILE}" ]]; then
    attempt_count="$(cat "${SSH_ATTEMPT_STATE_FILE}")"
  fi
  attempt_count=$((attempt_count + 1))
  printf '%s\n' "${attempt_count}" >"${SSH_ATTEMPT_STATE_FILE}"
  if (( attempt_count <= MOCK_READINESS_SSH_FAIL_COUNT )); then
    cat >&2 <<'SSH_RETRY_EOF'
ERROR: [0] Error during local connection to [stdin]: Error while connecting [4047: 'Failed to lookup instance'].
Connection closed by UNKNOWN port 65535
SSH_RETRY_EOF
    exit 255
  fi
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
  template_name=""
  for ((i=1; i <= $#; i++)); do
    if [[ "${!i}" == "describe" ]]; then
      next=$((i + 1))
      template_name="${!next}"
      break
    fi
  done
  if [[ "$*" == *"--format=value(labels.openclaw_managed,labels.openclaw_stack_id,labels.openclaw_tool,labels.openclaw_lifecycle)"* ]]; then
    if [[ "${MOCK_TEMPLATE_EXISTS:-false}" == "true" ]]; then
      printf '%s\t%s\t%s\t%s\n' \
        "${MOCK_TEMPLATE_LABEL_OPENCLAW_MANAGED:-$(label_default_value "${template_name}" openclaw_managed)}" \
        "${MOCK_TEMPLATE_LABEL_OPENCLAW_STACK_ID:-$(label_default_value "${template_name}" openclaw_stack_id)}" \
        "${MOCK_TEMPLATE_LABEL_OPENCLAW_TOOL:-$(label_default_value "${template_name}" openclaw_tool)}" \
        "${MOCK_TEMPLATE_LABEL_OPENCLAW_LIFECYCLE:-$(label_default_value "${template_name}" openclaw_lifecycle)}"
      exit 0
    fi
    exit 1
  fi
  if [[ "$*" == *"--flatten=properties.metadata.items[]"* && "$*" == *"--format=value(properties.metadata.items.key,properties.metadata.items.value)"* ]]; then
    if [[ "${MOCK_DESTROY_TEMPLATE_DESCRIBE_FAIL:-false}" == "true" ]]; then
      exit 1
    fi
    if [[ -n "${MOCK_DESTROY_TEMPLATE_METADATA_LINES:-}" ]]; then
      printf '%b\n' "${MOCK_DESTROY_TEMPLATE_METADATA_LINES}"
      exit 0
    fi
    printf 'startup_script_source\t%s\n' "${MOCK_DESTROY_STARTUP_SCRIPT_SOURCE:-embedded-vm-prereqs-v1}"
    printf 'startup_profile\t%s\n' "${MOCK_DESTROY_STARTUP_PROFILE:-vm-prereqs-v1}"
    printf 'startup_contract_version\t%s\n' "${MOCK_DESTROY_STARTUP_CONTRACT_VERSION:-startup-ready-v1}"
    printf 'startup_ready_sentinel\t%s\n' "${MOCK_DESTROY_STARTUP_READY_SENTINEL:-/var/lib/openclaw/startup-ready-v1}"
    exit 0
  fi
  if [[ "$*" == *"accessConfigs"* ]]; then
    if [[ "${MOCK_TEMPLATE_HAS_EXTERNAL_IP:-false}" == "true" ]]; then
      printf '%s\n' "External NAT"
      exit 0
    fi
    exit 0
  fi
  if [[ "${MOCK_TEMPLATE_EXISTS:-false}" == "true" ]]; then
    printf '%s\n' "${template_name:-${MOCK_TEMPLATE_NAME:-oc-template}}"
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

if [[ "$*" == *"compute instances describe"* && "$*" == *"--format=value(labels.openclaw_managed,labels.openclaw_stack_id,labels.openclaw_tool,labels.openclaw_lifecycle)"* ]]; then
  instance_name=""
  for ((i=1; i <= $#; i++)); do
    if [[ "${!i}" == "describe" ]]; then
      next=$((i + 1))
      instance_name="${!next}"
      break
    fi
  done
  if [[ "${MOCK_INSTANCE_EXISTS:-false}" == "true" ]]; then
    printf '%s\t%s\t%s\t%s\n' \
      "${MOCK_INSTANCE_LABEL_OPENCLAW_MANAGED:-$(label_default_value "${instance_name}" openclaw_managed)}" \
      "${MOCK_INSTANCE_LABEL_OPENCLAW_STACK_ID:-$(label_default_value "${instance_name}" openclaw_stack_id)}" \
      "${MOCK_INSTANCE_LABEL_OPENCLAW_TOOL:-$(label_default_value "${instance_name}" openclaw_tool)}" \
      "${MOCK_INSTANCE_LABEL_OPENCLAW_LIFECYCLE:-$(label_default_value "${instance_name}" openclaw_lifecycle)}"
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

if [[ "$*" == *"compute instances describe"* && "$*" == *"--flatten=disks[]"* && "$*" == *"--format=value(disks.boot,disks.autoDelete)"* ]]; then
  describe_instance=""
  for ((i=1; i <= $#; i++)); do
    if [[ "${!i}" == "describe" ]]; then
      next=$((i + 1))
      describe_instance="${!next}"
      break
    fi
  done
  if [[ "${describe_instance}" == "${MOCK_CLONE_INSTANCE_NAME:-oc-clone}" ]]; then
    if [[ "${MOCK_DESTROY_CLONE_DESCRIBE_FAIL:-false}" == "true" ]]; then
      exit 1
    fi
    if [[ -n "${MOCK_DESTROY_CLONE_DISK_ROWS:-}" ]]; then
      printf '%b\n' "${MOCK_DESTROY_CLONE_DISK_ROWS}"
      exit 0
    fi
    printf '%s\n' "true true"
    exit 0
  fi
  if [[ "${MOCK_DESTROY_INSTANCE_DESCRIBE_FAIL:-false}" == "true" ]]; then
    exit 1
  fi
  if [[ -n "${MOCK_DESTROY_DISK_ROWS:-}" ]]; then
    printf '%b\n' "${MOCK_DESTROY_DISK_ROWS}"
    exit 0
  fi
  printf '%s\n' "true true"
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

if [[ "$*" == *"compute disks describe"* && "$*" == *"--flatten=resourcePolicies[]"* && "$*" == *"--format=value(resourcePolicies.basename())"* ]]; then
  if [[ "${MOCK_DESTROY_SNAPSHOT_DISK_DESCRIBE_FAIL:-false}" == "true" ]]; then
    exit 1
  fi
  if [[ -n "${MOCK_DESTROY_SNAPSHOT_POLICY_ROWS:-}" ]]; then
    printf '%b\n' "${MOCK_DESTROY_SNAPSHOT_POLICY_ROWS}"
    exit 0
  fi
  printf '%s\n' "${MOCK_DESTROY_SNAPSHOT_POLICY_NAME:-oc-daily-snapshots}"
  exit 0
fi

if [[ "$*" == *"compute routers describe"* ]]; then
  if [[ "$*" == *"--format=value(network.basename())"* ]]; then
    if [[ "${MOCK_DESTROY_ROUTER_DESCRIBE_FAIL:-false}" == "true" ]]; then
      exit 1
    fi
    if [[ -n "${MOCK_DESTROY_ROUTER_NETWORK_ROWS:-}" ]]; then
      printf '%b\n' "${MOCK_DESTROY_ROUTER_NETWORK_ROWS}"
      exit 0
    fi
    printf '%s\n' "${MOCK_DESTROY_ROUTER_NETWORK:-default}"
    exit 0
  fi
  if [[ "${MOCK_ROUTER_EXISTS:-false}" == "true" ]]; then
    printf '%s\n' "${MOCK_ROUTER_NAME:-oc-router}"
    exit 0
  fi
  exit 1
fi

if [[ "$*" == *"compute routers nats describe"* ]]; then
  if [[ "$*" == *"--format=value(natIpAllocateOption,sourceSubnetworkIpRangesToNat)"* ]]; then
    if [[ "${MOCK_DESTROY_NAT_DESCRIBE_FAIL:-false}" == "true" ]]; then
      exit 1
    fi
    if [[ -n "${MOCK_DESTROY_NAT_MODE_ROWS:-}" ]]; then
      printf '%b\n' "${MOCK_DESTROY_NAT_MODE_ROWS}"
      exit 0
    fi
    printf '%s\n' "AUTO_ONLY ALL_SUBNETWORKS_ALL_IP_RANGES"
    exit 0
  fi
  if [[ "${MOCK_NAT_EXISTS:-false}" == "true" ]]; then
    printf '%s\n' "${MOCK_NAT_NAME:-oc-nat}"
    exit 0
  fi
  exit 1
fi

if [[ "$*" == *"compute instances delete"* ]]; then
  if [[ "${MOCK_DESTROY_FAIL_INSTANCE_DELETE:-false}" == "true" ]]; then
    echo "mocked instance delete failure" >&2
    exit 41
  fi
  exit 0
fi

if [[ "$*" == *"compute disks remove-resource-policies"* ]]; then
  if [[ "${MOCK_DESTROY_FAIL_SNAPSHOT_DETACH:-false}" == "true" ]]; then
    echo "mocked snapshot detach failure" >&2
    exit 45
  fi
  exit 0
fi

if [[ "$*" == *"compute resource-policies delete"* ]]; then
  if [[ "${MOCK_DESTROY_FAIL_SNAPSHOT_DELETE:-false}" == "true" ]]; then
    echo "mocked snapshot delete failure" >&2
    exit 46
  fi
  exit 0
fi

if [[ "$*" == *"compute instance-templates delete"* ]]; then
  if [[ "${MOCK_DESTROY_FAIL_TEMPLATE_DELETE:-false}" == "true" ]]; then
    echo "mocked template delete failure" >&2
    exit 42
  fi
  exit 0
fi

if [[ "$*" == *"compute routers nats delete"* ]]; then
  if [[ "${MOCK_DESTROY_FAIL_NAT_DELETE:-false}" == "true" ]]; then
    echo "mocked NAT delete failure" >&2
    exit 43
  fi
  exit 0
fi

if [[ "$*" == *"compute routers delete"* ]]; then
  if [[ "${MOCK_DESTROY_FAIL_ROUTER_DELETE:-false}" == "true" ]]; then
    echo "mocked router delete failure" >&2
    exit 44
  fi
  exit 0
fi

if [[ "$*" == *"compute machine-images describe"* && "$*" == *"--format=value(name)"* ]]; then
  if [[ "${MOCK_DESTROY_MACHINE_IMAGE_DESCRIBE_FAIL:-false}" == "true" ]]; then
    exit 1
  fi
  printf '%s\n' "${MOCK_DESTROY_MACHINE_IMAGE_DESCRIBE_NAME:-${MOCK_DESTROY_MACHINE_IMAGE_NAME:-oc-image-20260324-001}}"
  exit 0
fi

if [[ "$*" == *"compute machine-images delete"* ]]; then
  if [[ "${MOCK_DESTROY_FAIL_MACHINE_IMAGE_DELETE:-false}" == "true" ]]; then
    echo "mocked machine image delete failure" >&2
    exit 47
  fi
  exit 0
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

  run_capture bash "${ROOT_DIR}/scripts/openclaw-gcp/destroy.sh" \
    --project-id hoangnb-openclaw \
    --instance-name oc-main \
    --template-name oc-template \
    --router-name oc-router \
    --nat-name oc-nat \
    --dry-run
  assert_status 0 "README destroy companion example parses in dry-run mode"
  assert_contains "${RUN_OUTPUT}" "Phase 1 target order:" "README destroy companion example emits teardown target order"

  run_capture bash "${ROOT_DIR}/scripts/openclaw-gcp/destroy.sh" \
    --project-id hoangnb-openclaw \
    --instance-name oc-main \
    --template-name oc-template \
    --router-name oc-router \
    --nat-name oc-nat \
    --dry-run
  assert_status 0 "runbook destroy dry-run example parses in dry-run mode"
  assert_contains "${RUN_OUTPUT}" "Dry-run mode: no resources were modified." "runbook destroy dry-run example stays mutation-safe"

  run_capture bash "${ROOT_DIR}/scripts/openclaw-gcp/repair-instance-bootstrap.sh" \
    --project-id hoangnb-openclaw \
    --instance-name oc-main \
    --openclaw-tag vX.Y.Z \
    --run-now \
    --dry-run
  assert_status 0 "repair-instance-bootstrap example parses in dry-run mode"

  run_capture bash "${ROOT_DIR}/bin/openclaw-gcp" welcome --stack-id team-dev --non-interactive
  assert_status 0 "Cloud Shell welcome entrypoint parses in non-interactive mode"
  assert_contains "${RUN_OUTPUT}" "./bin/openclaw-gcp up --stack-id team-dev" "welcome entrypoint points to the stack-native up command"
}

test_stack_wrapper_up_status_down_contract() {
  local mock_dir home_dir state_file log_content
  mock_dir="$(new_mock_env stack-wrapper)"
  home_dir="${mock_dir}/home"
  mkdir -p "${home_dir}"
  TESTS_RUN=$((TESTS_RUN + 1))

  run_capture run_with_mock "${mock_dir}" \
    HOME="${home_dir}" \
    MOCK_INSTANCE_EXISTS=true \
    MOCK_TEMPLATE_EXISTS=true \
    MOCK_ROUTER_EXISTS=true \
    MOCK_NAT_EXISTS=true \
    bash "${ROOT_DIR}/bin/openclaw-gcp" up \
    --stack-id team-dev \
    --project-id hoangnb-openclaw \
    --openclaw-tag v1.2.3 \
    --non-interactive \
    --dry-run

  assert_status 0 "wrapper up dry-run resolves stack names and delegates safely"
  assert_contains "${RUN_OUTPUT}" "instance_name=oc-team-dev" "wrapper up derives the instance name from stack ID"
  assert_contains "${RUN_OUTPUT}" "template_name=oc-team-dev-template" "wrapper up derives the template name from stack ID"
  assert_contains "${RUN_OUTPUT}" "router_name=oc-team-dev-router" "wrapper up derives the router name from stack ID"
  assert_contains "${RUN_OUTPUT}" "nat_name=oc-team-dev-nat" "wrapper up derives the NAT name from stack ID"
  assert_contains "${RUN_OUTPUT}" "labels=openclaw_managed=true,openclaw_stack_id=team-dev,openclaw_tool=openclaw-gcp,openclaw_lifecycle=persistent" "wrapper up emits the stack label contract"
  assert_contains "${RUN_OUTPUT}" "Dry-run mode: skipping current-stack state write." "wrapper up keeps dry-run mutation-free"

  state_file="${home_dir}/.config/openclaw-gcp/current-stack.env"
  if [[ -f "${state_file}" ]]; then
    fail "wrapper up dry-run should not write local state"
    cat "${state_file}"
  else
    pass "wrapper up dry-run leaves local state untouched"
  fi

  run_capture run_with_mock "${mock_dir}" \
    HOME="${home_dir}" \
    MOCK_INSTANCE_EXISTS=true \
    MOCK_TEMPLATE_EXISTS=true \
    MOCK_ROUTER_EXISTS=true \
    MOCK_NAT_EXISTS=true \
    bash "${ROOT_DIR}/bin/openclaw-gcp" status \
    --stack-id team-dev \
    --project-id hoangnb-openclaw

  assert_status 0 "wrapper status shows live stack summary"
  assert_contains "${RUN_OUTPUT}" "instance (oc-team-dev): present (labels verified)" "wrapper status verifies instance labels against stack ID"
  assert_contains "${RUN_OUTPUT}" "template (oc-team-dev-template): present (labels verified)" "wrapper status verifies template labels against stack ID"
  assert_contains "${RUN_OUTPUT}" "router (oc-team-dev-router): present" "wrapper status reports router presence"
  assert_contains "${RUN_OUTPUT}" "nat (oc-team-dev-nat): present" "wrapper status reports NAT presence"

  run_capture run_with_mock "${mock_dir}" \
    HOME="${home_dir}" \
    MOCK_INSTANCE_EXISTS=true \
    MOCK_TEMPLATE_EXISTS=true \
    bash "${ROOT_DIR}/bin/openclaw-gcp" down \
    --stack-id team-dev \
    --project-id hoangnb-openclaw \
    --dry-run

  assert_status 0 "wrapper down dry-run verifies anchors then delegates to destroy"
  assert_contains "${RUN_OUTPUT}" "[down] Stack anchors verified through GCP labels." "wrapper down reports label-backed verification before destroy"
  assert_contains "${RUN_OUTPUT}" "gcloud compute instances delete oc-team-dev" "wrapper down dry-run passes the derived instance name to destroy"
  assert_contains "${RUN_OUTPUT}" "gcloud compute instance-templates delete oc-team-dev-template" "wrapper down dry-run passes the derived template name to destroy"
  assert_contains "${RUN_OUTPUT}" "gcloud compute routers nats delete oc-team-dev-nat" "wrapper down dry-run passes the derived NAT name to destroy"
  assert_contains "${RUN_OUTPUT}" "gcloud compute routers delete oc-team-dev-router" "wrapper down dry-run passes the derived router name to destroy"

  log_content="$(cat "${mock_dir}/gcloud.log")"
  assert_contains "${log_content}" "GCLOUD compute instances describe oc-team-dev --project hoangnb-openclaw --zone asia-southeast1-a --format=value(labels.openclaw_managed,labels.openclaw_stack_id,labels.openclaw_tool,labels.openclaw_lifecycle)" "wrapper down checks instance labels before teardown"
  assert_contains "${log_content}" "GCLOUD compute instance-templates describe oc-team-dev-template --project hoangnb-openclaw --region asia-southeast1 --format=value(labels.openclaw_managed,labels.openclaw_stack_id,labels.openclaw_tool,labels.openclaw_lifecycle)" "wrapper down checks template labels before teardown"
}

test_stack_wrapper_state_persists_when_up_fails() {
  local mock_dir home_dir state_file state_content
  mock_dir="$(new_mock_env stack-wrapper-state)"
  home_dir="${mock_dir}/home"
  mkdir -p "${home_dir}"
  TESTS_RUN=$((TESTS_RUN + 1))

  run_capture run_with_mock "${mock_dir}" \
    HOME="${home_dir}" \
    MOCK_INSTANCE_EXISTS=true \
    MOCK_SSH_FAIL_HANDOFF=true \
    bash "${ROOT_DIR}/bin/openclaw-gcp" up \
    --stack-id team-dev \
    --project-id hoangnb-openclaw \
    --openclaw-tag v1.2.3 \
    --non-interactive

  assert_status 1 "wrapper up still leaves convenience state behind when the install handoff fails"
  assert_contains "${RUN_OUTPUT}" "Saved current stack convenience state to" "wrapper up writes state before the delegated install finishes"
  assert_contains "${RUN_OUTPUT}" "Install handoff failed:" "wrapper up still surfaces delegated install failure"

  state_file="${home_dir}/.config/openclaw-gcp/current-stack.env"
  if [[ -f "${state_file}" ]]; then
    pass "wrapper up failure leaves a current-stack file for later status/down"
  else
    fail "wrapper up failure should still leave a current-stack file"
  fi
  state_content="$(cat "${state_file}")"
  assert_contains "${state_content}" "CURRENT_STACK_ID=team-dev" "current-stack file records stack ID after failed up"
  assert_contains "${state_content}" "LAST_PROJECT_ID=hoangnb-openclaw" "current-stack file records project context after failed up"
  assert_contains "${state_content}" "LAST_REGION=asia-southeast1" "current-stack file records region context after failed up"
  assert_contains "${state_content}" "LAST_ZONE=asia-southeast1-a" "current-stack file records zone context after failed up"
}

test_stack_wrapper_down_safety_guards() {
  local mock_dir home_dir state_file state_content
  mock_dir="$(new_mock_env stack-wrapper-down-safety)"
  home_dir="${mock_dir}/home"
  mkdir -p "${home_dir}/.config/openclaw-gcp"
  state_file="${home_dir}/.config/openclaw-gcp/current-stack.env"
  cat >"${state_file}" <<'EOF'
# openclaw-gcp local convenience state
CURRENT_STACK_ID=team-dev
LAST_PROJECT_ID=hoangnb-openclaw
LAST_REGION=asia-southeast1
LAST_ZONE=asia-southeast1-a
LIFECYCLE=persistent
EOF
  TESTS_RUN=$((TESTS_RUN + 1))

  run_capture run_with_mock "${mock_dir}" \
    HOME="${home_dir}" \
    CLOUD_SHELL=true \
    MOCK_INSTANCE_EXISTS=true \
    MOCK_TEMPLATE_EXISTS=true \
    bash "${ROOT_DIR}/bin/openclaw-gcp" down --dry-run

  assert_status 1 "wrapper down requires an explicit stack outside interactive Cloud Shell even when current state exists"
  assert_contains "${RUN_OUTPUT}" "down requires --stack-id outside interactive Cloud Shell sessions" "wrapper down explains the non-interactive explicit-stack requirement"

  run_capture run_with_mock "${mock_dir}" \
    HOME="${home_dir}" \
    MOCK_INSTANCE_EXISTS=true \
    MOCK_INSTANCE_LABEL_OPENCLAW_STACK_ID=other-stack \
    MOCK_TEMPLATE_EXISTS=true \
    bash "${ROOT_DIR}/bin/openclaw-gcp" down \
    --stack-id team-dev \
    --project-id hoangnb-openclaw \
    --dry-run

  assert_status 1 "wrapper down fails closed when a labeled anchor does not match the requested stack"
  assert_contains "${RUN_OUTPUT}" "label mismatch" "wrapper down reports label mismatch before destroy"
  assert_contains "${RUN_OUTPUT}" "Refusing teardown because the labeled GCP anchors do not match." "wrapper down preserves stack-identity safety"

  run_capture run_with_mock "${mock_dir}" \
    HOME="${home_dir}" \
    MOCK_INSTANCE_EXISTS=true \
    MOCK_TEMPLATE_EXISTS=true \
    bash "${ROOT_DIR}/bin/openclaw-gcp" down \
    --stack-id team-dev \
    --project-id hoangnb-openclaw \
    --yes \
    --non-interactive

  assert_status 0 "wrapper down succeeds non-interactively when stack is explicit and anchors verify"
  assert_contains "${RUN_OUTPUT}" "Destroy completed successfully." "wrapper down surfaces successful delegated destroy completion"
  assert_contains "${RUN_OUTPUT}" "Cleared current stack pointer in" "wrapper down clears remembered current stack after success"

  state_content="$(cat "${state_file}")"
  assert_contains "${state_content}" "CURRENT_STACK_ID=" "wrapper down clears the current stack pointer after success"
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

test_install_readiness_probe_retries_fresh_vm_iap_lookup_delay() {
  local mock_dir
  local log_content
  mock_dir="$(new_mock_env install-readiness-retry)"
  TESTS_RUN=$((TESTS_RUN + 1))

  run_capture run_with_mock "${mock_dir}" \
    MOCK_INSTANCE_EXISTS=true \
    MOCK_READINESS_SSH_FAIL_COUNT=2 \
    OPENCLAW_READINESS_SSH_MAX_ATTEMPTS=4 \
    OPENCLAW_READINESS_SSH_RETRY_DELAY_SECONDS=0 \
    bash "${ROOT_DIR}/scripts/openclaw-gcp/install.sh" \
    --project-id hoangnb-openclaw \
    --instance-name oc-main \
    --zone asia-southeast1-a

  assert_status 0 "install.sh retries transient fresh-VM IAP lookup failures"
  assert_contains "${RUN_OUTPUT}" "Readiness gate: instance not yet reachable through IAP SSH (attempt 1/4); retrying in 0s." "install.sh reports first transient readiness retry"
  assert_contains "${RUN_OUTPUT}" "Readiness gate: instance not yet reachable through IAP SSH (attempt 2/4); retrying in 0s." "install.sh reports second transient readiness retry"
  assert_contains "${RUN_OUTPUT}" "Readiness gate passed." "install.sh eventually passes readiness after transient IAP delay"
  assert_contains "${RUN_OUTPUT}" "Interactive SSH handoff stage: launching upstream installer." "install.sh continues to handoff after readiness retries succeed"

  log_content="$(cat "${mock_dir}/gcloud.log")"
  assert_contains "${log_content}" "GCLOUD compute ssh oc-main --project hoangnb-openclaw --zone asia-southeast1-a --tunnel-through-iap --command" "install.sh emits readiness SSH command during retry flow"
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

test_destroy_help_parser_and_confirmation_contract() {
  local mock_dir
  mock_dir="$(new_mock_env destroy-help-parser)"
  TESTS_RUN=$((TESTS_RUN + 1))

  run_capture bash "${ROOT_DIR}/scripts/openclaw-gcp/destroy.sh" --help
  assert_status 0 "destroy.sh --help renders usage"
  assert_contains "${RUN_OUTPUT}" "Destroy the standard OpenClaw GCP deployment by exact resource names." "destroy.sh help describes exact-name contract"
  assert_contains "${RUN_OUTPUT}" "--dry-run prints plan and commands without mutating resources" "destroy.sh help describes dry-run safety contract"
  assert_contains "${RUN_OUTPUT}" "--snapshot-policy-name <name>" "destroy.sh help includes snapshot policy extra flag"
  assert_contains "${RUN_OUTPUT}" "--clone-instance-name <name>" "destroy.sh help includes clone extra flag"
  assert_contains "${RUN_OUTPUT}" "--machine-image-name <name>" "destroy.sh help includes machine image extra flag"

  run_capture bash "${ROOT_DIR}/scripts/openclaw-gcp/destroy.sh" --project-id
  assert_status 1 "destroy.sh rejects missing values for value-taking flags"
  assert_contains "${RUN_OUTPUT}" "Error: missing value for --project-id" "destroy.sh reports a controlled missing-value parser error"
  assert_not_contains "${RUN_OUTPUT}" "shift count out of range" "destroy.sh avoids raw shell shift failures for missing option values"

  run_capture bash "${ROOT_DIR}/scripts/openclaw-gcp/destroy.sh" \
    --project-id hoangnb-openclaw \
    --snapshot-policy-disk oc-main \
    --dry-run
  assert_status 1 "destroy.sh requires snapshot-policy-name when snapshot disk context is passed"
  assert_contains "${RUN_OUTPUT}" "--snapshot-policy-disk requires --snapshot-policy-name" "destroy.sh enforces snapshot disk parser guardrail"

  run_capture bash -c "printf 'NOPE\n' | env PATH=\"${mock_dir}/bin:\${PATH}\" MOCK_GCLOUD_LOG=\"${mock_dir}/gcloud.log\" bash \"${ROOT_DIR}/scripts/openclaw-gcp/destroy.sh\" --project-id hoangnb-openclaw --interactive"
  assert_status 1 "destroy.sh interactive mode requires typed confirmation"
  assert_contains "${RUN_OUTPUT}" "typed confirmation did not match; aborting" "destroy.sh rejects incorrect typed confirmation token"

  local log_content
  log_content="$(cat "${mock_dir}/gcloud.log")"
  assert_not_contains "${log_content}" "GCLOUD compute instances delete" "destroy.sh confirmation failure emits no instance delete command"
  assert_not_contains "${log_content}" "GCLOUD compute instance-templates delete" "destroy.sh confirmation failure emits no template delete command"
  assert_not_contains "${log_content}" "GCLOUD compute routers nats delete" "destroy.sh confirmation failure emits no NAT delete command"
  assert_not_contains "${log_content}" "GCLOUD compute routers delete" "destroy.sh confirmation failure emits no router delete command"

  mock_dir="$(new_mock_env destroy-explicit-project-guard)"
  run_capture run_with_mock "${mock_dir}" \
    MOCK_PROJECT_ID=prod-openclaw \
    bash "${ROOT_DIR}/scripts/openclaw-gcp/destroy.sh" \
    --yes
  assert_status 1 "destroy.sh rejects ambient gcloud project fallback for real deletes"
  assert_contains "${RUN_OUTPUT}" "real destructive runs require explicit --project-id" "destroy.sh explains explicit project targeting requirement"
  log_content="$(cat "${mock_dir}/gcloud.log")"
  assert_not_contains "${log_content}" "GCLOUD compute instances delete" "destroy.sh ambient project refusal emits no instance delete command"
  assert_not_contains "${log_content}" "GCLOUD compute instance-templates delete" "destroy.sh ambient project refusal emits no template delete command"
  assert_not_contains "${log_content}" "GCLOUD compute routers nats delete" "destroy.sh ambient project refusal emits no NAT delete command"
  assert_not_contains "${log_content}" "GCLOUD compute routers delete" "destroy.sh ambient project refusal emits no router delete command"
}

test_destroy_dry_run_contract() {
  local mock_dir
  mock_dir="$(new_mock_env destroy-dry-run)"
  TESTS_RUN=$((TESTS_RUN + 1))

  run_capture run_with_mock "${mock_dir}" \
    bash "${ROOT_DIR}/scripts/openclaw-gcp/destroy.sh" \
    --project-id hoangnb-openclaw \
    --dry-run

  assert_status 0 "destroy.sh dry-run succeeds"
  assert_contains "${RUN_OUTPUT}" "Phase 1 target order:" "destroy.sh dry-run prints deterministic target order"
  assert_contains "${RUN_OUTPUT}" "gcloud compute instances delete oc-main" "destroy.sh dry-run prints planned instance delete command"
  assert_contains "${RUN_OUTPUT}" "gcloud compute instance-templates delete oc-template" "destroy.sh dry-run prints planned template delete command"
  assert_contains "${RUN_OUTPUT}" "gcloud compute routers nats delete oc-nat" "destroy.sh dry-run prints planned NAT delete command"
  assert_contains "${RUN_OUTPUT}" "gcloud compute routers delete oc-router" "destroy.sh dry-run prints planned router delete command"
  assert_contains "${RUN_OUTPUT}" "Dry-run mode: no resources were modified." "destroy.sh dry-run reports no mutations"
  assert_not_contains "${RUN_OUTPUT}" "Running Phase 1 qualification checks..." "destroy.sh dry-run exits before qualification checks"
  assert_not_contains "${RUN_OUTPUT}" "snapshot_policy_name:" "destroy.sh default dry-run omits extra-resource rows when extras are not requested"

  local log_content
  log_content="$(cat "${mock_dir}/gcloud.log" 2>/dev/null || true)"
  assert_not_contains "${log_content}" "GCLOUD compute instances describe" "destroy.sh dry-run does not invoke instance qualification describes"
  assert_not_contains "${log_content}" "GCLOUD compute instances delete" "destroy.sh dry-run emits no delete command"

  run_capture run_with_mock "${mock_dir}" \
    bash "${ROOT_DIR}/scripts/openclaw-gcp/destroy.sh" \
    --project-id hoangnb-openclaw \
    --snapshot-policy-name oc-daily-snapshots \
    --snapshot-policy-disk oc-main \
    --machine-image-name oc-image-20260324-001 \
    --clone-instance-name oc-clone \
    --dry-run
  assert_status 0 "destroy.sh extra-resource dry-run succeeds"
  assert_contains "${RUN_OUTPUT}" "Phase 2 explicit extra targets:" "destroy.sh dry-run prints explicit extra targets when named"
  assert_contains "${RUN_OUTPUT}" "snapshot_policy_name: oc-daily-snapshots" "destroy.sh dry-run shows named snapshot policy"
  assert_contains "${RUN_OUTPUT}" "clone_instance_name: oc-clone" "destroy.sh dry-run shows named clone target"
  assert_contains "${RUN_OUTPUT}" "machine_image_name: oc-image-20260324-001" "destroy.sh dry-run shows named machine image target"
  assert_contains "${RUN_OUTPUT}" "gcloud compute disks remove-resource-policies oc-main" "destroy.sh dry-run prints planned snapshot detach command when disk context is provided"
  assert_contains "${RUN_OUTPUT}" "gcloud compute machine-images delete oc-image-20260324-001" "destroy.sh dry-run prints planned machine-image delete command when named"
}

test_destroy_qualification_failures_block_deletes() {
  local mock_dir
  local log_content
  TESTS_RUN=$((TESTS_RUN + 1))

  mock_dir="$(new_mock_env destroy-qual-extra-disk)"
  run_capture run_with_mock "${mock_dir}" MOCK_DESTROY_DISK_ROWS=$'true true\nfalse true' \
    bash "${ROOT_DIR}/scripts/openclaw-gcp/destroy.sh" \
    --project-id hoangnb-openclaw \
    --yes
  assert_status 1 "destroy.sh rejects instances with extra attached disks"
  assert_contains "${RUN_OUTPUT}" "Qualification failed [instance-disk-safety]" "destroy.sh reports disk safety predicate failure for extra disk"
  log_content="$(cat "${mock_dir}/gcloud.log")"
  assert_not_contains "${log_content}" "GCLOUD compute instances delete" "extra-disk qualification failure emits no delete commands"

  mock_dir="$(new_mock_env destroy-qual-autodelete)"
  run_capture run_with_mock "${mock_dir}" MOCK_DESTROY_DISK_ROWS=$'true false' \
    bash "${ROOT_DIR}/scripts/openclaw-gcp/destroy.sh" \
    --project-id hoangnb-openclaw \
    --yes
  assert_status 1 "destroy.sh rejects sole-disk autoDelete=false predicates"
  assert_contains "${RUN_OUTPUT}" "disk predicate mismatch" "destroy.sh explains autoDelete mismatch"
  log_content="$(cat "${mock_dir}/gcloud.log")"
  assert_not_contains "${log_content}" "GCLOUD compute instances delete" "autoDelete=false qualification failure emits no delete commands"

  mock_dir="$(new_mock_env destroy-qual-template)"
  run_capture run_with_mock "${mock_dir}" \
    MOCK_DESTROY_TEMPLATE_METADATA_LINES=$'startup_script_source\tembedded-vm-prereqs-v1\nstartup_profile\tvm-prereqs-v1\nstartup_contract_version\tstartup-ready-v1' \
    bash "${ROOT_DIR}/scripts/openclaw-gcp/destroy.sh" \
    --project-id hoangnb-openclaw \
    --yes
  assert_status 1 "destroy.sh rejects template startup metadata drift"
  assert_contains "${RUN_OUTPUT}" "required metadata key missing: startup_ready_sentinel" "destroy.sh reports missing startup contract metadata key"
  log_content="$(cat "${mock_dir}/gcloud.log")"
  assert_not_contains "${log_content}" "GCLOUD compute instances delete" "template metadata failure emits no delete commands"

  mock_dir="$(new_mock_env destroy-qual-router)"
  run_capture run_with_mock "${mock_dir}" MOCK_DESTROY_ROUTER_NETWORK=custom-shared-network \
    bash "${ROOT_DIR}/scripts/openclaw-gcp/destroy.sh" \
    --project-id hoangnb-openclaw \
    --yes
  assert_status 1 "destroy.sh rejects router ownership drift"
  assert_contains "${RUN_OUTPUT}" "Qualification failed [router-network-ownership]" "destroy.sh reports router-network predicate failure"
  log_content="$(cat "${mock_dir}/gcloud.log")"
  assert_not_contains "${log_content}" "GCLOUD compute instances delete" "router ownership failure emits no delete commands"

  mock_dir="$(new_mock_env destroy-qual-nat)"
  run_capture run_with_mock "${mock_dir}" MOCK_DESTROY_NAT_MODE_ROWS="MANUAL_ONLY ALL_SUBNETWORKS_ALL_IP_RANGES" \
    bash "${ROOT_DIR}/scripts/openclaw-gcp/destroy.sh" \
    --project-id hoangnb-openclaw \
    --yes
  assert_status 1 "destroy.sh rejects NAT allocation-mode drift"
  assert_contains "${RUN_OUTPUT}" "Qualification failed [nat-parent-and-mode]" "destroy.sh reports NAT mode predicate failure"
  log_content="$(cat "${mock_dir}/gcloud.log")"
  assert_not_contains "${log_content}" "GCLOUD compute instances delete" "NAT mode failure emits no delete commands"
}

test_destroy_delete_order_and_mixed_failure_summary() {
  local mock_dir
  local log_content
  TESTS_RUN=$((TESTS_RUN + 1))

  mock_dir="$(new_mock_env destroy-success-order)"
  run_capture run_with_mock "${mock_dir}" \
    bash "${ROOT_DIR}/scripts/openclaw-gcp/destroy.sh" \
    --project-id hoangnb-openclaw \
    --yes

  assert_status 0 "destroy.sh succeeds when all Phase 1 deletes succeed"
  log_content="$(cat "${mock_dir}/gcloud.log")"
  assert_ordered_line_patterns "${log_content}" "GCLOUD compute instances delete oc-main" "GCLOUD compute instance-templates delete oc-template" "destroy.sh deletes template after instance"
  assert_ordered_line_patterns "${log_content}" "GCLOUD compute instance-templates delete oc-template" "GCLOUD compute routers nats delete oc-nat" "destroy.sh deletes NAT after template"
  assert_ordered_line_patterns "${log_content}" "GCLOUD compute routers nats delete oc-nat" "GCLOUD compute routers delete oc-router" "destroy.sh deletes router after NAT"
  assert_contains "${RUN_OUTPUT}" "instance:oc-main => succeeded" "destroy.sh summary marks instance deletion succeeded"
  assert_contains "${RUN_OUTPUT}" "template:oc-template => succeeded" "destroy.sh summary marks template deletion succeeded"
  assert_contains "${RUN_OUTPUT}" "nat:oc-nat => succeeded" "destroy.sh summary marks NAT deletion succeeded"
  assert_contains "${RUN_OUTPUT}" "router:oc-router => succeeded" "destroy.sh summary marks router deletion succeeded"

  mock_dir="$(new_mock_env destroy-mixed-failure)"
  run_capture run_with_mock "${mock_dir}" MOCK_DESTROY_FAIL_TEMPLATE_DELETE=true \
    bash "${ROOT_DIR}/scripts/openclaw-gcp/destroy.sh" \
    --project-id hoangnb-openclaw \
    --yes

  assert_status 1 "destroy.sh exits non-zero on mixed-success teardown"
  assert_contains "${RUN_OUTPUT}" "template:oc-template => failed" "destroy.sh summary marks template deletion failed"
  assert_contains "${RUN_OUTPUT}" "nat:oc-nat => succeeded" "destroy.sh continues to NAT deletion after template failure"
  assert_contains "${RUN_OUTPUT}" "router:oc-router => succeeded" "destroy.sh continues to router deletion after template failure"
  assert_contains "${RUN_OUTPUT}" "manual cleanup hint:" "destroy.sh prints manual cleanup hints for failed resources"
  assert_contains "${RUN_OUTPUT}" "Destroy completed with failures." "destroy.sh prints mixed-failure completion banner"

  log_content="$(cat "${mock_dir}/gcloud.log")"
  assert_contains "${log_content}" "GCLOUD compute routers nats delete oc-nat" "destroy.sh still issues NAT delete in mixed-failure run"
  assert_contains "${log_content}" "GCLOUD compute routers delete oc-router" "destroy.sh still issues router delete in mixed-failure run"
}

test_destroy_phase2_extra_resource_contract() {
  local mock_dir
  local log_content
  TESTS_RUN=$((TESTS_RUN + 1))

  mock_dir="$(new_mock_env destroy-phase2-snapshot-mismatch)"
  run_capture run_with_mock "${mock_dir}" \
    MOCK_DESTROY_SNAPSHOT_POLICY_ROWS="some-other-policy" \
    bash "${ROOT_DIR}/scripts/openclaw-gcp/destroy.sh" \
    --project-id hoangnb-openclaw \
    --snapshot-policy-name oc-daily-snapshots \
    --snapshot-policy-disk oc-main \
    --yes
  assert_status 1 "destroy.sh fails closed when named snapshot policy is not attached to the named disk"
  assert_contains "${RUN_OUTPUT}" "Qualification failed [snapshot-policy-attachment]" "destroy.sh reports snapshot attachment predicate failure"
  log_content="$(cat "${mock_dir}/gcloud.log")"
  assert_not_contains "${log_content}" "GCLOUD compute resource-policies delete oc-daily-snapshots" "snapshot attachment mismatch emits no snapshot delete command"
  assert_not_contains "${log_content}" "GCLOUD compute instances delete oc-main" "snapshot attachment mismatch blocks Phase 1 deletes"

  mock_dir="$(new_mock_env destroy-phase2-clone-mismatch)"
  run_capture run_with_mock "${mock_dir}" \
    MOCK_CLONE_INSTANCE_NAME=oc-clone \
    MOCK_DESTROY_CLONE_DISK_ROWS="true false" \
    bash "${ROOT_DIR}/scripts/openclaw-gcp/destroy.sh" \
    --project-id hoangnb-openclaw \
    --clone-instance-name oc-clone \
    --yes
  assert_status 1 "destroy.sh exits non-zero when clone safety predicate fails"
  assert_contains "${RUN_OUTPUT}" "clone-instance:oc-clone => failed (disk predicate mismatch" "destroy.sh reports clone disk safety mismatch in summary"
  log_content="$(cat "${mock_dir}/gcloud.log")"
  assert_not_contains "${log_content}" "GCLOUD compute instances delete oc-clone" "clone mismatch emits no clone delete command"

  mock_dir="$(new_mock_env destroy-phase2-success-order)"
  run_capture run_with_mock "${mock_dir}" \
    MOCK_CLONE_INSTANCE_NAME=oc-clone \
    MOCK_DESTROY_MACHINE_IMAGE_NAME=oc-image-20260324-001 \
    MOCK_DESTROY_MACHINE_IMAGE_DESCRIBE_NAME=oc-image-20260324-001 \
    MOCK_DESTROY_SNAPSHOT_POLICY_NAME=oc-daily-snapshots \
    bash "${ROOT_DIR}/scripts/openclaw-gcp/destroy.sh" \
    --project-id hoangnb-openclaw \
    --snapshot-policy-name oc-daily-snapshots \
    --snapshot-policy-disk oc-main \
    --clone-instance-name oc-clone \
    --machine-image-name oc-image-20260324-001 \
    --yes
  assert_status 0 "destroy.sh succeeds when all explicit Phase 2 extra resources delete cleanly"
  assert_contains "${RUN_OUTPUT}" "snapshot-policy:oc-daily-snapshots => succeeded" "destroy.sh summary marks snapshot policy cleanup succeeded"
  assert_contains "${RUN_OUTPUT}" "clone-instance:oc-clone => succeeded" "destroy.sh summary marks clone cleanup succeeded"
  assert_contains "${RUN_OUTPUT}" "machine-image:oc-image-20260324-001 => succeeded" "destroy.sh summary marks machine image cleanup succeeded"
  log_content="$(cat "${mock_dir}/gcloud.log")"
  assert_ordered_line_patterns "${log_content}" "GCLOUD compute disks remove-resource-policies oc-main" "GCLOUD compute instances delete oc-main" "snapshot detach runs before core instance delete"
  assert_ordered_line_patterns "${log_content}" "GCLOUD compute routers delete oc-router" "GCLOUD compute instances describe oc-clone" "clone cleanup starts after core stack completes"
  assert_ordered_line_patterns "${log_content}" "GCLOUD compute instances delete oc-clone" "GCLOUD compute machine-images describe oc-image-20260324-001" "machine-image cleanup runs after clone cleanup"

  mock_dir="$(new_mock_env destroy-phase2-mixed-failure-continues)"
  run_capture run_with_mock "${mock_dir}" \
    MOCK_CLONE_INSTANCE_NAME=oc-clone \
    MOCK_DESTROY_CLONE_DISK_ROWS="true false" \
    MOCK_DESTROY_MACHINE_IMAGE_NAME=oc-image-20260324-001 \
    MOCK_DESTROY_MACHINE_IMAGE_DESCRIBE_NAME=oc-image-20260324-001 \
    bash "${ROOT_DIR}/scripts/openclaw-gcp/destroy.sh" \
    --project-id hoangnb-openclaw \
    --clone-instance-name oc-clone \
    --machine-image-name oc-image-20260324-001 \
    --yes
  assert_status 1 "destroy.sh mixed extra-resource failure exits non-zero"
  assert_contains "${RUN_OUTPUT}" "clone-instance:oc-clone => failed" "destroy.sh reports clone failure in mixed extra-resource run"
  assert_contains "${RUN_OUTPUT}" "machine-image:oc-image-20260324-001 => succeeded" "destroy.sh still runs later machine-image cleanup after clone failure"
  assert_contains "${RUN_OUTPUT}" "Destroy completed with failures." "destroy.sh prints mixed-failure completion banner for extra-resource failures"
  log_content="$(cat "${mock_dir}/gcloud.log")"
  assert_contains "${log_content}" "GCLOUD compute machine-images delete oc-image-20260324-001" "destroy.sh continues to machine-image delete after clone failure"
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
  test_stack_wrapper_up_status_down_contract
  test_stack_wrapper_state_persists_when_up_fails
  test_stack_wrapper_down_safety_guards
  test_install_help_and_noninteractive_gcloud_guard
  test_install_parser_missing_value_guard
  test_install_prompt_and_nonprompt_behavior
  test_install_readiness_gate_dry_run_contract
  test_install_readiness_probe_retries_fresh_vm_iap_lookup_delay
  test_install_firewall_preflight_predicate
  test_install_cross_zone_existing_instance_guard
  test_install_reuse_eligibility_guardrails
  test_install_repairable_reuse_contract_auto_repairs
  test_install_ssh_handoff_contract_and_failure_summary
  test_cloud_nat_idempotent_flow
  test_repair_instance_bootstrap_flow
  test_repair_instance_bootstrap_rejects_invalid_metadata_values
  test_destroy_help_parser_and_confirmation_contract
  test_destroy_dry_run_contract
  test_destroy_qualification_failures_block_deletes
  test_destroy_delete_order_and_mixed_failure_summary
  test_destroy_phase2_extra_resource_contract
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
