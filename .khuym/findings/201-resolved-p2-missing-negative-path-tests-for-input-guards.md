---
status: resolved
priority: p2
source_agent: test-coverage
tags: [test-coverage, security]
created: 2026-03-24
feature: openclaw-gcp-instance-strategy
---

# Negative-path guards now have automated coverage

## Problem Statement

The scripts had important validation branches, but none were previously exercised automatically.

## Acceptance Criteria

- [x] Unpinned startup-script URL input is rejected in automation.
- [x] Mutually exclusive startup-script inputs are rejected in automation.
- [x] Tag, identity-mode, region/zone, and snapshot-policy guard paths are covered.

## Resolution

**Resolved by:** Codex review fix  
**Resolution date:** 2026-03-24  
**Resolution:** Extended `tests/openclaw-gcp/test.sh` with negative-path assertions for startup-script pinning, mutual exclusivity, `pin-me` rejection, region/zone mismatch, snapshot policy validation, and missing explicit identity selection.  
**Status change:** pending → resolved
