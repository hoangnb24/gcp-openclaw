#!/usr/bin/env bash
set -euo pipefail

OPENCLAW_STACK_TOOL="openclaw-gcp"
OPENCLAW_STACK_LABEL_MANAGED_KEY="openclaw_managed"
OPENCLAW_STACK_LABEL_STACK_KEY="openclaw_stack_id"
OPENCLAW_STACK_LABEL_TOOL_KEY="openclaw_tool"
OPENCLAW_STACK_LABEL_LIFECYCLE_KEY="openclaw_lifecycle"
OPENCLAW_STACK_DEFAULT_LIFECYCLE="persistent"
OPENCLAW_STACK_RESOURCE_PREFIX="oc"
OPENCLAW_STACK_MAX_ID_LEN="40"
OPENCLAW_STACK_LOG_SOURCE_READINESS="readiness"
OPENCLAW_STACK_LOG_SOURCE_INSTALL="install"
OPENCLAW_STACK_LOG_SOURCE_BOOTSTRAP="bootstrap"
OPENCLAW_STACK_LOG_SOURCE_GATEWAY="gateway"

oc_stack_die() {
  echo "Error: $*" >&2
  exit 1
}

oc_stack_normalize_id() {
  local raw="${1:-}"
  local normalized
  normalized="$(printf '%s' "${raw}" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9-]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')"

  [[ -n "${normalized}" ]] || return 1
  [[ "${normalized}" =~ ^[a-z] ]] || normalized="s-${normalized}"
  if ((${#normalized} > OPENCLAW_STACK_MAX_ID_LEN)); then
    normalized="${normalized:0:OPENCLAW_STACK_MAX_ID_LEN}"
    normalized="${normalized%-}"
  fi

  [[ "${normalized}" =~ ^[a-z][a-z0-9-]*$ ]] || return 1
  printf '%s\n' "${normalized}"
}

oc_stack_require_id() {
  local raw="${1:-}"
  local normalized
  normalized="$(oc_stack_normalize_id "${raw}")" || oc_stack_die "invalid stack ID '${raw}'"
  printf '%s\n' "${normalized}"
}

oc_stack_instance_name() {
  local stack_id
  stack_id="$(oc_stack_require_id "${1:-}")"
  printf '%s-%s\n' "${OPENCLAW_STACK_RESOURCE_PREFIX}" "${stack_id}"
}

oc_stack_template_name() {
  local stack_id
  stack_id="$(oc_stack_require_id "${1:-}")"
  printf '%s-%s-template\n' "${OPENCLAW_STACK_RESOURCE_PREFIX}" "${stack_id}"
}

oc_stack_router_name() {
  local stack_id
  stack_id="$(oc_stack_require_id "${1:-}")"
  printf '%s-%s-router\n' "${OPENCLAW_STACK_RESOURCE_PREFIX}" "${stack_id}"
}

oc_stack_nat_name() {
  local stack_id
  stack_id="$(oc_stack_require_id "${1:-}")"
  printf '%s-%s-nat\n' "${OPENCLAW_STACK_RESOURCE_PREFIX}" "${stack_id}"
}

oc_stack_labels_csv() {
  local stack_id lifecycle
  stack_id="$(oc_stack_require_id "${1:-}")"
  lifecycle="${2:-${OPENCLAW_STACK_DEFAULT_LIFECYCLE}}"
  printf '%s=true,%s=%s,%s=%s,%s=%s\n' \
    "${OPENCLAW_STACK_LABEL_MANAGED_KEY}" \
    "${OPENCLAW_STACK_LABEL_STACK_KEY}" "${stack_id}" \
    "${OPENCLAW_STACK_LABEL_TOOL_KEY}" "${OPENCLAW_STACK_TOOL}" \
    "${OPENCLAW_STACK_LABEL_LIFECYCLE_KEY}" "${lifecycle}"
}

oc_stack_state_dir() {
  printf '%s\n' "${HOME}/.config/openclaw-gcp"
}

oc_stack_state_file() {
  printf '%s/current-stack.env\n' "$(oc_stack_state_dir)"
}

oc_stack_state_ensure_dir() {
  mkdir -p "$(oc_stack_state_dir)"
}

oc_stack_state_write_current() {
  local stack_id project_id region zone lifecycle state_file temp_file
  stack_id="$(oc_stack_require_id "${1:-}")"
  project_id="${2:-}"
  region="${3:-}"
  zone="${4:-}"
  lifecycle="${5:-${OPENCLAW_STACK_DEFAULT_LIFECYCLE}}"
  state_file="$(oc_stack_state_file)"
  temp_file="${state_file}.tmp"

  oc_stack_state_ensure_dir
  cat >"${temp_file}" <<EOF
# openclaw-gcp local convenience state
CURRENT_STACK_ID=${stack_id}
LAST_PROJECT_ID=${project_id}
LAST_REGION=${region}
LAST_ZONE=${zone}
LIFECYCLE=${lifecycle}
EOF
  mv "${temp_file}" "${state_file}"
}

oc_stack_state_exists() {
  [[ -f "$(oc_stack_state_file)" ]]
}

oc_stack_state_get() {
  local key="${1:-}" state_file value
  [[ -n "${key}" ]] || oc_stack_die "missing state key"
  state_file="$(oc_stack_state_file)"
  [[ -f "${state_file}" ]] || return 1
  value="$(awk -F= -v k="${key}" '$1==k {print substr($0, index($0,"=")+1)}' "${state_file}" | tail -n1)"
  [[ -n "${value}" ]] || return 1
  printf '%s\n' "${value}"
}

oc_stack_state_get_or_empty() {
  local key="${1:-}" value=""
  if value="$(oc_stack_state_get "${key}" 2>/dev/null)"; then
    printf '%s\n' "${value}"
    return 0
  fi
  printf '\n'
}

oc_stack_state_clear_current_if_matches() {
  local stack_id state_file current_stack_id temp_file
  stack_id="$(oc_stack_require_id "${1:-}")"
  state_file="$(oc_stack_state_file)"
  [[ -f "${state_file}" ]] || return 0

  current_stack_id="$(oc_stack_state_get_or_empty CURRENT_STACK_ID)"
  [[ "${current_stack_id}" == "${stack_id}" ]] || return 0

  temp_file="${state_file}.tmp"
  cat >"${temp_file}" <<EOF
# openclaw-gcp local convenience state
CURRENT_STACK_ID=
LAST_PROJECT_ID=$(oc_stack_state_get_or_empty LAST_PROJECT_ID)
LAST_REGION=$(oc_stack_state_get_or_empty LAST_REGION)
LAST_ZONE=$(oc_stack_state_get_or_empty LAST_ZONE)
LIFECYCLE=
EOF
  mv "${temp_file}" "${state_file}"
}

oc_stack_is_cloud_shell() {
  [[ "${CLOUD_SHELL:-}" == "true" ]]
}

oc_stack_is_interactive_session() {
  [[ -t 0 && -t 1 ]]
}

oc_stack_print_contract() {
  local stack_id lifecycle
  stack_id="$(oc_stack_require_id "${1:-}")"
  lifecycle="${2:-${OPENCLAW_STACK_DEFAULT_LIFECYCLE}}"

  cat <<EOF
stack_id=${stack_id}
instance_name=$(oc_stack_instance_name "${stack_id}")
template_name=$(oc_stack_template_name "${stack_id}")
router_name=$(oc_stack_router_name "${stack_id}")
nat_name=$(oc_stack_nat_name "${stack_id}")
labels=$(oc_stack_labels_csv "${stack_id}" "${lifecycle}")
state_file=$(oc_stack_state_file)
EOF
}

oc_stack_log_sources_space_list() {
  printf '%s\n' \
    "${OPENCLAW_STACK_LOG_SOURCE_READINESS} ${OPENCLAW_STACK_LOG_SOURCE_INSTALL} ${OPENCLAW_STACK_LOG_SOURCE_BOOTSTRAP} ${OPENCLAW_STACK_LOG_SOURCE_GATEWAY}"
}

oc_stack_log_sources_csv() {
  printf '%s\n' \
    "${OPENCLAW_STACK_LOG_SOURCE_READINESS},${OPENCLAW_STACK_LOG_SOURCE_INSTALL},${OPENCLAW_STACK_LOG_SOURCE_BOOTSTRAP},${OPENCLAW_STACK_LOG_SOURCE_GATEWAY}"
}

oc_stack_require_log_source() {
  local raw="${1:-}"
  local normalized=""
  normalized="$(printf '%s' "${raw}" | tr '[:upper:]' '[:lower:]')"

  case "${normalized}" in
    "${OPENCLAW_STACK_LOG_SOURCE_READINESS}"|\
    "${OPENCLAW_STACK_LOG_SOURCE_INSTALL}"|\
    "${OPENCLAW_STACK_LOG_SOURCE_BOOTSTRAP}"|\
    "${OPENCLAW_STACK_LOG_SOURCE_GATEWAY}")
      printf '%s\n' "${normalized}"
      return 0
      ;;
  esac

  oc_stack_die "unsupported logs source '${raw}'. Supported sources: $(oc_stack_log_sources_csv)"
}
