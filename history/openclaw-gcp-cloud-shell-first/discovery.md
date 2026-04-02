# Discovery Report: OpenClaw GCP Cloud-Shell-First UX

**Date**: 2026-04-01
**Feature**: `openclaw-gcp-cloud-shell-first`
**CONTEXT.md reference**: `history/openclaw-gcp-cloud-shell-first/CONTEXT.md`

---

## Institutional Learnings

> Read during Phase 0 from `history/learnings/`

### Critical Patterns (Always Applied)

- None applicable. `history/learnings/critical-patterns.md` was not present.

### Domain-Specific Learnings

No prior learnings for this domain.

---

## Agent A: Architecture Snapshot

> Source: file tree analysis, current shell entrypoints, existing planning artifacts

### Relevant Packages / Modules

| Package/Module | Purpose | Key Files |
|----------------|---------|-----------|
| `scripts/openclaw-gcp/` | Operator shell scripts for provisioning, install handoff, destroy, backups, and clones | `install.sh`, `destroy.sh`, `create-instance.sh`, `create-template.sh`, `create-cloud-nat.sh` |
| `docs/openclaw-gcp/` | Operator-facing runbooks and lifecycle docs | `README.md`, `backup-and-restore.md`, `sizing-and-cost.md` |
| `tests/openclaw-gcp/` | Mocked shell integration tests and docs smoke coverage | `test.sh` |
| `.khuym/` | Workflow state and findings from prior work in this repo | `.khuym/STATE.md`, `.khuym/findings/*` |
| `history/` | Prior planning records for adjacent features | `openclaw-gcp-one-line-installer/*`, `openclaw-gcp-destroy-script/*` |

### Entry Points

- **Current primary product entrypoint**: `scripts/openclaw-gcp/install.sh`
- **Current destructive companion**: `scripts/openclaw-gcp/destroy.sh`
- **Provisioning core**: `scripts/openclaw-gcp/create-instance.sh`
- **Template contract owner**: `scripts/openclaw-gcp/create-template.sh`
- **Network helper**: `scripts/openclaw-gcp/create-cloud-nat.sh`
- **Root product story today**: `README.md`
- **Detailed operator story today**: `docs/openclaw-gcp/README.md`

### Key Files to Model After

- `scripts/openclaw-gcp/install.sh` — already combines preflight, create-or-reuse behavior, readiness gating, and interactive SSH handoff. This is the strongest lower-level engine for a new `up` wrapper.
- `scripts/openclaw-gcp/destroy.sh` — already embodies the repo’s safety posture: exact-target qualification, typed confirmation, and explicit `--project-id` protection.
- `scripts/openclaw-gcp/create-instance.sh` — already handles deterministic template-backed instance creation and internal-only NAT setup without entangling itself with SSH/install UX.
- `scripts/openclaw-gcp/create-template.sh` — already owns startup metadata, image resolution, and drift rejection, so it is the natural place to add stack metadata and labels for template-backed resources.
- `scripts/openclaw-gcp/create-machine-image.sh` — already shows a precedent for using `gcloud --labels` in this repo.
- `tests/openclaw-gcp/test.sh` — already encodes the repo’s shell contract style and documentation smoke coverage.

---

## Agent B: Pattern Search

> Source: direct file reading, grep over scripts/docs/tests, prior planning artifacts

### Similar Existing Implementations

| Feature/Component | Location | Pattern Used | Reusable? |
|-------------------|----------|--------------|-----------|
| Interactive top-level operator flow | `scripts/openclaw-gcp/install.sh` | Wrapper script over lower-level infra helpers with staged, human-readable output | Yes |
| Deterministic provisioning core | `scripts/openclaw-gcp/create-instance.sh` | Thin orchestration over template + NAT helpers with create-if-missing semantics | Yes |
| Exact-name teardown | `scripts/openclaw-gcp/destroy.sh` | Qualification checks before delete, deterministic order, dry-run-first posture | Yes |
| Metadata contract persistence | `scripts/openclaw-gcp/create-template.sh` | Stable metadata schema validated at write time and read during later flows | Yes |
| Resource label precedent | `scripts/openclaw-gcp/create-machine-image.sh` | Adds labels through native `gcloud` support | Partially |
| Docs-as-contract verification | `tests/openclaw-gcp/test.sh` | README and runbook examples executed in dry-run mode | Yes |

### Reusable Utilities

- **Help/parser structure**: nearly every script follows the same `print_help`, `die`, `require_option_value`, and `unknown option` contract.
- **Interactive vs non-interactive branching**: `install.sh` and `destroy.sh` already encode how the repo wants TTY-sensitive prompts to behave.
- **Project resolution and safety**: `destroy.sh` already refuses real deletes when the project comes only from ambient `gcloud` config.
- **Drift rejection**: `create-template.sh` rejects ignored template-shaping flags when reusing an existing template.
- **Dry-run transparency**: the operator scripts print the exact `gcloud` commands they would execute instead of hiding actions behind abstractions.

### Naming Conventions

- Action-first shell file names: `install.sh`, `destroy.sh`, `create-instance.sh`, `repair-instance-bootstrap.sh`.
- Resource names are short and human-readable: `oc-main`, `oc-template`, `oc-router`, `oc-nat`.
- Boolean choices use explicit flags (`--dry-run`, `--non-interactive`, `--no-address`) instead of config files.
- Documentation examples are expected to remain executable in dry-run mode and are enforced in tests.

---

## Agent C: Constraints Analysis

> Source: repo layout, Makefile, test harness, local `gcloud` help output

### Runtime & Framework

- **Runtime**: Bash shell scripts
- **Primary operator dependency**: Google Cloud CLI
- **Repo shape**: shell/doc repo only; no application runtime or package manager layer

### Existing Dependencies (Relevant to This Feature)

| Package | Purpose |
|---------|---------|
| `bash` | Runtime for all operator scripts and test harness |
| `gcloud` | Provisioning, labeling, resource discovery, SSH, and teardown |
| `make` | Single test-suite wrapper |

### New Dependencies Needed

| Package | Reason | Risk Level |
|---------|--------|------------|
| No new local package dependency is obviously required | The feature can stay as shell + `gcloud` + docs | LOW |

### Build / Quality Requirements

```bash
bash tests/openclaw-gcp/test.sh
make test
```

### Repo-Level Constraints

- The current product story is still installer-first in `README.md` and `docs/openclaw-gcp/README.md`, so Phase 1 must rewrite the public narrative rather than merely add another advanced path.
- `tests/openclaw-gcp/test.sh` already validates dry-run documentation examples, which means the new Cloud-Shell-first docs and command surface need corresponding smoke coverage to avoid drift.
- The current scripts are intentionally layered: `create-instance.sh` is infra-only, `install.sh` owns the human session flow, and `destroy.sh` owns safety-checked teardown. The new product layer should preserve that separation instead of collapsing everything into one giant shell script.
- Local `gcloud` help confirms that `gcloud compute instances create` and `gcloud compute instance-templates create` support `--labels`, while `gcloud compute routers create` and `gcloud compute routers nats create` do not expose label flags in the current CLI. That means Phase 1 cannot rely on labels alone for every managed resource.
- `create-machine-image.sh` already uses labels, so label usage is consistent with repo precedent, but not yet centralized or generalized.

---

## Agent D: External Research

> Source: official Google Cloud Shell documentation and reference pages

### Official Documentation

| Topic | Source | Key Finding |
|------|--------|-------------|
| Open in Cloud Shell parameters | `https://docs.cloud.google.com/shell/docs/open-in-cloud-shell` | Official parameters include `cloudshell_git_repo`, `cloudshell_workspace`, `cloudshell_print`, `cloudshell_tutorial`, `cloudshell_open_in_editor`, `show`, and `ephemeral`. |
| Repo trust / credential model | `https://docs.cloud.google.com/shell/docs/open-in-cloud-shell` | Only allowlisted repos owned by Google open in the default credentialed environment; other repos use a temporary Cloud Shell environment without automatic access to the user’s credentials. |
| Persistent home directory | `https://docs.cloud.google.com/shell/docs/how-cloud-shell-works` | Default Cloud Shell provides 5 GB of persistent `$HOME` storage that survives sessions; the VM itself is temporary. |
| Authorization prompts | `https://docs.cloud.google.com/shell/docs/how-cloud-shell-works` | The first credentialed CLI/API use in Cloud Shell can prompt the user to authorize access. |
| gcloud config persistence | `https://docs.cloud.google.com/shell/docs/configuring-cloud-shell` | `gcloud` preferences are stored in a temporary folder for the current tab only unless the user explicitly persists them through `$HOME/.bashrc` or `CLOUDSDK_CONFIG`. |
| Cloud Shell tutorials | `https://cloud.google.com/shell/docs/cloud-shell-tutorials/tutorials` | Open in Cloud Shell can launch a tutorial hosted in the repo through `cloudshell_tutorial`. |
| Project/API setup widgets | `https://docs.cloud.google.com/shell/docs/cloud-shell-tutorials/directives-project-setup` | Tutorial directives can provide project selection and API enable buttons inside the browser experience. |
| Tutorial code blocks | `https://docs.cloud.google.com/shell/docs/cloud-shell-tutorials/markdown-extensions` | `sh` code blocks in tutorials get a copy-to-Cloud-Shell affordance, which helps make one command obvious without custom browser code. |

### Community / Vendor Patterns

- **Pattern**: Use Open in Cloud Shell to clone the repo, set the working directory, and launch a tutorial or printed instructions rather than forcing local setup.
  - Why it applies: it directly supports D1 and the “browser-first operator terminal” goal.
  - Reference: official Open in Cloud Shell docs document repository cloning plus tutorial and print parameters.

- **Pattern**: Treat `$HOME` persistence as convenience state, not sole source of truth.
  - Why it applies: the VM is temporary, ephemeral mode exists, and `$HOME` can be recycled after long inactivity.
  - Reference: official “How Cloud Shell works” docs.

- **Pattern**: Use tutorial directives for project selection and API enablement rather than inventing custom browser-side onboarding.
  - Why it applies: the feature explicitly wants Cloud Shell first, but without a hosted control plane.
  - Reference: official tutorial directive docs.

### Known Gotchas / Anti-Patterns

- **Gotcha**: non-Google repos opened via Open in Cloud Shell do not get the default credentialed environment automatically.
  - Why it matters: this repo cannot assume ambient credentials or project selection on first launch from the button.
  - How to avoid: make auth/project readiness explicit in the welcome and `up` flow, and use tutorial/project widgets where helpful.

- **Gotcha**: the documented Open in Cloud Shell parameters cover cloning, opening files, printing instructions, and launching tutorials, but the docs do not document arbitrary repo command auto-execution as a launch parameter.
  - Why it matters: the desired “auto-run welcome script” may need to be approximated through officially supported tutorial/print behavior rather than a hidden command injection trick.
  - How to avoid: stay inside official launch/documented behaviors and let validating confirm the closest compliant handoff.

- **Gotcha**: `gcloud` preferences do not persist across sessions by default even when `$HOME` does.
  - Why it matters: the tool should persist its own current-stack convenience state and should not rely on tab-local `gcloud` config to rediscover project/region defaults later.
  - How to avoid: store explicit stack/project metadata in the local state file and keep project selection visible in `status`.

- **Anti-pattern**: using a custom Cloud Shell image just to get a nicer first-run experience.
  - Common mistake: reach for `cloudshell_image` too early.
  - Correct approach: avoid it in Phase 1 because the official docs say it creates a temporary environment with a scratch home directory, which conflicts with the desired local persistence story.

- **Anti-pattern**: assuming labels can be stamped on every GCP resource in the current flow.
  - Common mistake: design teardown/discovery entirely around labels without checking actual command support.
  - Correct approach: use labels where they are supported and deterministic stack-derived naming for unlabeled router/NAT resources.

### Open Questions

- [ ] What is the closest officially supported Open in Cloud Shell landing flow that satisfies D1’s “auto-run welcome” intent without relying on undocumented command execution?
- [ ] Should Phase 1 use `cloudshell_tutorial`, `cloudshell_print`, or both for the welcome experience?
- [ ] Should the local convenience state persist only stack data, or also the last known project/region/zone to compensate for Cloud Shell’s tab-local `gcloud` preferences?
- [ ] For router/NAT, is deterministic naming sufficient for the durable stack contract, or should Phase 1 also stamp stack identity into descriptions/metadata where available?

---

## Summary for Synthesis (Phase 2 Input)

**What we have**: a solid shell-based GCP operator repo with strong preflight, deterministic provisioning, guarded teardown, and a mocked test suite that already acts as a behavior contract. The current repo already knows how to provision, reuse, repair, install, and destroy; it just does so through rawer entrypoints and an installer-first narrative.

**What we need**: a thin product layer that makes Cloud Shell the primary landing surface, makes the stack the unit of ownership, maps that stack to existing scripts safely, and rewrites docs/tests around a dead-simple `up` / `down` / `status` experience.

**Key constraints from research**:
- Open in Cloud Shell supports official clone/tutorial/print/workspace parameters, but not clearly documented arbitrary repo-command execution.
- `$HOME` persists across normal sessions, but `gcloud` preferences do not persist by default and ephemeral mode removes the persistence benefit entirely.
- Labels are available on instances and templates, but not on the router/NAT create commands currently used by this repo.

**Institutional warnings to honor**:
- No prior institutional learnings for this domain.

---

## Phase 3 Planning Addendum

**Date**: 2026-04-02

### Additional Architecture Findings

- `bin/openclaw-gcp` already owns the stack-native command surface, so adding `ssh` and `logs` there keeps the wrapper thin and avoids new top-level entrypoints.
- `bin/openclaw-gcp status --json` already exists, which means Phase 3 can strengthen a real machine-readable contract instead of introducing an unrelated new automation interface.
- `scripts/openclaw-gcp/lib-stack.sh` already owns stack naming plus convenience state and is the natural place for any small shared day-2 helper constants if the wrapper needs them.

### Additional Pattern Findings

- `scripts/openclaw-gcp/install.sh` already defines the repo’s best-known SSH and remote-log contracts:
  - readiness log: `~/.openclaw-gcp/install-logs/readiness-gate.log`
  - installer transcript symlink: `~/.openclaw-gcp/install-logs/latest.log`
  - IAP-backed SSH invocation shape for both readiness and interactive handoff
- `scripts/openclaw-gcp/bootstrap-openclaw.sh` already documents the current Docker deployment’s gateway log entrypoint: `docker logs --tail 100 openclaw_openclaw-gateway_1`
- The current tests cover bring-up, teardown, and recovery well, but there is not yet wrapper-level coverage for first-class `ssh` or `logs` commands.

### Phase 3 Constraints

- A new `ssh` command should reuse existing stack resolution and anchor verification instead of bypassing them.
- A new `logs` command should expose only known, documented log sources rather than pretending to be a general remote log browser.
- Phase 3 should grow `status --json` additively and leave the default human-readable summary intact.
