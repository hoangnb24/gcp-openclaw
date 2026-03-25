# Sizing And Cost Baselines

This note captures the operating baseline for OpenClaw on GCP and the size-up rules that match the repository defaults.

Reference materials:

- [discovery.md](../../history/openclaw-gcp-instance-strategy/discovery.md)
- [approach.md](../../history/openclaw-gcp-instance-strategy/approach.md)

## Default Deployment Profile

- Region: `asia-southeast1`
- Zone: `asia-southeast1-a`
- Machine type: `e2-standard-2`
- Boot disk: `pd-balanced`
- Boot disk size: `30 GiB`
- Networking posture: internal-only VM with Cloud NAT for egress and IAP for operator access

The repository scripts expose these defaults directly through:

- `create-template.sh`
- `create-instance.sh`
- `create-cloud-nat.sh`
- `create-snapshot-policy.sh`

## Compute Baseline

The table below uses a 730-hour month approximation.

| Machine type | vCPU / RAM | Hourly (USD) | Approx monthly (USD) | Recommended use |
|---|---:|---:|---:|---|
| `e2-small` | 2 / 2 GiB | 0.016752855 | 12.23 | Minimum-only fallback |
| `e2-medium` | 2 / 4 GiB | 0.03350571 | 24.46 | Light workload or temporary cost pressure |
| `e2-standard-2` | 2 / 8 GiB | 0.06701142 | 48.92 | Default always-on profile |
| `e2-standard-4` | 4 / 16 GiB | 0.13402284 | 97.84 | Scale-up path for sustained pressure |

Sizing guidance:

- `e2-micro` is not suitable for this workload
- `e2-small` is a minimum-only fallback
- `e2-medium` works for lighter usage or temporary cost pressure
- `e2-standard-2` is the default
- `e2-standard-4` is the first scale-up step when CPU or memory pressure persists

## Storage And Snapshot Baseline

| Resource | Baseline price | Approx monthly interpretation |
|---|---:|---|
| `pd-balanced` | 0.000136986 USD / GiB hour | ~0.10 USD / GiB month |
| Standard snapshots | 0.000068493 USD / GiB hour | ~0.05 USD / GiB month |

Practical examples:

- a `30 GiB` `pd-balanced` boot disk is about 3 USD per month before regional variance
- a fully unique `30 GiB` standard snapshot footprint is about 1.50 USD per month
- incremental snapshot storage is usually lower than the fully unique footprint

## Recommended Overrides

Use these runtime overrides when the default profile is not the right fit:

- `create-template.sh --machine-type <type>`
- `create-template.sh --disk-size-gb <size>`
- `create-instance.sh --machine-type <type>`
- `create-instance.sh --disk-size-gb <size>`
- `create-instance.sh --region <region> --zone <zone>`
- `create-snapshot-policy.sh --region <region> --zone <zone>`

Preferred override rules:

- keep `30 GiB` as the baseline disk size
- move to `50 GiB` when workspace retention and cache growth make free space tight
- keep `asia-southeast1` as the default region unless price or latency requirements point elsewhere
- `us-central1` is the price-first regional fallback

## Escalation Path

Scale the deployment when any of the following persists:

- repeated memory pressure or container restarts
- active OpenClaw sessions slow noticeably under normal use
- workspace growth increases snapshot or restore windows

Escalation order:

1. increase disk from `30 GiB` to `50 GiB`
2. move from `e2-standard-2` to `e2-standard-4` if compute pressure remains
3. recheck the snapshot policy and retention window after each size change

## Networking Cost And Posture Notes

- the recommended posture keeps the VM internal-only with `--no-address`
- Cloud NAT handles outbound package downloads and image pulls
- IAP handles operator SSH access
- this keeps the baseline aligned with org policies that restrict external IPv4 addresses

## Implementation Notes

- template creation resolves Debian image families to concrete images and records the result in the resolution record
- instance creation preserves the internal-only path and auto-ensures Cloud NAT when required
- backup workflows assume persistent disks plus scheduled snapshots
- clone workflows assume post-clone credential reinjection or re-auth
