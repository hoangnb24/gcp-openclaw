# OpenClaw GCP Cloud-Shell-First UX — Context

**Feature slug:** openclaw-gcp-cloud-shell-first
**Date:** 2026-04-01
**Exploring session:** complete
**Scope:** Deep

---

## Feature Boundary

Turn this repo into a Cloud-Shell-first operator experience where the primary story is: click an official Open in Cloud Shell entrypoint, land in this repo, receive a safe guided welcome, run a dead-simple `up` command, and later run a dead-simple `down` command that destroys exactly the stack the tool owns while preserving the repo's existing safety and determinism. This phase does not introduce a hosted control plane or a ground-up rewrite.

**Domain type(s):** READ | CALL | RUN | ORGANIZE

---

## Locked Decisions

These are fixed. Planning must implement them exactly. No creative reinterpretation.

### Cloud Shell Entry And First-Run UX
- **D1** Use an official `Open in Cloud Shell` launch as the primary quickstart, and have it open the repo plus auto-run a safe, non-mutating welcome script.
  *Rationale: The browser-first experience should feel guided and obvious without provisioning anything automatically.*

- **D2** The first real `up` run must require an explicit stack name from the user, and that chosen stack becomes the remembered current stack in local Cloud Shell state.
  *Rationale: Stack ownership should stay explicit and teardown-safe rather than being auto-named.*

- **D3** On first-run in Cloud Shell, the welcome script should interactively ask for the stack name and then hand the user into the exact `up` command path.
  *Rationale: This keeps the experience guided and low-friction while preserving explicit user intent.*

### Stack Model And Safety
- **D4** `down` should default to the remembered current stack only for interactive Cloud Shell use. Non-interactive or automation usage must require an explicit stack selection.
  *Rationale: Human UX should stay simple, but destructive automation must remain stricter and explicit.*

- **D5** GCP labels are the durable source of truth for stack ownership and discovery. Local Cloud Shell state is only a convenience pointer to the current stack.
  *Rationale: Cloud Shell local state can persist across normal sessions but is not durable enough to be the sole source of truth.*

- **D6** The product layer should derive managed GCP resource names from the stack ID automatically and keep those raw names out of the primary UX.
  *Rationale: The stack, not individual router/template/NAT names, is the unit of ownership in the new operator story.*

- **D7** New stacks should default to the `persistent` lifecycle.
  *Rationale: Even in the simplified Cloud-Shell-first flow, the product should not imply demo-only or short-lived behavior by default.*

### Status Experience
- **D8** `status` should default to a human-readable operator summary, with an optional machine-readable mode if that can be added cleanly in Phase 1.
  *Rationale: Browser-first operators need a reassuring summary of the current stack and its managed resources, while leaving room for automation later.*

### Agent's Discretion
- Planning may choose the exact wrapper shape for the new product layer, such as a top-level `bin/openclaw-gcp`, `scripts/openclaw-gcp/up.sh` and companions, or an equally thin alternative, as long as the primary UX remains simple and the implementation layers over existing scripts instead of replacing them wholesale.
- Planning may choose the exact local state file format and path in Cloud Shell, provided it is small, human-inspectable, and clearly treated as convenience state rather than the durable contract.
- Planning may choose whether optional machine-readable `status` output ships in Phase 1 if it stays thin and does not dilute the human-first default output.

---

## Specific Ideas & References

- The target story is: `Open in Cloud Shell -> welcome -> up -> status -> down`.
- Cloud Shell is the browser-based operator terminal, not the OpenClaw runtime host.
- Keep `gcloud` as the backend execution engine, but increase product value through workflow UX, stack identity, state discovery, resumability, and clearer operator contracts.
- Preserve existing guardrails already present in the repo: exact-name destroy behavior, readiness gating, reuse/repair logic, and dry-run-friendly command contracts.
- Suggested label family from the user request:
  - `openclaw_managed=true`
  - `openclaw_stack_id=<id>`
  - `openclaw_tool=openclaw-gcp`
  - `openclaw_lifecycle=persistent` by default in Phase 1

---

## Existing Code Context

From the quick codebase scout during exploring.
Downstream agents: read these files before planning to avoid reinventing existing patterns.

### Reusable Assets
- `README.md` — current root-level product story; today it is installer-first and should become Cloud-Shell-first in Phase 1.
- `docs/openclaw-gcp/README.md` — current operator runbook with install and destroy guidance; likely the main place to reshape the browser-first quickstart and stack-based operator story.
- `scripts/openclaw-gcp/install.sh` — current primary operator entrypoint; already performs local preflight checks, create-or-reuse behavior, readiness gating, repair/reuse logic, and SSH handoff to the upstream installer.
- `scripts/openclaw-gcp/destroy.sh` — current exact-name destroy companion with qualification gates, typed confirmation, explicit `--project-id` protection for destructive runs, deterministic delete ordering, and dry-run behavior.
- `scripts/openclaw-gcp/create-instance.sh` — current composition layer that ensures template and Cloud NAT, then creates the VM; a strong candidate to remain the lower-level provisioning engine behind a new `up` wrapper.
- `scripts/openclaw-gcp/create-template.sh` — deterministic template creation path that already persists and validates metadata contracts, which is a likely insertion point for stack labels/metadata propagation.
- `tests/openclaw-gcp/test.sh` — shell test suite with mocked `gcloud` behavior and strong contract coverage for docs examples, dry-run output, readiness logic, and destroy safety.

### Established Patterns
- Deterministic operator contracts: `scripts/openclaw-gcp/create-template.sh` records resolved image and startup-contract details, rejects ambiguous reuse, and prints dry-run commands rather than hiding side effects.
- Reuse/repair instead of blind recreate: `scripts/openclaw-gcp/install.sh` checks existing instance metadata, allows repairable legacy contracts, and reruns readiness checks after repair.
- Strong destroy safety posture: `scripts/openclaw-gcp/destroy.sh` qualifies exact resources before deletion, keeps explicit target order, and requires typed confirmation in interactive real runs.
- Documentation-backed shell contracts: `tests/openclaw-gcp/test.sh` already validates README and runbook command examples in dry-run mode, which makes it a natural enforcement point for the new Cloud-Shell-first UX.

### Integration Points
- `scripts/openclaw-gcp/install.sh` — likely lower-level engine for the new `up` command or a source of reusable preflight/readiness/handoff functions.
- `scripts/openclaw-gcp/create-instance.sh` — likely lower-level engine for stack-derived resource creation and reuse.
- `scripts/openclaw-gcp/create-template.sh` — likely place to add stack labels or metadata on template-backed resources if label coverage needs to start at template creation time.
- `scripts/openclaw-gcp/destroy.sh` — likely lower-level engine for the new `down` command once stack-derived names or stack-discovered resources are resolved.
- `README.md` and `docs/openclaw-gcp/README.md` — primary docs surfaces for the Open in Cloud Shell button, browser-first quickstart, and the simplified `up` / `down` / `status` story.
- `tests/openclaw-gcp/test.sh` — primary verification surface for preserving guardrails while adding the new wrapper UX and docs examples.

---

## Canonical References

**Downstream agents MUST read these before planning or implementing.**

- `README.md` — current root product positioning and quickstart that Phase 1 will need to recenter around Cloud Shell.
- `docs/openclaw-gcp/README.md` — current operator runbook and destroy guidance whose contracts must remain safe after productization.
- `tests/openclaw-gcp/test.sh` — existing behavior contract for shell flows, documentation examples, dry-run safety, readiness gating, and destroy safeguards.

---

## Outstanding Questions

### Deferred to Planning
- [ ] Verify the exact official Google-supported `Open in Cloud Shell` launch URL/button parameters for this repo and the safest way to auto-run a welcome script without violating the desired non-mutating startup behavior. — This requires official documentation research and should be settled before implementation details are finalized.
- [ ] Decide the thinnest concrete command surface for Phase 1, such as `bin/openclaw-gcp` versus `scripts/openclaw-gcp/up.sh` and companions. — This requires codebase-aware planning to minimize churn while keeping the UX simple.
- [ ] Decide the exact stack-derived naming convention for instance/template/router/NAT resources. — Planning should choose a stable, readable, label-compatible naming contract that preserves exact-target safety.
- [ ] Decide the exact local convenience state path and file shape in Cloud Shell. — Planning should pick a path that aligns with Cloud Shell persistence expectations while making it clear that labels remain the durable truth.
- [ ] Determine which managed GCP resources can and should receive labels directly versus requiring fallback metadata or name derivation. — Planning should confirm label support across the relevant `gcloud` resource types so the durable stack contract remains accurate.

---

## Deferred Ideas

- Add first-class `ssh` and `logs` commands after Phase 1 — explicitly mentioned as later commands, but out of scope for the current practical productization layer.
- Build a hosted control plane or move away from Bash — explicitly out of scope for this phase because the desired solution is a thin UX layer over the existing operator scripts.
- Expose richer lifecycle controls beyond the default `persistent` posture — possible future work after the stack model and Cloud-Shell-first UX are proven.

---

## Handoff Note

CONTEXT.md is the single source of truth for this feature.

- **planning** reads: locked decisions, code context, canonical refs, deferred-to-planning questions
- **validating** reads: locked decisions (to verify plan-checker coverage)
- **reviewing** reads: locked decisions (for UAT verification)

Decision IDs (D1, D2...) are stable. Reference them by ID in all downstream artifacts.
