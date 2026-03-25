#!/usr/bin/env bash
set -euo pipefail

metadata_value() {
  local key="$1"
  curl -fsH "Metadata-Flavor: Google" \
    "http://metadata.google.internal/computeMetadata/v1/instance/attributes/${key}"
}

ensure_docker_compose() {
  if docker compose version >/dev/null 2>&1; then
    return
  fi

  if apt-get install -y docker-compose-plugin; then
    docker compose version >/dev/null 2>&1 && return
  fi

  apt-get install -y docker-compose

  if ! docker compose version >/dev/null 2>&1 && command -v docker-compose >/dev/null 2>&1; then
    install -d -m 0755 /usr/local/lib/docker/cli-plugins
    cat >/usr/local/lib/docker/cli-plugins/docker-compose <<'EOS'
#!/usr/bin/env bash
if [[ "${1:-}" == "docker-cli-plugin-metadata" ]]; then
  cat <<'EOF'
{"SchemaVersion":"0.1.0","Vendor":"OpenClaw GCP bootstrap","Version":"fallback-v1","ShortDescription":"Docker Compose compatibility wrapper"}
EOF
  exit 0
fi
if [[ "${1:-}" == "compose" ]]; then
  shift
fi
exec /usr/bin/docker-compose "$@"
EOS
    chmod 0755 /usr/local/lib/docker/cli-plugins/docker-compose
  fi

  docker compose version >/dev/null 2>&1
}

ensure_openclaw_checkout() {
  local repo_root="/opt/openclaw"
  local repo_dir="${repo_root}/openclaw"
  local tag=""

  install -d -m 0755 "${repo_root}"
  tag="$(metadata_value openclaw_tag || true)"

  if [[ -d "${repo_dir}/.git" ]]; then
    if [[ -n "${tag}" ]]; then
      git -C "${repo_dir}" fetch --depth 1 origin "refs/tags/v${tag}" || true
      if git -C "${repo_dir}" rev-parse -q --verify "FETCH_HEAD^{commit}" >/dev/null 2>&1; then
        git -C "${repo_dir}" checkout -f FETCH_HEAD
        return
      fi
    fi
    git -C "${repo_dir}" fetch --depth 1 origin main
    git -C "${repo_dir}" checkout -f FETCH_HEAD
    return
  fi

  if [[ -n "${tag}" ]] && git clone --depth 1 --branch "v${tag}" https://github.com/openclaw/openclaw.git "${repo_dir}"; then
    return
  fi

  git clone --depth 1 https://github.com/openclaw/openclaw.git "${repo_dir}"
}

install_openclaw_setup_wrapper() {
  cat >/usr/local/bin/openclaw-docker-setup <<'EOS'
#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "openclaw-docker-setup: $*" >&2
  exit 1
}

seed_user_checkout() {
  local source_dir="/opt/openclaw/openclaw"
  local repo_dir="${OPENCLAW_REPO_DIR:-${HOME}/openclaw}"
  local parent_dir=""
  local temp_dir=""

  [[ -d "${source_dir}" ]] || die "missing staged repo: ${source_dir}"

  if [[ -x "${repo_dir}/scripts/docker/setup.sh" ]]; then
    printf '%s\n' "${repo_dir}"
    return
  fi

  if [[ -e "${repo_dir}" ]]; then
    die "existing path is not a usable OpenClaw checkout: ${repo_dir}"
  fi

  parent_dir="$(dirname "${repo_dir}")"
  install -d -m 0755 "${parent_dir}"
  temp_dir="$(mktemp -d "${parent_dir}/.openclaw-repo.XXXXXX")"
  trap 'rm -rf "${temp_dir}"' EXIT

  tar -C "${source_dir}" --exclude .git -cf - . | tar -C "${temp_dir}" -xf -
  mv "${temp_dir}" "${repo_dir}"
  trap - EXIT

  printf '%s\n' "${repo_dir}"
}

read_env_value() {
  local file_path="$1"
  local key="$2"
  local line=""

  [[ -f "${file_path}" ]] || return 0

  while IFS= read -r line || [[ -n "${line}" ]]; do
    if [[ "${line}" == "${key}="* ]]; then
      printf '%s\n' "${line#*=}"
      return 0
    fi
  done <"${file_path}"
}

ensure_user_openclaw_dirs() {
  local host_uid=""
  local host_gid=""

  host_uid="$(id -u)"
  host_gid="$(id -g)"

  docker run --rm \
    --user root \
    -e HOST_UID="${host_uid}" \
    -e HOST_GID="${host_gid}" \
    -v "${HOME}:/host-home" \
    --entrypoint sh \
    "${OPENCLAW_IMAGE}" \
    -c 'mkdir -p /host-home/.openclaw /host-home/.openclaw/workspace /host-home/.openclaw/identity /host-home/.openclaw/agents/main/agent /host-home/.openclaw/agents/main/sessions && chown -R "${HOST_UID}:${HOST_GID}" /host-home/.openclaw'
}

ensure_gateway_token() {
  local env_path="$1"
  local existing_token=""

  existing_token="$(read_env_value "${env_path}" OPENCLAW_GATEWAY_TOKEN || true)"
  if [[ -n "${existing_token}" ]]; then
    printf '%s\n' "${existing_token}"
    return 0
  fi

  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 32
    return 0
  fi

  python3 - <<'PY'
import secrets
print(secrets.token_hex(32))
PY
}

upsert_env() {
  local file_path="$1"
  shift
  local -a entries=("$@")
  local tmp_path=""
  local line=""
  local key=""
  local entry=""
  local replaced="false"
  local seen=" "

  tmp_path="$(mktemp)"

  if [[ -f "${file_path}" ]]; then
    while IFS= read -r line || [[ -n "${line}" ]]; do
      key="${line%%=*}"
      replaced="false"
      for entry in "${entries[@]}"; do
        if [[ "${key}" == "${entry%%=*}" ]]; then
          printf '%s\n' "${entry}" >>"${tmp_path}"
          seen="${seen}${key} "
          replaced="true"
          break
        fi
      done

      if [[ "${replaced}" != "true" ]]; then
        printf '%s\n' "${line}" >>"${tmp_path}"
      fi
    done <"${file_path}"
  fi

  for entry in "${entries[@]}"; do
    key="${entry%%=*}"
    if [[ "${seen}" != *" ${key} "* ]]; then
      printf '%s\n' "${entry}" >>"${tmp_path}"
    fi
  done

  mv "${tmp_path}" "${file_path}"
}

OPENCLAW_IMAGE_VALUE="$(curl -fsH "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/attributes/openclaw_image" || true)"
OPENCLAW_TAG_VALUE="$(curl -fsH "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/attributes/openclaw_tag" || true)"

if [[ -n "${OPENCLAW_IMAGE_VALUE}" && -n "${OPENCLAW_TAG_VALUE}" ]]; then
  export OPENCLAW_IMAGE="${OPENCLAW_IMAGE_VALUE}:${OPENCLAW_TAG_VALUE}"
fi

OPENCLAW_REPO_DIR="$(seed_user_checkout)"
OPENCLAW_CONFIG_DIR="${OPENCLAW_CONFIG_DIR:-${HOME}/.openclaw}"
OPENCLAW_WORKSPACE_DIR="${OPENCLAW_WORKSPACE_DIR:-${OPENCLAW_CONFIG_DIR}/workspace}"
OPENCLAW_GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
OPENCLAW_BRIDGE_PORT="${OPENCLAW_BRIDGE_PORT:-18790}"
OPENCLAW_GATEWAY_BIND="${OPENCLAW_GATEWAY_BIND:-lan}"

if ! docker info >/dev/null 2>&1; then
  if [[ "${OPENCLAW_DOCKER_GROUP_ACTIVATED:-}" != "1" ]] && id -nG "${USER}" 2>/dev/null | tr ' ' '\n' | grep -Fx docker >/dev/null 2>&1; then
    export OPENCLAW_DOCKER_GROUP_ACTIVATED=1

    quoted_self="$(printf '%q' "$0")"
    quoted_repo="$(printf '%q' "${OPENCLAW_REPO_DIR}")"
    quoted_home="$(printf '%q' "${HOME}")"
    quoted_user="$(printf '%q' "${USER}")"
    quoted_image="$(printf '%q' "${OPENCLAW_IMAGE:-}")"
    quoted_config_dir="$(printf '%q' "${OPENCLAW_CONFIG_DIR}")"
    quoted_workspace_dir="$(printf '%q' "${OPENCLAW_WORKSPACE_DIR}")"
    quoted_gateway_port="$(printf '%q' "${OPENCLAW_GATEWAY_PORT}")"
    quoted_bridge_port="$(printf '%q' "${OPENCLAW_BRIDGE_PORT}")"
    quoted_gateway_bind="$(printf '%q' "${OPENCLAW_GATEWAY_BIND}")"
    quoted_args=""
    if [[ $# -gt 0 ]]; then
      printf -v quoted_args ' %q' "$@"
    fi

    exec sg docker -c "export HOME=${quoted_home} USER=${quoted_user} OPENCLAW_REPO_DIR=${quoted_repo} OPENCLAW_IMAGE=${quoted_image} OPENCLAW_CONFIG_DIR=${quoted_config_dir} OPENCLAW_WORKSPACE_DIR=${quoted_workspace_dir} OPENCLAW_GATEWAY_PORT=${quoted_gateway_port} OPENCLAW_BRIDGE_PORT=${quoted_bridge_port} OPENCLAW_GATEWAY_BIND=${quoted_gateway_bind} OPENCLAW_DOCKER_GROUP_ACTIVATED=1 && exec ${quoted_self}${quoted_args}"
  fi

  die "docker access is not ready for user ${USER}. Rerun the instance bootstrap so it can attach the operator to the docker group."
fi

cd "${OPENCLAW_REPO_DIR}"

if [[ "${1:-}" == "--interactive" ]]; then
  shift
  exec ./scripts/docker/setup.sh "$@"
fi

ENV_FILE="${OPENCLAW_REPO_DIR}/.env"
OPENCLAW_GATEWAY_TOKEN="$(ensure_gateway_token "${ENV_FILE}")"
export OPENCLAW_IMAGE OPENCLAW_CONFIG_DIR OPENCLAW_WORKSPACE_DIR OPENCLAW_GATEWAY_PORT OPENCLAW_BRIDGE_PORT OPENCLAW_GATEWAY_BIND OPENCLAW_GATEWAY_TOKEN

ensure_user_openclaw_dirs

upsert_env "${ENV_FILE}" \
  "OPENCLAW_CONFIG_DIR=${OPENCLAW_CONFIG_DIR}" \
  "OPENCLAW_WORKSPACE_DIR=${OPENCLAW_WORKSPACE_DIR}" \
  "OPENCLAW_GATEWAY_PORT=${OPENCLAW_GATEWAY_PORT}" \
  "OPENCLAW_BRIDGE_PORT=${OPENCLAW_BRIDGE_PORT}" \
  "OPENCLAW_GATEWAY_BIND=${OPENCLAW_GATEWAY_BIND}" \
  "OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN}" \
  "OPENCLAW_IMAGE=${OPENCLAW_IMAGE}"

echo "==> Fixing data-directory permissions"
docker run --rm \
  --user root \
  -e HOME=/home/node \
  -v "${OPENCLAW_CONFIG_DIR}:/home/node/.openclaw" \
  -v "${OPENCLAW_WORKSPACE_DIR}:/home/node/.openclaw/workspace" \
  --entrypoint sh \
  "${OPENCLAW_IMAGE}" \
  -c 'find /home/node/.openclaw -xdev -exec chown node:node {} +; [ -d /home/node/.openclaw/workspace/.openclaw ] && chown -R node:node /home/node/.openclaw/workspace/.openclaw || true'

echo "==> Pre-seeding gateway config"
docker run --rm \
  -e HOME=/home/node \
  -v "${OPENCLAW_CONFIG_DIR}:/home/node/.openclaw" \
  -v "${OPENCLAW_WORKSPACE_DIR}:/home/node/.openclaw/workspace" \
  --entrypoint openclaw \
  "${OPENCLAW_IMAGE}" \
  config set gateway.mode local >/dev/null

docker run --rm \
  -e HOME=/home/node \
  -v "${OPENCLAW_CONFIG_DIR}:/home/node/.openclaw" \
  -v "${OPENCLAW_WORKSPACE_DIR}:/home/node/.openclaw/workspace" \
  --entrypoint openclaw \
  "${OPENCLAW_IMAGE}" \
  config set gateway.bind "${OPENCLAW_GATEWAY_BIND}" >/dev/null

if [[ "${OPENCLAW_GATEWAY_BIND}" != "loopback" ]]; then
  ALLOWED_ORIGIN_JSON="$(printf '["http://127.0.0.1:%s"]' "${OPENCLAW_GATEWAY_PORT}")"
  docker run --rm \
    -e HOME=/home/node \
    -v "${OPENCLAW_CONFIG_DIR}:/home/node/.openclaw" \
    -v "${OPENCLAW_WORKSPACE_DIR}:/home/node/.openclaw/workspace" \
    --entrypoint openclaw \
    "${OPENCLAW_IMAGE}" \
    config set gateway.controlUi.allowedOrigins "${ALLOWED_ORIGIN_JSON}" --strict-json >/dev/null
fi

CLI_RUN_IDS="$(docker ps -aq --filter name=openclaw_openclaw-cli_run || true)"
if [[ -n "${CLI_RUN_IDS}" ]]; then
  docker rm -f ${CLI_RUN_IDS} >/dev/null 2>&1 || true
fi

docker compose rm -sf openclaw-gateway >/dev/null 2>&1 || true

echo "==> Starting gateway"
docker compose up -d openclaw-gateway >/dev/null

echo "==> Onboarding (non-interactive baseline)"
ONBOARD_ARGS=(
  --mode local
  --no-install-daemon
  --non-interactive
  --accept-risk
  --auth-choice skip
  --skip-channels
  --skip-search
  --skip-skills
  --skip-ui
  --gateway-auth token
  --gateway-bind "${OPENCLAW_GATEWAY_BIND}"
  --gateway-token "${OPENCLAW_GATEWAY_TOKEN}"
  --json
)

if [[ "${OPENCLAW_GATEWAY_BIND}" != "loopback" ]]; then
  ONBOARD_ARGS+=(--skip-health)
fi

docker compose run --rm openclaw-cli onboard "${ONBOARD_ARGS[@]}"

echo "==> Gateway health"
if curl -fsS "http://127.0.0.1:${OPENCLAW_GATEWAY_PORT}/healthz" >/dev/null 2>&1; then
  echo "Gateway health check passed on http://127.0.0.1:${OPENCLAW_GATEWAY_PORT}/healthz"
else
  echo "Gateway health check is still warming up; retry curl http://127.0.0.1:${OPENCLAW_GATEWAY_PORT}/healthz in a few seconds."
fi

echo "OpenClaw baseline is ready."
echo "Provider auth was skipped intentionally for day-1 bootstrap."
echo "Use openclaw-docker-setup --interactive later if you want the full upstream setup flow."
EOS
  chmod 0755 /usr/local/bin/openclaw-docker-setup
}

install_openclaw_cli_wrapper() {
  cat >/usr/local/bin/openclaw <<'EOS'
#!/usr/bin/env bash
set -euo pipefail

if ! docker info >/dev/null 2>&1; then
  if [[ "${OPENCLAW_DOCKER_GROUP_ACTIVATED:-}" != "1" ]] && id -nG "${USER}" 2>/dev/null | tr ' ' '\n' | grep -Fx docker >/dev/null 2>&1; then
    quoted_self="$(printf '%q' "$0")"
    quoted_home="$(printf '%q' "${HOME}")"
    quoted_user="$(printf '%q' "${USER}")"
    quoted_args=""
    if [[ $# -gt 0 ]]; then
      printf -v quoted_args ' %q' "$@"
    fi
    exec sg docker -c "export HOME=${quoted_home} USER=${quoted_user} OPENCLAW_DOCKER_GROUP_ACTIVATED=1 && exec ${quoted_self}${quoted_args}"
  fi

  echo "openclaw: docker access is not ready for user ${USER}" >&2
  exit 1
fi

OPENCLAW_REPO_DIR="${OPENCLAW_REPO_DIR:-${HOME}/openclaw}"
if [[ ! -x "${OPENCLAW_REPO_DIR}/scripts/docker/setup.sh" ]]; then
  /usr/local/bin/openclaw-docker-setup >/dev/null
fi

cd "${OPENCLAW_REPO_DIR}"
docker compose up -d openclaw-gateway >/dev/null

if [[ "${1:-}" == "daemon" ]]; then
  subcommand="${2:-status}"
  case "${subcommand}" in
    status)
      echo "OpenClaw Docker deployment"
      echo
      echo "systemd daemon commands are not applicable on this host because the gateway is managed by Docker Compose."
      echo
      docker ps --format "table {{.Names}}\t{{.Status}}" | sed -n '1,10p'
      echo
      if curl -fsS http://127.0.0.1:18789/healthz >/dev/null 2>&1; then
        echo "Gateway health: live"
      else
        echo "Gateway health: unavailable"
      fi
      echo "Use 'openclaw status' for app-level status."
      echo "Use 'docker logs --tail 100 openclaw_openclaw-gateway_1' for gateway logs."
      exit 0
      ;;
    *)
      echo "openclaw daemon ${subcommand}: not supported on the Docker deployment" >&2
      echo "Use 'openclaw status' or inspect 'openclaw_openclaw-gateway_1' with docker." >&2
      exit 1
      ;;
  esac
fi

exec docker compose run --no-deps --rm openclaw-cli "$@"
EOS
  chmod 0755 /usr/local/bin/openclaw
}

ensure_openclaw_state_dirs() {
  local openclaw_home="$1"
  local owner_name="$2"
  local group_name="$3"

  install -d -m 0755 "${openclaw_home}/.openclaw" "${openclaw_home}/.openclaw/workspace"
  chown "${owner_name}:${group_name}" "${openclaw_home}/.openclaw" "${openclaw_home}/.openclaw/workspace"
}

install -d -m 0755 /var/log/openclaw
exec > >(tee -a /var/log/openclaw/bootstrap.log) 2>&1

apt-get update -y
apt-get install -y docker.io git curl ca-certificates
ensure_docker_compose
systemctl enable --now docker

install -d -m 0755 /opt/openclaw
ensure_openclaw_checkout
install_openclaw_setup_wrapper
install_openclaw_cli_wrapper

OPENCLAW_HOME="/root"
OPENCLAW_OWNER="root"
OPENCLAW_GROUP="root"
if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
  RESOLVED_HOME="$(getent passwd "${SUDO_USER}" | cut -d: -f6 || true)"
  if [[ -n "${RESOLVED_HOME}" ]]; then
    OPENCLAW_HOME="${RESOLVED_HOME}"
    OPENCLAW_OWNER="${SUDO_USER}"
    OPENCLAW_GROUP="$(id -gn "${SUDO_USER}")"
  fi
fi

ensure_openclaw_state_dirs "${OPENCLAW_HOME}" "${OPENCLAW_OWNER}" "${OPENCLAW_GROUP}"

if [[ "${OPENCLAW_OWNER}" != "root" ]]; then
  usermod -aG docker "${OPENCLAW_OWNER}"
fi

echo "OpenClaw bootstrap baseline is installed."
echo "Docker Compose is available via: $(docker compose version --short 2>/dev/null || echo plugin-wrapper)"
echo "OpenClaw repo is available at /opt/openclaw/openclaw"
echo "Run openclaw-docker-setup to seed a user-writable checkout under \$HOME/openclaw and complete the non-interactive local baseline."
echo "Run openclaw <command> to execute the CLI through Docker after baseline setup."
echo "Pass --interactive if you explicitly want the upstream interactive Docker setup flow."
echo "The bootstrap attaches the operator user to the docker group for future sessions, and the wrapper self-heals current sessions through sg docker when needed."
echo "Inject runtime credentials after boot using Secret Manager or operator auth."
