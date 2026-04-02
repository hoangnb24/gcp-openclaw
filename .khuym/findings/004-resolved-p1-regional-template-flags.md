---
status: resolved
priority: p1
source_agent: code-quality
tags: [code-quality, error-handling]
created: 2026-03-24
feature: openclaw-gcp-instance-strategy
---

# Regional template operations were not consistently region-scoped

## Problem Statement

The template workflow mixed regional-template creation with global-style lookup and consumption paths. That could break reruns and instance creation for the primary repeatable provisioning flow, which is central to D5 and D6.

## Evidence

**File:** `scripts/openclaw-gcp/create-template.sh`  
**Line(s):** 95-99, 171-182, 230-239

**File:** `scripts/openclaw-gcp/create-instance.sh`  
**Line(s):** 151-156

**Why this was a problem:**  
Regional templates need explicit regional scoping in describe/delete flows, and instance creation should consume them with the matching regional selector.

## Proposed Solutions

### Option A — [Recommended] Use region-aware template commands consistently
Use `--instance-template-region` on create, `--region` on describe/delete, and `--instance-template-region` when creating an instance from the template.
**Pros:** Matches current `gcloud` semantics and preserves repeatability.  
**Cons:** Requires keeping zone/region inputs aligned.  
**Effort:** Small

### Option B — Fall back to global templates only
Avoid regional template semantics entirely.
**Pros:** Simpler command surface.  
**Cons:** Conflicts with the selected regional operator model and weakens D6 behavior.  
**Effort:** Medium

## Acceptance Criteria

- [x] Template existence checks and deletes are region-scoped for regional templates.
- [x] Instance creation from the template passes the regional template selector explicitly.
- [x] Zone and region mismatch is rejected early.

## Resolution

**Resolved by:** Codex review fix  
**Resolution date:** 2026-03-24  
**Resolution:** Switched template creation to `--instance-template-region`, added `--region` to template describe/delete, passed `--instance-template-region` in instance creation, and added a guard that validates `--zone` belongs to `--region`. Verified with local `gcloud --help`, mocked `gcloud` command capture, `bash -n`, and `--help`.  
**Status change:** pending → resolved
