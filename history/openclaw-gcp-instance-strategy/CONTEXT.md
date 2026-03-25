# OpenClaw GCP Instance Strategy — Context

**Feature slug:** openclaw-gcp-instance-strategy
**Date:** 2026-03-24
**Exploring session:** complete
**Scope:** Standard

---

## Feature Boundary

Define the deployment and operating strategy for running OpenClaw on GCP for project `hoangnb-openclaw`, including the recommended instance profile for the first always-on environment and the product requirements for creating future persistent instances cheaply and quickly via a repeatable CLI/script flow. This exploring scope does not design the provisioning implementation itself.

**Domain type(s):** RUN | ORGANIZE | READ

---

## Locked Decisions

These are fixed. Planning must implement them exactly. No creative reinterpretation.

### Deployment Intent
- **D1** The first OpenClaw deployment is an always-on GCP instance for the user's own regular use, with stability prioritized over absolute minimum monthly cost.
  *Rationale: The user wants a dependable primary environment rather than a stop/start sandbox.*

- **D2** The near-term workload is medium: one main user, longer-running sessions, multiple services/containers, and low tolerance for slowdown.
  *Rationale: This rules out planning around the bare-minimum VM profile.*

### Cost and Lifecycle
- **D3** Cost strategy is balanced: keep the main instance reasonably sized now while preserving a path to create future instances at reasonable cost, without optimizing everything for the absolute cheapest option.

- **D4** Future spawned OpenClaw instances are persistent full environments with their own long-lived state and disks, not disposable workers or temporary sandboxes.
  *Rationale: New instances are expected to remain meaningful environments after creation.*

### Provisioning Experience
- **D5** Future instance creation should use a repeatable CLI or script flow, not a console-only checklist and not full infrastructure-as-code as the initial target.
  *Rationale: The user wants fast repeatability without the upfront complexity of a full IaC program.*

- **D6** The provisioning flow should use one default GCP region but allow selecting another region when creating a new instance.
  *Rationale: Simplicity is preferred, but the workflow must still support price or availability changes.*

### Data Protection
- **D7** Long-lived instances should use persistent disks, and the repeatable operating flow should include snapshots or backup steps, but backup/restore does not need to be a first-class platform capability on day one.
  *Rationale: Moderate protection is required because future instances are persistent, but the user does not want to front-load a full backup platform.*

### Agent's Discretion
- Planning may choose the exact GCP machine family, disk defaults, image strategy, and scripting approach as long as they satisfy D1-D7 and the canonical OpenClaw GCP requirements.

---

## Specific Ideas & References

- Project already created: `hoangnb-openclaw`.
- The OpenClaw GCP install guide frames `e2-small` as the minimum recommended size, `e2-medium` as the more reliable option for local Docker builds, and warns that `e2-micro` often fails with Docker build OOMs.
- The guide assumes durable host state in `~/.openclaw` and `~/.openclaw/workspace`, loopback binding on the VM, and SSH tunneling from the laptop for Control UI access.

---

## Existing Code Context

From the quick codebase scout during exploring.
Downstream agents: read these files before planning to avoid reinventing existing patterns.

### Reusable Assets
- None found. The repository root was empty during the exploring scan on 2026-03-24.

### Established Patterns
- None found locally. Planning should treat the OpenClaw documentation as the primary starting point.

### Integration Points
- No existing local code or automation was present to extend.

---

## Canonical References

**Downstream agents MUST read these before planning or implementing.**

- `https://docs.openclaw.ai/install/gcp` — Official OpenClaw guide for GCP Compute Engine deployment, including minimum machine guidance, persistent host directories, Docker Compose shape, and SSH tunnel access pattern.

---

## Outstanding Questions

### Resolve Before Planning

None.

### Deferred to Planning

- [ ] Recommend the concrete default machine type, disk size, and default region for the first `hoangnb-openclaw` instance under D1-D7 — requires current tradeoff analysis against the OpenClaw GCP guide and GCP pricing/availability.
- [ ] Define the repeatable CLI/script flow for creating additional persistent instances, including whether to clone from a base image, startup script, or another lightweight automation pattern — requires implementation research.
- [ ] Define the minimum viable backup/snapshot procedure for long-lived instances so D7 is satisfied without overbuilding day one operations — requires operational design.

---

## Deferred Ideas

- Full infrastructure-as-code provisioning was explicitly deferred in favor of a lighter CLI/script workflow.
- Disposable burst-capacity instances were considered but rejected for this work because future spawned environments are intended to be persistent.

---

## Handoff Note

CONTEXT.md is the single source of truth for this feature.

- **planning** reads: locked decisions, code context, canonical refs, deferred-to-planning questions
- **validating** reads: locked decisions (to verify plan-checker coverage)
- **reviewing** reads: locked decisions (for UAT verification)

Decision IDs (D1, D2...) are stable. Reference them by ID in all downstream artifacts.
