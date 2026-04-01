# Spike Findings: br-3ap

## Question

Can the wrapper safely rediscover one Phase 1 stack from labeled instance/template anchors inside one known project context, auto-repair local state only when exactly one candidate exists, and still fail closed when anchors disagree or multiple stacks are present?

## Result

YES

## Repo + CLI Evidence

1. Current gap is real and scoped to missing/stale local state recovery.
   - Command run:
     - `HOME="$(mktemp -d)" bash bin/openclaw-gcp status --project-id hoangnb-openclaw`
   - Output:
     - `Error: no stack ID provided and no CURRENT_STACK_ID found ...`
   - This confirms the phase need: `status` currently exits before any recovery path when local pointer is absent.

2. Label anchors already exist as durable truth primitives and are actively verified in wrapper flows.
   - `scripts/openclaw-gcp/lib-stack.sh` defines canonical stack label keys and local convenience-state helpers.
   - `bin/openclaw-gcp` already verifies anchor labels via:
     - `gcloud compute instances describe ... --format=value(labels.openclaw_managed,labels.openclaw_stack_id,labels.openclaw_tool,labels.openclaw_lifecycle)`
     - `gcloud compute instance-templates describe ... --format=value(labels.openclaw_managed,labels.openclaw_stack_id,labels.openclaw_tool,labels.openclaw_lifecycle)`
   - Existing behavior is already fail-closed on label mismatch (`verify_stack_anchors_or_die`).

3. Safety posture is proven by current tests and can be extended to recovery without changing destructive boundaries.
   - Verification run: `bash tests/openclaw-gcp/test.sh` (PASS 28 test groups)
   - Relevant passing assertions include:
     - wrapper status verifies instance/template labels against stack ID
     - wrapper down checks instance/template labels before teardown
     - wrapper down fails closed when a labeled anchor mismatches
     - wrapper down preserves explicit/non-interactive strictness

4. Exact-one candidate contract is implementable and deterministic.
   - Prototype reconciliation run (project-scoped anchor IDs):
     - `RESULT=YES_EXACT_ONE candidate=team-dev`
     - `RESULT=NO_AMBIGUOUS candidates=team-dev team-prod`
     - `RESULT=NO_ANCHOR_DISAGREEMENT ...`
     - `RESULT=NO_NO_CANDIDATE`
   - This demonstrates that exact-one auto-repair and fail-closed ambiguity/disagreement are both mechanically straightforward.

## Recovery Contract (for implementation bead `br-33v`)

1. Scope all recovery discovery to one known project context (`--project-id` / remembered project / active gcloud project).
2. Build candidate stack IDs from label-anchored instance/template discovery only (`openclaw_managed=true`, `openclaw_tool=openclaw-gcp`, `openclaw_stack_id` present).
3. Reconcile candidates conservatively:
   - one candidate => recoverable
   - zero candidates => no recovery
   - multiple candidates => ambiguous (must require explicit `--stack-id`)
   - anchor disagreement/partial mismatch => fail closed (no auto-repair)
4. Auto-repair `CURRENT_STACK_ID` only in the exact-one recoverable case.
5. Keep `down` behavior unchanged in strictness: no multi-stack guessing in destructive flows.

## Consequence For Phase 2

Story 1 implementation (`br-33v`) is unblocked: recovery-aware `status` can be added safely by extending existing label-anchor patterns and preserving the current fail-closed destroy boundary.
