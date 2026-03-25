# OpenClaw On GCP

This repository provides a repeatable operator workflow for running OpenClaw on Google Cloud with deterministic template creation, Docker-based host wrappers, internal-only networking, Cloud NAT for egress, and IAP for operator access.

The deployment model centers on a regional instance template plus a small set of maintenance scripts:

- deterministic template creation
- VM creation from a regional template
- automatic Cloud NAT handling for internal-only templates
- host bootstrap and repair through embedded startup metadata
- recurring disk snapshots
- machine-image capture and clone workflows

Reference planning materials live in:

- [CONTEXT.md](../../history/openclaw-gcp-instance-strategy/CONTEXT.md)
- [discovery.md](../../history/openclaw-gcp-instance-strategy/discovery.md)
- [approach.md](../../history/openclaw-gcp-instance-strategy/approach.md)

## Scope

This repository covers VM provisioning, bootstrap, repair, backup, and clone runbooks.
It does not store provider secrets, `.env` files, or OpenClaw application data.

## Baseline Defaults

- Project example: `hoangnb-openclaw`
- Region default: `asia-southeast1`
- Zone default: `asia-southeast1-a`
- Machine type default: `e2-standard-2`
- Disk default: `pd-balanced`, `30 GiB`
- OS default: Debian 12
- Template networking default: supports both external-IP and internal-only paths
- Recommended networking posture: internal-only VM with Cloud NAT for egress and IAP for SSH

## Why This Flow Exists

The scripts in `scripts/openclaw-gcp/` cover the operational steps that are easy to drift when done manually:

- resolving a concrete Debian image from a family
- recording the resolved image and bootstrap metadata in `.khuym/runtime/openclaw-gcp/resolved-debian-image.txt`
- enforcing explicit template identity mode
- creating internal-only templates with `--no-address`
- ensuring Cloud NAT for internal-only templates
- installing Docker plus Docker Compose compatibility
- staging the OpenClaw repo on the VM
- installing host-level `openclaw-docker-setup` and `openclaw` wrappers
- repairing host and container access to `~/.openclaw`

## Script Inventory

Provisioning and networking:

- `create-template.sh`
- `create-instance.sh`
- `create-cloud-nat.sh`
- `repair-instance-bootstrap.sh`

Backup and clone workflows:

- `create-snapshot-policy.sh`
- `create-machine-image.sh`
- `spawn-from-image.sh`

Every operator script supports `-h` and `--help`.
Every provisioning and maintenance command supports `--dry-run`.

## Quickstart

### 1. Create the template

Use an explicit identity mode and pin the OpenClaw tag.

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

This flow:

- resolves a concrete Debian image
- records the resolved image, bootstrap source, and identity mode
- creates a regional instance template
- embeds the bootstrap script into instance metadata
- creates an internal-only template when `--no-address` is used

Identity mode is always explicit:

- use `--no-service-account` for instances that do not need GCP API access
- use `--service-account ... --scopes ...` when the VM needs API access

Template guardrails:

- `--openclaw-tag` is required when creating or replacing a template
- the sentinel value `pin-me` is rejected
- `--startup-script-file` and `--startup-script-url` are mutually exclusive
- `--startup-script-url` requires `--startup-script-sha256`
- existing templates are reused by default
- explicit template-shaping flags against a reused template are rejected unless `--replace-existing` is used

### 2. Create the VM

```bash
bash scripts/openclaw-gcp/create-instance.sh \
  --project-id hoangnb-openclaw \
  --instance-name oc-main \
  --region asia-southeast1 \
  --zone asia-southeast1-a \
  --no-create-template
```

For internal-only templates, `create-instance.sh` ensures Cloud NAT automatically unless you pass `--no-ensure-cloud-nat`.

This script supports three common modes:

- create the template and the VM in one run
- reuse an existing template with `--no-create-template`
- rebuild the template first with `--replace-template`

When template creation is enabled, template-shaping options are forwarded through the same interface:

- `--machine-type`, `--disk-type`, `--disk-size-gb`
- `--image-project`, `--image-family`, `--image-name`
- `--openclaw-image`, `--openclaw-tag`
- `--startup-script-file`, `--startup-script-url`, `--startup-script-sha256`
- `--service-account`, `--scopes`, `--no-service-account`
- `--no-address`

Cloud NAT overrides:

- `--ensure-cloud-nat`
- `--no-ensure-cloud-nat`
- `--network`
- `--router-name`
- `--nat-name`

### 3. Reach the VM

```bash
gcloud compute ssh \
  --project hoangnb-openclaw \
  --zone asia-southeast1-a \
  oc-main
```

For internal-only instances, `gcloud` uses IAP tunneling.

### 4. Run the host baseline

From the VM shell:

```bash
openclaw-docker-setup
```

The host wrapper:

- seeds a user-writable checkout under `~/openclaw`
- reuses `/opt/openclaw/openclaw` as the staged source checkout
- prepares `~/.openclaw`, `workspace`, `identity`, and session directories
- writes or reuses `.env`
- pre-seeds `gateway.mode=local`
- pre-seeds `gateway.bind`
- sets `gateway.controlUi.allowedOrigins` when the bind mode is not `loopback`
- starts `openclaw-gateway`
- runs `openclaw-cli onboard` in non-interactive mode with gateway token auth
- reapplies shared permissions to `~/.openclaw` after onboarding

The wrapper uses container ownership plus ACLs for shared runtime state:

- `~/.openclaw` is created with container UID/GID ownership for runtime-managed files
- the host operator account receives read/write ACL access
- default ACLs are applied to directories so future files remain writable to both host and container users

If the operator is in the `docker` group, the wrapper can self-heal the active shell session through `sg docker`.

### 5. Verify the installation

From the VM shell:

```bash
openclaw status
```

You can also verify the gateway directly:

```bash
curl -fsS http://127.0.0.1:18789/healthz
```

Expected response:

```json
{"ok":true,"status":"live"}
```

`openclaw daemon status` is supported as a Docker-aware status summary on this host.
Other `openclaw daemon ...` subcommands are not supported in this deployment model.

## Host Commands On The VM

### `openclaw-docker-setup`

This is the supported baseline command for the Docker deployment.

Behavior:

- ensures Docker access for the current user
- seeds a user checkout under `${OPENCLAW_REPO_DIR:-$HOME/openclaw}`
- prepares `${OPENCLAW_CONFIG_DIR:-$HOME/.openclaw}`
- prepares `${OPENCLAW_WORKSPACE_DIR:-$HOME/.openclaw/workspace}`
- persists gateway configuration in `.env`
- starts the gateway before CLI onboarding
- performs non-interactive onboarding with:
  - `--mode local`
  - `--no-install-daemon`
  - `--non-interactive`
  - `--accept-risk`
  - `--auth-choice skip`
  - `--skip-channels`
  - `--skip-search`
  - `--skip-skills`
  - `--skip-ui`
  - `--gateway-auth token`

Interactive escape hatch:

```bash
openclaw-docker-setup --interactive
```

Any arguments after `--interactive` are passed through to the upstream `scripts/docker/setup.sh`.

Environment overrides honored by the wrapper:

- `OPENCLAW_REPO_DIR`
- `OPENCLAW_CONFIG_DIR`
- `OPENCLAW_WORKSPACE_DIR`
- `OPENCLAW_GATEWAY_PORT`
- `OPENCLAW_BRIDGE_PORT`
- `OPENCLAW_GATEWAY_BIND`

### `openclaw`

This wrapper keeps the Docker Compose deployment as the CLI entrypoint on the VM.

Behavior:

- seeds the baseline automatically if the user checkout is missing
- ensures `openclaw-gateway` is up before each CLI invocation
- runs the CLI through `docker compose run --no-deps --rm openclaw-cli`
- intercepts `openclaw daemon status` and returns Docker-specific health guidance

Examples:

```bash
openclaw status
openclaw status --deep
openclaw logs --follow
openclaw security audit
openclaw daemon status
```

## Command Reference

### `create-template.sh`

Core options:

- `--project-id`
- `--template-name`
- `--region`
- `--zone`
- `--machine-type`
- `--disk-type`
- `--disk-size-gb`
- `--image-project`
- `--image-family`
- `--image-name`
- `--openclaw-image`
- `--openclaw-tag`
- `--startup-script-file`
- `--startup-script-url`
- `--startup-script-sha256`
- `--service-account`
- `--scopes`
- `--no-service-account`
- `--no-address`
- `--resolution-record`
- `--replace-existing`
- `--dry-run`

Operational notes:

- `--image-name` overrides family resolution
- `--no-service-account` implies `--no-scopes` in the generated `gcloud` command
- the template metadata records `openclaw_image`, `openclaw_tag`, `startup_script_source`, and the resolved Debian image name
- `--resolution-record` writes the resolved image and bootstrap inputs to disk for later reuse checks

### `create-instance.sh`

Core options:

- `--project-id`
- `--instance-name`
- `--template-name`
- `--region`
- `--zone`
- `--machine-type`
- `--disk-type`
- `--disk-size-gb`
- `--image-project`
- `--image-family`
- `--image-name`
- `--openclaw-image`
- `--openclaw-tag`
- `--startup-script-file`
- `--startup-script-url`
- `--startup-script-sha256`
- `--service-account`
- `--scopes`
- `--no-service-account`
- `--no-address`
- `--ensure-cloud-nat`
- `--no-ensure-cloud-nat`
- `--network`
- `--router-name`
- `--nat-name`
- `--resolution-record`
- `--no-create-template`
- `--replace-template`
- `--dry-run`

Operational notes:

- the instance is created from `projects/<project>/regions/<region>/instanceTemplates/<template>`
- with `--no-create-template`, the script inspects the existing template to decide whether Cloud NAT is required
- with `--replace-template`, the template is recreated before the VM is created

### `create-cloud-nat.sh`

Core options:

- `--project-id`
- `--region`
- `--network`
- `--router-name`
- `--nat-name`
- `--dry-run`

Operational notes:

- both the router and NAT are created with create-if-missing semantics
- reruns reuse existing resources cleanly

### `repair-instance-bootstrap.sh`

Core options:

- `--project-id`
- `--instance-name`
- `--zone`
- `--openclaw-image`
- `--openclaw-tag`
- `--run-now`
- `--no-tunnel-through-iap`
- `--dry-run`

Operational notes:

- refreshes instance metadata with the embedded bootstrap script from this repository
- updates `startup_script_source` metadata to the embedded bootstrap version tracked by the repo
- `--run-now` triggers `sudo google_metadata_script_runner startup` over SSH immediately after the metadata update

Example:

```bash
bash scripts/openclaw-gcp/repair-instance-bootstrap.sh \
  --project-id hoangnb-openclaw \
  --instance-name oc-main \
  --zone asia-southeast1-a \
  --openclaw-tag 2026.3.23 \
  --run-now
```

### `create-snapshot-policy.sh`

Core options:

- `--project-id`
- `--policy-name`
- `--region`
- `--zone`
- `--start-hour-utc`
- `--max-retention-days`
- `--on-source-disk-delete`
- `--target-disk`
- `--target-disk-zone`
- `--dry-run`

Operational notes:

- valid `--on-source-disk-delete` values are `KEEP_AUTO_SNAPSHOTS` and `APPLY_RETENTION_POLICY`
- when `--region` changes and `--zone` is not set, the script derives `<region>-a`
- a target disk can be attached in the same invocation

### `create-machine-image.sh`

Core options:

- `--project-id`
- `--source-instance`
- `--source-zone`
- `--image-name`
- `--image-family`
- `--description`
- `--storage-location`
- `--dry-run`

Operational notes:

- `--image-name` defaults to `oc-image-<utc-timestamp>`
- `--image-family` records an `openclaw-family=<value>` label for grouping and latest-in-family workflows

### `spawn-from-image.sh`

Core options:

- `--project-id`
- `--instance-name`
- `--machine-image`
- `--zone`
- `--machine-type`
- `--subnet`
- `--service-account`
- `--scopes`
- `--dry-run`

Operational notes:

- use this flow for persistent clone creation
- re-auth or reinject credentials intentionally after clone creation

## Internal-Only Networking

For the internal-only path:

- use `--no-address` on template creation
- use IAP for SSH access
- use Cloud NAT for package downloads and image pulls

You can create or refresh NAT explicitly with:

```bash
bash scripts/openclaw-gcp/create-cloud-nat.sh \
  --project-id hoangnb-openclaw \
  --region asia-southeast1
```

## Security Posture

Baseline security rules:

- do not pass provider secrets through template metadata
- do not commit runtime secrets to this repository
- inject runtime credentials after boot through operator auth, Secret Manager, or service-account-based access
- use `--no-service-account` unless the instance needs GCP API access

The baseline onboarding flow intentionally skips provider auth.
The gateway and workspace come up first, then provider access is configured as a separate operator action.

## Rerun And Drift Behavior

- `create-template.sh` reuses existing templates by default
- `create-template.sh --replace-existing` recreates the template
- `create-instance.sh --replace-template` rebuilds the template before creating the VM
- `repair-instance-bootstrap.sh` is the supported path for refreshing existing VMs when bootstrap behavior changes

## Troubleshooting

### `Missing required argument [--no-scopes]`

`create-template.sh` and `create-instance.sh` pass `--no-scopes` automatically when `--no-service-account` is selected.

### Org policy blocks external IPs

Use:

- `--no-address`
- IAP for SSH
- Cloud NAT for outbound package and image access

### `docker: command not found` or Docker service is missing

Refresh the instance bootstrap:

```bash
bash scripts/openclaw-gcp/repair-instance-bootstrap.sh \
  --project-id hoangnb-openclaw \
  --instance-name oc-main \
  --zone asia-southeast1-a \
  --openclaw-tag 2026.3.23 \
  --run-now
```

### `openclaw-docker-setup` reports permission errors under `~/.openclaw`

The wrapper reconciles shared state by restoring container ownership and reapplying host ACLs for the operator account.
If the local wrapper is older than the repository version, rerun the repair flow so the VM metadata and installed wrapper match the repository.

Typical failure shape:

- `EACCES: permission denied, open '/home/node/.openclaw/openclaw.json....tmp'`

### `openclaw` is missing on the VM

The bootstrap installs `/usr/local/bin/openclaw`.
Rerun the repair flow if it is missing.

### `openclaw daemon status` looks systemd-oriented

This host wrapper intercepts `openclaw daemon status` and translates it into a Docker deployment summary.
Use `openclaw status` for application-level checks.

## Recommended Operating Profile

For the default deployment profile:

1. Use `asia-southeast1`.
2. Use `e2-standard-2`.
3. Keep the VM internal-only with IAP plus Cloud NAT.
4. Use `openclaw-docker-setup` for baseline recovery instead of manual drift.
5. Use `openclaw status` and `curl -fsS http://127.0.0.1:18789/healthz` for health verification.
