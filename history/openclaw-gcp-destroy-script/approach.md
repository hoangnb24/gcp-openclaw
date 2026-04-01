# Approach: OpenClaw GCP Destroy Script

**Date**: 2026-03-31
**Feature**: `openclaw-gcp-destroy-script`
**Based on**:
- `history/openclaw-gcp-destroy-script/discovery.md`
- `history/openclaw-gcp-destroy-script/CONTEXT.md`

---

## 1. Gap Analysis

> What exists vs. what the feature requires.

| Component | Have | Need | Gap Size |
|-----------|------|------|----------|
| Primary destroy entrypoint | No destroy-side orchestrator | `scripts/openclaw-gcp/destroy.sh` with installer-aligned CLI UX | New |
| Core stack teardown | Create-side flow for template, NAT/router, and VM | Exact-name delete path for VM, template, NAT, and router | New |
| Optional extra cleanup | Standalone create helpers for snapshot policy, machine image, clone instance | Explicit-name cleanup flags and delete sequencing for those extras | New |
| Safety UX | `install.sh` prompt and dry-run patterns | Typed confirmation, `--yes`, and clear deletion-plan output | New variation of existing pattern |
| Failure reporting | Human-readable summaries in `install.sh` | Best-effort delete loop with per-resource success/failure summary | New variation of existing pattern |
| Verification | Mock `gcloud` harness and docs smoke tests | Destroy-specific parser, dry-run, confirmation, ordering, and partial-failure tests | Extend existing pattern |
| Docs | Installer-first quickstart and runbook | Destroy companion commands and teardown guidance | Update existing docs |

---

## 2. Recommended Approach

Add one repo-native destroy orchestrator at `scripts/openclaw-gcp/destroy.sh` that mirrors `install.sh` in tone and CLI structure, but renders and executes a delete plan instead of a create-or-reuse plan. The script should own only exact-name deletion of the default installer stack plus explicitly named extras, with a strict inspection phase up front that refuses to proceed when the target shape looks shared or outside the expected OpenClaw contract. Real deletion should be a two-stage flow: first summarize the resources and commands that will run, then require typed confirmation unless `--yes` or `--dry-run` is present. Execution should be best-effort in dependency order, collecting per-resource outcomes and exiting non-zero with manual cleanup guidance if anything fails.

### Why This Approach

- It matches the operator experience already established in `scripts/openclaw-gcp/install.sh`, so users do not have to learn a second CLI style for the companion teardown flow.
- It honors locked decision `D2` by forcing exact-name inputs and refusing broad discovery or heuristic deletion.
- It keeps the implementation inside the repo's existing shell + `gcloud` model, which means the feature can inherit the current test harness in `tests/openclaw-gcp/test.sh`.
- It contains the main destructive risk by separating "inspect and summarize" from "actually delete", which is especially important for disk and shared-infra edge cases identified during discovery.

### Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Entry point | `scripts/openclaw-gcp/destroy.sh` | Symmetric with `install.sh`; simplest discoverable companion entrypoint |
| Resource scope model | Core stack defaults + optional explicit extra flags | Honors `D1` and `D3` while keeping `D2` intact |
| Safety gate | Typed confirmation prompt in interactive mode, `--yes` for automation, `--dry-run` for preview | Required by `D4` and matches the repo's CLI patterns |
| Execution model | Inspect first, then best-effort delete loop with collected outcomes | Required by `D5`; lets the script keep cleaning even after partial failure |
| Verification surface | Extend `tests/openclaw-gcp/test.sh` instead of creating a second harness | Lowest-friction fit with current repo patterns |

---

## 3. Alternatives Considered

### Option A: Add several small delete helpers and no orchestrator

- Description: create `delete-instance.sh`, `delete-template.sh`, `delete-cloud-nat.sh`, and let users compose them manually.
- Why considered: it mirrors the narrow helper style used elsewhere in `scripts/openclaw-gcp/`.
- Why rejected: the user explicitly asked for a companion to `install.sh`, and the safety/summary/typed-confirmation experience is better enforced in one orchestrator than across multiple manual commands.

### Option B: Delete only the VM and leave infrastructure cleanup to the operator

- Description: make the first version destroy only `oc-main` and postpone template/NAT/router teardown.
- Why considered: it is operationally simpler and less risky.
- Why rejected: it violates `D1`, which explicitly requires full teardown by default.

### Option C: Auto-discover all "related" resources from the instance and remove them

- Description: inspect labels, networking, attached resources, and name prefixes to decide what to delete.
- Why considered: it could reduce required flags and feel more automatic.
- Why rejected: it conflicts directly with `D2`, which forbids guessy or broad deletion behavior.

---

## 4. Risk Map

> Every component that is part of this feature must appear here.

| Component | Risk Level | Reason | Verification Needed |
|-----------|------------|--------|---------------------|
| `destroy.sh` CLI contract | **MEDIUM** | New script, but strongly modeled after `install.sh` | Normal test coverage |
| Core stack delete ordering | **MEDIUM** | New destructive path across multiple resources | Dry-run and command-order tests |
| Attached disk / instance delete semantics | **HIGH** | Destructive behavior depends on actual GCP delete semantics and attached-disk shape | Spike in validating |
| Shared-infra guardrails for template/NAT/router | **HIGH** | Mistakes here could delete resources outside the intended OpenClaw deployment | Spike in validating |
| Optional extra resource cleanup | **MEDIUM** | New flags and sequencing, but built on existing resource helper surfaces | Contract tests |
| Partial-failure summary loop | **MEDIUM** | New behavior path with mixed success/failure state | Failure-path tests |
| Docs updates and smoke coverage | **LOW** | Established doc/test pattern already exists | Docs smoke tests |

### Risk Classification Reference

```text
Pattern in codebase?        -> YES = LOW base
External dependency?        -> YES = HIGH
Blast radius > 5 files?     -> YES = HIGH
Otherwise                   -> MEDIUM
```

### HIGH-Risk Summary (for khuym:validating skill)

- `Attached disk / instance delete semantics`: validate that Phase 1's qualification rule is enforceable from `gcloud` inspection output: proceed only when the instance has exactly one attached disk and that disk is `boot=true` and `autoDelete=true`; otherwise fail before deletion.
- `Shared-infra guardrails for template/NAT/router`: validate that Phase 1's qualification rule is enforceable from `gcloud` inspection output: proceed only when the template exposes the current startup contract metadata, the router is bound to the requested network, and the NAT exists under that router with the expected all-subnets + auto-allocate configuration.

---

## 5. Proposed File Structure

> Where new files will live.

```text
scripts/
  openclaw-gcp/
    destroy.sh                    # New destroy-side orchestrator
tests/
  openclaw-gcp/
    test.sh                       # Extend mock gcloud + destroy contract tests
docs/
  openclaw-gcp/
    README.md                     # Add teardown workflow and troubleshooting
README.md                         # Surface destroy companion command
history/
  openclaw-gcp-destroy-script/
    discovery.md
    approach.md
    phase-plan.md
```

---

## 6. Dependency Order

> Dependency order for later bead creation.

```text
Layer 1: Decide CLI contract and resource inspection rules
Layer 2: Implement core stack delete flow and confirmation gate
Layer 3: Extend to optional explicit extras and partial-failure reporting
Layer 4: Update docs and smoke coverage
```

### Parallelizable Groups

- Group A: core CLI contract tests and main script scaffolding
- Group B: optional extra-resource cleanup, after Group A defines the flag surface
- Group C: docs updates, after the command surface is stable

---

## 7. Institutional Learnings Applied

> From Phase 0.

No prior institutional learnings relevant to this feature.

---

## 8. Open Questions for Validating

> Items that could not be fully resolved in planning.

- [ ] Can the destroy flow reliably inspect and enforce the planned instance qualification rule of `exactly one attached disk`, `boot=true`, and `autoDelete=true` before deletion in both real GCP output and the shell test harness?
- [ ] Can the destroy flow reliably inspect and enforce the planned infra qualification rule of current startup-contract metadata on the template, requested-network ownership on the router, and expected all-subnets/auto-allocate settings on the NAT before deletion?
