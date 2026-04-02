---
status: resolved
priority: p2
source_agent: code-quality
tags: [code-quality, security]
created: 2026-03-24
feature: openclaw-gcp-instance-strategy
---

# Remote startup script URL could drift across reruns

## Problem Statement

The template script previously accepted a remote startup-script URL without requiring a pinned content digest. That allowed the same command to produce different templates over time if the remote content changed.

## Evidence

**File:** `scripts/openclaw-gcp/create-template.sh`  
**Line(s):** 21-23, 56-58, 110-130, 163-165, 194-201, 217-228

**File:** `docs/openclaw-gcp/README.md`  
**Line(s):** 76-80

**Why this was a problem:**  
Mutable remote bootstrap content breaks deterministic reruns and weakens operator trust in the provisioning flow.

## Proposed Solutions

### Option A — [Recommended] Require SHA-256 when using URL mode
Require `--startup-script-sha256`, verify the downloaded content against it, and record the digest in runtime metadata.
**Pros:** Preserves URL mode while keeping deterministic behavior.  
**Cons:** Slightly more operator input when using remote scripts.  
**Effort:** Small

### Option B — Remove URL mode entirely
Allow only local startup-script files or embedded scripts.
**Pros:** Strongly deterministic.  
**Cons:** Removes a potentially useful operator path.  
**Effort:** Small

## Acceptance Criteria

- [x] URL mode fails fast unless a SHA-256 digest is provided.
- [x] Downloaded startup scripts are verified against the provided digest before template creation.
- [x] The recorded startup-script source includes the pinned digest.

## Resolution

**Resolved by:** Codex review fix  
**Resolution date:** 2026-03-24  
**Resolution:** Added `--startup-script-sha256`, enforced it for URL mode, verified downloaded content via SHA-256, and stored the digest in the recorded startup-script source and operator docs. Verified with a local file-backed URL, mocked `gcloud`, `bash -n`, and a negative test confirming URL mode fails without the digest.  
**Status change:** pending → resolved
