# OpenClaw on GCP

This repository now centers on a Cloud-Shell-first operator flow for provisioning or reusing an OpenClaw VM on GCP, validating prerequisites, and handing off to the upstream interactive installer over IAP SSH.

## Cloud Shell Quickstart

[![Open in Cloud Shell](https://gstatic.com/cloudssh/images/open-btn.svg)](https://console.cloud.google.com/cloudshell/open?cloudshell_git_repo=https://github.com/hoangnb24/gcp-openclaw&cloudshell_workspace=gcp-openclaw&cloudshell_tutorial=docs/openclaw-gcp/cloud-shell-quickstart.md)

Use the button above to open this repo in Google Cloud Shell with a repo-hosted tutorial.
The tutorial and welcome flow are non-mutating and guide you toward the Phase 1 stack-native path:

```bash
bash scripts/openclaw-gcp/cloudshell-welcome.sh
```

For full browser-first flow details, see [Cloud Shell quickstart](docs/openclaw-gcp/cloud-shell-quickstart.md).

## Direct Installer Entry

The existing installer entrypoint remains available directly:

```bash
bash scripts/openclaw-gcp/install.sh
```

The installer performs local preflight checks, provisions or reuses the VM through the existing template-backed infrastructure path, runs readiness gating, opens an interactive SSH handoff, and launches the upstream OpenClaw installer.

## Primary Workflow

- Browser-first entrypoint: official `Open in Cloud Shell` URL + `scripts/openclaw-gcp/cloudshell-welcome.sh`
- Direct operator entrypoint: `scripts/openclaw-gcp/install.sh`
- Secure defaults: internal-only VM networking, Cloud NAT for egress, IAP for SSH
- Readiness contract: startup sentinel and package-manager-idle gating before installer handoff
- Handoff behavior: PTY-preserving transcript capture and success continuity via `exec bash -il`

## Destroy Companion

Use the repo-native destroy companion to plan or run teardown for the exact resources you name.
The script does not do broad discovery, and `--dry-run` is the safe first step before any real deletion.

```bash
bash scripts/openclaw-gcp/destroy.sh \
  --project-id <gcp-project-id> \
  --instance-name oc-main \
  --template-name oc-template \
  --router-name oc-router \
  --nat-name oc-nat \
  --dry-run
```

For full teardown guidance, optional extras (snapshot policy, clone instance, machine image), and confirmation behavior, use the [OpenClaw GCP operator runbook](docs/openclaw-gcp/README.md).

## Day-2 Operations

- [Operator runbook](docs/openclaw-gcp/README.md)
- [Backup and restore](docs/openclaw-gcp/backup-and-restore.md)
- [Sizing and cost baselines](docs/openclaw-gcp/sizing-and-cost.md)

## Verification

Run the repository test suite:

```bash
make test
```

## Compatibility

Legacy infrastructure-oriented scripts are still available for advanced or migration use, but they are no longer the primary quickstart path:

- `scripts/openclaw-gcp/create-template.sh`
- `scripts/openclaw-gcp/create-instance.sh`
- `scripts/openclaw-gcp/bootstrap-openclaw.sh`

## Deprecated

The former Docker/bootstrap-first operator story is deprecated in favor of the installer-first flow above.
