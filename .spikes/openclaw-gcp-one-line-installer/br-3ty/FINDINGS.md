# Spike Findings: Legacy Template And Instance Compatibility

## Question
How should legacy templates and reused instances be detected and handled safely?

## Result
YES.

## Findings
- The existing code already has the right contract anchor: `startup_script_source` metadata is written by `create-template.sh` and refreshed by `repair-instance-bootstrap.sh`.
- The new one-line flow should keep that pattern and introduce a new startup profile value such as `embedded-vm-prereqs-v1`.
- Reuse policy:
  - Reuse is allowed only when `startup_script_source` matches the new minimal profile.
  - Missing or mismatched `startup_script_source` should be treated as legacy.
  - Legacy templates should be recreated, not silently reused.
  - Legacy instances may be repaired only if metadata can be refreshed and the startup script can be rerun safely; otherwise the installer should refuse reuse with exact guidance.
- Current drift refusal for explicit template-shaping flags during template reuse is already strong and should remain intact.

## Evidence
- `scripts/openclaw-gcp/create-template.sh`
- `scripts/openclaw-gcp/repair-instance-bootstrap.sh`
- `tests/openclaw-gcp/test.sh`

## Decision
The plan is viable if `br-6w1` keeps `startup_script_source` as the authoritative compatibility key and makes legacy detection/refuse-or-repair behavior explicit.
