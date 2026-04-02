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

## 4) Keep destructive targeting separate from convenience state
- Source review bead: `br-3l2`
- Pattern: remembered Cloud Shell state is helpful for operator ergonomics, but destructive flows become unsafe when they treat that state as authoritative for stack or project targeting.
- Compounding move: define one explicit rule for destructive commands: live or explicit context wins, convenience state is interactive-only and never silently overrides non-interactive intent.
- Payoff: reduces cross-project teardown accidents and keeps D4-style safety decisions from regressing in future wrappers.

## 5) Prefer convergent teardown contracts over all-or-nothing qualification
- Source review bead: `br-3c6`
- Pattern: wrapper-level ownership checks can say "this is my stack" while deeper destroy helpers still assume every anchor is intact, which blocks cleanup after partial failures.
- Compounding move: design teardown flows to converge from verified partial states, with targeted break-glass paths only when ownership is ambiguous.
- Payoff: rerunning cleanup becomes reliable after interrupted deletes instead of producing stranded resources and manual cleanup dead ends.

## 6) Machine-readable commands need machine-readable failure shapes too
- Source review bead: `br-3ea`
- Pattern: a command can look automation-friendly on the happy path but still fall back to human text on common error paths.
- Compounding move: whenever a JSON mode is introduced, define the error envelope at the same time as the success shape and freeze both in tests.
- Payoff: avoids brittle stderr scraping and keeps automation contracts trustworthy as features grow.
