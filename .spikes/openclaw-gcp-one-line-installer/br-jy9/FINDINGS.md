# Spike Findings: Minimum Replacement Test Surface

## Question
What minimum contract tests replace the Docker/bootstrap assertions?

## Result
YES.

## Findings
- The old suite’s main over-coupling is the startup-script content block that asserts Docker/OpenClaw bootstrap lines directly.
- The new minimum mocked contract surface should cover:
  - minimal startup metadata contract
  - preflight failure and recovery guidance
  - prompt vs non-prompt behavior
  - reuse-eligible existing instance path
  - readiness wait and refusal of legacy or incompatible instances
  - interactive SSH handoff command construction
  - success continuity in the remote shell
  - upstream failure summary plus remote log retrieval hint
- Core infra guardrails around templates, NAT, and regional behavior should remain covered.

## Evidence
- `tests/openclaw-gcp/test.sh`

## Decision
The plan is viable if `br-30x` swaps the Docker/bootstrap-specific assertions for installer-flow contract tests instead of weakening overall coverage.
