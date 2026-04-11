# OpenClaw On GCP Runbook

This runbook documents the Cloud Shell-first wrapper workflow and the lower-level GCP scripts that sit underneath it.

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

`welcome` prints the next `up` command and can chain directly into it when you confirm or pass `--yes`.
`up` is the bring-up action.
`status` explains both the remembered local stack context and the GCP-backed ownership anchors.
`ssh` and `logs` use the same stack and anchor verification contract as `status`.
`down` tears down the same stack contract without making you retype router/template/NAT names manually.
This workflow expects an existing accessible GCP project and does not create new projects for you.
Set one with `gcloud config set project <PROJECT_ID>` or pass `--project-id <PROJECT_ID>` to `up`.

## Cloud Shell Persistence And State

The wrapper stores a small convenience file at:

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

If local state disappears, becomes stale, or you use ephemeral Cloud Shell, `status` attempts project-scoped label recovery first and repairs local state only when one candidate is trustworthy.
`down` verifies anchors before it will destroy anything.

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
- prints the next `up` command before provisioning
- can immediately chain into `up` if the operator confirms or passes `--yes`
- reminds the operator that an existing GCP project is required
- shows the current `gcloud` project when one is already set

Options:
- `--stack-id <id>`
- `--yes`
- `--non-interactive`

## `up`

```bash
./bin/openclaw-gcp up --stack-id my-stack
```

Behavior:
- requires an explicit stack ID on the first real run
- derives the managed resource names automatically
- writes the current-stack convenience state before delegating so partial bring-up is still recoverable by `status` and `down`
- delegates real work to [`scripts/openclaw-gcp/install.sh`](../../scripts/openclaw-gcp/install.sh)

Common options:
- `--stack-id <id>`
- `--project-id <id>`
- `--region <region>`
- `--zone <zone>`
- `--lifecycle <name>`
- `--openclaw-tag <tag>`
- `--openclaw-image <image>`
- `--service-account <email>`
- `--scopes <csv>`
- `--no-service-account`
- `--allow-external-ip`
- `--interactive`
- `--non-interactive`
- `--dry-run`

Inherited safety/behavior from the existing install engine:
- local prerequisite validation
- project/API/zone/firewall checks
- create-or-reuse behavior
- readiness gating
- repair of eligible legacy startup contracts
- interactive IAP SSH handoff to a SHA-256-pinned upstream installer fetched from `https://openclaw.ai/install.sh`

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

`status --json` is additive and mirrors the human summary semantics for successful status resolution.
In addition to the existing top-level fields, it includes:

- `context`: whether `gcloud` and project context were resolved, plus contextual note text
- `state`: local convenience file values (`current_stack_id`, last project/region/zone, lifecycle, repaired flag)
- `recovery`: recovery note plus recovered and partial candidate IDs

This allows automation to inspect resolved status results directly without relying on the human summary format.

Options:
- `--stack-id <id>`
- `--project-id <id>`
- `--region <region>`
- `--zone <zone>`
- `--lifecycle <name>`
- `--json`

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

Options:
- `--stack-id <id>`
- `--project-id <id>`
- `--region <region>`
- `--zone <zone>`
- SSH passthrough args after `--`

## `logs`

```bash
./bin/openclaw-gcp logs --source readiness
```

Behavior:
- uses the same stack resolution and remote-access verification as `ssh`
- stays on IAP-backed `gcloud compute ssh` path
- supports only these named sources: `readiness`, `install`, `bootstrap`, `gateway`
- returns the most recent 200 lines from the selected source
- exits non-zero with explicit messaging for unsupported or unavailable sources

Example sources:

```bash
./bin/openclaw-gcp logs --source install
./bin/openclaw-gcp logs --source bootstrap
./bin/openclaw-gcp logs --source gateway
```

Source map:
- `readiness`: `$HOME/.openclaw-gcp/install-logs/readiness-gate.log`
- `install`: `$HOME/.openclaw-gcp/install-logs/latest.log`
- `bootstrap`: `/var/log/openclaw/bootstrap.log`
- `gateway`: `docker logs --tail 200 openclaw_openclaw-gateway_1`

Options:
- `--source <name>`
- `--stack-id <id>`
- `--project-id <id>`
- `--region <region>`
- `--zone <zone>`

## `down`

```bash
./bin/openclaw-gcp down
```

Behavior:
- in interactive Cloud Shell only, defaults to the remembered current stack
- outside interactive Cloud Shell, requires `--stack-id`
- requires a resolvable project context, preferring explicit or live `gcloud` context over remembered local state
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

Exact-name cleanup extras:
- `--snapshot-policy-name <name>`
- `--snapshot-policy-disk <name>`
- `--snapshot-policy-disk-zone <zone>`
- `--clone-instance-name <name>`
- `--clone-zone <zone>`
- `--machine-image-name <name>`

Common options:
- `--stack-id <id>`
- `--project-id <id>`
- `--region <region>`
- `--zone <zone>`
- `--lifecycle <name>`
- `--network <name>`
- `--dry-run`
- `--yes`
- `--interactive`
- `--non-interactive`

## What `down` Preserves

The wrapper keeps the destroy contract narrow and explicit.
The underlying destroy engine provides:

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
For normal operations, prefer `./bin/openclaw-gcp`.

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
