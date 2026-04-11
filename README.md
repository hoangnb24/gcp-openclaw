# OpenClaw on GCP

Cloud Shell is the primary operator terminal for OpenClaw on GCP.
The main operator flow is:

`Open in Cloud Shell -> welcome -> up -> status -> ssh/logs -> down`

## Cloud Shell Quickstart

[![Open in Cloud Shell](https://gstatic.com/cloudssh/images/open-btn.svg)](https://shell.cloud.google.com/cloudshell/editor?cloudshell_git_repo=https://github.com/hoangnb24/gcp-openclaw&cloudshell_git_branch=main&cloudshell_workspace=.&cloudshell_tutorial=docs/openclaw-gcp/cloud-shell-quickstart.md&show=ide%2Cterminal)

The official Cloud Shell launch above clones this repo, opens the repo workspace, and launches the repo-hosted quickstart tutorial.
It does not auto-provision anything.

For branch-specific validation, use the same URL and replace `cloudshell_git_branch=main` with the branch you want to open.
For example: `cloudshell_git_branch=<branch-name>`.

If you are testing with the `cloudshell_open` helper inside Cloud Shell instead of the browser URL, keep the workspace at repo root:
`--open_workspace "."`

In Cloud Shell, the happy path is:

```bash
./bin/openclaw-gcp welcome
./bin/openclaw-gcp up --stack-id my-stack
./bin/openclaw-gcp status
./bin/openclaw-gcp ssh
./bin/openclaw-gcp logs --source readiness
./bin/openclaw-gcp down
```

`welcome` prints the next `up` command and can chain directly into it when you confirm or pass `--yes`.
`up` uses your stack ID to derive the VM, template, router, and NAT names automatically and then delegates to the existing install engine underneath.
`down` delegates to the existing destroy engine, but only after verifying that the stack's labeled GCP anchors match the stack you asked for.
`ssh` and `logs` use the same stack-selection and anchor-verification safety model as `status` and stay on IAP-backed `gcloud compute ssh`.
This workflow expects an existing accessible GCP project and does not create projects for you.
Set one with `gcloud config set project <PROJECT_ID>` or pass `--project-id <PROJECT_ID>` to `up`.

For the full Cloud Shell walkthrough, see [Cloud Shell quickstart](docs/openclaw-gcp/cloud-shell-quickstart.md).

## Stack Model

The stack is the unit of ownership.
You name the stack once, and the wrapper derives the raw GCP resource names for you:

- VM instance: `oc-<stack-id>`
- Instance template: `oc-<stack-id>-template`
- Cloud Router: `oc-<stack-id>-router`
- Cloud NAT: `oc-<stack-id>-nat`

The wrapper applies these labels on labelable resources in the bring-up path:

- `openclaw_managed=true`
- `openclaw_stack_id=<stack-id>`
- `openclaw_tool=openclaw-gcp`
- `openclaw_lifecycle=persistent`

Those labels on the instance/template anchors are the durable ownership truth.
Router and NAT stay deterministic companion resources derived from the stack ID because the current CLI path here does not expose label flags there.

## What Persists In Cloud Shell

This repo stores a small convenience pointer at `~/.config/openclaw-gcp/current-stack.env`.
That file remembers the current stack plus the last-known project, region, and zone so the next `status` and interactive Cloud Shell `down` can stay simple.

In normal Cloud Shell usage, `$HOME` is persistent, so that file usually survives when you come back later.
But Cloud Shell itself is still a temporary VM, `gcloud` tab preferences do not persist by default, and ephemeral Cloud Shell sessions can discard local state entirely.

That is why local state stays convenience-only and teardown verifies labeled GCP anchors first.
`status` includes recovery-aware behavior:
- if exactly one trustworthy label candidate exists, `status` recovers that stack and repairs `current-stack.env`
- if multiple candidates exist, recovery fails closed and requires `--stack-id`
- if context is insufficient (for example no project context), `status` tells you exactly what input is missing

## Primary Commands

```bash
./bin/openclaw-gcp welcome
```

Cloud Shell guidance entrypoint.
It asks for a stack ID in interactive mode, shows the next `up` command, and can chain directly into `up` when you confirm or pass `--yes`.
It also reminds you that the flow expects an existing GCP project and shows the current `gcloud` project if one is already set.

```bash
./bin/openclaw-gcp up --stack-id my-stack
```

Primary bring-up path.
On first use, you must name the stack explicitly.
After that, the wrapper remembers the current stack in local Cloud Shell state.

```bash
./bin/openclaw-gcp status
```

Shows the current or explicit stack, the local convenience state, and whether the stack's GCP anchors exist with matching OpenClaw labels.
When local state is missing or stale, `status` runs project-scoped label recovery and clearly distinguishes recovered, ambiguous, and insufficient-context outcomes.

```bash
./bin/openclaw-gcp status --json
```

Machine-readable view of the same truth as human `status` on successful status resolution.
The JSON includes additive `context`, `state`, and `recovery` sections so automation can inspect resolved status results directly.

```bash
./bin/openclaw-gcp ssh
```

Opens IAP-backed SSH only after verified labeled anchors confirm the stack identity.
Fail-closed rules stay explicit: missing project context, missing instance anchor, or mismatched anchors stop the command.

```bash
./bin/openclaw-gcp logs --source <name>
```

Fetches named remote logs over the same verified IAP path.
Supported sources are exact and closed: `readiness`, `install`, `bootstrap`, `gateway`.
Each source returns the most recent 200 lines from its mapped remote log surface.
Unsupported or unavailable sources return non-zero with explicit messages.

```bash
./bin/openclaw-gcp down
```

Interactive Cloud Shell convenience path for the remembered current stack.
Outside interactive Cloud Shell sessions, use `--stack-id` explicitly.

## Command Options

- `welcome` supports `--stack-id <id>`, `--yes`, and `--non-interactive`.
- `up` supports `--stack-id`, `--project-id`, `--region`, `--zone`, `--lifecycle`, plus install passthrough flags such as `--openclaw-tag`, `--openclaw-image`, `--service-account`, `--scopes`, `--no-service-account`, `--allow-external-ip`, `--interactive`, `--non-interactive`, and `--dry-run`.
- `status` supports `--stack-id`, `--project-id`, `--region`, `--zone`, `--lifecycle`, and `--json`.
- `ssh` supports `--stack-id`, `--project-id`, `--region`, `--zone`, and SSH passthrough args after `--`.
- `logs` supports `--source <name>`, `--stack-id`, `--project-id`, `--region`, and `--zone`.
- `down` supports `--stack-id`, `--project-id`, `--region`, `--zone`, `--lifecycle`, `--network`, `--dry-run`, `--yes`, `--interactive`, `--non-interactive`, and exact-name cleanup extras such as `--snapshot-policy-name`, `--snapshot-policy-disk`, `--snapshot-policy-disk-zone`, `--clone-instance-name`, `--clone-zone`, and `--machine-image-name`.

## Safety Properties

- `up` uses the existing preflight checks, create-or-reuse logic, readiness gating, repair path, and a SHA-256-pinned upstream installer handoff from [`scripts/openclaw-gcp/install.sh`](scripts/openclaw-gcp/install.sh).
- `ssh` and `logs` require stack-anchor verification and keep the IAP-only remote access posture.
- `down` uses the existing exact-name qualification checks, deterministic delete ordering, typed confirmation, and dry-run behavior from [`scripts/openclaw-gcp/destroy.sh`](scripts/openclaw-gcp/destroy.sh).
- The wrapper refuses to tear down if the labeled instance/template anchors do not match the requested stack, and destructive project targeting prefers explicit or live project context over remembered local state.

## Direct Engines

The thin product layer is intentionally layered over the existing scripts, not a rewrite.
These lower-level entrypoints are available for advanced or migration workflows:

- [`scripts/openclaw-gcp/install.sh`](scripts/openclaw-gcp/install.sh)
- [`scripts/openclaw-gcp/destroy.sh`](scripts/openclaw-gcp/destroy.sh)
- [`scripts/openclaw-gcp/create-instance.sh`](scripts/openclaw-gcp/create-instance.sh)
- [`scripts/openclaw-gcp/create-template.sh`](scripts/openclaw-gcp/create-template.sh)
- [`scripts/openclaw-gcp/repair-instance-bootstrap.sh`](scripts/openclaw-gcp/repair-instance-bootstrap.sh)
- [`scripts/openclaw-gcp/create-cloud-nat.sh`](scripts/openclaw-gcp/create-cloud-nat.sh)
- [`scripts/openclaw-gcp/create-snapshot-policy.sh`](scripts/openclaw-gcp/create-snapshot-policy.sh)
- [`scripts/openclaw-gcp/create-machine-image.sh`](scripts/openclaw-gcp/create-machine-image.sh)
- [`scripts/openclaw-gcp/spawn-from-image.sh`](scripts/openclaw-gcp/spawn-from-image.sh)

## Operator Docs

- [OpenClaw GCP runbook](docs/openclaw-gcp/README.md)
- [Cloud Shell quickstart](docs/openclaw-gcp/cloud-shell-quickstart.md)
- [Backup and restore](docs/openclaw-gcp/backup-and-restore.md)
- [Sizing and cost baselines](docs/openclaw-gcp/sizing-and-cost.md)

## Verification

```bash
bash tests/openclaw-gcp/test.sh
make test
```
