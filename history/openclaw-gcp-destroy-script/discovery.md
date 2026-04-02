# Discovery Report: OpenClaw GCP Destroy Script

**Date**: 2026-03-31
**Feature**: `openclaw-gcp-destroy-script`
**CONTEXT.md reference**: `history/openclaw-gcp-destroy-script/CONTEXT.md`

---

## Institutional Learnings

> Read during Phase 0 from `history/learnings/`

### Critical Patterns (Always Applied)

- None applicable. `history/learnings/critical-patterns.md` is not present in this repo.

### Domain-Specific Learnings

No prior learnings for this domain.

---

## Agent A: Architecture Snapshot

> Source: file tree analysis, script reads, repo docs

### Relevant Packages / Modules

| Package/Module | Purpose | Key Files |
|----------------|---------|-----------|
| `scripts/openclaw-gcp/` | Operator CLI layer for GCP provisioning and day-2 actions | `install.sh`, `create-instance.sh`, `create-template.sh`, `create-cloud-nat.sh`, `create-snapshot-policy.sh`, `create-machine-image.sh`, `spawn-from-image.sh` |
| `tests/openclaw-gcp/` | Shell contract tests with mock `gcloud` behavior | `test.sh` |
| `docs/openclaw-gcp/` | Operator runbooks and examples | `README.md`, `backup-and-restore.md`, `sizing-and-cost.md` |
| repo root docs | Canonical primary workflow summary | `README.md`, `Makefile` |

### Entry Points

- **Primary CLI**: `scripts/openclaw-gcp/install.sh`
- **Provisioning orchestration**: `scripts/openclaw-gcp/create-instance.sh`
- **Template lifecycle**: `scripts/openclaw-gcp/create-template.sh`
- **Networking helper**: `scripts/openclaw-gcp/create-cloud-nat.sh`
- **Day-2 resources**: `scripts/openclaw-gcp/create-snapshot-policy.sh`, `scripts/openclaw-gcp/create-machine-image.sh`, `scripts/openclaw-gcp/spawn-from-image.sh`
- **Verification**: `tests/openclaw-gcp/test.sh` via `make test`

### Key Files to Model After

- `scripts/openclaw-gcp/install.sh` — best current reference for human-facing CLI behavior: preflight checks, prompt strategy, `--dry-run`, and failure summaries.
- `scripts/openclaw-gcp/create-instance.sh` — authoritative source for the default deployment resource names and create-side dependency order: template -> Cloud NAT/router -> VM.
- `scripts/openclaw-gcp/create-cloud-nat.sh` — defines the router/NAT pairing and idempotent reuse behavior the destroy flow must unwind carefully.
- `scripts/openclaw-gcp/create-snapshot-policy.sh` — existing pattern for optional resource flags, region/zone validation, and attach semantics.
- `tests/openclaw-gcp/test.sh` — existing mock harness for `gcloud`, SSH, and docs smoke coverage that should absorb the destroy contract tests.

---

## Agent B: Pattern Search

> Source: grep, script reads, test harness inspection

### Similar Existing Implementations

| Feature/Component | Location | Pattern Used | Reusable? |
|-------------------|----------|--------------|-----------|
| Primary operator script | `scripts/openclaw-gcp/install.sh` | Explicit long flags, fail-fast helpers, interactive/non-interactive split, dry-run rendering | Yes |
| Resource helper CLI | `scripts/openclaw-gcp/create-cloud-nat.sh` | Focused single-purpose shell command wrapper with idempotent existence checks | Yes |
| Resource policy helper | `scripts/openclaw-gcp/create-snapshot-policy.sh` | Explicit optional resource flags and zone/region validation | Yes |
| Day-2 image helper | `scripts/openclaw-gcp/create-machine-image.sh` | Narrow command wrapper with printed inputs and dry-run | Yes |
| Test harness | `tests/openclaw-gcp/test.sh` | Mock `gcloud` script plus log assertions over generated commands | Yes |

### Reusable Utilities

- **Validation / exits**: local `die`, `fail_preflight`, `require_command`, and `validate_zone_region_pair` patterns already exist in shell scripts and should be mirrored instead of reinvented.
- **Interactive gating**: `install.sh` already contains `is_interactive_session`, prompt-or-fail behavior, and dry-run-friendly contract output.
- **Mocking**: `tests/openclaw-gcp/test.sh` already intercepts `gcloud` subcommands and records command strings for assertions.
- **Docs smoke coverage**: `test_docs_smoke_commands` already verifies README and runbook examples parse correctly in dry-run mode.

### Naming Conventions

- Scripts live in `scripts/openclaw-gcp/` and use kebab-case file names such as `create-cloud-nat.sh` and `repair-instance-bootstrap.sh`.
- Flags are long-form and explicit: `--project-id`, `--instance-name`, `--router-name`, `--dry-run`.
- User-facing summaries print structured key/value lines before rendering or executing the final command.
- Tests use `test_<behavior>()` functions and assert over both exit status and logged `GCLOUD ...` command strings.

---

## Agent C: Constraints Analysis

> Source: `Makefile`, shell scripts, test harness

### Runtime & Framework

- **Shell runtime**: Bash with `set -euo pipefail`
- **Primary external dependency**: `gcloud`
- **Language**: POSIX-style shell scripting with Bash arrays and conditionals
- **Execution model**: local operator CLI, not a service or package-managed app

### Existing Dependencies (Relevant to This Feature)

| Package | Version | Purpose |
|---------|---------|---------|
| `gcloud` | environment-provided | Create, inspect, and eventually delete Compute Engine resources |
| `bash` | environment-provided | Script runtime and test runtime |

### New Dependencies Needed

| Package | Reason | Risk Level |
|---------|--------|------------|
| None expected | Feature fits the existing shell + `gcloud` operator model | LOW |

### Build / Quality Requirements

```bash
make test
```

### Database / Storage (if applicable)

- Not applicable. This feature operates on GCP infrastructure through shell commands and existing docs/tests.

---

## Agent D: External Research

> Source: official Google Cloud documentation
> Guided by locked decisions in CONTEXT.md

### Library Documentation

| Library | Version | Key Docs |
|---------|---------|----------|
| Google Cloud CLI | current docs | `gcloud compute instances delete` supports explicit `--delete-disks` and `--keep-disks`, which can override attached disk auto-delete behavior: https://docs.cloud.google.com/sdk/gcloud/reference/compute/instances/delete |
| Compute Engine docs | current docs | Instance deletion docs emphasize that CLI deletes can preserve or remove attached disks explicitly: https://cloud.google.com/compute/docs/instances/deleting-instance |
| Google Cloud CLI | current docs | `gcloud compute routers nats delete` requires the NAT name plus `--router` and usually `--region`: https://docs.cloud.google.com/sdk/gcloud/reference/compute/routers/nats/delete |
| Compute Engine docs | current docs | Regional instance templates have delete-specific behavior and constraints worth honoring in tests: https://cloud.google.com/compute/docs/instance-templates/get-list-delete-instance-templates |
| Google Cloud CLI | current docs | Snapshot policy removal uses `gcloud compute resource-policies delete`, and attachment cleanup has a dedicated remove-resource-policies command: https://cloud.google.com/sdk/gcloud/reference/compute/resource-policies/delete and https://cloud.google.com/sdk/gcloud/reference/compute/instances/remove-resource-policies |

### Community Patterns

- No community research needed. The feature is an extension of an existing shell/GCP operator surface and official docs were sufficient.

### Known Gotchas / Anti-Patterns

- **Gotcha**: instance deletion can preserve or delete attached disks explicitly.
  - Why it matters: this feature is destructive, and the exact boot-disk/data-disk semantics determine whether "full cleanup" is achieved or whether the script accidentally exceeds its contract.
  - How to avoid: validate attached disks before deletion and make the chosen delete behavior explicit in code and tests.

- **Gotcha**: Cloud NAT deletion is scoped to a router and region.
  - Why it matters: deleting NAT without the router context is not enough, and router deletion order matters if the NAT still exists.
  - How to avoid: teardown order should remove NAT before router and keep both names explicit.

- **Anti-pattern**: broad infra discovery followed by sweeping deletion.
  - Common mistake: infer "related" resources from naming patterns or incidental references and remove them opportunistically.
  - Correct approach: honor D2 by deleting only exact named resources that pass expected contract checks.

---

## Open Questions

> Items that were not resolvable through research alone.
> These will be raised to the synthesis step in Phase 2.

- [ ] What exact attached-disk contract should the destroy script enforce before it can claim "full cleanup" for the VM path without guessing about extra disks?
- [ ] Which contract checks are sufficient to treat a router/NAT/template as safe repo-managed teardown targets instead of shared infrastructure?

---

## Summary for Synthesis (Phase 2 Input)

> Brief synthesis for the next planning step.

**What we have**: a repo that already manages the OpenClaw GCP lifecycle through focused shell entrypoints, with the default installer stack clearly centered on `install.sh`, `create-instance.sh`, `create-template.sh`, and `create-cloud-nat.sh`.

**What we need**: one destroy-side orchestrator that mirrors the installer UX, unwinds the default stack safely, and optionally removes explicit extra resources without any broad discovery.

**Key constraints from research**:
- The repo's quality gate is a Bash contract suite in `tests/openclaw-gcp/test.sh`, so the destroy flow should be planned as a shell-first feature with mockable `gcloud` commands.
- Attached disk deletion semantics are important and should be treated as a validation-risk item rather than guessed at implementation time.

**Institutional warnings to honor**:
- No prior institutional learnings for this domain.
