# Phase Plan: OpenClaw GCP Destroy Script

**Date**: 2026-03-31
**Feature**: `openclaw-gcp-destroy-script`
**Based on**:
- `history/openclaw-gcp-destroy-script/CONTEXT.md`
- `history/openclaw-gcp-destroy-script/discovery.md`
- `history/openclaw-gcp-destroy-script/approach.md`

---

## 1. Feature Summary

This feature adds the missing destroy-side companion to the new one-line OpenClaw GCP installer. When it is done, an operator can preview and then safely tear down an OpenClaw deployment by exact resource names, starting with the standard installer stack and optionally including extra repo-managed artifacts like snapshot policies or machine images when those names are supplied explicitly. The work is phased because the core safety loop for deleting the default deployment has to be believable before we widen the script to optional extras and before we publish the operator docs around it.

---

## 2. Why This Breakdown

- Phase 1 must happen first because nothing else matters until a user can safely destroy the standard installer-created stack with a typed confirmation, dry-run preview, and a trustworthy summary.
- Optional extras are separate because they add more resource shapes and more edge cases, but they are not needed to prove that the main deployment can be torn down safely.
- Docs and smoke coverage come last because the command surface should settle before we freeze examples in README and the runbook.

---

## 3. Phase Overview Table

| Phase | What Changes In Real Life | Why This Phase Exists Now | Demo Walkthrough | Unlocks Next |
|-------|----------------------------|---------------------------|------------------|--------------|
| Phase 1: Safely Remove The Standard Deployment | An operator can preview and destroy the default installer stack: VM, template, NAT, and router, with typed confirmation and a final outcome summary. | This is the smallest believable version of the feature and covers the primary day-2 need. | Run `bash scripts/openclaw-gcp/destroy.sh --project-id ... --dry-run`, inspect the plan, then run it for real and see the core stack removed or a precise failure summary. | Optional extra-resource teardown |
| Phase 2: Add Explicit Extra Resource Cleanup | The destroy command can also remove optional snapshot policies, machine images, and clone-related resources when the operator names them explicitly. | After the core stack works, we can widen the command without weakening its exact-name safety contract. | Run destroy with explicit extra flags and see those resources included in the plan and deletion summary. | Final operator docs and examples |
| Phase 3: Publish The Teardown Story | The repo docs and smoke tests describe the destroy companion flow clearly enough for normal operator use. | Docs should reflect the final settled CLI contract rather than a moving target. | Read the updated README/runbook and verify the documented dry-run commands pass in the test suite. | Review, merge, and ship |

---

## 4. Phase Details

### Phase 1: Safely Remove The Standard Deployment

- **What Changes In Real Life**: a user can run one destroy command and confidently remove the default OpenClaw installer stack without manually stitching together delete commands.
- **Why This Phase Exists Now**: it closes the main operational loop first and gives us the safest core before any optional extras expand the blast radius.
- **Stories Inside This Phase**:
  - Story 1: Define the destroy command contract — choose the entrypoint, flags, typed confirmation, and dry-run output so operators can see exactly what will be deleted.
  - Story 2: Qualify the target for safe teardown — inspect the standard stack, verify it matches the expected repo-managed shape, and fail before deletion if the instance has unexpected attached disks or shared-looking infra.
  - Story 3: Tear down the qualified core stack — delete instance, template, NAT, and router in dependency order with best-effort continuation and truthful reporting.
  - Story 4: Prove the contract in tests — extend the shell harness for parser behavior, qualification failures, confirmation behavior, command order, and partial failures.
- **Demo Walkthrough**: An operator runs the destroy command in dry-run mode against a standard deployment and sees the full delete plan for `oc-main`, `oc-template`, `oc-nat`, and `oc-router`. Then they rerun it interactively, type the required confirmation token, and the script either completes the teardown or returns a non-zero summary that lists the exact resources that still need manual cleanup.
- **Unlocks Next**: once the default stack is safely removable, we can add optional extras without muddying the core contract.

### Phase 2: Add Explicit Extra Resource Cleanup

- **What Changes In Real Life**: the same destroy command can also clean up optional repo-managed resources such as snapshot policies, machine images, and clone instances when their names are provided explicitly.
- **Why This Phase Exists Now**: it extends the command only after the core deployment teardown is already trustworthy.
- **Stories Inside This Phase**:
  - Story 1: Add explicit extra-resource flags — expose the optional names the operator can pass for snapshot-policy, machine-image, and clone-related cleanup.
  - Story 2: Enforce extra-resource ownership boundaries — make sure those deletes stay exact-name only and fail on ambiguous/shared shapes instead of guessing.
  - Story 3: Expand failure-path and mixed-resource tests — verify partial success summaries still make sense when extras are included.
- **Demo Walkthrough**: An operator passes the snapshot policy and machine image names alongside the standard destroy flags, and the script previews then removes those named resources as part of the same summarized teardown.
- **Unlocks Next**: once the script surface is complete, docs can freeze the final operator story.

### Phase 3: Publish The Teardown Story

- **What Changes In Real Life**: operators can discover and use the destroy companion flow from the repo docs without reading the implementation.
- **Why This Phase Exists Now**: docs and smoke tests should match the final command contract, not an intermediate one.
- **Stories Inside This Phase**:
  - Story 1: Update the root README — surface the destroy companion flow near the installer-first primary path.
  - Story 2: Update the OpenClaw GCP runbook — explain destroy usage, dry-run, confirmation, and failure-summary behavior.
  - Story 3: Lock examples into smoke coverage — add docs examples to the existing shell test suite so future changes cannot silently break operator docs.
- **Demo Walkthrough**: A new operator reads the README and runbook, copies the documented destroy dry-run command, and the repo test suite confirms those examples still parse.
- **Unlocks Next**: review, merge, and normal day-2 operator usage.

---

## 5. Phase Order Check

- [x] Phase 1 is obviously first
- [x] Each later phase depends on or benefits from the one before it
- [x] No phase is just a technical bucket with no user/system meaning

---

## 6. Approval Summary

- **Current phase to prepare next**: `Phase 3 - Publish The Teardown Story`
- **What the user should picture after that phase**: repo docs clearly show the destroy companion flow, its safety boundaries, and copy-paste examples that are protected by smoke coverage.
- **What will not happen until later phases**: no new destroy behavior should be added in this phase; this is a docs-and-smoke-only closeout.
