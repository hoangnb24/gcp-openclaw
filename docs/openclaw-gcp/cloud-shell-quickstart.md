# OpenClaw GCP Cloud Shell Quickstart

This is the official Phase 1 browser-first landing flow.
It uses only documented Open in Cloud Shell parameters and does not rely on launch-time command execution.

## 1. Open This Repo In Cloud Shell

Use the official launch URL below or click the button in the root README:

```text
https://shell.cloud.google.com/cloudshell/editor?cloudshell_git_repo=https://github.com/hoangnb24/gcp-openclaw&cloudshell_workspace=.&cloudshell_tutorial=docs/openclaw-gcp/cloud-shell-quickstart.md&show=ide,terminal
```

Documented parameters used:

- `cloudshell_git_repo`: clones this repository into Cloud Shell
- `cloudshell_workspace=.`: opens the repo root as the workspace
- `cloudshell_tutorial`: launches this repo-hosted tutorial
- `show=ide,terminal`: keeps the editor and terminal visible together

What this does not do:

- it does not auto-run arbitrary repo commands
- it does not auto-provision infrastructure

## 2. Start The Non-Mutating Welcome Flow

Run:

```sh
./bin/openclaw-gcp welcome
```

The welcome flow:

- asks for a stack ID in interactive mode
- explains the next `up` command
- stays non-mutating until you explicitly choose to continue

## 3. Bring Up One Stack

Run:

```sh
./bin/openclaw-gcp up --stack-id my-stack
```

Notes:

- the first real `up` run requires an explicit stack ID
- the wrapper derives the VM/template/router/NAT names automatically
- the wrapper remembers the current stack in `~/.config/openclaw-gcp/current-stack.env`
- if project or tag inputs are still missing, the underlying install engine prompts interactively

## 4. Check The Stack

Run:

```sh
./bin/openclaw-gcp status
```

This shows:

- the current stack ID
- the last-known project/region/zone context
- whether the labeled instance/template anchors exist and match the stack
- whether the deterministic router/NAT companions exist

## 5. Tear The Stack Down

Interactive Cloud Shell convenience path:

```sh
./bin/openclaw-gcp down
```

Explicit path:

```sh
./bin/openclaw-gcp down --stack-id my-stack
```

Safe planning first:

```sh
./bin/openclaw-gcp down --stack-id my-stack --dry-run
```

The wrapper verifies the stack anchors first, then hands teardown off to the existing exact-name destroy engine with its normal confirmation and qualification behavior.

## 6. What Persists If You Return Later

Default Cloud Shell keeps a persistent `$HOME`, so this repo's convenience file usually survives:

```text
~/.config/openclaw-gcp/current-stack.env
```

That means next month you can often reopen Cloud Shell, return to this repo, and run:

```sh
./bin/openclaw-gcp status
./bin/openclaw-gcp down
```

Important caveats:

- Cloud Shell VMs are temporary even though `$HOME` is usually persistent
- `gcloud` config is tab-local by default and may not still remember your project
- ephemeral Cloud Shell sessions can discard local state entirely

That is why the local file is only convenience state.
The durable ownership contract remains the GCP labels on the instance/template anchors.

## 7. If Auth Or Project Context Is Missing

For non-Google allowlisted repositories, Cloud Shell can open in a temporary environment without automatic access to the user's default credentials.
If `up` or `status` tells you auth or project context is missing, follow the emitted `gcloud` guidance from the scripts.

The wrapper is intentionally thin.
It keeps the main UX simple while preserving the existing safety, determinism, and operator guardrails underneath.
