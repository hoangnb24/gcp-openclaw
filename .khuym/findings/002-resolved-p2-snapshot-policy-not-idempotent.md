---
status: resolved
priority: p2
source_agent: code-quality
tags: [code-quality, error-handling]
created: 2026-03-24
feature: openclaw-gcp-instance-strategy
---

# Snapshot policy script was not repeatable when the policy already existed

## Problem Statement

The snapshot policy script always executed a fresh `resource-policies create snapshot-schedule` call. On rerun, that failed before the attachment step, which made it awkward to reuse the same policy for additional disks later.

## Evidence

**File:** `scripts/openclaw-gcp/create-snapshot-policy.sh`  
**Line(s):** 56-61, 111-138

**Why this was a problem:**  
Normal follow-up operations should be able to reuse an existing policy and still attach it to more disks.

## Proposed Solutions

### Option A — [Recommended] Ensure policy exists, then attach
Check whether the policy already exists, create only if missing, and always allow the attach path to continue.
**Pros:** Idempotent and matches day-1 operational usage.  
**Cons:** Does not rebuild changed policy parameters unless a separate replace mode is added later.  
**Effort:** Small

### Option B — Split create and attach into separate scripts
Require separate operator calls for policy creation and policy attachment.
**Pros:** Explicit behavior.  
**Cons:** More operator friction for the common case.  
**Effort:** Medium

## Acceptance Criteria

- [x] Re-running the snapshot policy script with an existing policy still succeeds.
- [x] Attachment to additional disks proceeds even when the policy already exists.

## Resolution

**Resolved by:** Codex review fix  
**Resolution date:** 2026-03-24  
**Resolution:** Added an idempotent `policy_exists` check so the script reuses existing policies and still executes the disk-attachment path. Verified with mocked `gcloud` reruns plus `bash -n` and `--help`.  
**Status change:** pending → resolved
