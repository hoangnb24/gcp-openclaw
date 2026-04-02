# Spike Findings: br-3ap

## Question

Can the Phase 2 wrapper safely rediscover one Phase 1 stack from the labeled instance/template anchors in a known project, auto-repair local `current-stack` state only when exactly one candidate exists, and otherwise fail closed when anchors disagree or multiple labeled stacks appear?

## Result

YES

## Evidence

- `bin/openclaw-gcp` already treats the OpenClaw labels as the durable truth: `resource_label_tuple` + `inspect_anchor` pull `labels.openclaw_managed`, `labels.openclaw_stack_id`, `labels.openclaw_tool`, and `labels.openclaw_lifecycle` for both the instance and the template before any `status` or `down` decision is made, so the new recovery path will build on the same checks.
- The existing `verify_stack_anchors_or_die` + `down` flow already refuses to continue unless at least one anchor exists with matching labels in the current project, proving both the labels and project-scoped context are reliable enough to drive safety decisions.
- `gcloud compute instances list` and `gcloud compute instance-templates list` both support filtering on label keys (e.g., `--filter="labels.openclaw_managed=true AND labels.openclaw_tool=openclaw-gcp"`), and the CLI already exposes the label values in `describe` calls, so we can list all candidates inside the known project/region context.
- A recovered stack identity can be derived from `labels.openclaw_stack_id` the same way the existing helpers derive it for new stacks (`oc_stack_require_id`, `oc_stack_instance_name`, `oc_stack_template_name`), so we do not need to invent a new naming contract.
- Project context resolution already reads `LAST_PROJECT_ID`, explicit `--project-id`, or `gcloud config get-value project`, so the Phase 2 recovery path can reuse those helpers to limit label discovery to the correct project.
- Tests mock gcloud and verify outputs for label interrogations; we can extend them to assert that the new `gcloud compute instances list` and `instance-templates list` commands are invoked with the right filters and that the logic honors the “exactly one candidate” rule before it repairs `CURRENT_STACK_ID`.

## Candidate Reconciliation Plan

1. Use the resolved project/region/zone context to run `gcloud compute instances list` with `--filter="labels.openclaw_managed=true labels.openclaw_tool=openclaw-gcp"` and `--format=value(name,zone,labels.openclaw_stack_id)` so we have the running instance anchors plus stack IDs.
2. Similarly list templates (`--filter` + `--format=value(name,region,labels...)`) to confirm matching stack IDs exist for each template anchor.
3. Build candidate objects keyed by `labels.openclaw_stack_id` and cross-check that at most one stack appears in both the instance and template sets (matching `openclaw_stack_id` values and label metadata).
4. When exactly one candidate survives, treat that stack ID as the recovered `STATUS` target and run the existing label/anchor inspection + deterministic router/NAT helpers to verify the rest of the stack contract before returning success.
5. When zero or multiple candidates remain, keep the current `status` behavior of failing with a clear explanation that no unique stack could be recovered and require the operator to pass `--stack-id` explicitly rather than auto-repairing.

## Auto-Repair Constraints

- Only write the local convenience state (`oc_stack_state_write_current`) when the recovery flow has exactly one trustworthy stack candidate covering both instance and template anchors.
- Do not mutate `CURRENT_STACK_ID` when `status` receives explicit `--stack-id`; recovery should only activate when the explicit stack ID is missing and the label discovery finds one candidate.
- Router/NAT names remain deterministic helpers derived from the recovered stack ID, not independently label-discovered resources, so later `down` continues to rely on the existing deterministic naming logic.

## Consequence for Implementation

With the above anchor discovery and exact-one-candidate guard, Story 1 has a safe Phase 2 path: `status` can recover a stack from labels when the local pointer is missing or stale, auto-repair state only when it is unambiguous, and otherwise fall back to the current fail-closed behavior. Story 2 keeps verifying the remaining companion resources, and Story 3 can document the ambiguous failure cases without introducing new destructive guessing.
