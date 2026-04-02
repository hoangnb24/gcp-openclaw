# Spike Findings: br-1ho

## Question

Can Phase 2 destroy verify snapshot-policy attachment and detach it safely without broad discovery?

## Answer

YES.

The safe contract is:
- allow explicit snapshot-policy cleanup only by exact policy name
- if the operator also supplies an explicit disk and disk zone, verify attachment on that exact disk before detaching
- perform snapshot-policy cleanup before any instance deletion that could remove that disk
- if no disk context is supplied, allow a delete-only best-effort policy path and let the final summary report any failure

## Verified Command Surfaces

### Disk attachment verification

Use the named disk only:

```bash
gcloud compute disks describe "$SNAPSHOT_POLICY_DISK" \
  --project "$PROJECT_ID" \
  --zone "$SNAPSHOT_POLICY_DISK_ZONE" \
  --flatten='resourcePolicies[]' \
  --format='value(resourcePolicies.basename())'
```

Why this shape:
- `gcloud compute disks describe` is the correct exact-name disk inspection entrypoint
- `resourcePolicies[]` is the relevant attachment surface on disk resources
- `basename()` matches the repo's existing pattern for comparing self-link-backed resource fields by name

### Explicit detach command

```bash
gcloud compute disks remove-resource-policies "$SNAPSHOT_POLICY_DISK" \
  --project "$PROJECT_ID" \
  --zone "$SNAPSHOT_POLICY_DISK_ZONE" \
  --resource-policies "$SNAPSHOT_POLICY_NAME"
```

This is directly supported by local `gcloud` help for `compute disks remove-resource-policies`.

### Explicit delete command

```bash
gcloud compute resource-policies delete "$SNAPSHOT_POLICY_NAME" \
  --project "$PROJECT_ID" \
  --region "$REGION" \
  --quiet
```

## Fail-Closed Rule

When disk context is provided:
- if the disk describe command fails: fail before any snapshot-policy detach/delete command
- if the describe output is empty: fail before any snapshot-policy detach/delete command
- if the named policy is not present in the returned attachment rows: fail before any snapshot-policy detach/delete command
- if the output is malformed or ambiguous enough that policy names cannot be parsed reliably: fail before any snapshot-policy detach/delete command

Multiple attached policies are not a blocker by themselves. The rule is whether the exact named policy is present on the exact named disk.

## Policy-Only Behavior

If the operator supplies `--snapshot-policy-name` without disk context:
- do not discover disks automatically
- do not attempt a detach step
- allow a delete-only best-effort policy cleanup path
- if the delete fails, report that failure in the shared final summary with manual guidance to detach the policy from its disk explicitly and retry

This keeps the flow exact-name only and avoids unsafe inference.

## Critical Ordering Constraint

Snapshot-policy cleanup must run before any instance deletion that could remove the named disk.

Practical reason:
- the default snapshot-policy workflow in this repo attaches the policy to the standard boot disk
- Phase 1 core teardown deletes the instance first
- that instance deletion can remove the boot disk before the policy can be verified or detached

So the deterministic Phase 2 order must place snapshot-policy detach/delete ahead of the core instance delete whenever snapshot-policy cleanup is requested.

## Implementation Impact

- `br-3p3` should use the exact describe + detach surfaces above
- `br-3p3` should treat disk context as the safe path for verified detach behavior
- `br-3p3` should preserve a policy-only best-effort delete path when disk context is omitted
- `br-89e` should assert that snapshot-policy cleanup happens before core instance deletion in mixed runs
