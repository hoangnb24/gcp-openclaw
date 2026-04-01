---
status: resolved
priority: p2
source_agent: code-quality
tags: [code-quality, bootstrap]
created: 2026-03-24
feature: openclaw-gcp-instance-strategy
---

# Embedded startup script now resolves the OpenClaw home directory safely

## Problem Statement

The embedded startup script previously defaulted to `/home/root` when it ran under the boot-time root context. That created OpenClaw state in the wrong home path.

## Acceptance Criteria

- [x] Root-context startup uses `/root`, not `/home/root`.
- [x] Non-root `SUDO_USER` still resolves through the account's actual home directory.

## Resolution

**Resolved by:** Codex review fix  
**Resolution date:** 2026-03-24  
**Resolution:** Updated the embedded startup script in `scripts/openclaw-gcp/create-template.sh` to resolve `SUDO_USER` via `getent passwd` and fall back to `/root` when no non-root user is present. Verified with mocked `gcloud` capture that inspects the generated startup script.  
**Status change:** pending → resolved
