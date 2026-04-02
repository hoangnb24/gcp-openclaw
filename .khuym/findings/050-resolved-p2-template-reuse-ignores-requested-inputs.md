---
status: resolved
priority: p2
source_agent: architecture
tags: [architecture, cli-contract]
created: 2026-03-24
feature: openclaw-gcp-instance-strategy
---

# Template reuse no longer silently ignores requested template changes

## Problem Statement

The template scripts previously accepted template-shaping flags even when an existing template would be reused, making callers think their requested changes had been applied.

## Acceptance Criteria

- [x] Existing-template reuse fails fast if explicit template-shaping flags would be ignored.
- [x] First-run template creation still works through `create-instance.sh`.
- [x] Docs explain the new rerun contract clearly.

## Resolution

**Resolved by:** Codex review fix  
**Resolution date:** 2026-03-24  
**Resolution:** Added explicit-template-input tracking in `scripts/openclaw-gcp/create-template.sh` and `scripts/openclaw-gcp/create-instance.sh`, so reuse now errors instead of silently discarding requested changes. `create-instance.sh` now forwards only explicitly supplied template-shaping flags, preserving the first-run path while keeping reruns deterministic. Verified with mocked `gcloud` tests and updated docs.  
**Status change:** pending → resolved
