---
status: resolved
priority: p3
source_agent: architecture
tags: [architecture, metadata]
created: 2026-03-24
feature: openclaw-gcp-instance-strategy
---

# Local resolution-record paths are no longer coupled into template metadata

## Problem Statement

This finding became stale after the earlier runtime-record cleanup. The current template metadata stores only stable cloud-relevant values, not the local `RESOLUTION_RECORD` path.

## Acceptance Criteria

- [x] No local workstation path is written into template metadata.

## Resolution

**Resolved by:** Codex review recheck  
**Resolution date:** 2026-03-24  
**Resolution:** Revalidated `scripts/openclaw-gcp/create-template.sh` and confirmed the template metadata now stores only `openclaw_image`, `openclaw_tag`, `startup_script_source`, and `debian_image_resolved`. The local record file path remains local-only. No code change was required in this pass.  
**Status change:** pending → resolved
