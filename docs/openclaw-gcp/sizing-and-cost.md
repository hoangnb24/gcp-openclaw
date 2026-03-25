# Sizing and Cost Baselines

This note records approved sizing and cost baselines for OpenClaw on GCP.
Values are taken from planning artifacts dated 2026-03-24 and should be refreshed when price models or regions change.

References:

- [history/openclaw-gcp-instance-strategy/discovery.md](../../history/openclaw-gcp-instance-strategy/discovery.md)
- [history/openclaw-gcp-instance-strategy/approach.md](../../history/openclaw-gcp-instance-strategy/approach.md)

## Compute Baseline (730h Month Approximation)

| Machine type | vCPU / RAM | Hourly (USD) | Approx monthly (USD) | Recommended use |
|---|---:|---:|---:|---|
| `e2-small` | 2 / 2 GiB | 0.016752855 | 12.23 | Minimum-only fallback |
| `e2-medium` | 2 / 4 GiB | 0.03350571 | 24.46 | Light workload or temporary cost pressure |
| `e2-standard-2` | 2 / 8 GiB | 0.06701142 | 48.92 | Default for always-on medium workload |
| `e2-standard-4` | 4 / 16 GiB | 0.13402284 | 97.84 | Scale-up path for sustained pressure |

## Storage and Snapshot Baseline

| Resource | Baseline price | Approx monthly interpretation |
|---|---:|---|
| `pd-balanced` | 0.000136986 USD / GiB hour | ~0.10 USD / GiB month |
| Standard snapshots | 0.000068493 USD / GiB hour | ~0.05 USD / GiB month |

Practical default examples:

- `30 GiB` `pd-balanced` boot disk is about 3 USD per month before regional variance.
- A fully unique `30 GiB` standard snapshot footprint is about 1.50 USD per month; incremental snapshots are usually lower.

## Recommended Default and Override Rules

- Primary default profile:
  - `e2-standard-2`
  - `pd-balanced`
  - `30 GiB`
  - `asia-southeast1`
- Primary zone within that region: `asia-southeast1-a`
- Price-first region fallback: `us-central1`.
- Default disk stays `30 GiB`; escalate to `50 GiB` when workspace retention and cache growth increase.
- `e2-micro` is not suitable for this workload.
- `e2-small` is minimum-only for this workload.
- Internal-only networking with Cloud NAT and IAP remains the recommended posture for the default profile.

## Escalation Path

Escalate machine size and disk together when any of the following persists:

- repeated memory pressure or container restarts
- long-running tasks slow the active OpenClaw session
- workspace retention pressure increases backup and restore windows

Recommended escalation sequence:

1. Increase disk from `30 GiB` to `50 GiB`.
2. Move from `e2-standard-2` to `e2-standard-4` if compute pressure remains.
3. Re-check backup/snapshot policy after each size step.

## Implementation Notes for Follow-On Beads

- Scripts must expose region and zone overrides at runtime.
- Scripts should preserve the internal-only template path and automatic Cloud NAT handling.
- Scripts must not write secrets to metadata, command flags, or committed files.
- Clone workflows require scrub and re-auth or secret reinjection after spawn.
