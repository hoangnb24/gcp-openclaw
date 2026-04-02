# Spike Findings: Interactive SSH Handoff

## Question
What `gcloud compute ssh` invocation preserves upstream installer interactivity and the required shell semantics?

## Result
YES, with one important constraint: do not pipe installer stdout through `tee` directly.

## Findings
- `gcloud compute ssh --command=...` runs a command and then exits.
- `gcloud` documents that interactive shell behavior requires allocating a pseudo-TTY, for example by passing `-- -t`.
- The upstream installer treats a non-TTY stdout as non-interactive, so a direct `... | tee log` wrapper would break prompt behavior.
- Recommended shape:
  - use `gcloud compute ssh "$INSTANCE" --project "$PROJECT_ID" --zone "$ZONE" --tunnel-through-iap --command="bash -lc '<remote script>'" -- -t`
  - inside the remote script, run the installer under `script -qefc` or another PTY-preserving transcript tool
  - on success, end the remote script with `exec bash -il`
  - on failure, print the remote log path and exit non-zero so SSH returns locally

## Sources
- https://cloud.google.com/sdk/gcloud/reference/compute/ssh
- https://cloud.google.com/compute/docs/connect/ssh-using-iap
- https://openclaw.ai/install.sh

## Decision
The plan is viable if `br-le9` uses `-- -t` plus a PTY-preserving transcript strategy and opens a login shell only after a successful upstream installer exit.
