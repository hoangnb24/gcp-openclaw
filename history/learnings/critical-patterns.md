# Critical Patterns

Promoted learnings from completed features. Read this file at the start of every
planning Phase 0 and every exploring Phase 0. These are the lessons that cost the
most to learn and save the most by knowing.

---

## [20260402] Destructive Automation Must Not Trust Remembered Local State
**Category:** failure
**Feature:** openclaw-gcp-cloud-shell-first
**Tags:** [stack-safety, automation, teardown]

Review bead `br-3l2` exposed that a remembered `current-stack.env` pointer can become a destructive target if non-interactive teardown treats convenience state as authoritative. Future destructive automation must require explicit targets or verified live context, and remembered local state must stay interactive-only. This rule is broader than Cloud Shell: any stale local pointer can become real blast radius if a destructive path trusts it too early.

**Full entry:** history/learnings/20260402-stack-safety-installer-integrity.md

## [20260402] Verify Remote Installer Integrity Before Happy-Path Execution
**Category:** failure
**Feature:** openclaw-gcp-cloud-shell-first
**Tags:** [security, installer, provisioning]

Review bead `br-2o3` showed that a user-friendly provisioning flow can still carry a live supply-chain hole if it executes remote code without a pinned integrity contract. Any primary onboarding or provisioning path that fetches code must download, verify, and only then execute a known artifact. If verification is missing, the happy path is not safe enough to ship.

**Full entry:** history/learnings/20260402-stack-safety-installer-integrity.md
