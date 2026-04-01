# Spike Findings: Rerun And Failure Observability

## Question
What rerun and failure-observability contract is safe after infra succeeds?

## Result
YES.

## Findings
- The wrapper must own a stable remote log location because the upstream installer uses temporary logs that are cleaned up on exit.
- Recommended remote log contract:
  - directory: `$HOME/.openclaw-gcp/install-logs/`
  - per-run log: `install-<UTC timestamp>.log`
  - stable pointer: `latest.log`
- On installer failure, the local summary should print:
  - instance name
  - zone
  - remote log path
  - exact rerun command
  - exact log retrieval command
- Rerun semantics:
  - reuse the existing VM
  - skip provisioning if the target already exists and is eligible
  - rerun only the readiness and SSH/install stages

## Evidence
- Current repo decision D3 requires reuse on rerun.
- Current repo decision D11 requires returning locally with guidance on failure.
- Current upstream installer cleans up temp files on exit.

## Decision
The plan is viable if `br-34k` defines the stable remote log contract and `br-le9` prints that contract in the local failure summary.
