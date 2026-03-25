# Backup and Restore Runbook

This runbook provides the day-1 protection baseline for persistent OpenClaw instances.
It follows `D7`: persistent disks plus snapshot/backup steps, without building a full backup platform in phase one.

## Protection Layers

1. Recurring disk snapshots via a snapshot schedule resource policy.
2. Ad-hoc machine images before major changes (upgrade checkpoints and clone sources).

Use recurring snapshots for regular recovery points.
Use machine images as milestone-grade checkpoints before risky operations.

## Recurring Snapshot Schedule

Create a daily snapshot schedule policy:

```bash
bash scripts/openclaw-gcp/create-snapshot-policy.sh \
  --project-id hoangnb-openclaw \
  --policy-name oc-daily-snapshots \
  --region asia-southeast1 \
  --start-hour-utc 18 \
  --max-retention-days 14
```

Rerun behavior:

- Re-running `create-snapshot-policy.sh` reuses the existing policy when it is already present.
- You can safely rerun it later with `--target-disk` to attach that policy to additional disks.

Attach the policy to an existing disk:

```bash
bash scripts/openclaw-gcp/create-snapshot-policy.sh \
  --project-id hoangnb-openclaw \
  --policy-name oc-daily-snapshots \
  --region asia-southeast1 \
  --target-disk oc-main \
  --target-disk-zone asia-southeast1-a
```

Region override note:
When you change `--region`, the script derives a matching `-a` zone for disk attachment unless you explicitly pass `--zone` or `--target-disk-zone`.

UTC caveat:
Snapshot schedules are defined in UTC windows and begin within the selected hour, not at an exact minute.
Pick hours with this window behavior in mind.

## Ad-Hoc Machine Image Before Major Upgrades

Before major OpenClaw or OS upgrades, capture a machine image with the repo script:

```bash
bash scripts/openclaw-gcp/create-machine-image.sh \
  --project-id hoangnb-openclaw \
  --source-instance oc-main \
  --source-zone asia-southeast1-a \
  --image-name oc-main-pre-upgrade-$(date -u +%Y%m%d-%H%M) \
  --storage-location asia-southeast1
```

Use this checkpoint for rollback or to seed a persistent clone.

## Restore from Snapshot (Boot Disk Recovery)

1. Identify the snapshot to restore:

```bash
gcloud compute snapshots list \
  --project hoangnb-openclaw \
  --filter='name~oc-daily-snapshots'
```

2. Create a replacement disk from snapshot:

```bash
gcloud compute disks create oc-main-restored-boot \
  --project hoangnb-openclaw \
  --zone asia-southeast1-a \
  --source-snapshot SNAPSHOT_NAME \
  --type pd-balanced
```

3. Stop the instance and swap boot disk:

```bash
gcloud compute instances stop oc-main \
  --project hoangnb-openclaw \
  --zone asia-southeast1-a

gcloud compute instances detach-disk oc-main \
  --project hoangnb-openclaw \
  --zone asia-southeast1-a \
  --disk oc-main

gcloud compute instances attach-disk oc-main \
  --project hoangnb-openclaw \
  --zone asia-southeast1-a \
  --disk oc-main-restored-boot \
  --boot

gcloud compute instances start oc-main \
  --project hoangnb-openclaw \
  --zone asia-southeast1-a
```

## Restore by Spawning from Machine Image

For full-instance rollback or fast replacement, spawn from the machine image with the repo script:

```bash
bash scripts/openclaw-gcp/spawn-from-image.sh \
  --project-id hoangnb-openclaw \
  --instance-name oc-main-recovery \
  --machine-image oc-main-pre-upgrade-YYYYMMDD-HHMM \
  --zone asia-southeast1-a
```

After restore or recovery:

- Re-auth and inject runtime credentials explicitly.
- Validate OpenClaw service health and workspace mount state.
- Re-attach or confirm snapshot policy on the active boot disk.
- Run `openclaw-docker-setup` on the restored VM if you need to restage the local baseline.
- Use `openclaw status` and `curl -fsS http://127.0.0.1:18789/healthz` to confirm the gateway is healthy.
