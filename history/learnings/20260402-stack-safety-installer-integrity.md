---
date: 2026-04-02
feature: openclaw-gcp-cloud-shell-first
categories: [pattern, decision, failure]
severity: critical
tags: [cloud-shell, stack-safety, installer-integrity, automation, testing]
---

# Learning: Wrap New UX Around Proven Engines

**Category:** pattern
**Severity:** standard
**Tags:** [architecture, cli]
**Applicable-when:** Adding a friendlier command surface on top of existing scripts that already carry the real safety and lifecycle logic

## What Happened

This feature introduced a top-level `bin/openclaw-gcp` product surface for `welcome`, `up`, `status`, `down`, `ssh`, and `logs`, but it kept `scripts/openclaw-gcp/install.sh` and `scripts/openclaw-gcp/destroy.sh` as the actual provisioning and teardown engines. That let the repo ship a Cloud-Shell-first experience without rewriting the strongest existing behavior, especially the readiness and exact-target destroy safeguards.

## Root Cause / Key Insight

The repo already had trustworthy lower-level contracts in the execution scripts. The cheapest safe move was to put new UX at the edge and translate stack-native intent into the existing engine inputs, rather than re-implementing proven infrastructure behavior inside the wrapper.

## Recommendation for Future Work

When productizing an operator workflow, add the new UX layer at the repo edge first. Reuse proven execution engines underneath it until there is a concrete reason to replace them.

---

# Learning: Keep Cloud Shell Landing Inside Official Platform Behavior

**Category:** decision
**Severity:** standard
**Tags:** [cloud-shell, docs]
**Applicable-when:** Designing a browser-first onboarding flow on top of Cloud Shell or another hosted terminal surface

## What Happened

The original intent was an official Open in Cloud Shell launch that felt like it auto-ran a guided welcome. Discovery and validation showed the supported path was more constrained: the durable option was an official repo clone plus tutorial/printed guidance, followed by a repo-local non-mutating `welcome` flow.

## Root Cause / Key Insight

The documented platform behavior was narrower than the aspirational UX. Staying inside the official launch contract produced a slightly less magical first-run experience, but it avoided undocumented launch-time command tricks that would have been brittle and hard to defend later.

## Recommendation for Future Work

When platform docs do not explicitly support launch-time command execution, do not approximate it with hidden hacks. Use the official tutorial or print surface, then make the first local command obvious and safe.

---

# Learning: Use Durable Labels As Truth And Local State As A Repairable Convenience Pointer

**Category:** pattern
**Severity:** standard
**Tags:** [stack-ownership, recovery]
**Applicable-when:** A workflow needs both durable remote ownership metadata and a lightweight local pointer for operator ergonomics

## What Happened

This feature made labeled instance and template resources the durable stack anchors while leaving router and NAT discovery to deterministic stack-derived names. It also let `status` repair `~/.config/openclaw-gcp/current-stack.env` only when exactly one trustworthy labeled stack candidate existed, which turned stale local state into a recoverable convenience instead of an ownership source.

## Root Cause / Key Insight

Cloud Shell state is helpful but can drift, and not every GCP resource in the current path supports labels. The combination of durable labeled anchors, deterministic companions, and exact-one recovery created a stack contract that stays ergonomic without guessing.

## Recommendation for Future Work

Store convenience state locally only for human workflows. Back ownership and recovery off durable remote anchors, and only auto-repair local state when the remote evidence is unambiguous.

---

# Learning: Destructive Automation Must Not Trust Remembered Local State

**Category:** failure
**Severity:** critical
**Tags:** [stack-safety, automation, teardown]
**Applicable-when:** Any destructive command can run in non-interactive mode, CI, or automation and has access to remembered local context

## What Happened

Review bead `br-3l2` found that non-interactive `bin/openclaw-gcp down` could still inherit `CURRENT_STACK_ID` and `LAST_PROJECT_ID` from `~/.config/openclaw-gcp/current-stack.env`, then pass those values as explicit destroy targets. That violated the feature's D4 safety contract and created a credible path to tearing down the wrong stack or even the wrong project until the wrapper was tightened to require explicit or live context for non-interactive destructive runs.

## Root Cause / Key Insight

The local state file was designed as an ergonomic pointer for interactive Cloud Shell use, but the teardown path treated it too broadly as target authority. Convenience state and destructive authority are not the same thing, and collapsing them is how stale local context turns into real blast radius.

## Recommendation for Future Work

Never let remembered local state silently satisfy destructive automation requirements. Require explicit targets or verified live context for non-interactive destructive commands, and reserve convenience-state fallback for interactive human workflows only.

---

# Learning: Verify Remote Installer Integrity Before Happy-Path Execution

**Category:** failure
**Severity:** critical
**Tags:** [security, installer, provisioning]
**Applicable-when:** A provisioning or onboarding flow downloads and executes remote code as part of the normal happy path

## What Happened

Review bead `br-2o3` caught that the primary `up` handoff still executed `https://openclaw.ai/install.sh` as an unpinned remote installer. The fix moved `scripts/openclaw-gcp/install.sh` to a stricter contract: download to a private cache path, verify a pinned SHA-256 digest, and execute only the verified local copy.

## Root Cause / Key Insight

The initial implementation optimized for a smooth remote handoff and preserved PTY behavior, but it left the trust boundary implicit. Any happy-path remote execution step is part of the product's real attack surface, so integrity verification has to be designed in from the start rather than added after review.

## Recommendation for Future Work

When remote code execution is part of the primary provisioning path, pin the artifact identity and verify it before execution. Do not ship a `curl | bash` happy path without an explicit integrity contract.

---

# Learning: Define JSON Error Shapes At The Same Time As JSON Success Shapes

**Category:** failure
**Severity:** standard
**Tags:** [automation, json, testing]
**Applicable-when:** Adding a machine-readable mode to a command that already has human-readable defaults

## What Happened

Phase 3 correctly expanded `status --json` instead of inventing a second automation command, and the output gained structured `context`, `state`, and `recovery` sections. Review follow-up `br-3ea` still found a contract gap: common error paths continued to fall back to human-oriented text, which meant automation consumers could not rely on a full machine-readable envelope.

## Root Cause / Key Insight

The team defined the happy-path JSON shape first because the human-readable status surface already existed and was the main operator story. That sequencing is tempting, but it leaves automation doing brittle stderr scraping the moment anything goes wrong.

## Recommendation for Future Work

Whenever a JSON mode ships, define the success and failure envelopes together and freeze both in tests. Treat machine-readable errors as part of the API, not as a later polish pass.
