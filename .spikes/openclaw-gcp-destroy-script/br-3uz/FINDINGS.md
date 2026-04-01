# Spike Findings: br-3uz

## Question

Can the destroy flow reliably inspect and enforce this rule before deletion in both GCP and the shell test harness: the instance qualifies only when it has exactly one attached disk and that disk reports `boot=true` and `autoDelete=true`?

## Verdict

YES

## Why

The Compute Engine instance surface exposes `disks[].boot` and `disks[].autoDelete`, which is enough to enforce the Phase 1 disk-safety predicate deterministically before any delete command runs. The existing shell harness already mocks `gcloud compute instances describe` branches, so it can extend that pattern to emit disk rows for pass/fail fixtures.

## Validated Inspection Surface

```bash
gcloud compute instances describe "$INSTANCE_NAME" \
  --project "$PROJECT_ID" \
  --zone "$ZONE" \
  --flatten='disks[]' \
  --format='value(disks.boot,disks.autoDelete)'
```

Qualification rule:

- proceed only if the command returns exactly one row
- normalize case and require that row to equal `true<TAB>true`
- fail closed on zero rows, multiple rows, missing fields, or any non-true value

## Destroy Implication

- The Phase 1 qualification gate can enforce the disk rule before deletion.
- The core teardown path should not pass `--delete-disks` or `--keep-disks`, because those flags override the default auto-delete behavior that the qualification step is validating.

## Constraints Added

- `br-1gf` must implement the exact predicate `count==1 && boot==true && autoDelete==true`.
- `br-k26` must add mock fixtures for pass, extra-disk failure, and `autoDelete=false` failure, and assert that qualification failures emit no delete commands.

## Sources

- https://cloud.google.com/compute/docs/reference/rest/v1/instances
- https://cloud.google.com/compute/docs/instances/deleting-instance
- https://cloud.google.com/compute/docs/disks/view-disk-details
