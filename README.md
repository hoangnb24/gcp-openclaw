# OpenClaw on GCP

This repository now centers on a one-line, installer-first operator flow for provisioning or reusing an OpenClaw VM on GCP, validating prerequisites, and handing off to the upstream interactive installer over IAP SSH.

## Quickstart

```bash
bash scripts/openclaw-gcp/install.sh
```

The installer performs local preflight checks, provisions or reuses the VM through the existing template-backed infrastructure path, runs readiness gating, opens an interactive SSH handoff, and launches:

```bash
curl -fsSL https://openclaw.ai/install.sh | bash
```

On successful completion, you remain in the remote VM shell.
If upstream install fails, the wrapper returns locally with a failure summary and exact log retrieval guidance.

## Primary Workflow

- Entry point: `scripts/openclaw-gcp/install.sh`
- Secure defaults: internal-only VM networking, Cloud NAT for egress, IAP for SSH
- Readiness contract: startup sentinel and package-manager-idle gating before installer handoff
- Handoff behavior: PTY-preserving transcript capture and success continuity via `exec bash -il`

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
