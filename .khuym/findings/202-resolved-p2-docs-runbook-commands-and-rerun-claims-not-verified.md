---
status: resolved
priority: p2
source_agent: test-coverage
tags: [test-coverage, docs]
created: 2026-03-24
feature: openclaw-gcp-instance-strategy
---

# Runbook commands and rerun claims are now covered by smoke tests

## Problem Statement

The docs published canonical operator commands and rerun expectations, but nothing automatically verified that they stayed aligned with the scripts.

## Acceptance Criteria

- [x] README command examples parse successfully in verification.
- [x] Backup runbook command examples parse successfully in verification.
- [x] Rerun and reuse semantics are exercised in automation.

## Resolution

**Resolved by:** Codex review fix  
**Resolution date:** 2026-03-24  
**Resolution:** Added docs-backed dry-run smoke checks for the README and backup runbook command examples, plus mocked reuse-path assertions for template and snapshot-policy reruns. This keeps the published flows tied to executable checks under `make test`.  
**Status change:** pending → resolved
