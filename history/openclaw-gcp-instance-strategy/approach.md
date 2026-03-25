# Approach: OpenClaw GCP Instance Strategy

**Date**: 2026-03-24
**Feature**: `openclaw-gcp-instance-strategy`
**Based on**:
- `history/openclaw-gcp-instance-strategy/discovery.md`
- `history/openclaw-gcp-instance-strategy/CONTEXT.md`

---

## 1. Gap Analysis

> What exists vs. what the feature requires.

| Component | Have | Need | Gap Size |
|-----------|------|------|----------|
| GCP project | `hoangnb-openclaw` already created | confirm project is used by scripts and docs | Small |
| Base VM recommendation | OpenClaw minimum guidance only | one concrete always-on recommendation honoring D1-D3 | Medium |
| Region strategy | default-region requirement in CONTEXT | one default plus override behavior | Medium |
| Repeatable provisioning | no scripts or docs yet | deterministic `gcloud` flow for first VM and future VMs | New |
| Persistent clone strategy | no clone workflow yet | a supported way to create long-lived copies quickly | New |
| Backup / restore workflow | D7 only | snapshot schedule baseline plus restore runbook | New |

---

## 2. Recommended Approach

> Specific strategy. Not "here are options" — a concrete recommendation.

Use a two-layer provisioning model:
1. a deterministic baseline built from a `gcloud`-driven instance template plus pinned startup/bootstrap logic, and
2. a persistent-clone path built from machine images taken from a known-good OpenClaw VM.

For the first always-on instance, recommend `e2-standard-2` with a `pd-balanced` boot disk, starting at `30 GiB`, Debian 12, and a default zone in `asia-southeast1` for latency to Vietnam, while preserving `--region` / `--zone` overrides so cost-sensitive clones can target `us-central1`. This gives materially more RAM headroom than OpenClaw’s documented minimums while staying inside the “reasonable cost” band implied by D1-D3. For backups, attach a standard snapshot schedule to the persistent disk and document ad-hoc machine-image creation before major upgrades or before using the VM as a cloning source.

### Why This Approach

- It honors **D1** and **D2** by sizing above OpenClaw’s minimum path without jumping to a much larger VM family.
- It honors **D4** and **D5** by separating deterministic rebuilds from full-environment persistent clones instead of pretending one primitive solves both.
- It honors **D6** by making region an explicit script input while still naming a clear default.
- It honors **D7** by using standard snapshot schedules as the day-1 safety net and machine images as milestone-grade recovery/cloning artifacts.
- It avoids the two main researched failures:
  - under-sizing to `e2-micro`/bare minimum
  - allowing startup scripts or image selection to drift over time

### Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Main VM shape | `e2-standard-2` | First E2 shape with 8 GiB RAM; better fit for D1-D2 than `e2-medium` |
| Main disk type | `pd-balanced` | Google positions it as the cost/performance middle ground for general-purpose workloads |
| Main disk size | `30 GiB` initial default | Low incremental cost, enough room above OpenClaw’s 20 GiB quick path, still cheap to clone |
| Default region | `asia-southeast1` | Best latency-first default for a Vietnam-based operator; matches D6 because scripts still allow overrides |
| Cost-sensitive override region | `us-central1` | Strong price-first fallback and the region used in OpenClaw’s quick path examples |
| Baseline provisioning primitive | Instance template + deterministic startup/bootstrap | Best fit for repeatable CLI-driven creation |
| Persistent clone primitive | Machine images | Official Google best fit for cloning persistent environments |
| Backup baseline | Standard snapshot schedule on persistent disks | Lowest-friction day-1 protection aligned with D7 |
| Milestone backup | Ad-hoc machine image before major changes | Gives whole-instance rollback and a clean cloning source |

---

## 3. Alternatives Considered

### Option A: Stay on `e2-medium` for the main always-on instance

- Description: use the OpenClaw guide’s “safer than minimum” VM as the main long-lived server
- Why considered: it is materially cheaper than `e2-standard-2` and already called out by OpenClaw as more reliable than `e2-small`
- Why rejected: 4 GiB RAM is still a narrow margin for D2’s medium, always-on usage profile with Docker and durable workspace growth

### Option B: Use only instance templates and startup scripts for everything

- Description: one deterministic baseline path and no machine-image workflow
- Why considered: simpler to explain and maintain
- Why rejected: it does not satisfy D4 well enough because persistent full-environment clones are not just “same config, fresh VM”; they often need a whole-machine copy path

### Option C: Use only machine images from a golden VM

- Description: clone every new instance from a machine image and skip deterministic bootstrap
- Why considered: fastest path to create persistent copies once the first environment is healthy
- Why rejected: it weakens repeatability and makes the system depend too much on a mutable golden server; Google explicitly recommends deterministic templates when repeatability matters

### Option D: Jump directly to full Terraform / IaC

- Description: codify the whole infrastructure in Terraform from day one
- Why considered: strongest long-term repeatability and auditability
- Why rejected: it directly conflicts with D5, which intentionally chose a lighter CLI/script path first

---

## 4. Risk Map

> Every component that is part of this feature must appear here.

| Component | Risk Level | Reason | Verification Needed |
|-----------|------------|--------|---------------------|
| Main VM sizing recommendation (`e2-standard-2`, `30 GiB`, `pd-balanced`) | **MEDIUM** | No local precedent; must balance cost vs. headroom for D1-D3 | Validate monthly cost math and confirm no hidden OpenClaw requirements |
| Deterministic bootstrap flow (startup script + pinned inputs) | **HIGH** | Novel implementation in this repo; external GCP behavior and version drift risks | Validate with a dry-run plan and script review |
| Instance template workflow | **MEDIUM** | Official pattern, but new in this repo | Confirm CLI flags and override behavior |
| Machine-image clone workflow | **HIGH** | External infra primitive, persistence-sensitive, and easy to misuse as the only source of truth; may also clone secrets or stale runtime state if boundaries are unclear | Validate when to create images, how to name/store them, and what state must be scrubbed or reinjected |
| Snapshot schedule + restore runbook | **MEDIUM** | Official feature with straightforward scope, but restore expectations must be explicit | Validate retention and restore steps |
| Region default / override policy | **MEDIUM** | Product tradeoff between latency and price rather than pure technical correctness | Validate default region rationale and override ergonomics |

### Risk Classification Reference

```
Pattern in codebase?        → YES = LOW base
External dependency?        → YES = HIGH
Blast radius > 5 files?    → YES = HIGH
Otherwise                   → MEDIUM
```

### HIGH-Risk Summary (for khuym:validating skill)

- `Deterministic bootstrap flow`: confirm the script/template design pins enough inputs to avoid drift across repeated launches.
- `Machine-image clone workflow`: confirm the plan clearly separates “baseline rebuild” from “persistent full clone” so operators do not rely on the wrong primitive.
- `Secret handling in clones`: confirm credentials are either injected post-provisioning or intentionally cloned with explicit documentation.

---

## 5. Proposed File Structure

> Where new files will live. Workers use this to plan their work.

```text
docs/
  openclaw-gcp/
    README.md                     # Operator-facing overview
    sizing-and-cost.md            # Main-instance recommendation and tradeoffs
    backup-and-restore.md         # Snapshot + machine-image runbook
scripts/
  openclaw-gcp/
    create-instance.sh            # Create baseline OpenClaw VM with overrides
    create-template.sh            # Create/update deterministic instance template
    create-machine-image.sh       # Capture a golden VM into a machine image
    spawn-from-image.sh           # Create a persistent clone from a machine image
    create-snapshot-policy.sh     # Create and attach snapshot schedule
```

---

## 6. Dependency Order

> Dependency order for bead creation. This is planning guidance, not a runtime wave scheduler.

```text
Layer 1: Documentation of sizing, region, and operating defaults
Layer 2: Baseline deterministic provisioning scripts (create VM / create template)
Layer 3: Protection scripts and runbooks (snapshot policy + restore docs)
Layer 4: Persistent clone workflow (machine image capture + spawn from image)
```

### Parallelizable Groups

- Group A: sizing/cost docs and backup/runbook docs can progress in parallel once defaults are locked
- Group B: `create-instance.sh` and `create-template.sh` are tightly related and should be implemented together
- Group C: `create-machine-image.sh` and `spawn-from-image.sh` depend on Group B but can be developed together after the baseline path exists

---

## 7. Institutional Learnings Applied

> From Phase 0 — how past learnings shaped this approach.

No prior institutional learnings relevant to this feature.

---

## 8. Open Questions for Validating

- [x] The first implementation should stop at VM provisioning plus runbooks. It should not generate a committed OpenClaw `.env` or Compose scaffold on day one because that expands scope into app configuration rather than infra/bootstrap guidance.
- [x] Keep `30 GiB` as the default disk size for the first always-on instance. Document `50 GiB` as the operator override when long-lived workspace retention or larger model/tooling footprints are expected.
- [x] Credentials for cloned persistent instances must be handled intentionally: prefer VM service-account access and Secret Manager for automation, and require post-provision credential injection or re-auth rather than silently inheriting provider secrets from a machine image.

## 9. Validation Decisions

### Spike Results

| Spike | Verdict | Decision Locked For Execution |
|------|---------|-------------------------------|
| Deterministic bootstrap flow | **YES** | Baseline scripts must resolve and record a specific Debian image at template-creation time, pin startup/bootstrap inputs, and avoid drifting defaults. |
| Machine-image clone workflow | **YES** | Machine images are approved for persistent full-environment clones and milestone rollback points, but they do not replace the deterministic baseline rebuild flow. |
| Secret handling in clones | **YES** | Clone workflows must require scrub + re-auth or reinjection. Scripts and docs must avoid encouraging secrets in metadata, flags, or committed files. |

### Execution-Phase Constraints

- `scripts/openclaw-gcp/create-template.sh` must use explicit, reproducible inputs and record the resolved boot image choice.
- `scripts/openclaw-gcp/create-instance.sh` must expose region and zone overrides and must not bake secrets into metadata.
- `scripts/openclaw-gcp/create-machine-image.sh` and `scripts/openclaw-gcp/spawn-from-image.sh` must explicitly distinguish baseline rebuilds from persistent clones.
- The docs must include a pre-capture scrub checklist and a post-clone re-auth or credential injection step.

### Source Notes

- Google’s deterministic template guidance supports the pinned-input baseline model: https://cloud.google.com/compute/docs/instance-templates/deterministic-instance-templates
- Google’s machine image guidance supports using machine images for cloning and instance-level backup: https://docs.cloud.google.com/compute/docs/machine-images
- Google’s Secret Manager and service-account guidance supports post-provision or service-account-based secret access rather than cloned credentials:
  - https://docs.cloud.google.com/secret-manager/docs/best-practices
  - https://cloud.google.com/iam/docs/best-practices-for-managing-service-account-keys
