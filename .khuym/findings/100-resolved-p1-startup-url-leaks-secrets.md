---
status: resolved
priority: p1
source_agent: security
tags: [security, auth]
created: 2026-03-24
feature: openclaw-gcp-instance-strategy
---

# Remote startup-script URLs no longer leak into template metadata

## Problem Statement

The template script previously persisted the raw startup-script URL into instance-template metadata and the local resolution record. Signed or credential-bearing URLs would have leaked secrets into clear-text metadata surfaces.

## Evidence

**File:** `scripts/openclaw-gcp/create-template.sh`  
**Line(s):** 221-235, 250-272

**File:** `docs/openclaw-gcp/README.md`  
**Line(s):** 77-82

**Why this was a problem:**  
Credential-bearing URLs in template metadata are a direct secret-handling failure.

## Proposed Solutions

### Option A — [Recommended] Store only digest-based provenance
Persist only a safe source identifier such as `url-sha256:<digest>` and keep raw URLs out of metadata and runtime records.
**Pros:** Preserves determinism without leaking secrets.  
**Cons:** Operators lose the raw URL breadcrumb in metadata.  
**Effort:** Small

### Option B — Ban URL mode entirely
Allow only embedded or local startup-script sources.
**Pros:** Strongest safety posture.  
**Cons:** Removes a supported operator path.  
**Effort:** Small

## Acceptance Criteria

- [x] Raw startup-script URLs are no longer persisted into template metadata.
- [x] Runtime resolution records store only safe digest-based provenance for URL mode.
- [x] Docs explicitly warn against signed or credential-bearing startup-script URLs.

## Resolution

**Resolved by:** Codex review fix  
**Resolution date:** 2026-03-24  
**Resolution:** Changed URL provenance to `url-sha256:<digest>`, removed the raw URL from metadata and the runtime record, and documented that signed or credential-bearing URLs must not be used. Verified with a signed-style URL dry-run and record inspection.  
**Status change:** pending → resolved
