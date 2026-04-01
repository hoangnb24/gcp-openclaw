# Approach: OpenClaw GCP One-Line Installer

**Date**: 2026-03-29
**Feature**: `openclaw-gcp-one-line-installer`
**Based on**:
- `history/openclaw-gcp-one-line-installer/discovery.md`
- `history/openclaw-gcp-one-line-installer/CONTEXT.md`

---

## 1. Gap Analysis

> What exists vs. what the feature requires.

| Component | Have | Need | Gap Size |
|-----------|------|------|----------|
| Primary entrypoint | `create-instance.sh` creates or reuses infra only | `install.sh` that preflights, prompts, provisions/reuses, SSHes, and launches upstream installer | New |
| Local prerequisite gate | only per-script command existence checks | full local readiness validation: `gcloud`, auth, project, APIs, and IAP-facing prerequisites | New |
| Input collection UX | flags only | interactive prompts in TTY mode plus explicit flag-only failure in non-interactive mode | New |
| Host bootstrap | `bootstrap-openclaw.sh` installs Docker, clones OpenClaw repo, creates wrappers, performs onboarding | minimal VM startup script that only prepares generic host prerequisites and logging | Replacement |
| Upstream install handoff | no automated SSH-to-install path | interactive SSH flow that runs `curl -fsSL https://openclaw.ai/install.sh | bash` on the VM | New |
| Template metadata contract | current template contract is tied to `openclaw_image`, `openclaw_tag`, and embedded Docker bootstrap | template contract that supports the new minimal startup path without requiring Docker/OpenClaw image metadata in the happy path | Medium |
| Docs | primary README/runbook narrate Docker/bootstrap wrapper flow | primary docs rewritten around `scripts/openclaw-gcp/install.sh` | Medium |
| Tests | contract suite locks current Docker/bootstrap behavior | contract suite updated to validate preflight, prompt handling, minimal bootstrap, and SSH installer handoff | High |

---

## 2. Recommended Approach

Introduce a new primary orchestrator at `scripts/openclaw-gcp/install.sh` that owns the full happy path: local preflight checks, interactive input resolution, template-backed instance ensure/reuse, a remote readiness probe, and the SSH handoff into the upstream OpenClaw installer. Keep the existing infrastructure core intact by continuing to rely on `create-instance.sh`, `create-template.sh`, and `create-cloud-nat.sh` for deterministic provisioning, but refactor the embedded template startup path away from the current Docker/OpenClaw bootstrap into a minimal host-readiness script. That minimal startup path should avoid long-lived product install work and instead establish a clear readiness boundary for the later SSH/install phase so the remote installer does not race package-manager locks or half-finished first-boot work. The SSH/install phase should be treated as a distinct stage after provisioning, not folded into `create-instance.sh`, so the current infra primitives remain scriptable and testable on their own. Rewrite the repo’s primary docs and tests around this new flow while preserving legacy scripts only as non-primary or deprecated paths where needed for compatibility.

### Why This Approach

- It honors **D4** by preserving the current template-based provisioning architecture instead of replacing it with direct VM creation.
- It honors **D1**, **D9**, and **D11** by making SSH handoff a first-class phase with explicit success and failure behavior rather than a best-effort remote command tacked onto provisioning.
- It honors **D12** by removing product installation responsibilities from the VM startup script and delegating them to the upstream installer, which already owns Node/Git/OpenClaw install and onboarding.
- It minimizes infrastructure regression risk by leaving `create-instance.sh` focused on infra orchestration and adding a new wrapper for the user-facing end-to-end flow.
- It avoids the biggest discovered anti-pattern: keeping a heavy repo-managed Docker/OpenClaw bootstrap active while also launching the upstream installer for the same VM lifecycle.

### Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| User-facing entrypoint | Add `scripts/openclaw-gcp/install.sh` | Matches D10 and keeps primary UX separate from infra primitives |
| Provisioning core | Reuse `create-instance.sh` / `create-template.sh` / `create-cloud-nat.sh` | Preserves deterministic infra model and existing guardrails |
| SSH/install phase placement | Keep it in `install.sh`, not `create-instance.sh` | Avoids bloating infra-only script contracts with interactive user session behavior |
| Startup script strategy | Replace embedded Docker bootstrap with a minimal generic readiness script | Matches D12 and reduces overlap with upstream `install.sh` |
| Prompt strategy | Prompt only in interactive TTY mode; require explicit flags in non-interactive mode | Matches D5 exactly |
| Existing-instance behavior | Detect and reuse existing VM only after a reuse-eligibility check | Matches D3 while avoiding silent reuse of non-ready or legacy-conflicting hosts |
| Preflight scope | Validate all knowable local prerequisites before provisioning | Matches D2 and D6 and avoids overpromising perfect prediction of remote/runtime failures |
| Remote readiness boundary | Probe the guest before launching upstream install | Separates “VM exists” from “installer handoff is safe” |
| Legacy path treatment | Keep legacy Docker/bootstrap code only as deprecated/non-primary compatibility, not as the default story | Matches D7 while limiting churn risk during migration |
| Failure observability | Capture installer output to a stable remote log path and print retrieval guidance locally | Makes D11 failure summaries actionable |

---

## 3. Alternatives Considered

### Option A: Fold the full one-line behavior into `create-instance.sh`

- Description: make `create-instance.sh` do preflight, prompting, SSH, and remote upstream install.
- Why considered: one less top-level script, simpler apparent surface area.
- Why rejected: it entangles an infra primitive with interactive user-session behavior, weakens script composability, and makes `--dry-run` / reuse / provisioning-only use cases much harder to preserve cleanly.

### Option B: Keep the current Docker/bootstrap startup path and just append an SSH-based upstream install

- Description: preserve `bootstrap-openclaw.sh` largely as-is, then SSH in and also run `https://openclaw.ai/install.sh`.
- Why considered: lower short-term code churn.
- Why rejected: it directly conflicts with D12, duplicates product-install responsibility, and risks creating two competing OpenClaw setup models on the same host.

### Option C: Collapse to direct VM creation and bypass templates in the one-line path

- Description: create the instance directly from `install.sh` without using templates by default.
- Why considered: simpler control flow in the installer wrapper.
- Why rejected: it violates D4 and throws away the repo’s strongest deterministic provisioning pattern.

### Option D: Make the new flow purely local-side and stop after printing SSH instructions

- Description: keep provisioning automated, but let the user manually run SSH and `curl ... | bash`.
- Why considered: lower implementation risk around interactive SSH behavior.
- Why rejected: it violates D1 because the required product experience is automatic SSH into the upstream installer.

---

## 4. Risk Map

> Every component that is part of this feature must appear here.

| Component | Risk Level | Reason | Verification Needed |
|-----------|------------|--------|---------------------|
| `scripts/openclaw-gcp/install.sh` orchestration | **MEDIUM** | New script, but built from established shell/orchestrator patterns already in repo | Contract tests for flags, prompts, dry-run, reuse path |
| Local prerequisite gate | **HIGH** | New logic over external GCP/IAP state, and D6 requires a stronger-than-usual readiness promise | Validating should spike the exact matrix and failure messaging |
| Interactive prompt layer | **MEDIUM** | New UX surface with TTY/non-TTY branching | Tests for interactive vs non-interactive behavior and flag precedence |
| Existing-instance reuse flow | **HIGH** | Top-level reuse now needs explicit eligibility checks across running, stopped, and legacy-configured hosts | Validating should spike eligibility rules and refusal paths |
| Existing template/instance migration compatibility | **HIGH** | Reused templates or instances may still carry the old Docker/bootstrap metadata contract and startup behavior | Validating should spike how the new installer detects or safely upgrades old template/runtime states |
| Minimal startup script replacement | **HIGH** | Replaces the repo’s current embedded bootstrap contract and touches template, repair, docs, and tests | Validating should spike the exact minimum host prep and migration shape |
| Startup readiness / package-manager lock timing | **HIGH** | Minimal startup still performs package work, and the SSH/install phase can collide with first-boot apt activity or incomplete readiness | Validating should spike readiness signaling and handoff timing |
| Remote readiness probe | **HIGH** | New transition point between “infra created” and “safe to launch vendor installer” | Validating should spike the exact guest checks and timeout behavior |
| Template metadata/flag contract simplification | **HIGH** | Current template contract is built around `openclaw_tag` and embedded Docker bootstrap assumptions | Validating should spike how to evolve template flags without accidental regression |
| SSH handoff into upstream `install.sh` | **HIGH** | External dependency plus TTY-sensitive behavior; `gcloud compute ssh --command` is not equivalent to a live interactive shell by default | Validating should spike the exact SSH invocation and success/failure semantics |
| Upstream installer integration | **HIGH** | External script outside repo control; behavior can change over time | Validate assumptions against current installer behavior and document fallback expectations |
| Partial-state recovery / rerun semantics | **HIGH** | Infra may succeed while SSH or vendor install fails, and the operator needs a safe rerun story | Validating should spike rerun/resume guidance |
| Remote failure observability | **MEDIUM** | Without remote log capture, local summaries will be too weak for debugging | Validate log path and retrieval UX |
| README/runbook migration | **MEDIUM** | Significant content rewrite but no novel technical pattern | Smoke-test updated commands and doc flow |
| Test suite migration | **HIGH** | Current tests hard-code Docker/bootstrap behavior and startup script contents | Validate new assertions cover the new primary flow without leaving blind spots |
| Legacy-path deprecation strategy | **MEDIUM** | Requires careful framing to avoid leaving the repo in an ambiguous dual-primary state | Validate docs and help text make the new primary story unambiguous |

### Risk Classification Reference

```
Pattern in codebase?        → YES = LOW base
External dependency?        → YES = HIGH
Blast radius > 5 files?    → YES = HIGH
Otherwise                   → MEDIUM
```

### HIGH-Risk Summary (for khuym:validating skill)

- `Local prerequisite gate`: determine the exact matrix of local/IAP/project/API checks the wrapper can promise before mutation.
- `Existing template/instance migration compatibility`: determine how the new installer recognizes and safely handles reused templates and VMs that still reflect the legacy bootstrap contract.
- `Minimal startup script replacement`: determine the exact minimum host prep to keep instances ready for SSH/upstream install without preserving Docker/bootstrap baggage.
- `Startup readiness / package-manager lock timing`: determine how the installer knows the VM is ready for SSH/upstream install without racing first-boot package operations.
- `Remote readiness probe`: determine the exact guest checks between VM creation/reuse and installer launch.
- `Template metadata/flag contract simplification`: determine how `openclaw_tag` / startup metadata evolve under the new primary flow without breaking template semantics and repair workflows.
- `SSH handoff into upstream install.sh`: determine the exact `gcloud compute ssh` invocation that preserves interactive installer behavior, leaves the user at a shell on success, and returns locally on failure.
- `Upstream installer integration`: validate the repo can rely on current upstream installer behavior without duplicating its dependency installation logic.
- `Partial-state recovery / rerun semantics`: determine how reruns behave after infra success but installer failure.
- `Test suite migration`: determine the minimum sufficient contract coverage after removing Docker/bootstrap from the primary flow.

---

## 5. Proposed File Structure

> Where new files will live. Workers use this to plan their work.

```text
scripts/
  openclaw-gcp/
    install.sh                    # New primary one-line installer entrypoint
    create-instance.sh            # Existing provisioning orchestrator retained
    create-template.sh            # Existing deterministic template builder, adapted for minimal startup
    create-cloud-nat.sh           # Existing NAT helper retained
    repair-instance-bootstrap.sh  # Existing repair script adapted to new startup script contract
    bootstrap-vm-prereqs.sh       # New minimal embedded startup script for host readiness
    bootstrap-openclaw.sh         # Legacy Docker/bootstrap path, deprecated or retained only for compatibility
docs/
  openclaw-gcp/
    README.md                     # Rewritten detailed runbook for new primary flow
README.md                         # Rewritten repo-level quickstart
tests/
  openclaw-gcp/
    test.sh                       # Expanded/updated shell contract tests
history/
  openclaw-gcp-one-line-installer/
    CONTEXT.md
    discovery.md
    approach.md
```

---

## 6. Dependency Order

> Dependency order for bead creation. This is planning guidance, not a runtime wave scheduler.

```text
Layer 1: Define the new startup/bootstrap contract and preflight expectations
Layer 2: Implement install.sh orchestration and prompt/preflight behavior
Layer 3: Adapt template/repair scripts to the minimal startup path
Layer 4: Rewrite docs and tests around the new primary flow
Layer 5: Final polish on deprecated legacy-path messaging and verification
```

### Parallelizable Groups

- Group A: startup-contract refactor and installer orchestration can be designed in parallel, but final merge depends on agreeing the startup contract.
- Group B: docs rewrite and test rewrite can proceed in parallel once the command surface and startup contract are stable.
- Group C: legacy-path cleanup/messaging should follow after the new primary flow and tests are stable.

---

## 7. Institutional Learnings Applied

No prior institutional learnings relevant to this feature.

---

## 8. Open Questions for Validating

- [ ] What exact `gcloud compute ssh` command shape preserves upstream installer interactivity while still allowing local-side failure handling and “stay connected on success” behavior?
- [ ] How will `install.sh` detect and safely handle reused templates or instances that still carry the legacy Docker/bootstrap startup contract?
- [ ] What VM readiness signal should gate the SSH/install phase so it does not race first-boot package operations or apt locks?
- [ ] Should `create-template.sh` make OpenClaw-specific flags optional, deprecated, or profile-dependent under the new primary flow?
- [ ] Should `repair-instance-bootstrap.sh` continue to target the same embedded script name/versioning scheme, or should startup script identity be reversioned explicitly for the minimal bootstrap path?
- [ ] How much of `bootstrap-openclaw.sh` should remain in-repo versus being replaced outright with `bootstrap-vm-prereqs.sh`?
