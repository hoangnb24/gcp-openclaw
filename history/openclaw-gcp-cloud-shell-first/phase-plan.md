# Phase Plan: OpenClaw GCP Cloud-Shell-First UX

**Date**: 2026-04-02
**Feature**: `openclaw-gcp-cloud-shell-first`
**Based on**:
- `history/openclaw-gcp-cloud-shell-first/CONTEXT.md`
- `history/openclaw-gcp-cloud-shell-first/discovery.md`
- `history/openclaw-gcp-cloud-shell-first/approach.md`

---

## 1. Feature Summary

This feature turns the repo from “run the installer script if you already understand the internals” into “open Cloud Shell in your browser, get guided into the repo, choose a stack name, run `up`, and later run `down` safely.” The work is phased because the first thing that matters is making one stack feel simple and trustworthy in the browser, while later phases harden recovery when local context is lost and add nicer day-2 commands like `ssh` and `logs`.

---

## 2. Why This Breakdown

- Phase 1 comes first because the repo needs one believable browser-first happy path before anything else matters.
- Recovery and drift handling are separate because they build on the stack contract from Phase 1 and should not delay the main `Open in Cloud Shell -> up -> down` story.
- Day-2 ergonomics like `ssh`, `logs`, and richer machine-readable status are valuable, but they are not required to make the primary stack story real.

---

## 3. Phase Overview Table

| Phase | What Changes In Real Life | Why This Phase Exists Now | Demo Walkthrough | Unlocks Next |
|-------|----------------------------|---------------------------|------------------|--------------|
| Phase 1: Browser-First Stack Workflow | A user can click an official Open in Cloud Shell button, land in a guided repo experience, bring up one named OpenClaw stack with `up`, inspect it with `status`, and tear it down with `down` without thinking in raw GCP resource names. | This is the core product promise and the minimum believable slice. | Open Cloud Shell, choose a stack, run `up`, see `status`, then run `down --dry-run` and a real `down` with the existing confirmation guard. | Recovery and drift handling |
| Phase 2: Recovery When Context Is Missing | A returning user or a fresh Cloud Shell session can rediscover and safely manage an existing stack even if the local current-stack pointer is gone or stale. | The happy path is not enough unless the system can recover from lost local context and still preserve safety. | Remove or stale the local state, run `status` or a recovery command, and still recover the right stack identity from GCP. | Richer multi-session confidence and better day-2 ops |
| Phase 3: Day-2 Operator Ergonomics | The stack-native tool grows into a practical operator surface with commands like `ssh`, `logs`, and richer machine-readable output. | These features are useful after the stack contract is proven, but they are not required for the first compelling browser-first story. | Run `ssh` into the current stack, fetch logs, or export structured status without falling back to raw script internals. | Review, polish, and broader adoption |

---

## 4. Phase Details

### Phase 1: Browser-First Stack Workflow

- **What Changes In Real Life**: OpenClaw on GCP becomes something a user can start from the browser with one official button and one simple stack-oriented command flow.
- **Why This Phase Exists Now**: The repo does not yet have a strong browser-first product story, and all later recovery or day-2 features depend on having a canonical stack contract first.
- **Stories Inside This Phase**:
  - Story 1: Land in Cloud Shell with a guided next step — the browser launch opens the repo and makes the welcome flow immediately obvious.
  - Story 2: Turn one stack name into a real `up` flow — the tool derives names, applies labels where supported, records current-stack convenience state, and delegates to the existing install/provisioning engine.
  - Story 3: Make `down` and `status` speak the same stack language — users can inspect what the stack is and tear it down safely without re-describing raw infrastructure.
  - Story 4: Make the docs and tests enforce the new primary story — the browser-first quickstart is published and checked instead of living only in design intent.
- **Demo Walkthrough**: A user clicks the Open in Cloud Shell button in the README, lands in the repo, follows the guided welcome, enters a stack name, runs `up`, sees OpenClaw come up on GCP using the current engine underneath, runs `status` to verify project/resource ownership, and then runs `down --dry-run` followed by a real `down` that still requires the typed confirmation guard.
- **Unlocks Next**: Safe rediscovery and recovery flows when the local convenience state is missing or stale.

### Phase 2: Recovery When Context Is Missing

- **What Changes In Real Life**: The stack-native workflow stops depending on “I am still in the same tab with the same local state” and becomes resilient to returning later.
- **Why This Phase Exists Now**: Cloud Shell state persistence is helpful but not absolute, and the repo needs a safe story for coming back after time passes or after local state is lost.
- **Stories Inside This Phase**:
  - Story 1: Rediscover stack anchors from GCP — labeled resources become enough to find the intended stack again.
  - Story 2: Reconcile unlabeled companion resources safely — router/NAT ownership is reconstructed from the stack naming contract instead of guesswork.
  - Story 3: Guide the operator through ambiguity — when state is stale or multiple stacks exist, the tool explains exactly what it can and cannot infer.
- **Demo Walkthrough**: A user returns to Cloud Shell later with no current-stack pointer, runs the recovery path, sees the tool reconstruct the intended stack identity from GCP plus deterministic naming, and safely resumes `status` or `down`.
- **Unlocks Next**: Higher-confidence operator ergonomics like `ssh`, `logs`, and multi-session workflows.

### Phase 3: Day-2 Operator Ergonomics

- **What Changes In Real Life**: The stack wrapper becomes the normal way to operate OpenClaw on GCP, not just the first-run path.
- **Why This Phase Exists Now**: Once the browser-first stack contract and recovery model are reliable, it makes sense to add convenience commands that keep operators inside the same product surface.
- **Stories Inside This Phase**:
  - Story 1: Add `ssh` for the current or explicit stack — operators can reach the VM without rebuilding raw `gcloud compute ssh` commands.
  - Story 2: Add `logs` and richer structured output — operators can inspect status and failure context more directly.
  - Story 3: Tighten advanced docs and automation affordances — machine-readable status and advanced flows become easier to script without compromising the human-first defaults.
- **Demo Walkthrough**: A user runs `status --json` for automation, `ssh` to the current stack for inspection, and `logs` to gather operator context, all while staying within the stack-native wrapper.
- **Unlocks Next**: Review, ship readiness, and future enhancements such as multi-stack listing or richer lifecycle controls.

---

## 5. Phase Order Check

- [x] Phase 1 is obviously first
- [x] Each later phase depends on or benefits from the one before it
- [x] No phase is just a technical bucket with no user/system meaning

---

## 6. Approval Summary

- **Current phase to prepare next**: `Phase 3 - Day-2 Operator Ergonomics`
- **What the user should picture after that phase**: after `up` or recovery, the wrapper becomes a practical day-2 surface where an operator can run `ssh`, fetch known logs, and script against richer `status --json` output without reconstructing raw `gcloud` commands.
- **What will not happen until later work**: broader multi-stack listing, richer lifecycle controls, or a hosted control plane remain outside this feature's planned phases.
