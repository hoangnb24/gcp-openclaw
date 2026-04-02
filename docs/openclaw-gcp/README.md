# OpenClaw On GCP Runbook

This runbook documents the Phase 3 browser-first day-2 workflow and the thin wrapper that now sits in front of the existing GCP scripts.

## Primary Quickstart

Start from the root [README](../../README.md) and use the official Open in Cloud Shell button.
Inside Cloud Shell, the primary flow is:

```bash
./bin/openclaw-gcp welcome
./bin/openclaw-gcp up --stack-id my-stack
./bin/openclaw-gcp status
./bin/openclaw-gcp ssh
./bin/openclaw-gcp logs --source readiness
./bin/openclaw-gcp down
```

`welcome` is non-mutating.
`up` is the real bring-up action.
`status` explains both the remembered local stack context and the GCP-backed ownership anchors.
`ssh` and `logs` use the same stack and anchor verification contract as `status`.
`down` tears down the same stack contract without making you retype router/template/NAT names manually.
Phase 1 expects an existing accessible GCP project and does not create new projects for you.
Set one with `gcloud config set project <PROJECT_ID>` or pass `--project-id <PROJECT_ID>` to `up`.

## Cloud Shell Persistence And State

Phase 1 stores a small convenience file at:

```bash
~/.config/openclaw-gcp/current-stack.env
```

It contains:

- `CURRENT_STACK_ID`
- `LAST_PROJECT_ID`
- `LAST_REGION`
- `LAST_ZONE`
- `LIFECYCLE`

In normal Cloud Shell usage, `$HOME` persists across sessions, so this file usually remains there when you come back later.
But that file is only convenience state.
The durable ownership truth is the label set on the stack's instance/template anchors:

- `openclaw_managed=true`
- `openclaw_stack_id=<stack-id>`
- `openclaw_tool=openclaw-gcp`
- `openclaw_lifecycle=persistent`

If local state disappears, becomes stale, or you use ephemeral Cloud Shell, `status` now attempts project-scoped label recovery first and repairs local state only when one candidate is trustworthy.
`down` still stays conservative and verifies anchors before it will destroy anything.

## Stack Command Surface

## `welcome`

```bash
./bin/openclaw-gcp welcome
```

Purpose:
- guide the first Cloud Shell interaction
- ask for a stack ID in interactive mode
- point directly at the exact `up` command

Behavior:
- never provisions infrastructure by itself
- can immediately chain into `up` if the operator confirms
- reminds the operator that an existing GCP project is required
- shows the current `gcloud` project when one is already set

## `up`

```bash
./bin/openclaw-gcp up --stack-id my-stack
```

Behavior:
- requires an explicit stack ID on the first real run
- derives the managed resource names automatically
- writes the current-stack convenience state before delegating so partial bring-up is still recoverable by `status` and `down`
- delegates real work to [`scripts/openclaw-gcp/install.sh`](../../scripts/openclaw-gcp/install.sh)

Inherited safety/behavior from the existing install engine:
- local prerequisite validation
- project/API/zone/firewall checks
- create-or-reuse behavior
- readiness gating
- repair of eligible legacy startup contracts
- interactive IAP SSH handoff to `curl -fsSL https://openclaw.ai/install.sh | bash`

## `status`

```bash
./bin/openclaw-gcp status
```

Behavior:
- uses `--stack-id` when provided
- otherwise uses remembered local state when still valid
- if local state is missing or stale, performs project-scoped recovery from labeled instance/template anchors
- prints project/region/zone context
- prints the expected instance/template/router/NAT names for the stack
- checks whether the instance/template anchors exist and whether their labels match the requested stack
- checks whether the deterministic router/NAT companions exist
- repairs `~/.config/openclaw-gcp/current-stack.env` only after exact-one-candidate recovery succeeds

Recovery outcomes:
- recovered: one trustworthy candidate was found and state was repaired
- ambiguous: multiple candidates were found, so `--stack-id` is required
- insufficient context: no stack pointer plus missing project context or missing `gcloud`

Machine-readable mode is also available:

```bash
./bin/openclaw-gcp status --json
```

`status --json` is additive and mirrors the human summary semantics.
In addition to the existing top-level fields, it now includes:

- `context`: whether `gcloud` and project context were resolved, plus contextual note text
- `state`: local convenience file values (`current_stack_id`, last project/region/zone, lifecycle, repaired flag)
- `recovery`: recovery note plus recovered and partial candidate IDs

This allows automation to reason about recovered, ambiguous, and insufficient-context outcomes directly.

## `ssh`

```bash
./bin/openclaw-gcp ssh
```

Behavior:
- resolves stack identity with the same explicit/current/recovered-single-candidate contract as `status`
- requires project context and `gcloud`
- requires a verified labeled instance anchor
- fails closed when template anchor exists but mismatches labels
- opens only IAP-backed `gcloud compute ssh`

Explicit stack selection is always available:

```bash
./bin/openclaw-gcp ssh --stack-id my-stack
```

## `logs`

```bash
./bin/openclaw-gcp logs --source readiness
```

Behavior:
- uses the same stack resolution and remote-access verification as `ssh`
- stays on IAP-backed `gcloud compute ssh` path
- supports only these named sources: `readiness`, `install`, `bootstrap`, `gateway`
- exits non-zero with explicit messaging for unsupported or unavailable sources

Example sources:

```bash
./bin/openclaw-gcp logs --source install
./bin/openclaw-gcp logs --source bootstrap
./bin/openclaw-gcp logs --source gateway
```

## `down`

```bash
./bin/openclaw-gcp down
```

Behavior:
- in interactive Cloud Shell only, defaults to the remembered current stack
- outside interactive Cloud Shell, requires `--stack-id`
- requires a resolvable project context
- verifies the instance/template anchors in GCP before delegating to destroy
- delegates real teardown to [`scripts/openclaw-gcp/destroy.sh`](../../scripts/openclaw-gcp/destroy.sh)
- clears the remembered current-stack pointer after a successful real teardown of that stack

Dry-run example:

```bash
./bin/openclaw-gcp down --stack-id my-stack --dry-run
```

Non-interactive example:

```bash
./bin/openclaw-gcp down --stack-id my-stack --yes --non-interactive
```

## What `down` Still Preserves

The new wrapper does not weaken the old destroy contract.
The underlying destroy engine still provides:

- exact-name qualification
- deterministic delete ordering
- typed confirmation for real interactive teardown
- explicit project targeting protection
- dry-run transparency

The wrapper simply resolves those exact names from the stack ID and refuses to proceed if the labeled anchors do not match.

## Default Operating Profile

- Region: `asia-southeast1`
- Zone: `asia-southeast1-a`
- Machine type: `e2-standard-2`
- Disk: `pd-balanced`, `30 GiB`
- Networking posture: internal-only VM, Cloud NAT egress, IAP SSH ingress
- Lifecycle label default: `persistent`

## Direct Engines

The lower-level scripts remain available:

- `bash scripts/openclaw-gcp/install.sh`
- `bash scripts/openclaw-gcp/destroy.sh`
- `bash scripts/openclaw-gcp/create-instance.sh`
- `bash scripts/openclaw-gcp/create-template.sh`

Use those when you intentionally want the lower-level contract.
For normal Phase 1 operations, prefer `./bin/openclaw-gcp`.

## Troubleshooting

If `up` fails before or during bring-up:
- rerun `./bin/openclaw-gcp status`
- inspect the remembered project/region/zone in `~/.config/openclaw-gcp/current-stack.env`
- use the existing install-script recovery messages and remote log hints

If `down` refuses to proceed:
- check that the project context is correct
- run `./bin/openclaw-gcp status --stack-id <stack-id>`
- confirm the instance/template anchors still exist and still carry the expected OpenClaw labels

If Cloud Shell opens next month and the convenience file is still present:
- `./bin/openclaw-gcp status`
- `./bin/openclaw-gcp down`

If the convenience file is gone or stale:
- run `./bin/openclaw-gcp status --project-id <PROJECT_ID>` to trigger recovery-aware status
- expect fail-closed ambiguity when more than one stack candidate exists
- pass `--stack-id` explicitly when status reports ambiguous or insufficient context

## Day-2 Docs

- [Cloud Shell quickstart](cloud-shell-quickstart.md)
- [Backup and restore](backup-and-restore.md)
- [Sizing and cost baselines](sizing-and-cost.md)
