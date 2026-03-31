# OpenClaw On GCP Runbook

This runbook documents the primary installer-first workflow for this repository.

## Quickstart

```bash
bash scripts/openclaw-gcp/install.sh
```

The command is interactive by default in a TTY and performs:

1. local prerequisite validation (`gcloud`, auth, project, required APIs, zone/region, IAP SSH firewall candidate)
2. instance create-or-reuse through the template-backed infrastructure path
3. startup-contract readiness gating
4. interactive IAP SSH handoff that launches `curl -fsSL https://openclaw.ai/install.sh | bash`

Success behavior:
- the upstream installer runs in a PTY-preserving SSH session
- when install succeeds, the session continues in the VM shell via `exec bash -il`

Failure behavior:
- the wrapper exits locally with a clear summary
- output includes an exact log retrieval hint for the remote installer log

## Default Operating Profile

- Region: `asia-southeast1`
- Zone: `asia-southeast1-a`
- Machine type: `e2-standard-2`
- Disk: `pd-balanced`, `30 GiB`
- Networking posture: internal-only VM, Cloud NAT egress, IAP SSH ingress

## Key Commands

- `bash scripts/openclaw-gcp/install.sh --help`
- `bash scripts/openclaw-gcp/install.sh --dry-run`

Common explicit inputs:
- `--project-id`
- `--instance-name`
- `--zone`
- `--region`
- `--openclaw-tag` (required in non-interactive runs when creating template-backed resources)

Non-interactive automation:
- pass `--non-interactive` and supply all required flags explicitly
- preflight errors fail before provisioning and include concrete recovery commands

## Destroy Workflow

Use the destroy companion to tear down OpenClaw resources by exact names only.
It does not discover or sweep unrelated/shared infrastructure.

Start with a dry run:

```bash
bash scripts/openclaw-gcp/destroy.sh \
  --project-id <gcp-project-id> \
  --instance-name oc-main \
  --template-name oc-template \
  --router-name oc-router \
  --nat-name oc-nat \
  --dry-run
```

Interactive safety behavior:
- real interactive runs require typing the confirmation token before deletions start
- automation can bypass the prompt with `--yes` (recommended only for controlled CI/ops workflows)

Automation example:

```bash
bash scripts/openclaw-gcp/destroy.sh \
  --project-id <gcp-project-id> \
  --instance-name oc-main \
  --template-name oc-template \
  --router-name oc-router \
  --nat-name oc-nat \
  --yes \
  --non-interactive
```

Optional explicit extra targets (deleted only when named):
- `--snapshot-policy-name <policy>`
- `--snapshot-policy-disk <disk>` with `--snapshot-policy-disk-zone <zone>` when detach context is needed
- `--clone-instance-name <name>` with `--clone-zone <zone>`
- `--machine-image-name <name>`

If any target delete fails, the script continues with remaining explicit targets, exits non-zero, and prints a final summary of succeeded vs failed actions.
Treat that summary as the manual cleanup checklist before considering teardown complete.

## Troubleshooting

Local preflight failures:
- read the emitted `Preflight failed:` message
- run the exact `Recovery:` command shown by the script

Readiness gate failures:
- script prints readiness failure reason
- script prints remote readiness log contract and retrieval hint

Installer handoff failures:
- script prints local failure summary and exact remote installer log retrieval command
- resolve issue remotely, then rerun `install.sh`

## Day-2 Docs

- [Backup and restore](backup-and-restore.md)
- [Sizing and cost baselines](sizing-and-cost.md)

## Compatibility

Legacy infrastructure-oriented script entrypoints remain available for migration and advanced workflows:

- `bash scripts/openclaw-gcp/create-template.sh ...`
- `bash scripts/openclaw-gcp/create-instance.sh ...`
- `bash scripts/openclaw-gcp/bootstrap-openclaw.sh ...`

## Deprecated

The old Docker/bootstrap-first primary workflow is deprecated. Use `bash scripts/openclaw-gcp/install.sh` as the canonical entrypoint.
