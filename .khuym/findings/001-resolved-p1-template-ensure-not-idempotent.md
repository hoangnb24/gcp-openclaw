---
status: resolved
priority: p1
source_agent: code-quality
tags: [code-quality, error-handling]
created: 2026-03-24
feature: openclaw-gcp-instance-strategy
---

# Non-idempotent template ensure flow broke repeatable provisioning

## Problem Statement

The original default path in `create-instance.sh` always called `create-template.sh`, and `create-template.sh` always attempted a fresh `instance-templates create` with the same name. After the first successful run, later runs failed before instance creation, which broke the repeatable CLI provisioning workflow required by D5.

## Evidence

**File:** `scripts/openclaw-gcp/create-template.sh`  
**Line(s):** 171-182, 230-271

**File:** `scripts/openclaw-gcp/create-instance.sh`  
**Line(s):** 114-149

**Why this was a problem:**  
The default "ensure template" path was not idempotent, so normal follow-on instance creation failed on existing templates.

## Proposed Solutions

### Option A — [Recommended] Ensure-or-reuse by default, explicit replace on demand
Make `create-template.sh` detect existing templates and reuse them by default, while adding an explicit replace flag for intentional recreation.
**Pros:** Matches operator expectations, preserves repeatability, avoids accidental destructive changes.  
**Cons:** Operators must opt in when they truly want to rebuild a template.  
**Effort:** Small

### Option B — Always delete and recreate
Delete any existing template before every create.
**Pros:** Keeps template contents aligned to latest flags.  
**Cons:** Destructive by default and riskier for routine operator use.  
**Effort:** Small

## Acceptance Criteria

- [x] Re-running `create-instance.sh` after a template already exists still reaches instance creation.
- [x] Operators have an explicit replace path when they intentionally want to rebuild the template.

## Resolution

**Resolved by:** Codex review fix  
**Resolution date:** 2026-03-24  
**Resolution:** `create-template.sh` now checks for an existing template and reuses it by default, writes a runtime reuse record, and supports `--replace-existing` for intentional recreation. `create-instance.sh` forwards this behavior with `--replace-template`. Verified with mocked `gcloud` reruns plus `bash -n` and `--help`.  
**Status change:** pending → resolved
