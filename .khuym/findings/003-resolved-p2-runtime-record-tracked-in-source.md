---
status: resolved
priority: p2
source_agent: code-quality
tags: [code-quality]
created: 2026-03-24
feature: openclaw-gcp-instance-strategy
---

# Runtime image-resolution record was tracked in source

## Problem Statement

The Debian image resolution record lived under `scripts/openclaw-gcp/` as a tracked file and was rewritten on operational runs. That mixed runtime state into source artifacts and would cause noisy working-tree churn during normal script usage.

## Evidence

**File:** `scripts/openclaw-gcp/create-template.sh`  
**Line(s):** 21, 101-109, 217-228

**File:** `scripts/openclaw-gcp/create-instance.sh`  
**Line(s):** 23

**File:** `.gitignore`  
**Line(s):** 1-5

**Why this was a problem:**  
Routine script execution should not mutate tracked source files.

## Proposed Solutions

### Option A — [Recommended] Move runtime state under ignored project runtime storage
Write the record into `.khuym/runtime/openclaw-gcp/` and ignore that path.
**Pros:** Keeps source clean while preserving useful operator breadcrumbs.  
**Cons:** Runtime records are no longer committed artifacts.  
**Effort:** Small

### Option B — Stop recording runtime state entirely
Remove the record file.
**Pros:** Simplest operational model.  
**Cons:** Loses useful execution details for operators.  
**Effort:** Small

## Acceptance Criteria

- [x] Operator runs no longer rewrite a tracked file under `scripts/openclaw-gcp/`.
- [x] The runtime record is written to an ignored runtime path instead.

## Resolution

**Resolved by:** Codex review fix  
**Resolution date:** 2026-03-24  
**Resolution:** Moved the default resolution record to `.khuym/runtime/openclaw-gcp/resolved-debian-image.txt`, ignored that runtime directory in `.gitignore`, and deleted the tracked `scripts/openclaw-gcp/.resolved-debian-image.txt` artifact. Verified with mocked reruns.  
**Status change:** pending → resolved
