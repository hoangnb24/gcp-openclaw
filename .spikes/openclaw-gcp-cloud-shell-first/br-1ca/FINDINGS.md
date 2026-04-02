# Spike Findings: br-1ca

## Question

Can the wrapper safely expose first-class `ssh` and named `logs` commands by reusing the existing stack-resolution and anchor-verification model, while staying honest about which remote log sources are truly supported?

## Result

YES

## Evidence

- `bin/openclaw-gcp` already has the right stack-selection shape for non-destructive day-2 commands: `resolve_stack_id_for_status` supports explicit stack selection, remembered current-stack reuse, exact-one recovery from labeled instance/template anchors, and fail-closed behavior on ambiguity or partial anchor disagreement.
- `bin/openclaw-gcp` already has reusable label-backed inspection helpers: `resource_label_tuple`, `inspect_anchor`, and `verify_stack_anchors_or_die` prove the wrapper can interrogate the labeled instance/template anchors before continuing.
- `scripts/openclaw-gcp/install.sh` already defines the repo's IAP-backed SSH posture and two concrete remote install-era log seams:
  - readiness log: `$HOME/.openclaw-gcp/install-logs/readiness-gate.log`
  - installer transcript symlink: `$HOME/.openclaw-gcp/install-logs/latest.log`
- `scripts/openclaw-gcp/bootstrap-openclaw.sh` already defines two concrete runtime-era log seams:
  - bootstrap log: `/var/log/openclaw/bootstrap.log`
  - gateway container logs: `docker logs --tail 100 openclaw_openclaw-gateway_1`
- The current mocked shell harness already covers stack-anchor verification and IAP SSH behavior for `status`, `down`, and `install.sh`, so Phase 3 can extend existing test patterns rather than inventing a new verification lane.

## Required Tightening

The current teardown helper is not the exact live-access gate by itself.

- `verify_stack_anchors_or_die` is safe for teardown because it fails on any label mismatch and requires at least one verified anchor, but `ssh`/`logs` need a stricter live-access rule: a verified **instance** anchor must be present before opening a shell or running a remote log command.
- Template verification should remain part of the safety model, but only as a consistency check:
  - if the template exists and its labels mismatch, fail closed
  - if the template is absent, allow `ssh`/`logs` to continue against the verified live instance because day-2 inspection of a running VM is still legitimate
- Phase 3 should not introduce any fallback access path such as serial console, SCP-based scraping, or non-IAP SSH. The remote-access contract stays `gcloud compute ssh ... --tunnel-through-iap`.

## Exact Safety Gate For `ssh` And `logs`

1. Resolve the stack with the same selection model already used by `status`:
   - explicit `--stack-id`, or
   - remembered current stack, or
   - exact-one recovered candidate from labeled instance/template anchors
2. Require explicit or recovered project context before remote access.
3. Require a verified labeled **instance** anchor for the resolved stack.
4. If the template exists, require it to carry matching OpenClaw labels; if it mismatches, stop.
5. Use only IAP-backed `gcloud compute ssh` for the remote command path.

## Exact Named Log-Source Set

Phase 3 should expose only these named sources:

- `readiness` -> `tail -n <N> "$HOME/.openclaw-gcp/install-logs/readiness-gate.log"`
- `install` -> `tail -n <N> "$HOME/.openclaw-gcp/install-logs/latest.log"`
- `bootstrap` -> `tail -n <N> /var/log/openclaw/bootstrap.log`
- `gateway` -> `docker logs --tail <N> openclaw_openclaw-gateway_1`

No broader "browse arbitrary files" or "run arbitrary docker logs" surface is justified by current repo contracts.

## Fail-Closed Rules

- Unsupported `--source` values must fail with the supported-source list.
- Missing project context or stack ambiguity must fail before any SSH attempt.
- Missing or mismatched instance anchor must fail before any SSH attempt.
- Missing log files, missing Docker, or missing gateway container should produce a clear "source unavailable" failure instead of guessing at alternates.

## Consequence For The Plan

Phase 3 remains valid if execution agents implement `ssh` and `logs` as thin wrapper commands over the existing stack-resolution plus IAP SSH posture, while freezing the supported log-source set to `readiness`, `install`, `bootstrap`, and `gateway`. The beads should explicitly carry the tighter live-access gate above so executors do not accidentally reuse the broader teardown helper unchanged.
