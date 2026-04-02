---
status: resolved
priority: p2
source_agent: security
tags: [security, code-quality]
created: 2026-03-24
feature: openclaw-gcp-instance-strategy
---

# Metadata value injection is blocked at validation time

## Problem Statement

The template script previously interpolated user-controlled values directly into a comma-delimited metadata string. Values containing commas or equals signs could break key/value boundaries and inject unintended metadata entries.

## Evidence

**File:** `scripts/openclaw-gcp/create-template.sh`  
**Line(s):** 135-141, 250-272

**Why this was a problem:**  
Metadata strings are structurally sensitive, so unvalidated delimiters can create unintended keys.

## Proposed Solutions

### Option A — [Recommended] Reject metadata-breaking characters
Validate user-controlled metadata values and reject commas, equals signs, and newlines before constructing the metadata string.
**Pros:** Small change, closes the injection path immediately.  
**Cons:** Slightly stricter input contract.  
**Effort:** Small

### Option B — Move all values to file-backed metadata inputs
Encode dynamic metadata through controlled file outputs instead of direct interpolation.
**Pros:** Stronger structural separation.  
**Cons:** More complex for a small CLI utility.  
**Effort:** Medium

## Acceptance Criteria

- [x] Metadata-persisted values are validated before interpolation.
- [x] Comma/equal-sign injection attempts fail fast before `gcloud` execution.

## Resolution

**Resolved by:** Codex review fix  
**Resolution date:** 2026-03-24  
**Resolution:** Added metadata-value validation for persisted fields and verified that comma-based injection attempts now fail fast before template creation.  
**Status change:** pending → resolved
