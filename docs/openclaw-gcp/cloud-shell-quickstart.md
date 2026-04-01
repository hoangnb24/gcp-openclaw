# OpenClaw GCP Cloud Shell Quickstart

This quickstart defines the official browser-first landing flow for Phase 1.
It is intentionally non-mutating until you run the explicit `up` command.

## 1) Open This Repo In Cloud Shell

Use this official launch URL:

```
https://console.cloud.google.com/cloudshell/open?cloudshell_git_repo=https://github.com/hoangnb24/gcp-openclaw&cloudshell_workspace=gcp-openclaw&cloudshell_tutorial=docs/openclaw-gcp/cloud-shell-quickstart.md
```

Launch parameters used:
- `cloudshell_git_repo` clones this repository into Cloud Shell.
- `cloudshell_workspace` opens the cloned repo folder.
- `cloudshell_tutorial` opens this repo-hosted tutorial asset.

## 2) Run The Welcome Entry Point

From the repo root in Cloud Shell:

```bash
bash scripts/openclaw-gcp/cloudshell-welcome.sh
```

The welcome script:
- introduces the stack-native operator model
- asks for your stack name in interactive mode
- prints (or hands off to) the exact `up` command path

The welcome script does not provision infrastructure.

## 3) Bring The Stack Up Explicitly

When prompted (or after the script prints it), run:

```bash
bin/openclaw-gcp up --stack-id <your-stack-id>
```

This explicit stack input is required on first run.

## 4) Continue With Stack-Native Flow

After `up` is available and successful, Phase 1 uses the same stack identity for:
- `bin/openclaw-gcp status`
- `bin/openclaw-gcp down`

## Notes

- This quickstart intentionally relies only on documented Cloud Shell launch parameters.
- No undocumented launch-time command execution is required.
