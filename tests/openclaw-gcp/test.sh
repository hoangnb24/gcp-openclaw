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
printf 'GCLOUD %s\n' "$*" >>"${LOG_FILE}"

if [[ "$*" == *"compute images describe-from-family"* ]]; then
  printf '%s\n' "${MOCK_IMAGE_NAME:-debian-12-bookworm-v20260310}"
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
  assert_contains "${log_content}" "apt-get install -y docker.io git curl ca-certificates" "embedded startup script installs Docker prerequisites"
  assert_contains "${log_content}" "apt-get install -y docker-compose-plugin" "embedded startup script attempts Docker Compose plugin install"
  assert_contains "${log_content}" "apt-get install -y docker-compose" "embedded startup script falls back to docker-compose package"
  assert_contains "${log_content}" "docker-cli-plugin-metadata" "embedded startup script installs a metadata-aware compose wrapper"
  assert_contains "${log_content}" "/usr/local/lib/docker/cli-plugins/docker-compose" "embedded startup script installs a compose wrapper when needed"
  assert_contains "${log_content}" "git clone --depth 1 --branch \"v\${tag}\" https://github.com/openclaw/openclaw.git" "embedded startup script clones the pinned OpenClaw repo"
  assert_contains "${log_content}" "/usr/local/bin/openclaw-docker-setup" "embedded startup script installs the OpenClaw setup wrapper"
  assert_contains "${log_content}" "/usr/local/bin/openclaw" "embedded startup script installs the OpenClaw CLI wrapper"
  assert_contains "${log_content}" "OPENCLAW_REPO_DIR=\"\$(seed_user_checkout)\"" "embedded wrapper seeds a user checkout before setup"
  assert_contains "${log_content}" "tar -C \"\${source_dir}\" --exclude .git -cf - . | tar -C \"\${temp_dir}\" -xf -" "embedded wrapper copies the staged repo into a user-writable checkout"
  assert_contains "${log_content}" "if ! docker info >/dev/null 2>&1; then" "embedded wrapper checks Docker access before starting setup"
  assert_contains "${log_content}" "exec sg docker -c" "embedded wrapper can self-heal current sessions through the docker group"
  assert_contains "${log_content}" "if [[ \"\${1:-}\" == \"--interactive\" ]]; then" "embedded wrapper keeps an explicit escape hatch to the upstream interactive setup"
  assert_contains "${log_content}" "config set gateway.mode local" "embedded wrapper pre-seeds gateway.mode before starting the gateway"
  assert_contains "${log_content}" "config set gateway.controlUi.allowedOrigins" "embedded wrapper pre-seeds Control UI origins for non-loopback bind"
  assert_contains "${log_content}" "--non-interactive" "embedded wrapper runs non-interactive onboarding by default"
  assert_contains "${log_content}" "--skip-health" "embedded wrapper skips the insecure non-loopback health probe during local LAN onboarding"
  assert_contains "${log_content}" "docker compose up -d openclaw-gateway" "embedded wrapper starts the gateway after pre-seeding config"
  assert_contains "${log_content}" "chown -R \"\${HOST_UID}:\${HOST_GID}\" /host-home/.openclaw" "embedded wrapper repairs host ownership for the operator OpenClaw state directory"
  assert_contains "${log_content}" "Provider auth was skipped intentionally for day-1 bootstrap." "embedded wrapper explains the day-1 auth posture"
  assert_contains "${log_content}" "docker compose run --no-deps --rm openclaw-cli \"\$@\"" "embedded CLI wrapper runs the OpenClaw CLI through Docker Compose"
  assert_contains "${log_content}" "if [[ \"\${1:-}\" == \"daemon\" ]]; then" "embedded CLI wrapper special-cases daemon commands for Docker deployments"
  assert_contains "${log_content}" "systemd daemon commands are not applicable on this host because the gateway is managed by Docker Compose." "embedded CLI wrapper explains daemon-status behavior on Docker"
  assert_not_contains "${log_content}" "cd /opt/openclaw/openclaw" "embedded wrapper no longer runs setup from the staged root-owned repo"
  assert_contains "${log_content}" "OPENCLAW_OWNER=\"root\"" "embedded startup script defaults OpenClaw state ownership to root"
  assert_contains "${log_content}" "OPENCLAW_GROUP=\"root\"" "embedded startup script defaults OpenClaw state group to root"
  assert_contains "${log_content}" "chown \"\${owner_name}:\${group_name}\"" "embedded startup script assigns ownership for OpenClaw state dirs"
  assert_contains "${log_content}" "usermod -aG docker \"\${OPENCLAW_OWNER}\"" "embedded startup script adds the operator user to the docker group"
  assert_contains "${log_content}" "OPENCLAW_HOME=\"/root\"" "embedded startup script falls back to /root"
  assert_not_contains "${log_content}" "/home/root/.openclaw" "embedded startup script no longer writes to /home/root"
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
  assert_contains "${log_content}" "startup_script_source=embedded-openclaw-bootstrap-v9" "repair-instance-bootstrap marks the refreshed bootstrap version"
  assert_contains "${log_content}" "GCLOUD compute ssh oc-main --project hoangnb-openclaw --zone asia-southeast1-a --tunnel-through-iap --command sudo google_metadata_script_runner startup" "repair-instance-bootstrap reruns startup over IAP by default"
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
  test_cloud_nat_idempotent_flow
  test_repair_instance_bootstrap_flow
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
