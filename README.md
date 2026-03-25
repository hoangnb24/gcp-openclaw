# OpenClaw on GCP

This repository provides scripted provisioning, bootstrap, repair, backup, and clone workflows for running OpenClaw on Google Cloud.
The scripts are designed for repeatable operator use with deterministic image resolution, explicit identity mode selection, internal-only VM support, Cloud NAT for egress, and IAP-based access.

The primary deployment flow is:

1. Create a deterministic regional instance template.
2. Create a VM from that template.
3. Reach the VM over `gcloud compute ssh`, typically through IAP.
4. Run the host bootstrap wrapper to seed the OpenClaw checkout, gateway config, and Docker-based CLI.

## Quickstart

Create a baseline template:

```bash
bash scripts/openclaw-gcp/create-template.sh \
  --project-id hoangnb-openclaw \
  --template-name oc-template \
  --region asia-southeast1 \
  --zone asia-southeast1-a \
  --openclaw-tag 2026.3.23 \
  --no-service-account \
  --no-address
```

Create a VM from that template:

```bash
bash scripts/openclaw-gcp/create-instance.sh \
  --project-id hoangnb-openclaw \
  --instance-name oc-main \
  --region asia-southeast1 \
  --zone asia-southeast1-a \
  --no-create-template
```

SSH to the instance and complete the host-side baseline:

```bash
gcloud compute ssh \
  --project hoangnb-openclaw \
  --zone asia-southeast1-a \
  oc-main

openclaw-docker-setup
openclaw status
```

For internal-only templates, instance creation auto-ensures Cloud NAT unless you disable that behavior with `--no-ensure-cloud-nat`.

## What The Repo Includes

- `scripts/openclaw-gcp/create-template.sh`
  Creates a deterministic regional instance template and records the resolved Debian image plus bootstrap metadata.
- `scripts/openclaw-gcp/create-instance.sh`
  Creates a VM from the regional template and auto-ensures Cloud NAT when the template is internal-only.
- `scripts/openclaw-gcp/create-cloud-nat.sh`
  Creates or reuses a Cloud Router and Cloud NAT for outbound access.
- `scripts/openclaw-gcp/repair-instance-bootstrap.sh`
  Refreshes a VM's startup metadata with the embedded bootstrap and can rerun it immediately over SSH.
- `scripts/openclaw-gcp/create-snapshot-policy.sh`
  Creates a recurring snapshot schedule policy and can attach it to a target disk.
- `scripts/openclaw-gcp/create-machine-image.sh`
  Captures a machine image from a known-good VM for rollback or persistent clone workflows.
- `scripts/openclaw-gcp/spawn-from-image.sh`
  Creates a new instance from a machine image, with optional overrides for machine type, subnet, and identity.

## Operator Model

- Region default: `asia-southeast1`
- Zone default: `asia-southeast1-a`
- Machine type default: `e2-standard-2`
- Boot disk default: `pd-balanced`, `30 GiB`
- Access path: internal-only VM with Cloud NAT for egress and IAP for operator SSH
- Template identity mode: explicit choice between `--no-service-account` and `--service-account ... --scopes ...`
- Template image resolution: Debian image family is resolved to a concrete image and written to `.khuym/runtime/openclaw-gcp/resolved-debian-image.txt`

## Host Commands Installed On The VM

The bootstrap installs two operator-facing commands:

- `openclaw-docker-setup`
  Seeds a user-writable checkout under `~/openclaw`, prepares `.env`, reconciles shared permissions on `~/.openclaw`, pre-seeds gateway config, starts `openclaw-gateway`, and runs the non-interactive onboarding baseline.
- `openclaw`
  Runs the OpenClaw CLI through Docker Compose and keeps the gateway started before each CLI invocation.

Useful examples:

```bash
openclaw status
openclaw status --deep
openclaw logs --follow
openclaw security audit
openclaw daemon status
```

`openclaw daemon status` returns Docker-specific guidance for this deployment.
Other `openclaw daemon ...` subcommands are not supported on this host wrapper.

## Command Surface

Every operator script supports `--help`.
Every provisioning and maintenance script supports `--dry-run`.

Important options by script:

- `create-template.sh`
  `--template-name`, `--machine-type`, `--disk-type`, `--disk-size-gb`, `--image-project`, `--image-family`, `--image-name`, `--openclaw-image`, `--openclaw-tag`, `--startup-script-file`, `--startup-script-url`, `--startup-script-sha256`, `--service-account`, `--scopes`, `--no-service-account`, `--no-address`, `--resolution-record`, `--replace-existing`
- `create-instance.sh`
  `--instance-name`, `--template-name`, `--machine-type`, `--disk-type`, `--disk-size-gb`, `--image-project`, `--image-family`, `--image-name`, `--openclaw-image`, `--openclaw-tag`, `--startup-script-file`, `--startup-script-url`, `--startup-script-sha256`, `--service-account`, `--scopes`, `--no-service-account`, `--no-address`, `--ensure-cloud-nat`, `--no-ensure-cloud-nat`, `--network`, `--router-name`, `--nat-name`, `--resolution-record`, `--no-create-template`, `--replace-template`
- `create-cloud-nat.sh`
  `--network`, `--router-name`, `--nat-name`
- `repair-instance-bootstrap.sh`
  `--openclaw-image`, `--openclaw-tag`, `--run-now`, `--no-tunnel-through-iap`
- `create-snapshot-policy.sh`
  `--policy-name`, `--region`, `--zone`, `--start-hour-utc`, `--max-retention-days`, `--on-source-disk-delete`, `--target-disk`, `--target-disk-zone`
- `create-machine-image.sh`
  `--source-instance`, `--source-zone`, `--image-name`, `--image-family`, `--description`, `--storage-location`
- `spawn-from-image.sh`
  `--machine-image`, `--machine-type`, `--subnet`, `--service-account`, `--scopes`

## Guardrails And Behaviors

- `create-template.sh` requires an explicit identity mode.
- `create-template.sh` requires `--openclaw-tag` when creating or replacing a template.
- `create-template.sh` rejects the sentinel tag value `pin-me`.
- `create-template.sh` accepts only one startup script source at a time.
- `create-template.sh` requires `--startup-script-sha256` when `--startup-script-url` is used.
- `create-template.sh` reuses an existing template by default and rejects explicit template-shaping flags that would otherwise be ignored.
- `create-instance.sh` auto-detects whether a reused template is internal-only and ensures Cloud NAT in that case.
- `create-cloud-nat.sh` uses create-if-missing semantics for both the router and NAT.
- `create-snapshot-policy.sh` derives a matching `-a` zone when the region changes and `--zone` is not set.
- `repair-instance-bootstrap.sh` refreshes the VM to the embedded bootstrap version tracked in this repository.

## Documentation

- [Operator runbook](docs/openclaw-gcp/README.md)
- [Backup and restore](docs/openclaw-gcp/backup-and-restore.md)
- [Sizing and cost baselines](docs/openclaw-gcp/sizing-and-cost.md)

## Verification

Run the shell test suite:

```bash
make test
```

This executes `tests/openclaw-gcp/test.sh`, which covers command parsing, guardrails, Cloud NAT behavior, bootstrap metadata refresh, and the embedded startup wrapper expectations.
