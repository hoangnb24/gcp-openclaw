---
status: resolved
priority: p2
source_agent: code-quality
tags: [code-quality, backup]
created: 2026-03-24
feature: openclaw-gcp-instance-strategy
---

# Snapshot policy attachment now derives a region-matching default zone

## Problem Statement

Changing `--region` without also changing `--zone` or `--target-disk-zone` could attach snapshot policies using the old `asia-southeast1-a` default.

## Acceptance Criteria

- [x] Region overrides derive a matching default `-a` zone when no zone is explicitly supplied.
- [x] Snapshot attachment rejects mismatched region and zone combinations.

## Resolution

**Resolved by:** Codex review fix  
**Resolution date:** 2026-03-24  
**Resolution:** Added region/zone validation to `scripts/openclaw-gcp/create-snapshot-policy.sh`, derived the default attachment zone from the selected region, and updated the runbook note in `docs/openclaw-gcp/backup-and-restore.md`. Verified with mocked `gcloud` capture and the new smoke suite.  
**Status change:** pending → resolved
