# OpenClaw on GCP

This repo now treats Cloud Shell as the primary operator terminal for OpenClaw on GCP.
The main Phase 1 story is:

`Open in Cloud Shell -> welcome -> up -> status -> down`

## Cloud Shell Quickstart

[![Open in Cloud Shell](https://gstatic.com/cloudssh/images/open-btn.svg)](https://shell.cloud.google.com/cloudshell/editor?cloudshell_git_repo=https://github.com/hoangnb24/gcp-openclaw&cloudshell_git_branch=main&cloudshell_workspace=.&cloudshell_tutorial=docs/openclaw-gcp/cloud-shell-quickstart.md&show=ide%2Cterminal)

The official Cloud Shell launch above clones this repo, opens the repo workspace, and launches the repo-hosted quickstart tutorial.
It does not auto-provision anything.

For pre-merge UAT on a feature branch, use the same URL but replace `cloudshell_git_branch=main` with the branch you are validating.
For this branch, that means `cloudshell_git_branch=feature/openclaw-gcp-one-line-installer`.

If you are testing with the `cloudshell_open` helper inside Cloud Shell instead of the browser URL, keep the workspace at repo root:
`--open_workspace "."`

In Cloud Shell, the happy path is:

```bash
./bin/openclaw-gcp welcome
./bin/openclaw-gcp up --stack-id my-stack
./bin/openclaw-gcp status
./bin/openclaw-gcp down
```

`welcome` is non-mutating.
`up` uses your stack ID to derive the VM, template, router, and NAT names automatically and then delegates to the existing install engine underneath.
`down` delegates to the existing destroy engine, but only after verifying that the stack's labeled GCP anchors match the stack you asked for.

For the full browser-first walkthrough, see [Cloud Shell quickstart](docs/openclaw-gcp/cloud-shell-quickstart.md).

## Stack Model

Phase 1 makes the stack the unit of ownership.
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

Those labels on the instance/template anchors are the durable ownership truth in Phase 1.
Router and NAT stay deterministic companion resources derived from the stack ID because the current CLI path here does not expose label flags there.

## What Persists In Cloud Shell

This repo stores a small convenience pointer at `~/.config/openclaw-gcp/current-stack.env`.
That file remembers the current stack plus the last-known project, region, and zone so the next `status` or `down` command can stay simple.

In normal Cloud Shell usage, `$HOME` is persistent, so that file usually survives when you come back later.
But Cloud Shell itself is still a temporary VM, `gcloud` tab preferences do not persist by default, and ephemeral Cloud Shell sessions can discard local state entirely.

That is why Phase 1 treats local state as convenience only and still verifies the labeled GCP anchors before teardown.
If local state is gone or stale, later recovery work can build on those labels safely.

## Primary Commands

```bash
./bin/openclaw-gcp welcome
```

Non-mutating Cloud Shell guidance.
In interactive mode it asks for a stack ID and offers to jump straight into `up`.

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

```bash
./bin/openclaw-gcp down
```

Interactive Cloud Shell convenience path for the remembered current stack.
Outside interactive Cloud Shell sessions, use `--stack-id` explicitly.

## Safety Properties Kept Intact

- `up` still uses the existing preflight checks, create-or-reuse logic, readiness gating, repair path, and upstream installer handoff from [`scripts/openclaw-gcp/install.sh`](scripts/openclaw-gcp/install.sh).
- `down` still uses the existing exact-name qualification checks, deterministic delete ordering, typed confirmation, and dry-run behavior from [`scripts/openclaw-gcp/destroy.sh`](scripts/openclaw-gcp/destroy.sh).
- Teardown now adds one extra safety layer before delegation: the wrapper refuses to tear down if the labeled instance/template anchors do not match the requested stack.

## Direct Engines Still Available

The thin product layer is intentionally layered over the existing scripts, not a rewrite.
These lower-level entrypoints still exist for advanced or migration workflows:

- [`scripts/openclaw-gcp/install.sh`](scripts/openclaw-gcp/install.sh)
- [`scripts/openclaw-gcp/destroy.sh`](scripts/openclaw-gcp/destroy.sh)
- [`scripts/openclaw-gcp/create-instance.sh`](scripts/openclaw-gcp/create-instance.sh)
- [`scripts/openclaw-gcp/create-template.sh`](scripts/openclaw-gcp/create-template.sh)

## Operator Docs

- [OpenClaw GCP runbook](docs/openclaw-gcp/README.md)
- [Cloud Shell quickstart](docs/openclaw-gcp/cloud-shell-quickstart.md)
- [Backup and restore](docs/openclaw-gcp/backup-and-restore.md)
- [Sizing and cost baselines](docs/openclaw-gcp/sizing-and-cost.md)

## Verification

```bash
make test
```
