# Approach: OpenClaw GCP Cloud-Shell-First UX

**Date**: 2026-04-01
**Feature**: `openclaw-gcp-cloud-shell-first`
**Based on**:
- `history/openclaw-gcp-cloud-shell-first/discovery.md`
- `history/openclaw-gcp-cloud-shell-first/CONTEXT.md`

---

## 1. Gap Analysis

| Component | Have | Need | Gap Size |
|-----------|------|------|----------|
| Browser-first launch | Repo has no Cloud Shell button, tutorial, or launch artifact | Official Open in Cloud Shell quickstart that opens this repo and makes the next action obvious | New |
| User-facing command surface | Raw scripts like `install.sh`, `destroy.sh`, `create-instance.sh` | One product entrypoint with `welcome`, `up`, `down`, and `status` | New |
| Stack identity | Users think in instance/template/router/NAT names | Explicit stack ID with deterministic resource naming and a stack-first UX | New |
| Durable ownership metadata | Some metadata contracts and one machine-image label precedent | Label policy for labelable resources plus deterministic rules for unlabeled ones | New |
| Local convenience state | No operator-facing current-stack state file | Small Cloud Shell state file for current stack and last-known context | New |
| Safe teardown by stack | `destroy.sh` already protects exact raw names | Stack-aware `down` that resolves the right raw names and still preserves destroy safeguards | Variation of existing pattern |
| Human-friendly visibility | No stack-native `status` command | Summary command that shows current stack, project, lifecycle, resource names, and existence | New |
| Public docs/tests | Installer-first README and runbook, with smoke tests for old examples | Cloud-Shell-first docs and tests that verify the new story end-to-end in dry-run/mock mode | Variation of existing pattern |

---

## 2. Recommended Approach

Add one thin product wrapper at the repo edge and keep the existing scripts as the execution engines underneath it. The wrapper should expose `welcome`, `up`, `down`, and `status`, translate a user-chosen stack ID into deterministic resource names, apply the stack label set on all labelable resources, persist a small current-stack convenience record in Cloud Shell, and delegate real provisioning/install and teardown to the current `install.sh`, `create-instance.sh`, `create-template.sh`, and `destroy.sh` flows. The browser entry should be an official Open in Cloud Shell launch from the docs, backed by a repo-hosted tutorial and/or printed instructions, so the repo gets the browser-first experience without inventing a separate control plane. For resource types without label support in the current CLI path, the approach should treat labeled instance/template resources as the durable anchors and use fixed stack-derived naming for router/NAT resolution.

### Why This Approach

- It honors **D6** by making the stack, not raw GCP resource names, the primary operator concept while still reusing the existing safe scripts.
- It honors **D5** by using labels as durable truth where GCP supports them, while keeping local Cloud Shell state as a convenience pointer only.
- It preserves the repo’s strongest proven behavior instead of replacing it: `install.sh` remains the “get OpenClaw running” engine, and `destroy.sh` remains the safety-critical delete engine.
- It keeps Phase 1 pragmatic: new UX at the top, minimal churn in proven internals, and no hosted platform or Bash migration.
- It stays inside officially documented Google Cloud Shell features instead of relying on brittle browser hacks.

### Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| User-facing command surface | Add one dispatcher such as `bin/openclaw-gcp` with `welcome`, `up`, `down`, and `status` subcommands | Keeps the primary UX dead-simple while hiding script sprawl |
| Welcome flow | Back the official Open in Cloud Shell button with a repo-hosted tutorial and/or printed instructions, and make the immediate next action the repo-native welcome flow | Matches D1 and uses documented Cloud Shell features rather than undocumented auto-exec |
| Provisioning engine | `up` delegates to `scripts/openclaw-gcp/install.sh` for real OpenClaw bring-up | Reuses the current preflight, readiness, repair, and install-handoff logic |
| Teardown engine | `down` resolves stack-derived names, then delegates to `scripts/openclaw-gcp/destroy.sh` | Preserves current safety gates and typed confirmation behavior |
| Stack naming | Use a sanitized stack ID to derive stable names for VM, template, router, and NAT | Matches D6 and makes unlabeled resources resolvable |
| Durable identity | Apply `openclaw_managed`, `openclaw_stack_id`, `openclaw_tool`, and `openclaw_lifecycle` labels on every resource in the current path that supports labels | Matches D5 and D7 while staying within actual CLI support |
| Unlabeled resource handling | Treat router/NAT as deterministic companions of a labeled stack anchor rather than independent discoverable resources | Necessary because current router/NAT create commands do not expose label flags |
| Local convenience state | Persist a small state file under `$HOME/.config/openclaw-gcp/` for `current-stack` plus per-stack summaries | Works with normal Cloud Shell persistence and does not depend on tab-local `gcloud` config |
| Status contract | Human-readable default output with optional machine-readable mode only if it stays thin | Matches D8 and keeps the initial operator flow friendly |
| Docs/test strategy | Rewrite root README and runbook around the Cloud-Shell-first story and enforce it with smoke tests | Ensures the new primary UX is real, not aspirational |

---

## 3. Alternatives Considered

### Option A: Keep the current scripts and only add a Cloud Shell button to the docs

- Description: add a button, but keep `scripts/openclaw-gcp/install.sh` as the only real story.
- Why considered: very small code change.
- Why rejected: it does not deliver the product shift to stack identity, dead-simple `up` / `down`, or browser-first clarity.

### Option B: Build a custom Cloud Shell image or per-user Cloud Shell bootstrap just to auto-run the welcome logic

- Description: use `cloudshell_image` or user-environment customization to get a more magical launch.
- Why considered: it seems like the fastest route to “auto-run” behavior.
- Why rejected: the official docs say custom-image launches create a temporary scratch-home environment, which conflicts with the desired persistence story, and it would add avoidable operational complexity in Phase 1.

### Option C: Rewrite the repo around one new monolithic script and retire the existing helpers immediately

- Description: replace `install.sh`, `destroy.sh`, `create-instance.sh`, and others with one new shell application.
- Why considered: a clean-slate product surface can look attractive.
- Why rejected: it throws away proven guardrails and invites regression in the exact areas this repo already does well.

### Option D: Save raw names in local state and treat labels as optional decoration

- Description: use a stack wrapper only as a local convenience over current exact-name flags.
- Why considered: smallest implementation effort.
- Why rejected: it violates D5’s durable-truth model and leaves too much of the old infrastructure vocabulary in the main UX.

---

## 4. Risk Map

| Component | Risk Level | Reason | Verification Needed |
|-----------|------------|--------|---------------------|
| Official Cloud Shell landing flow | **HIGH** | The desired welcome behavior must fit documented Cloud Shell launch features and this repo is not a Google allowlisted repo | Validate exact Open in Cloud Shell URL parameters and landing behavior |
| `bin/openclaw-gcp` command surface | **MEDIUM** | New user-facing wrapper, but on top of existing script patterns | Dry-run tests and parser/help coverage |
| Stack naming and derivation | **MEDIUM** | New naming contract across several existing scripts | Contract tests for derived names and collision/normalization rules |
| Label strategy on labelable resources | **MEDIUM** | Existing repo has limited label usage today, but `gcloud` support is straightforward on instance/template paths | Mock tests for emitted commands and status/discovery behavior |
| Router/NAT ownership model | **HIGH** | Current CLI path does not support labels there, so stack truth becomes mixed | Validate whether deterministic naming alone is sufficient and safe |
| Local state persistence model | **MEDIUM** | Cloud Shell `$HOME` persists, but `gcloud` config does not and ephemeral mode changes the rules | Tests for missing-state and stale-state messaging |
| `up` delegation into `install.sh` | **MEDIUM** | Existing install flow is proven, but it currently expects raw names and legacy prompts | Dry-run/mocked tests for wrapper-to-engine argument mapping |
| `down` delegation into `destroy.sh` | **HIGH** | Safety-critical destructive flow now adds stack resolution behavior ahead of the current guardrails | Validate current-stack vs explicit-stack behavior and error paths |
| `status` discovery contract | **MEDIUM** | New operator output surface combining local state, labels, and existence checks | Tests for readable summary and recovery hints |
| Docs migration | **MEDIUM** | Primary quickstart and runbook narrative will change significantly | Documentation smoke tests and final readability review |
| Test suite evolution | **MEDIUM** | New commands and docs examples need coverage, but the harness already exists | Expand mocked test groups and keep `make test` green |

### Risk Classification Reference

```
Pattern in codebase?        → YES = LOW base
External dependency?        → YES = HIGH
Blast radius > 5 files?    → YES = HIGH
Otherwise                   → MEDIUM
```

### HIGH-Risk Summary (for khuym:validating skill)

- `Official Cloud Shell landing flow`: confirm the exact documented launch pattern and the best supported approximation of the desired welcome behavior.
- `Router/NAT ownership model`: confirm that label anchors plus deterministic stack naming are sufficient to preserve the durable stack contract.
- `down` delegation into `destroy.sh`: confirm the safety contract for interactive current-stack teardown versus explicit non-interactive teardown.

---

## 5. Proposed File Structure

```text
bin/
  openclaw-gcp                     # New human-facing dispatcher: welcome/up/down/status
scripts/
  openclaw-gcp/
    install.sh                     # Existing OpenClaw bring-up engine reused by `up`
    destroy.sh                     # Existing teardown engine reused by `down`
    create-instance.sh             # Existing provisioning core
    create-template.sh             # Existing template + metadata contract
    create-cloud-nat.sh            # Existing router/NAT helper
    lib-stack.sh                   # New shared stack naming/state/label helpers
    cloudshell-welcome.sh          # New non-mutating welcome flow
docs/
  openclaw-gcp/
    README.md                      # Rewritten runbook with Cloud-Shell-first quickstart
    cloud-shell-quickstart.md      # New tutorial / printed-instructions source
README.md                          # Rewritten root quickstart with Open in Cloud Shell button
tests/
  openclaw-gcp/
    test.sh                        # Expanded smoke + contract tests for wrapper/docs
history/
  openclaw-gcp-cloud-shell-first/
    CONTEXT.md
    discovery.md
    approach.md
    phase-plan.md
```

---

## 6. Dependency Order

```text
Layer 1: Define the stack contract (naming, labels, local state, command surface)
Layer 2: Create the browser landing + welcome path around official Cloud Shell features
Layer 3: Wire `up`, `down`, and `status` to existing engines using the stack contract
Layer 4: Rewrite docs and tests to enforce the new primary story
Layer 5: Add recovery and advanced day-2 ergonomics in later phases
```

### Parallelizable Groups

- Group A: browser landing artifacts and stack-helper design can proceed in parallel, but both depend on agreeing the final command surface.
- Group B: `up`, `down`, and `status` can share the same stack helper once naming/state rules are fixed.
- Group C: docs rewrite and smoke tests can proceed after the wrapper surface stabilizes.

---

## 7. Institutional Learnings Applied

No prior institutional learnings relevant to this feature.

---

## 8. Open Questions for Validating

- [x] What is the exact officially supported Open in Cloud Shell URL and parameter combination this repo should ship, and how close can it get to D1’s desired welcome behavior without relying on undocumented command execution?
  Resolution: use `cloudshell_git_repo`, `cloudshell_workspace=.`, `cloudshell_tutorial`, and optional `cloudshell_print`, `cloudshell_open_in_editor`, and `show` parameters. Phase 1 should not assume launch-time repo command execution.
- [x] For router/NAT resources that do not support labels in the current CLI path, is deterministic naming alone enough to satisfy the durable stack contract, or should Phase 1 also persist extra ownership hints?
  Resolution: yes for Phase 1, as long as router/NAT remain deterministic companions of labeled stack anchors and all ambiguity fails closed.
- [ ] What should happen when local current-stack state exists but no longer matches labeled resources in GCP?
- [x] Should the current-stack state include last-known project/region/zone explicitly so the UX is resilient to Cloud Shell’s non-persistent `gcloud` preferences?
  Resolution: yes. Phase 1 should persist that last-known context as convenience metadata while still treating GCP-backed anchors as the durable truth.

---

## 9. Phase 3 Extension

Phase 3 should continue the same thin-wrapper philosophy rather than opening a new architectural lane.

### Recommended Phase 3 Shape

- Add `ssh` to `bin/openclaw-gcp` and make it reuse the same stack-resolution and anchor-verification rules already trusted by `status` and `down`.
- Add `logs` to `bin/openclaw-gcp` and restrict it to a named set of remote log sources already grounded in repo behavior:
  - readiness
  - install
  - bootstrap
  - gateway
- Expand `status --json` rather than invent a second machine-readable command surface.
- Keep docs and tests as first-class contract work, because these day-2 commands are only useful if operators and automation can trust the exact same behavior.

### Phase 3 High-Risk Components

| Component | Risk Level | Reason | Verification Needed |
|-----------|------------|--------|---------------------|
| Shared remote-access contract for `ssh` and `logs` | **HIGH** | The wrapper must preserve stack-anchor safety while opening a live operator shell path | Validate whether the current `status`/`down` anchor checks are the right gate for day-2 remote access |
| Named remote log-source contract | **HIGH** | The repo has real log seams, but Phase 3 must expose only sources that are truthful and supportable | Validate the exact source list and fail-closed behavior before implementation |
| Richer `status --json` contract | **MEDIUM** | The command already exists, but automation fields need to stay additive and consistent | Shell assertions for JSON fields and recovery/state semantics |

### Phase 3 Proposed File Focus

```text
bin/openclaw-gcp                               # add ssh/logs and richer json output
scripts/openclaw-gcp/lib-stack.sh             # optional small shared helpers/constants
README.md                                     # advanced day-2 command examples
docs/openclaw-gcp/README.md                   # runbook-level ssh/logs/json guidance
docs/openclaw-gcp/cloud-shell-quickstart.md   # browser-first day-2 follow-on path
tests/openclaw-gcp/test.sh                    # mocked shell coverage for new commands
```
