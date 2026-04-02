---
status: resolved
priority: p2
source_agent: code-quality
tags: [code-quality]
created: 2026-03-24
feature: openclaw-gcp-instance-strategy
---

# `--no-create-template` path required an unrelated OpenClaw tag

## Problem Statement

The instance creation script previously enforced `--openclaw-tag` even when `--no-create-template` was set. In that path the script skips template creation, so the tag requirement was unrelated to the executed command path.

## Evidence

**File:** `scripts/openclaw-gcp/create-instance.sh`  
**Line(s):** 111-119

**Why this was a problem:**  
Operators reusing an existing template should not be blocked by validation for a code path that is not running.

## Proposed Solutions

### Option A — [Recommended] Gate validation by execution path
Require `--openclaw-tag` only when `ENSURE_TEMPLATE=true`.
**Pros:** Aligns validation with real behavior.  
**Cons:** Slightly more branching in validation.  
**Effort:** Small

### Option B — Keep the unconditional requirement and document it
Force the tag even on reuse-only paths.
**Pros:** Simpler validation logic.  
**Cons:** Confusing operator experience and unnecessary friction.  
**Effort:** Small

## Acceptance Criteria

- [x] `--no-create-template` can execute without an explicit OpenClaw tag.
- [x] Template-ensure paths still require an explicit non-placeholder tag.

## Resolution

**Resolved by:** Codex review fix  
**Resolution date:** 2026-03-24  
**Resolution:** Gated OpenClaw tag validation behind the template-ensure path and updated the help text to reflect that contract. Verified with mocked runs of both `--no-create-template` and template-ensure flows.  
**Status change:** pending → resolved
