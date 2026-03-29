#!/usr/bin/env bash
set -euo pipefail

STARTUP_READY_SENTINEL="/var/lib/openclaw/startup-ready-v1"
STARTUP_LOG_DIR="/var/log/openclaw"
STARTUP_LOG_FILE="${STARTUP_LOG_DIR}/startup-prereqs.log"

install -d -m 0755 "${STARTUP_LOG_DIR}" /var/lib/openclaw
exec > >(tee -a "${STARTUP_LOG_FILE}") 2>&1

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ca-certificates curl

cat >"${STARTUP_READY_SENTINEL}" <<EOF
ready_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
startup_script_source=embedded-vm-prereqs-v1
startup_profile=vm-prereqs-v1
EOF

echo "OpenClaw VM prerequisites are ready."
echo "Readiness sentinel: ${STARTUP_READY_SENTINEL}"
