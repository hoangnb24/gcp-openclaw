---
status: resolved
priority: p2
source_agent: security
tags: [security, iam]
created: 2026-03-24
feature: openclaw-gcp-instance-strategy
---

# Template creation now requires an explicit VM identity mode

## Problem Statement

The baseline template flow previously relied on implicit Compute Engine defaults for service account attachment and OAuth scopes, which could over-privilege the VM.

## Acceptance Criteria

- [x] Template creation requires either `--no-service-account` or explicit `--service-account` plus `--scopes`.
- [x] The chosen identity mode is reflected in the operator-facing docs and verification suite.

## Resolution

**Resolved by:** Codex review fix  
**Resolution date:** 2026-03-24  
**Resolution:** Added explicit identity flags and validation to `scripts/openclaw-gcp/create-template.sh`, threaded them through `scripts/openclaw-gcp/create-instance.sh`, and updated the README to recommend `--no-service-account` unless the VM truly needs GCP API access. Verified with smoke tests that cover both positive and negative identity-selection paths.  
**Status change:** pending → resolved
