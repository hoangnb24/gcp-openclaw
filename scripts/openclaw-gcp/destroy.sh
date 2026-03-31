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

require_typed_confirmation

echo
echo "Confirmation gate passed."
echo "Phase 1 scaffold complete: qualification and teardown execution are handled in subsequent stories."
