# OpenClaw GCP One-Line Installer — Context

**Feature slug:** openclaw-gcp-one-line-installer
**Date:** 2026-03-29
**Exploring session:** complete
**Scope:** Standard

---

## Feature Boundary

Replace the repository's current primary Docker/bootstrap operator flow with a simpler one-line GCP installer that verifies all required local prerequisites, provisions or reuses the target VM through the existing template-based infra path, automatically SSHes into the instance, and immediately launches the upstream OpenClaw installer via `curl -fsSL https://openclaw.ai/install.sh | bash`.

**Domain type(s):** RUN | CALL | READ

---

## Locked Decisions

These are fixed. Planning must implement them exactly. No creative reinterpretation.

### Primary Flow
- **D1** The one-line installer must provision the VM, automatically SSH into it, and immediately launch `curl -fsSL https://openclaw.ai/install.sh | bash` so the user lands directly in the upstream interactive installer on the instance.
  *Rationale: The user wants the first terminal experience on the VM to mirror running the upstream onboarding flow directly, not a repo-managed Docker bootstrap.*

- **D7** This upstream-install path replaces the current Docker/bootstrap path as the repository's primary productized workflow, and the repo should be rewritten around that new primary path on the feature branch.
  *Rationale: The user wants this to become the main supported experience, not an experimental side path.*

- **D9** After the upstream installer completes successfully, the wrapper leaves the user inside the VM's SSH session at a normal shell prompt.
  *Rationale: The user wants continuity in the remote shell after onboarding rather than being dropped back to the local machine automatically.*

- **D10** The primary user-facing entrypoint is a new repo script invoked as `bash scripts/openclaw-gcp/install.sh`.
  *Rationale: The user wants a clear repo-native one-line entrypoint rather than a root wrapper or remote curl bootstrap.*

### Readiness And Failure Handling
- **D2** Before any provisioning begins, the installer must check prerequisites and fail fast with a clear checklist plus exact recovery commands instead of attempting remediation automatically.
  *Rationale: The user does not want the tool making local environment changes or interactive recovery decisions on their behalf.*

- **D6** The prerequisite gate must verify everything required for the flow to work, including `gcloud`, authenticated sessions, active project, required APIs, and any other mandatory local readiness checks.
  *Rationale: The user explicitly wants the flow to catch all must-have setup issues up front instead of failing later during provisioning.*

- **D5** Missing required inputs should be collected through interactive terminal prompts during normal use, but in non-interactive contexts the installer must exit with a clear error telling the caller to pass flags explicitly.
  *Rationale: The user wants a friendly interactive default without making automation ambiguous or hanging in non-interactive shells.*

- **D3** If the requested VM already exists, the installer must reuse that instance rather than replacing it, then continue by SSHing into it and launching the upstream installer there.
  *Rationale: Reusing an existing target is safer and aligns with an operator rerunning the installer against a known instance.*

- **D11** If the upstream installer exits with an error, the wrapper should end the SSH session and print a local-side failure summary plus next steps.
  *Rationale: The user chose a clean failure return to the local terminal rather than leaving them inside the VM for manual debugging by default.*

### Infra Shape And Boot Behavior
- **D4** The one-line installer must preserve the current template-based provisioning architecture and wrap it behind a simpler entrypoint rather than replacing the underlying infra primitives with direct instance creation.
  *Rationale: The existing deterministic template model remains valuable and should stay the foundation underneath the simpler UX.*

- **D8** The new primary flow keeps the current secure default networking posture: internal-only VM, Cloud NAT for egress, and IAP for SSH.
  *Rationale: The user wants the simplified installer to preserve the current secure-by-default access model.*

- **D12** The VM startup/bootstrap step should preinstall only general prerequisites such as package updates and `curl`, while leaving all actual OpenClaw installation and onboarding to `https://openclaw.ai/install.sh`.
  *Rationale: The user wants to stop managing OpenClaw installation inside repo-owned startup scripts and delegate product installation to the upstream installer.*

### Agent's Discretion
- Planning may decide the exact prompt wording, prerequisite command set, and script decomposition as long as D1-D12 are honored.
- Planning may decide how much of the legacy Docker/bootstrap implementation remains in the repo as non-primary or deprecated code, as long as the new primary workflow no longer depends on that path.

---

## Specific Ideas & References

- Upstream installer command to launch on the VM: `curl -fsSL https://openclaw.ai/install.sh | bash`
- The user wants the terminal experience to feel like they were automatically SSHed into the VM and immediately dropped into `openclaw onboard`.
- The user explicitly wants this work done on a new branch and merged after it is ready.

---

## Existing Code Context

From the quick codebase scout during exploring.
Downstream agents: read these files before planning to avoid reinventing existing patterns.

### Reusable Assets
- `scripts/openclaw-gcp/create-instance.sh` — current top-level provisioning orchestrator; already handles template creation, Cloud NAT auto-ensure, and VM creation.
- `scripts/openclaw-gcp/create-template.sh` — current deterministic template creator with strong guardrails around identity mode, startup script sources, and image resolution.
- `scripts/openclaw-gcp/create-cloud-nat.sh` — current idempotent NAT helper for the internal-only networking posture.
- `scripts/openclaw-gcp/repair-instance-bootstrap.sh` — existing example of running `gcloud compute ssh` with IAP and remote commands after metadata changes.
- `tests/openclaw-gcp/test.sh` — current contract tests for parsing, guardrails, NAT behavior, repair flow, and the embedded startup wrapper expectations.

### Established Patterns
- Deterministic provisioning inputs are treated as a first-class requirement and recorded explicitly.
- The default operator posture is internal-only instances with Cloud NAT and IAP-based SSH.
- Scripts favor fail-fast validation, explicit help surfaces, and `--dry-run` support.
- Existing instance-template reuse already rejects silent drift when explicit template-shaping flags would be ignored.

### Integration Points
- `scripts/openclaw-gcp/create-instance.sh` — likely remains the provisioning backbone beneath the new `install.sh` entrypoint.
- `scripts/openclaw-gcp/bootstrap-openclaw.sh` — current host bootstrap implementation that the new primary flow is expected to replace or drastically reduce in responsibility.
- `README.md` — current primary operator runbook that still documents the Docker/bootstrap path and must be rewritten for the new default flow.
- `docs/openclaw-gcp/README.md` — current detailed runbook for the existing operator experience and a likely target for primary-flow documentation changes.

---

## Canonical References

**Downstream agents MUST read these before planning or implementing.**

- `README.md` — Defines the current primary operator story that this feature is replacing.
- `docs/openclaw-gcp/README.md` — Defines the current detailed provisioning and host-baseline runbook.
- `scripts/openclaw-gcp/create-instance.sh` — Current provisioning orchestrator and the most important integration seam for the new entrypoint.
- `scripts/openclaw-gcp/create-template.sh` — Current template and guardrail logic that must remain compatible with the new flow.
- `scripts/openclaw-gcp/bootstrap-openclaw.sh` — Current repo-managed host bootstrap path that is being displaced as the primary productized installer.
- `tests/openclaw-gcp/test.sh` — Current behavioral contract and likely verification surface to update.

---

## Outstanding Questions

### Resolve Before Planning

None.

### Deferred to Planning

- [ ] Define the exact prerequisite matrix and how each failure is detected and reported locally — requires implementation-level command and UX design.
- [ ] Define the exact interactive prompt set and precedence between prompts, flags, and existing `gcloud` configuration — requires CLI flow design.
- [ ] Define the minimal VM startup script contents needed before SSH handoff now that repo-managed OpenClaw installation is no longer primary — requires provisioning design.
- [ ] Decide how the new `install.sh` entrypoint composes with existing scripts versus which responsibilities move out of `create-instance.sh` — requires codebase-level refactor planning.
- [ ] Define the migration strategy for legacy Docker/bootstrap docs, tests, and helper scripts so the new upstream-install flow becomes the repository's primary story cleanly.

---

## Deferred Ideas

- Automatic local prerequisite remediation was explicitly rejected; the installer should instruct rather than repair.
- Defaulting missing required inputs from repo defaults without prompting in interactive use was rejected in favor of prompt-first UX.
- Auto-replacing existing instances was rejected in favor of reuse.
- Leaving the user inside a failed SSH session for manual debugging was rejected in favor of returning to the local shell with guidance.

---

## Handoff Note

CONTEXT.md is the single source of truth for this feature.

- **planning** reads: locked decisions, code context, canonical refs, deferred-to-planning questions
- **validating** reads: locked decisions (to verify plan-checker coverage)
- **reviewing** reads: locked decisions (for UAT verification)

Decision IDs (D1, D2...) are stable. Reference them by ID in all downstream artifacts.
