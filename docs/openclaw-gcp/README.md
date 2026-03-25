# OpenClaw on GCP

This repo provides a scripted, repeatable way to run OpenClaw on Google Cloud.
The current operator baseline is validated against project `hoangnb-openclaw` in region `asia-southeast1`.

This document is the day-1 operator runbook for:

- creating a deterministic baseline VM
- reaching an internal-only VM through IAP
- bootstrapping Docker and OpenClaw without manual drift
- recovering a partially configured VM with a repair script
- capturing backups and long-lived clones

It is aligned with the locked decisions in [CONTEXT.md](../../history/openclaw-gcp-instance-strategy/CONTEXT.md) and the approved implementation approach in [approach.md](../../history/openclaw-gcp-instance-strategy/approach.md).

## Scope

This repo is responsible for VM provisioning and operator runbooks.
It does not commit provider secrets, `.env` files, or OpenClaw application data.

## Tested Baseline

- Project: `hoangnb-openclaw`
- Region: `asia-southeast1`
- Zone: `asia-southeast1-a`
- Machine type: `e2-standard-2`
- Disk: `pd-balanced`, `30 GiB`
- OS: Debian 12
- OpenClaw image: `ghcr.io/openclaw/openclaw:2026.3.23`
- Networking: internal-only VM with Cloud NAT for egress and IAP for operator access

This is the recommended default for a personal, always-on OpenClaw instance with moderate daily usage.

## Sizing Guidance

- `e2-micro` is not suitable.
- `e2-small` is an emergency minimum, not a good steady-state choice.
- `e2-medium` is acceptable for lighter workloads or short-term cost pressure.
- `e2-standard-2` is the default and the currently validated profile.
- Move to `e2-standard-4` when CPU or RAM pressure is sustained.

## Why This Flow Exists

The scripts in `scripts/openclaw-gcp/` intentionally cover the parts that were painful to do manually:

- deterministic Debian image resolution
- explicit template identity mode
- internal-only VM creation
- automatic Cloud NAT for internal-only templates
- Docker and Docker Compose installation
- staging the OpenClaw repo on the VM
- a host `openclaw-docker-setup` command for baseline setup
- a host `openclaw` command that runs the OpenClaw CLI through Docker
- repair of stale `~/.openclaw` ownership from older container-created state

The goal is that operators do not need to keep re-learning one-off fixes.

## Access Model

This setup assumes:

- no external IP on the VM
- outbound internet through Cloud NAT
- inbound operator access through `gcloud compute ssh` with IAP

If your org blocks external IPs, this is the intended path.

## Scripts

Baseline scripts:

- `create-template.sh`
- `create-instance.sh`
- `create-cloud-nat.sh`
- `repair-instance-bootstrap.sh`

Backup and clone scripts:

- `create-snapshot-policy.sh`
- `create-machine-image.sh`
- `spawn-from-image.sh`

## Key Options

The most important operator-facing flags are:

- `create-template.sh`
  - `--no-service-account`
  - `--service-account ... --scopes ...`
  - `--no-address`
  - `--startup-script-file ...`
  - `--startup-script-url ... --startup-script-sha256 ...`
  - `--replace-existing`
  - `--dry-run`
- `create-instance.sh`
  - `--no-create-template`
  - `--replace-template`
  - `--ensure-cloud-nat`
  - `--no-ensure-cloud-nat`
  - `--no-address`
  - `--dry-run`
- `create-cloud-nat.sh`
  - `--network`
  - `--router-name`
  - `--nat-name`
  - `--dry-run`
- `repair-instance-bootstrap.sh`
  - `--run-now`
  - `--no-tunnel-through-iap`
  - `--dry-run`
- `create-machine-image.sh`
  - `--image-family`
  - `--storage-location`
  - `--dry-run`
- `spawn-from-image.sh`
  - `--machine-type`
  - `--subnet`
  - `--service-account`
  - `--scopes`
  - `--dry-run`
- `create-snapshot-policy.sh`
  - `--target-disk`
  - `--target-disk-zone`
  - `--start-hour-utc`
  - `--max-retention-days`
  - `--dry-run`

## Prerequisites

Before running the scripts locally:

- install and authenticate `gcloud`
- select or pass the correct project
- ensure Compute Engine API is enabled
- ensure you have permission to create templates, VMs, routers, and NAT
- ensure IAP TCP forwarding is allowed for your operator account if the VM is internal-only

## Day-1 Baseline

### 1. Create the template

Use an explicit OpenClaw image tag and an explicit identity choice.

```bash
bash scripts/openclaw-gcp/create-template.sh \
  --project-id hoangnb-openclaw \
  --region asia-southeast1 \
  --zone asia-southeast1-a \
  --openclaw-image ghcr.io/openclaw/openclaw \
  --openclaw-tag 2026.3.23 \
  --no-service-account \
  --no-address
```

What this does:

- resolves a concrete Debian 12 image
- creates a regional instance template
- embeds the OpenClaw bootstrap startup script
- creates an internal-only template when `--no-address` is used

### 2. Create the VM

```bash
bash scripts/openclaw-gcp/create-instance.sh \
  --project-id hoangnb-openclaw \
  --instance-name oc-main \
  --region asia-southeast1 \
  --zone asia-southeast1-a \
  --no-create-template
```

For an internal-only template, `create-instance.sh` auto-ensures Cloud NAT unless you explicitly disable that behavior.

### 3. SSH into the VM

```bash
gcloud compute ssh \
  --project hoangnb-openclaw \
  --zone asia-southeast1-a \
  oc-main
```

If the instance has no external IP, `gcloud` will automatically fall back to IAP tunneling.

### 4. Run the baseline setup on the VM

From the VM shell:

```bash
openclaw-docker-setup
```

What this does automatically:

- uses a user-writable checkout under `~/openclaw`
- repairs stale ownership under `~/.openclaw` if an older run left it owned by container UID `1000`
- writes or reuses the local `.env`
- pre-seeds required gateway config for local LAN bind
- starts the gateway in the correct order
- runs a non-interactive day-1 onboarding pass with `auth-choice=skip`

This is the supported default.

If you explicitly want the upstream interactive Docker setup flow instead, run:

```bash
openclaw-docker-setup --interactive
```

### 5. Check the installation

From the VM shell:

```bash
openclaw status
```

You should see a status table with a reachable local gateway.

You can also verify the health endpoint directly:

```bash
curl -fsS http://127.0.0.1:18789/healthz
```

Expected response:

```json
{"ok":true,"status":"live"}
```

For this Docker-based deployment, do not use `openclaw daemon status` as the primary health check.
That upstream command is aimed at systemd-style daemon installs, while this runbook uses Docker Compose for the gateway.
The host wrapper handles `openclaw daemon status` with Docker-specific guidance.

## What Gets Installed on the VM

The embedded bootstrap installs:

- Docker
- Docker Compose support
- `git`
- `curl`
- `ca-certificates`
- a staged OpenClaw checkout under `/opt/openclaw/openclaw`
- `openclaw-docker-setup` under `/usr/local/bin`
- `openclaw` under `/usr/local/bin`

It also adds the operator user to the `docker` group and self-heals current sessions through `sg docker` when needed.

## Repair Flow

Use the repair script when:

- startup script behavior changed in this repo
- the VM was created before Cloud NAT existed
- Docker bootstrap partially ran and needs to be reapplied
- the host wrappers need to be refreshed

Run locally:

```bash
bash scripts/openclaw-gcp/repair-instance-bootstrap.sh \
  --project-id hoangnb-openclaw \
  --instance-name oc-main \
  --zone asia-southeast1-a \
  --openclaw-tag 2026.3.23 \
  --run-now
```

This updates the VM metadata to the embedded bootstrap in this repo and immediately reruns the startup script over SSH.

Use `--no-tunnel-through-iap` only when your SSH path does not require IAP.

## Host Commands on the VM

The VM exposes two host-level commands after bootstrap:

- `openclaw-docker-setup`
  - completes the baseline Docker setup
  - repairs stale `~/.openclaw` ownership
  - pre-seeds gateway config
  - starts the gateway and runs a non-interactive onboard pass
- `openclaw`
  - runs the OpenClaw CLI through the Docker deployment
  - is the preferred entrypoint for day-2 CLI operations

Examples:

```bash
openclaw status
openclaw status --deep
openclaw logs --follow
openclaw security audit
openclaw daemon status
```

## Internal-Only Networking Notes

For the internal-only path:

- the VM does not need an external IPv4 address
- operator access happens through IAP
- package installs and image pulls rely on Cloud NAT

If a VM was created before Cloud NAT was available, rerun the repair flow above.

If you ever need to create NAT explicitly, use:

```bash
bash scripts/openclaw-gcp/create-cloud-nat.sh \
  --project-id hoangnb-openclaw \
  --region asia-southeast1
```

## Security Notes

Current baseline rules:

- do not pass provider secrets through template metadata
- do not store long-lived secrets in this repo
- inject runtime credentials after boot through operator auth, service account access, or Secret Manager
- use `--no-service-account` unless the VM truly needs GCP API access

OpenClaw-specific note:

- the current validated baseline uses `gateway.bind=lan`
- `openclaw status` reports a warning if `gateway.auth.rateLimit` is not configured

That warning is real.
Before exposing the gateway beyond a trusted boundary, configure auth rate limiting and complete any provider-specific hardening you need.

Recommended next hardening step:

- set `gateway.auth.rateLimit` in `~/.openclaw/openclaw.json`
- rerun `openclaw status` or `openclaw security audit`

## Provider Auth

The day-1 bootstrap intentionally uses:

- `auth-choice=skip`
- no channel setup
- no provider login

That means the baseline gets the gateway and workspace into a healthy state first.
Provider authentication is a separate step after the VM is healthy.

## Backups

### Snapshot policy

Create a daily snapshot policy:

```bash
bash scripts/openclaw-gcp/create-snapshot-policy.sh \
  --project-id hoangnb-openclaw \
  --policy-name oc-daily-snapshots \
  --region asia-southeast1 \
  --start-hour-utc 18 \
  --max-retention-days 14
```

Attach it to a disk:

```bash
bash scripts/openclaw-gcp/create-snapshot-policy.sh \
  --project-id hoangnb-openclaw \
  --policy-name oc-daily-snapshots \
  --region asia-southeast1 \
  --target-disk oc-main \
  --target-disk-zone asia-southeast1-a
```

## Persistent Clones

Use machine images only for long-lived full-environment clones.
Do not use them as a replacement for deterministic baseline rebuilds.

### Capture a machine image

Before capture:

1. Remove local provider tokens and temporary credentials.
2. Remove or rotate any user-managed service account keys on disk.
3. Remove `.env` or secret files that should not be inherited.
4. Confirm the source VM still boots and runs OpenClaw correctly.

Then capture:

```bash
bash scripts/openclaw-gcp/create-machine-image.sh \
  --project-id hoangnb-openclaw \
  --source-instance oc-main \
  --source-zone asia-southeast1-a \
  --image-name oc-image-20260324-001
```

### Spawn a clone

```bash
bash scripts/openclaw-gcp/spawn-from-image.sh \
  --project-id hoangnb-openclaw \
  --instance-name oc-clone-a \
  --machine-image oc-image-20260324-001 \
  --zone us-central1-a
```

After clone creation:

1. Re-auth providers intentionally.
2. Reinject credentials intentionally.
3. Do not assume secrets inherited from the source are still valid or appropriate.
4. Validate service health before production use.

## Rerun and Drift Behavior

- `create-instance.sh` can create the template on first run and reuse it later.
- `--replace-template` intentionally rebuilds the template.
- template-shaping flags against an existing template without `--replace-template` are rejected instead of ignored
- `repair-instance-bootstrap.sh` is the supported way to refresh existing VMs after bootstrap changes

## Troubleshooting

### `Missing required argument [--no-scopes]`

If you use `--no-service-account`, the scripts pass `--no-scopes` automatically.
If you still see this, rerun with the scripts in this repo.

### Org policy blocks external IPs

Use:

- `--no-address`
- IAP for SSH
- Cloud NAT for outbound package and image access

### `docker: command not found` or Docker service missing

Run the repair flow:

```bash
bash scripts/openclaw-gcp/repair-instance-bootstrap.sh \
  --project-id hoangnb-openclaw \
  --instance-name oc-main \
  --zone asia-southeast1-a \
  --openclaw-tag 2026.3.23 \
  --run-now
```

### `openclaw-docker-setup` says permission denied under `~/.openclaw`

That stale ownership case is handled automatically by the wrapper.
If you still hit it, rerun the repair flow so the wrapper on the VM matches this repo.

### `openclaw` says command not found

The host `openclaw` wrapper is installed by the bootstrap.
If it is missing, rerun the repair flow.

### `openclaw daemon status` looks systemd-specific

That command is intercepted by the host wrapper for this Docker deployment.
Use it as a Docker health summary only.
For application-level checks, use `openclaw status`.

## Current Recommendation

For `hoangnb-openclaw` today:

1. keep `asia-southeast1` as the default region
2. keep `e2-standard-2` as the default size
3. keep the VM internal-only with IAP + Cloud NAT
4. use `openclaw-docker-setup` for baseline recovery instead of manual tweaking
5. use `openclaw status` from the VM shell to confirm health
