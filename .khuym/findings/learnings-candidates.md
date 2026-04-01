# Learnings Candidates

## 1) Treat installer handoff as a two-channel success contract (remote success + transport status)
- Source beads: `br-20b`, `br-27e`
- Pattern: interactive SSH handoffs can return non-zero after a successful remote install due to terminal/session teardown behavior.
- Compounding move: standardize a success-marker contract (for example, remote success sentinel or explicit final marker) and test a full matrix: create/new, reuse, remote fail, transport-only fail, and post-success disconnect.
- Payoff: prevents false failure reporting and keeps installer UX consistent across shells and `gcloud` SSH edge cases.

## 2) Centralize startup-contract metadata as a shared schema across create/install/repair
- Source beads: `br-2jn`, `br-27e`
- Pattern: startup metadata keys/values (`startup_profile`, `startup_contract_version`, sentinel, log paths) are spread across scripts, which risks drift during migrations and repairs.
- Compounding move: define one contract source (constants + validation helper) consumed by template creation, install preflight/readiness, and repair flows; require schema parity tests when fields change.
- Payoff: lowers migration regressions and makes reuse-repair behavior predictable.

## 3) Make sensitive log/transcript retention explicitly opt-in, with strict path/permission policy
- Source beads: `br-2jj`, `br-1dp`, `br-3kd`
- Pattern: onboarding transcripts and bootstrap logs can contain sensitive data; permissive defaults and loose matching logic create security footguns.
- Compounding move: default to minimal/no persistent transcript capture, gate persistence behind explicit debug flags, enforce private perms (`0700` dir, `0600` files), and use exact-token parsers for security-critical checks (for example exact CIDR membership, not substring matching).
- Payoff: reduces accidental data exposure while preserving debuggability when intentionally enabled.
