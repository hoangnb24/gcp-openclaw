# OpenClaw GCP Destroy Script — Context

**Feature slug:** openclaw-gcp-destroy-script
**Date:** 2026-03-31
**Exploring session:** complete
**Scope:** Standard

---

## Feature Boundary

Add a repo-native destroy entrypoint beside `scripts/openclaw-gcp/install.sh` that fully tears down an OpenClaw GCP deployment by exact resource names, with safe confirmation behavior, dry-run support, and clear partial-failure reporting, without guessing about shared or custom infrastructure.

**Domain type(s):** RUN | CALL | READ

---

## Locked Decisions

These are fixed. Planning must implement them exactly. No creative reinterpretation.

### Destruction Scope
- **D1** The destroy script must perform a full teardown by default, removing the deployment's primary resources rather than only deleting the VM instance.
  *Rationale: The user wants the destroy path to be a real cleanup command, not a narrow instance-only helper.*

- **D3** Full cleanup includes the core installer stack plus optional repo-managed extras like snapshot policies and machine-image or clone-related artifacts, but those extras are deleted only when their exact names are explicitly provided.
  *Rationale: The user wants the script capable of complete cleanup without broad discovery or accidental deletion of unrelated resources.*

### Safety Boundaries
- **D2** Destruction must be exact-name and contract-bound only; the script deletes only the resources explicitly addressed by its flags and must fail instead of guessing when a target appears shared, custom, or outside the expected OpenClaw contract.
  *Rationale: The user does not want the destroy flow making broad inferences about surrounding GCP infrastructure.*

- **D4** Interactive runs must require an explicit typed confirmation before any real deletion begins, while automation may bypass that confirmation with a `--yes` style flag.
  *Rationale: The command is intentionally destructive and needs a stronger guardrail than a default yes/no prompt.*

### Failure Handling
- **D5** If teardown hits a partial failure, the script must continue attempting the remaining explicitly targeted deletions, then exit non-zero with a final summary showing what succeeded, what failed, and what still needs manual cleanup.
  *Rationale: The user wants maximum cleanup progress in one run without hiding failures.*

### Agent's Discretion
- Planning may choose the exact script name, flag layout, deletion order, and summary format as long as D1-D5 are preserved.
- Planning may decide which optional extras are supported in the first version, as long as core teardown is complete and any extra-resource deletion remains explicit-name only.

---

## Specific Ideas & References

- The new destroy entrypoint must live beside the current installer flow under `scripts/openclaw-gcp/`.
- The destroy experience should mirror the current operator style established by `install.sh`: clear help text, `--dry-run`, explicit flags, and user-friendly failure guidance.
- The script is meant to complement the already-shipped one-line installer branch rather than replace its provisioning architecture.

---

## Existing Code Context

From the quick codebase scout during exploring.
Downstream agents: read these files before planning to avoid reinventing existing patterns.

### Reusable Assets
- `scripts/openclaw-gcp/install.sh` — current primary operator entrypoint with strong preflight UX, `--dry-run`, interactive/non-interactive handling, and failure-summary patterns that the destroy flow should likely mirror.
- `scripts/openclaw-gcp/create-instance.sh` — provisioning orchestrator that defines the core deployment resource names and the create path for VM, template, and Cloud NAT dependencies.
- `scripts/openclaw-gcp/create-template.sh` — deterministic template helper with contract metadata and explicit drift guardrails, useful for defining what counts as an expected repo-managed resource.
- `scripts/openclaw-gcp/create-cloud-nat.sh` — idempotent helper that creates the Cloud Router and Cloud NAT pair the destroy flow may need to tear down.
- `scripts/openclaw-gcp/create-snapshot-policy.sh` — existing day-2 script that defines the snapshot policy surface and attachment model relevant to optional extra cleanup.
- `scripts/openclaw-gcp/create-machine-image.sh` — existing machine-image creation surface relevant to optional explicit extra cleanup.
- `scripts/openclaw-gcp/spawn-from-image.sh` — existing clone flow that shows how machine-image-derived resources are named and consumed.
- `tests/openclaw-gcp/test.sh` — current shell contract test suite where the destroy flow will likely need parser, dry-run, and failure-path coverage.

### Established Patterns
- Operator scripts in this repo prefer fail-fast validation, explicit help text, and `--dry-run` support.
- The current primary OpenClaw GCP story is template-backed provisioning with internal-only networking, Cloud NAT egress, and IAP SSH access.
- Shared infra assumptions are guarded carefully; the installer and template flows already reject ambiguous drift instead of silently proceeding.
- User-facing scripts print concrete next steps and recovery guidance instead of silently swallowing infrastructure state mismatches.

### Integration Points
- `README.md` — documents the current primary entrypoint and will need to mention the destroy companion flow.
- `docs/openclaw-gcp/README.md` — operator runbook likely needs teardown guidance aligned with the new script contract.
- `scripts/openclaw-gcp/install.sh` — the closest CLI/UX reference for flags, prompts, dry-run behavior, and human-readable summaries.
- `scripts/openclaw-gcp/create-instance.sh` and `scripts/openclaw-gcp/create-cloud-nat.sh` — define the core resources and default names the destroy flow must understand.
- `scripts/openclaw-gcp/create-snapshot-policy.sh`, `scripts/openclaw-gcp/create-machine-image.sh`, and `scripts/openclaw-gcp/spawn-from-image.sh` — define optional extra resources that may be removed only when explicitly named.

---

## Canonical References

**Downstream agents MUST read these before planning or implementing.**

- `history/openclaw-gcp-one-line-installer/CONTEXT.md` — defines the primary installer flow this destroy script is complementing.
- `README.md` — defines the current primary operator story and where the new destroy entrypoint will be surfaced.
- `docs/openclaw-gcp/README.md` — defines the operator runbook that should gain teardown instructions.
- `scripts/openclaw-gcp/install.sh` — defines the current CLI contract style to mirror for destroy.
- `scripts/openclaw-gcp/create-instance.sh` — defines how core resources are created and named.
- `scripts/openclaw-gcp/create-template.sh` — defines expected template contract details and exact-name drift rules.
- `scripts/openclaw-gcp/create-cloud-nat.sh` — defines router/NAT naming and ownership expectations.
- `scripts/openclaw-gcp/create-snapshot-policy.sh` — defines optional snapshot-policy cleanup surface.
- `scripts/openclaw-gcp/create-machine-image.sh` — defines optional machine-image cleanup surface.
- `tests/openclaw-gcp/test.sh` — current verification surface for shell contract behavior.

---

## Outstanding Questions

### Resolve Before Planning

None.

### Deferred to Planning

- [ ] Decide the exact destroy entrypoint name and whether it should be `destroy.sh` or a more specific `destroy-instance-stack.sh` style variant under `scripts/openclaw-gcp/` — requires CLI contract design.
- [ ] Define the exact flag set for optional extra resources such as snapshot policies, machine images, and clone-related resources — requires existing script surface review and usability tradeoff analysis.
- [ ] Define the deletion order and exact contract checks that prevent removing shared infrastructure while still allowing full teardown of repo-managed defaults — requires implementation design against GCP dependencies.
- [ ] Define how boot-disk cleanup is detected and reported, especially when instance deletion and disk lifecycle behavior diverge from default expectations — requires GCP behavior verification.
- [ ] Define the exact summary/reporting format for partial failures and the most useful manual cleanup hints — requires CLI UX design.
- [ ] Decide the required automated test matrix for dry-run, confirmation, exact-name protection, and partial-failure continuation behavior — requires shell test planning.

---

## Deferred Ideas

- Broad auto-discovery of related infrastructure was explicitly rejected; the destroy flow must not infer or sweep custom/shared resources.
- Weak confirmation UX such as plain `y/N` prompts was rejected in favor of typed confirmation.
- Stop-on-first-error teardown was rejected in favor of best-effort continuation with a non-zero final summary.

---

## Handoff Note

CONTEXT.md is the single source of truth for this feature.

- **planning** reads: locked decisions, code context, canonical refs, deferred-to-planning questions
- **validating** reads: locked decisions (to verify plan-checker coverage)
- **reviewing** reads: locked decisions (for UAT verification)

Decision IDs (D1, D2...) are stable. Reference them by ID in all downstream artifacts.
