#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WRAPPER_PATH="${REPO_ROOT}/bin/openclaw-gcp"

STACK_ID=""
ASSUME_YES="false"
NON_INTERACTIVE="false"
CURRENT_PROJECT_ID=""

print_help() {
  cat <<EOF
Usage: $(basename "$0") [options]

Cloud Shell-first welcome flow for OpenClaw on GCP.
This script is non-mutating guidance only.

Options:
  --stack-id <id>      Stack ID to use for the next up command
  --yes                In interactive mode, run the up command immediately if available
  --non-interactive    Do not prompt; require --stack-id
  -h, --help           Show help
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

is_interactive_session() {
  [[ -t 0 && -t 1 ]]
}

resolve_current_project_id() {
  local value=""
  if command -v gcloud >/dev/null 2>&1; then
    value="$(gcloud config get-value project 2>/dev/null || true)"
    [[ "${value}" == "(unset)" ]] && value=""
  fi
  printf '%s\n' "${value}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stack-id)
      require_option_value "$1" "${2-}"
      STACK_ID="$2"
      shift 2
      ;;
    --yes)
      ASSUME_YES="true"
      shift
      ;;
    --non-interactive)
      NON_INTERACTIVE="true"
      shift
      ;;
    -h|--help)
      print_help
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

if [[ "${NON_INTERACTIVE}" == "false" ]] && ! is_interactive_session; then
  NON_INTERACTIVE="true"
fi

if [[ -z "${STACK_ID}" ]]; then
  if [[ "${NON_INTERACTIVE}" == "true" ]]; then
    die "missing required --stack-id in non-interactive mode"
  fi
  read -r -p "Choose your stack ID (for example: team-dev): " STACK_ID
  [[ -n "${STACK_ID}" ]] || die "stack ID cannot be empty"
fi

CURRENT_PROJECT_ID="$(resolve_current_project_id)"

cat <<EOF
OpenClaw GCP Cloud Shell Welcome
===============================
This welcome flow is non-mutating. It only prepares your next step.

Selected stack ID: ${STACK_ID}

Next command:
  ./bin/openclaw-gcp up --stack-id ${STACK_ID}

This stack ID becomes your explicit operator identity for the Phase 1 flow.
This flow expects an existing accessible GCP project.
It does not create GCP projects for you.
Current gcloud project: ${CURRENT_PROJECT_ID:-not set}
Set one now with:
  gcloud config set project <PROJECT_ID>
Or pass it explicitly to up:
  ./bin/openclaw-gcp up --stack-id ${STACK_ID} --project-id <PROJECT_ID>
After a real up run, the current stack pointer is stored at:
  $HOME/.config/openclaw-gcp/current-stack.env
That file is convenience state for Cloud Shell. The durable ownership truth remains the GCP labels on the stack's instance/template anchors.
EOF

if [[ -x "${WRAPPER_PATH}" ]]; then
  if [[ "${NON_INTERACTIVE}" == "true" ]]; then
    if [[ "${ASSUME_YES}" == "true" ]]; then
      exec "${WRAPPER_PATH}" up --stack-id "${STACK_ID}"
    fi
    exit 0
  fi

  if [[ "${ASSUME_YES}" == "true" ]]; then
    exec "${WRAPPER_PATH}" up --stack-id "${STACK_ID}"
  fi

  read -r -p "Run this command now? [y/N]: " run_now
  case "${run_now}" in
    y|Y|yes|YES)
      exec "${WRAPPER_PATH}" up --stack-id "${STACK_ID}"
      ;;
    *)
      ;;
  esac
fi
