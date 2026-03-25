# Backup And Restore Runbook

This repository uses two complementary protection layers for persistent OpenClaw instances on GCP:

1. recurring disk snapshots through a resource policy
2. ad-hoc machine images for rollback points and persistent clone sources

Use recurring snapshots for routine recovery points.
Use machine images before upgrades, risky maintenance, or when you want a long-lived full-environment clone source.

## Snapshot Schedule

Create the standard daily policy:

```bash
bash scripts/openclaw-gcp/create-snapshot-policy.sh \
  --project-id hoangnb-openclaw \
  --policy-name oc-daily-snapshots \
  --region asia-southeast1 \
  --start-hour-utc 18 \
  --max-retention-days 14
```

Attach the policy to a disk in the same run or later:

```bash
bash scripts/openclaw-gcp/create-snapshot-policy.sh \
  --project-id hoangnb-openclaw \
  --policy-name oc-daily-snapshots \
  --region asia-southeast1 \
  --target-disk oc-main \
  --target-disk-zone asia-southeast1-a
```

Supported snapshot policy options:

- `--policy-name`
- `--region`
- `--zone`
- `--start-hour-utc`
- `--max-retention-days`
- `--on-source-disk-delete`
- `--target-disk`
- `--target-disk-zone`
- `--dry-run`

Operational notes:

- valid `--on-source-disk-delete` values are `KEEP_AUTO_SNAPSHOTS` and `APPLY_RETENTION_POLICY`
- policy creation uses create-if-missing semantics
- reruns reuse an existing policy cleanly
- when `--region` changes and `--zone` is not passed, the script derives `<region>-a`
- `--target-disk-zone` defaults to the effective `--zone` value
- schedule windows are defined in UTC and begin within the selected hour, not at an exact minute

Example with retention-policy cleanup on source-disk deletion:

```bash
bash scripts/openclaw-gcp/create-snapshot-policy.sh \
  --project-id hoangnb-openclaw \
  --policy-name oc-daily-snapshots \
  --region asia-southeast1 \
  --start-hour-utc 18 \
  --max-retention-days 14 \
  --on-source-disk-delete APPLY_RETENTION_POLICY
```

## Machine Images

Create a machine image from a known-good VM:

```bash
bash scripts/openclaw-gcp/create-machine-image.sh \
  --project-id hoangnb-openclaw \
  --source-instance oc-main \
  --source-zone asia-southeast1-a \
  --image-name oc-main-pre-upgrade-$(date -u +%Y%m%d-%H%M) \
  --storage-location asia-southeast1
```

Supported machine-image options:

- `--source-instance`
- `--source-zone`
- `--image-name`
- `--image-family`
- `--description`
- `--storage-location`
- `--dry-run`

Operational notes:

- `--image-name` defaults to `oc-image-<utc-timestamp>`
- `--image-family` stores an `openclaw-family=<value>` label for grouping
- capture the image only after sensitive runtime credentials have been scrubbed or rotated

Example with an image-family label and description:

```bash
bash scripts/openclaw-gcp/create-machine-image.sh \
  --project-id hoangnb-openclaw \
  --source-instance oc-main \
  --source-zone asia-southeast1-a \
  --image-family stable \
  --description "Rollback point before OpenClaw upgrade"
```

## Clone Creation

Create a persistent clone from a machine image:

```bash
bash scripts/openclaw-gcp/spawn-from-image.sh \
  --project-id hoangnb-openclaw \
  --instance-name oc-main-recovery \
  --machine-image oc-main-pre-upgrade-YYYYMMDD-HHMM \
  --zone asia-southeast1-a
```

Supported clone options:

- `--machine-image`
- `--zone`
- `--machine-type`
- `--subnet`
- `--service-account`
- `--scopes`
- `--dry-run`

Example with explicit placement and identity:

```bash
bash scripts/openclaw-gcp/spawn-from-image.sh \
  --project-id hoangnb-openclaw \
  --instance-name oc-clone-a \
  --machine-image oc-image-20260324-001 \
  --zone us-central1-a \
  --machine-type e2-standard-4 \
  --subnet default \
  --service-account my-vm@hoangnb-openclaw.iam.gserviceaccount.com \
  --scopes https://www.googleapis.com/auth/cloud-platform
```

Security notes:

- do not assume provider credentials inherited from a machine image are appropriate for the new instance
- re-auth or reinject credentials intentionally after clone creation

## Restore From Snapshot

### Boot disk recovery

1. Identify the snapshot to restore:

```bash
gcloud compute snapshots list \
  --project hoangnb-openclaw \
  --filter='name~oc-daily-snapshots'
```

2. Create a replacement disk from that snapshot:

```bash
gcloud compute disks create oc-main-restored-boot \
  --project hoangnb-openclaw \
  --zone asia-southeast1-a \
  --source-snapshot SNAPSHOT_NAME \
  --type pd-balanced
```

3. Stop the instance and swap the boot disk:

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

## Restore From Machine Image

For full-instance rollback or fast replacement, create a fresh instance from the stored machine image:

```bash
bash scripts/openclaw-gcp/spawn-from-image.sh \
  --project-id hoangnb-openclaw \
  --instance-name oc-main-recovery \
  --machine-image oc-main-pre-upgrade-YYYYMMDD-HHMM \
  --zone asia-southeast1-a
```

## Post-Restore Checklist

- re-auth providers intentionally
- reinject runtime credentials intentionally
- validate `openclaw status`
- validate `curl -fsS http://127.0.0.1:18789/healthz`
- reattach or confirm the snapshot policy on the active boot disk
- rerun `openclaw-docker-setup` if the restored VM needs the host baseline refreshed
