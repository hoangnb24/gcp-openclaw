# Spike Findings: Minimal Startup Contract And Readiness Signal

## Question
What minimal startup contract and readiness signal avoid first-boot package races?

## Result
YES.

## Findings
- The startup script should do only generic host preparation needed before SSH handoff, for example:
  - package index refresh if required
  - install `curl` and `ca-certificates`
  - ensure any helper needed for transcript capture is present if not already available
- The startup script should not install Docker, clone OpenClaw, or run onboarding.
- A machine-readable completion marker is required. Recommended sentinel:
  - `/var/lib/openclaw/startup-ready-v1`
- The SSH stage should trust the VM only after:
  - the sentinel exists
  - package-manager locks are clear
  - required host tools for handoff exist (`bash`, `curl`)
- This is safer than trusting free-form boot logs or arbitrary sleep durations.

## Evidence
- Current heavy first-boot behavior in `scripts/openclaw-gcp/bootstrap-openclaw.sh`
- Current lack of any readiness marker in startup or repair flow

## Decision
The plan is viable if `br-6w1` defines a prereq-only startup script plus a ready sentinel and `br-34k` gates SSH on that contract instead of using timing guesses.
