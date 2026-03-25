# Discovery Report: OpenClaw GCP Instance Strategy

**Date**: 2026-03-24
**Feature**: `openclaw-gcp-instance-strategy`
**CONTEXT.md reference**: `history/openclaw-gcp-instance-strategy/CONTEXT.md`

---

## Institutional Learnings

> Read during Phase 0 from `history/learnings/`

### Critical Patterns (Always Applied)

- None applicable. `history/learnings/critical-patterns.md` was not present.

### Domain-Specific Learnings

No prior learnings for this domain.

---

## Agent A: Architecture Snapshot

> Source: local file tree analysis and planning context

### Relevant Packages / Modules

| Package/Module | Purpose | Key Files |
|----------------|---------|-----------|
| `.khuym/` | Workflow state for the planning pipeline | `.khuym/STATE.md` |
| `history/openclaw-gcp-instance-strategy/` | Planning artifacts for this feature | `CONTEXT.md` |

### Entry Points

- **Docs/Planning**: `history/openclaw-gcp-instance-strategy/CONTEXT.md`
- **Implementation surface to be created later**: shell scripts and Markdown runbooks in the repository root or a future `scripts/` and `docs/` layout

### Key Files to Model After

- `history/openclaw-gcp-instance-strategy/CONTEXT.md` — locked product decisions D1-D7

### Architecture Notes

- There is no existing codebase or automation to extend. This plan is effectively a greenfield operational bootstrap.
- The canonical runtime architecture comes from the OpenClaw GCP guide:
  - persistent state on host in `~/.openclaw` and `~/.openclaw/workspace`
  - Docker-based OpenClaw Gateway on a Debian VM
  - loopback binding with SSH tunnel access from the laptop

---

## Agent B: Pattern Search

> Source: local repo scan and official Google/OpenClaw documentation

### Similar Existing Implementations

| Feature/Component | Location | Pattern Used | Reusable? |
|-------------------|----------|--------------|-----------|
| Existing provisioning automation | None found locally | None | No |
| Existing GCP runbook | None found locally | None | No |

### Reusable Utilities

- **CLI foundation**: local `gcloud` is installed (`Google Cloud SDK 543.0.0`) and suitable for the repeatable flow locked by D5.
- **Issue tracking**: local `br` CLI is installed and usable for bead decomposition.

### Naming Conventions

- GCP resources should use kebab-case names derived from the project and role, for example:
  - `oc-main`
  - `oc-template`
  - `oc-snapshots-daily`
  - `oc-image-YYYYMMDD`
- Region and zone should be explicit flags in scripts, not hidden constants.
- Generated artifacts should separate:
  - base provisioning
  - clone provisioning
  - backup / restore operations

### Pattern Findings from Official Docs

- **OpenClaw VM sizing baseline**: the OpenClaw GCP guide positions `e2-small` as the quick-path baseline, `e2-medium` as a safer build target, and warns that `e2-micro` can OOM during Docker builds.
- **Deterministic provisioning pattern**: Google recommends deterministic instance templates and startup scripts so repeated VM creation does not drift over time.
- **Cloning persistent environments**: Google documents machine images as the right primitive for instance cloning and multi-disk backup, whereas instance templates are best for repeatable configuration.

---

## Agent C: Constraints Analysis

> Source: local environment plus official pricing/ops docs

### Runtime & Framework

- **Runtime**: Shell + `gcloud` CLI automation on the operator machine; Debian 12 VM on GCP for OpenClaw
- **Primary control plane**: Compute Engine + Persistent Disk + snapshots/machine images
- **OpenClaw deployment mode**: Docker on Compute Engine, accessed by SSH tunnel or other secured remote path

### Existing Dependencies (Relevant to This Feature)

| Package | Version | Purpose |
|---------|---------|---------|
| `gcloud` | `543.0.0` | Compute Engine and project automation |
| `br` | local CLI | planning artifact tracking |

### New Dependencies Needed

| Package | Reason | Risk Level |
|---------|--------|------------|
| None required for planning | The initial implementation can be shell scripts plus `gcloud` | LOW |

### Build / Quality Requirements

```bash
# The future implementation should at minimum support:
bash scripts/<script>.sh --help
shellcheck scripts/*.sh
markdownlint docs/*.md  # if docs are added and tooling is available
```

### Storage / Backup Constraints

- OpenClaw host state is expected to live on persistent host directories, not in ephemeral container layers.
- `pd-balanced` is the best default disk type for this feature’s balance of cost and responsiveness; Google describes it as the general-purpose cost/performance middle ground.
- Standard snapshots are incremental and independent of VM lifecycle, making them a low-friction day-1 backup primitive.

### Pricing Baselines from Official Sources

These are current official Google Cloud baseline prices gathered on 2026-03-24. They vary by region and discount model.

#### VM baseline prices from Google Cloud Compute Engine E2 pricing

Default hourly rates on the pricing page’s Iowa (`us-central1`) view:

| Machine type | vCPU / RAM | Hourly | Approx. 730h month |
|--------------|------------|--------|--------------------|
| `e2-small` | 2 vCPU / 2 GiB | `$0.016752855` | `$12.23/mo` |
| `e2-medium` | 2 vCPU / 4 GiB | `$0.03350571` | `$24.46/mo` |
| `e2-standard-2` | 2 vCPU / 8 GiB | `$0.06701142` | `$48.92/mo` |
| `e2-standard-4` | 4 vCPU / 16 GiB | `$0.13402284` | `$97.84/mo` |

Implication for D1-D3:
- `e2-medium` matches OpenClaw’s “more reliable than minimum” guidance but still only provides 4 GiB RAM.
- `e2-standard-2` is the first E2 shape that gives meaningful headroom for a medium always-on workload without jumping to a much larger class.

#### Disk and backup pricing baselines

From Google Cloud disk pricing baselines:

| Resource | Price | Approx. monthly equivalent |
|----------|-------|----------------------------|
| `pd-balanced` provisioned space | `$0.000136986 / GiB hour` | `$0.10 / GiB month` |
| Standard snapshot storage | `$0.000068493 / GiB hour` | `$0.05 / GiB month` |
| Archive snapshot storage | `$0.000026027 / GiB hour` | `$0.019 / GiB month` |
| Archive snapshot retrieval | `$0.019 / GiB` | retrieval charge |

Practical implications:
- a `30 GiB` `pd-balanced` disk is about `$3/mo` before regional variance
- a fully unique `30 GiB` standard snapshot footprint is about `$1.50/mo`, though incremental snapshots are usually lower in practice

### Region Constraints

- The locked decision is one default region with override support, not a fixed single-region design.
- No pricing source reviewed guaranteed that Singapore is cheaper than Iowa; in practice, closer regions for Southeast Asia often trade higher price for lower latency.
- The user appears to operate from Vietnam, so `asia-southeast1` (Singapore) is the strongest latency-first default candidate, while `us-central1` remains the strongest cost-first fallback candidate.

---

## Agent D: External Research

> Source: official OpenClaw and Google Cloud documentation

### Library Documentation

| Library / Platform | Version | Key Docs |
|--------------------|---------|----------|
| OpenClaw GCP deployment | current docs as of 2026-03-24 | https://docs.openclaw.ai/install/gcp |
| Compute Engine E2 pricing | current docs as of 2026-03-24 | https://cloud.google.com/products/compute/pricing/general-purpose |
| Disk and image pricing | current docs as of 2026-03-24 | https://cloud.google.com/compute/disks-image-pricing |
| Instance templates | current docs as of 2026-03-24 | https://cloud.google.com/compute/docs/instance-templates |
| Create instance templates | current docs as of 2026-03-24 | https://cloud.google.com/compute/docs/instance-templates/create-instance-templates |
| Startup scripts | current docs as of 2026-03-24 | https://cloud.google.com/compute/docs/instances/startup-scripts/linux |
| Deterministic instance templates | current docs as of 2026-03-24 | https://cloud.google.com/compute/docs/instance-templates/deterministic-instance-templates |
| Machine images | current docs as of 2026-03-24 | https://cloud.google.com/compute/docs/machine-images |
| Snapshot schedules | current docs as of 2026-03-24 | https://cloud.google.com/compute/docs/disks/scheduled-snapshots |

### Community / Vendor Patterns

- **Pattern**: use a deterministic startup script plus instance template for repeatable creation of baseline VMs
  - Why it applies: satisfies D5 with a lightweight CLI/script path and avoids full IaC
  - Reference: Google’s instance template and deterministic template docs

- **Pattern**: use machine images for cloning a fully configured persistent VM once the golden source instance is in a good state
  - Why it applies: satisfies D4 because future instances are persistent environments, not disposable stateless workers
  - Reference: Google’s machine images docs explicitly list instance cloning as a prime use case

- **Pattern**: use standard snapshot schedules for steady day-2 protection, with ad-hoc machine images before major upgrades
  - Why it applies: satisfies D7 without building an elaborate backup platform
  - Reference: snapshot schedule and snapshot type docs

### Known Gotchas / Anti-Patterns

- **Gotcha**: sizing to free-tier or near-free-tier shapes can fail the initial Docker build
  - Why it matters: OpenClaw specifically warns that `e2-micro` often OOMs and `e2-small` is only the minimum path
  - How to avoid: do not plan around `e2-micro`; treat `e2-medium` as floor and `e2-standard-2` as the first serious always-on option

- **Gotcha**: startup-script-based provisioning can drift if versions and image references are not pinned
  - Why it matters: a supposedly repeatable spawn flow becomes nondeterministic across weeks or months
  - How to avoid: pin Debian image family/version assumptions, Docker image tags, OpenClaw revision/source, and script inputs

- **Anti-pattern**: using only instance templates to clone persistent environments
  - Common mistake: assuming an instance template alone captures a fully configured long-lived VM
  - Correct approach: use instance templates for baseline configuration and machine images when you need a true full-environment clone

- **Anti-pattern**: using only machine images for all provisioning
  - Common mistake: cloning everything from a mutable “golden server” and losing a deterministic rebuild story
  - Correct approach: keep a deterministic bootstrap path and layer machine-image cloning on top for persistent replicas

- **Gotcha**: machine images can capture more state than operators intend, including local configuration and possibly embedded secrets
  - Why it matters: a persistent-clone workflow can accidentally replicate credentials or stale runtime state into every new environment
  - How to avoid: define whether secrets are injected after provisioning or intentionally cloned, and keep secret handling explicit in scripts and docs

- **Gotcha**: snapshot schedules operate on UTC windows and begin within the selected hour
  - Why it matters: operators can assume a local-time exact execution guarantee that does not exist
  - How to avoid: document snapshot times in UTC and choose a retention/frequency pattern that does not depend on minute-level precision

### Open Questions

- [ ] Should the first implementation deliver only operator-facing scripts/docs, or also create an initial “golden image” workflow for cloning after the first VM is configured?
- [ ] Should the default disk size be `30 GiB` or `50 GiB` for the first instance, given D2’s medium workload and OpenClaw’s durable workspace expectations?
- [ ] How should provider/model credentials be handled in the clone workflow so machine images do not unintentionally spread secrets or stale auth state?

---

## Summary for Synthesis (Phase 2 Input)

**What we have**: an empty repository with a locked product direction, a working `gcloud` CLI, and official documentation for OpenClaw on GCP plus the relevant Compute Engine primitives.

**What we need**: a concrete operating strategy that picks the default VM shape, region policy, disk/backup defaults, and the exact lightweight automation pattern for both first deployment and future persistent clones.

**Key constraints from research**:
- OpenClaw’s own guide already rules out `e2-micro` for reliable builds and treats `e2-small` as minimum only.
- Persistent instances need durable host directories, not ephemeral container-only state.
- Instance templates are best for deterministic baseline creation; machine images are best for persistent full-environment cloning.
- Snapshot schedules are the simplest day-1 backup primitive and standard snapshots are incremental.
- Secret handling for cloned instances must be explicit; otherwise a “golden” machine image can become an accidental secret distribution mechanism.

**Institutional warnings to honor**:
- No prior institutional learnings exist for this domain, so planning must rely on locked decisions D1-D7 and official vendor docs.
