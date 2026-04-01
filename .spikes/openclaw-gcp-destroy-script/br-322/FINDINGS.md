# Spike Findings: br-322

## Question

What exact contract should Phase 2 use for machine-image and clone cleanup?

## Answer

YES.

Phase 2 can support both resource types safely with this contract:
- machine-image cleanup is exact-name only, with an explicit existence check by image name
- no additional ownership marker is required for machine images in Phase 2
- clone cleanup is exact-name plus explicit zone, and it reuses the Phase 1 one-disk `boot=true` + `autoDelete=true` guard before deletion

## Verified Command Surfaces

### Machine-image describe

```bash
gcloud compute machine-images describe "$MACHINE_IMAGE_NAME" \
  --project "$PROJECT_ID" \
  --format='value(name)'
```

### Machine-image delete

```bash
gcloud compute machine-images delete "$MACHINE_IMAGE_NAME" \
  --project "$PROJECT_ID" \
  --quiet
```

Local `gcloud` help confirms both exact-name entrypoints.

### Clone-instance qualification

Reuse the existing instance disk gate with clone-specific inputs:

```bash
gcloud compute instances describe "$CLONE_INSTANCE_NAME" \
  --project "$PROJECT_ID" \
  --zone "$CLONE_ZONE" \
  --flatten='disks[]' \
  --format='value(disks.boot,disks.autoDelete)'
```

### Clone delete

```bash
gcloud compute instances delete "$CLONE_INSTANCE_NAME" \
  --project "$PROJECT_ID" \
  --zone "$CLONE_ZONE" \
  --quiet
```

## Ownership And Safety Conclusions

### Machine images

No stronger ownership marker is available or trustworthy enough to require here:
- `create-machine-image.sh` only guarantees exact image naming
- labels like `openclaw-family=...` are optional
- descriptions are operator-editable and not a reliable ownership contract

So the safest Phase 2 rule is:
- exact-name only
- fail closed if describe returns empty or errors
- do not attempt family-based, label-based, or prefix-based discovery

### Clone instances

The safest Phase 2 rule is to reuse the Phase 1 one-disk guard:
- require exactly one attached disk row
- require `boot=true`
- require `autoDelete=true`
- fail before clone deletion on empty, malformed, multi-disk, or predicate-mismatch output

Why this is sufficient for Phase 2:
- the repo's clone story is based on the standard OpenClaw VM shape, which is still a one-disk instance
- this rule intentionally rejects richer or custom clone shapes instead of guessing whether they are safe to remove
- if future clone workflows intentionally support multi-disk instances, that should be a later phase with a new validated contract

## Explicit Input Rule

Clone cleanup must require:
- `--clone-instance-name`
- optional `--clone-zone`

If `--clone-zone` is omitted, it may safely default to the main `--zone`.

If the clone lives in a different zone than the main instance, the operator must pass `--clone-zone` explicitly. The destroy flow must not search zones automatically.

## Fail-Closed Rule

### Machine images

- describe failure -> fail before machine-image delete
- empty describe output -> fail before machine-image delete

### Clone instances

- describe failure -> fail before clone delete
- empty describe output -> fail before clone delete
- malformed disk output -> fail before clone delete
- more than one disk row -> fail before clone delete
- any sole-disk predicate mismatch -> fail before clone delete

## Implementation Impact

- `br-32o` should add exact-name machine-image describe/delete with no extra ownership inference
- `br-32o` should add clone cleanup using the explicit zone plus reused one-disk gate
- `br-89e` should include clone safety mismatch fixtures and mixed-resource success/failure runs that include machine images
