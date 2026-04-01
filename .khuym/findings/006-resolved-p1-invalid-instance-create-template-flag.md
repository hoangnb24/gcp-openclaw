---
status: resolved
priority: p1
source_agent: code-quality
tags: [code-quality, error-handling]
created: 2026-03-24
feature: openclaw-gcp-instance-strategy
---

# Instance creation used an unsupported template-region flag

## Problem Statement

The instance creation script was passing `--instance-template-region` to `gcloud compute instances create`, which the local CLI does not support. That made the core provisioning command fail even when the rest of the template flow was correct.

## Evidence

**File:** `scripts/openclaw-gcp/create-instance.sh`  
**Line(s):** 165-172

**Why this was a problem:**  
An unsupported CLI flag breaks the primary day-1 provisioning path outright.

## Proposed Solutions

### Option A — [Recommended] Use a fully scoped regional template reference
Pass `--source-instance-template` as `projects/<project>/regions/<region>/instanceTemplates/<name>` instead of adding a separate unsupported flag.
**Pros:** Matches local CLI behavior and keeps regional template selection explicit.  
**Cons:** Slightly longer generated command.  
**Effort:** Small

### Option B — Fall back to global template names
Use only global templates so plain template names work unambiguously.
**Pros:** Shorter commands.  
**Cons:** Gives up the regional template model already chosen for this feature.  
**Effort:** Medium

## Acceptance Criteria

- [x] `create-instance.sh` no longer emits the unsupported `--instance-template-region` flag.
- [x] The generated command still references the intended regional template explicitly.

## Resolution

**Resolved by:** Codex review fix  
**Resolution date:** 2026-03-24  
**Resolution:** Replaced the unsupported flag with a fully scoped regional template resource path in `--source-instance-template`. Verified with local `gcloud` help, mocked command capture, `bash -n`, and `--help`.  
**Status change:** pending → resolved
