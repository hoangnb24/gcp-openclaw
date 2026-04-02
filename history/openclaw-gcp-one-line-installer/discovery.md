# Discovery Report: OpenClaw GCP One-Line Installer

**Date**: 2026-03-29
**Feature**: `openclaw-gcp-one-line-installer`
**CONTEXT.md reference**: `history/openclaw-gcp-one-line-installer/CONTEXT.md`

---

## Institutional Learnings

> Read during Phase 0 from `history/learnings/`

### Critical Patterns (Always Applied)

- None applicable. `history/learnings/critical-patterns.md` was not present.

### Domain-Specific Learnings

No prior learnings for this domain.

---

## Agent A: Architecture Snapshot

> Source: file tree analysis, existing script entrypoints, approved CONTEXT.md

### Relevant Packages / Modules

| Package/Module | Purpose | Key Files |
|----------------|---------|-----------|
| `scripts/openclaw-gcp/` | Shell-based provisioning, bootstrap, repair, backup, and clone flows | `create-instance.sh`, `create-template.sh`, `create-cloud-nat.sh`, `bootstrap-openclaw.sh`, `repair-instance-bootstrap.sh` |
| `docs/openclaw-gcp/` | Operator runbooks and lifecycle documentation | `README.md`, `backup-and-restore.md`, `sizing-and-cost.md` |
| `tests/openclaw-gcp/` | Mocked shell integration tests acting as behavior contract | `test.sh` |
| `.khuym/` | Runtime records and workflow state for this repo | `.khuym/STATE.md`, `.khuym/runtime/...` |

### Entry Points

- **Primary provisioning entrypoint today**: `scripts/openclaw-gcp/create-instance.sh`
- **Template builder**: `scripts/openclaw-gcp/create-template.sh`
- **Network prerequisite helper**: `scripts/openclaw-gcp/create-cloud-nat.sh`
- **Remote repair / SSH precedent**: `scripts/openclaw-gcp/repair-instance-bootstrap.sh`
- **Primary docs entrypoint today**: `README.md`

### Key Files to Model After

- `scripts/openclaw-gcp/create-instance.sh` — demonstrates the existing top-level orchestration pattern that the new `install.sh` should wrap rather than replace.
- `scripts/openclaw-gcp/create-template.sh` — demonstrates fail-fast validation, deterministic inputs, and drift guardrails.
- `scripts/openclaw-gcp/repair-instance-bootstrap.sh` — demonstrates `gcloud compute ssh` command assembly with `--tunnel-through-iap` and remote `--command`.
- `tests/openclaw-gcp/test.sh` — demonstrates the repo’s contract-test style with mocked `gcloud`.

---

## Agent B: Pattern Search

> Source: grep, direct file reading, test harness inspection

### Similar Existing Implementations

| Feature/Component | Location | Pattern Used | Reusable? |
|-------------------|----------|--------------|-----------|
| Baseline VM creation | `scripts/openclaw-gcp/create-instance.sh` | Orchestrator script over helper scripts with staged logging | Yes |
| Deterministic template creation | `scripts/openclaw-gcp/create-template.sh` | Strict validation + resolution record + create/reuse logic | Yes |
| NAT auto-ensure for internal-only templates | `scripts/openclaw-gcp/create-instance.sh` + `scripts/openclaw-gcp/create-cloud-nat.sh` | Template inspection + helper invocation | Yes |
| Remote SSH command execution | `scripts/openclaw-gcp/repair-instance-bootstrap.sh` | `gcloud compute ssh` with optional IAP | Yes |
| Dry-run documentation verification | `tests/openclaw-gcp/test.sh` | README/runbook smoke tests | Yes |

### Reusable Utilities

- **CLI help + validation**: all operator scripts follow the same `print_help`, `die`, `require_command`, `unknown option` structure.
- **Template reuse guard**: `create-template.sh` rejects explicit template-shaping flags when reusing an existing template.
- **Zone/region validation**: `create-template.sh`, `create-instance.sh`, and `create-snapshot-policy.sh` all enforce region-zone consistency.
- **Resolution record pattern**: `create-template.sh` writes resolved image and metadata inputs to `.khuym/runtime/openclaw-gcp/resolved-debian-image.txt`.
- **Mocked `gcloud` harness**: `tests/openclaw-gcp/test.sh` already supports high-confidence shell contract tests without real GCP calls.

### Naming Conventions

- Scripts use action-first kebab-case names: `create-*`, `spawn-*`, `repair-*`.
- Default resource names are stable and operator-friendly: `oc-main`, `oc-template`, `oc-router`, `oc-nat`.
- Required project selection is always explicit with `--project-id`.
- Provisioning/maintenance scripts consistently support `--help` and `--dry-run`.
- Boolean behavior is expressed through explicit flags rather than config files.

---

## Agent C: Constraints Analysis

> Source: repo file layout, local tool versions, shell/test entrypoints

### Runtime & Framework

- **Runtime**: POSIX-style shell scripts executed with Bash
- **Language**: Bash (`GNU bash 5.3.9`)
- **OS in current dev environment**: `Darwin arm64`
- **Primary operator dependency**: Google Cloud CLI (`Google Cloud SDK 543.0.0`)
- **Repository shape**: shell/doc repo only; no `package.json`, no local Node/TypeScript build system

### Existing Dependencies (Relevant to This Feature)

| Package | Version | Purpose |
|---------|---------|---------|
| `gcloud` | `543.0.0` | Provisioning, template inspection, VM creation, SSH/IAP access |
| `bash` | `5.3.9` | Execution runtime for all repo scripts |
| `make` | system tool | Single test entrypoint wrapper |

### New Dependencies Needed

| Package | Reason | Risk Level |
|---------|--------|------------|
| No new local package dependency is clearly required | The new flow can stay shell + `gcloud` | LOW |
| `https://openclaw.ai/install.sh` | New upstream runtime dependency for host-side install/onboarding | HIGH |
| Required Google Cloud APIs / IAM / firewall readiness | New explicit prerequisite surface for one-line flow | HIGH |

### Build / Quality Requirements

```bash
# Existing verification surface in this repo
bash -n scripts/openclaw-gcp/*.sh tests/openclaw-gcp/test.sh
make test
```

### Repo-Level Constraints

- The highest current regression surface is the startup-script/bootstrap contract in `tests/openclaw-gcp/test.sh`, which asserts Docker/bootstrap-specific script content very tightly.
- Current docs are coupled to the Docker-first host bootstrap path and will need coordinated rewriting if the primary flow changes.
- `create-instance.sh` currently does not own any SSH/install behavior; adding auto-SSH likely belongs in a new wrapper rather than changing its core contract.

---

## Agent D: External Research

> Source: official OpenClaw docs, direct inspection of `https://openclaw.ai/install.sh`, official Google Cloud docs

### Library Documentation

| Library / Platform | Version | Key Docs |
|--------------------|---------|----------|
| OpenClaw installer | current docs as of 2026-03-29 | https://docs.openclaw.ai/install/installer |
| OpenClaw install overview | current docs as of 2026-03-29 | https://docs.openclaw.ai/install |
| Compute Engine API prerequisites | current docs as of 2026-03-29 | https://docs.cloud.google.com/compute/docs/api/prereqs |
| IAP TCP forwarding overview | current docs as of 2026-03-29 | https://docs.cloud.google.com/iap/docs/tcp-forwarding-overview |
| Connect to Linux VMs using IAP | current docs as of 2026-03-29 | https://docs.cloud.google.com/compute/docs/connect/ssh-using-iap |
| Service enablement with Service Usage | current docs as of 2026-03-29 | https://docs.cloud.google.com/service-usage/docs/hierarchical-service-activation/manage-enablement |

### Community / Vendor Patterns

- **Pattern**: keep the local wrapper focused on infra readiness and hand off product installation to the vendor-maintained installer.
  - Why it applies: locked decision D12 explicitly moves OpenClaw installation responsibility away from repo-owned bootstrap logic.
  - Reference: OpenClaw installer docs show `install.sh` is the recommended macOS/Linux installation path.

- **Pattern**: use IAP TCP forwarding for SSH to internal-only VMs.
  - Why it applies: locked decision D8 keeps the secure default of internal-only VMs with IAP access.
  - Reference: Google documents `gcloud compute ssh --tunnel-through-iap` as the supported path for internal-IP SSH.

- **Pattern**: explicitly verify and enable required project services before attempting resource creation.
  - Why it applies: locked decisions D2 and D6 require full readiness checks up front, not deferred provisioning failures.
  - Reference: Google’s Service Usage docs note that APIs must be enabled before they can be used.

### Known Gotchas / Anti-Patterns

- **Gotcha**: `install.sh` is interactive when a TTY is present, but defaults to `npm` and warns when no TTY is available unless flags are supplied.
  - Why it matters: the auto-SSH handoff must preserve an interactive terminal if the desired experience is the upstream onboarding flow.
  - How to avoid: launch the installer from an actual SSH terminal session, not a detached non-interactive remote command, when the goal is onboarding.

- **Gotcha**: OpenClaw’s `install.sh` is broader than “download OpenClaw”; it can install Node, Git, build tools, Homebrew (on macOS), and can alter npm prefix / PATH behavior on Linux.
  - Why it matters: the repo’s VM startup script should stay minimal and must not make conflicting assumptions about OpenClaw or Node already being installed.
  - How to avoid: keep the VM bootstrap limited to generic host readiness and let `install.sh` own product/runtime installation.

- **Gotcha**: IAP SSH still requires project/auth readiness plus firewall allowance from IAP IP ranges to port `22`.
  - Why it matters: internal-only networking alone is not enough; a “works end-to-end” installer must catch missing IAP prerequisites early or ensure the environment already satisfies them.
  - How to avoid: include explicit readiness checks for auth/project/API state and decide during planning whether firewall handling is automated or documented as a hard prerequisite.

- **Anti-pattern**: embedding more repo-managed OpenClaw onboarding logic into the startup script while also adopting the upstream installer.
  - Common mistake: keeping the old bootstrap path alive inside metadata while also invoking `install.sh`, creating overlapping ownership.
  - Correct approach: reduce startup metadata to minimal machine prep and make the SSH-triggered upstream installer the only primary OpenClaw install/onboard path.

- **Anti-pattern**: hiding project/API/IAM failures behind a late provisioning error.
  - Common mistake: attempting VM creation first and surfacing opaque `gcloud` failures later.
  - Correct approach: do prerequisite gating first, and present exact recovery commands before provisioning starts.

### Open Questions

- [ ] Which exact services should the readiness gate verify or enable-ability-test beyond `compute.googleapis.com` and `iap.googleapis.com`? The feature requires “everything required,” but the final matrix still needs to be locked in approach planning.
- [ ] Should the new primary flow automate or only verify the IAP firewall-rule requirement for port `22` from `35.235.240.0/20`?
- [ ] Should the SSH handoff invoke plain `bash` on the piped installer or pass explicit upstream flags/env vars to control versioning and prompt behavior in edge cases?

---

## Summary for Synthesis (Phase 2 Input)

**What we have**: a clean shell-based GCP operator repo with a strong provisioning core, deterministic template logic, Cloud NAT support, IAP SSH precedent, and a contract-style shell test suite. The current primary story is still centered on a repo-managed Docker/bootstrap path.

**What we need**: a new top-level `scripts/openclaw-gcp/install.sh` that becomes the primary productized workflow by wrapping the existing template-based provisioning path, enforcing prerequisite readiness, and handing off host installation/onboarding to the upstream OpenClaw installer over an interactive SSH session.

**Key constraints from research**:
- The new flow should keep using existing provisioning primitives rather than rewriting infra shape.
- OpenClaw `install.sh` is interactive and TTY-sensitive, and it owns Node/OpenClaw installation plus onboarding.
- Internal-only IAP SSH requires more than just `--tunnel-through-iap`; project auth, permissions, and firewall readiness matter.
- Current tests and docs are tightly coupled to the Docker/bootstrap startup script and will need deliberate migration.

**Institutional warnings to honor**:
- No prior institutional learnings exist for this domain.
