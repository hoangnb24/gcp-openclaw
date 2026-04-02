# Spike Findings: br-lgy

## Question

Can the wrapper safely delegate to `scripts/openclaw-gcp/destroy.sh` while honoring interactive current-stack convenience, explicit non-interactive targeting, explicit project targeting, and fail-closed stack resolution?

## Result

YES

## Evidence

- `scripts/openclaw-gcp/destroy.sh` already requires typed confirmation for interactive destructive runs and refuses non-interactive destructive runs without `--yes`.
- The same script already fails closed when a real destructive run tries to rely on the ambient `gcloud` project instead of an explicit `--project-id`.
- The destroy script already accepts exact raw targets for instance, template, router, and NAT and performs its own qualification checks before deletion.
- The new wrapper design only needs to resolve a stack into those exact raw names and pass them explicitly into `destroy.sh`.

## Safe Wrapper Constraints

The wrapper delegation is safe if it obeys all of these rules:

- interactive usage may default to the remembered current stack
- non-interactive usage must require an explicit stack argument
- the wrapper must pass explicit `--project-id` into `destroy.sh`
- the wrapper must resolve stack identity before calling `destroy.sh`; if resolution is ambiguous, it must abort rather than guess
- the wrapper must preserve, not replace, `destroy.sh` confirmation and qualification behavior

## Consequence For The Plan

Story 3 remains valid as a thin wrapper over the existing destroy engine. The execution risk is in stack resolution, not in the underlying delete mechanics, so validating should push that fail-closed contract into the affected beads.
