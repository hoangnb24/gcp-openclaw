# Spike Findings: br-rfo

## Question

Can this repo deliver a credible Phase 1 guided landing using only officially documented Open in Cloud Shell behavior, and if so, which exact mechanism should it use for the welcome experience?

## Result

YES

## Evidence

- Official Open in Cloud Shell docs say the required launch parameter is `cloudshell_git_repo`, which clones the repository into Cloud Shell and opens the project root.
- The same docs list `cloudshell_print` for printing an instruction file into the terminal, `cloudshell_tutorial` for launching a tutorial Markdown file from the repo, `cloudshell_open_in_editor` for opening specific files, and `cloudshell_workspace` for setting the working directory.
- The Open in Cloud Shell docs do not document an arbitrary “run this repo command on launch” parameter for general repositories.
- The same page states that non-Google allowlisted repositories use a temporary Cloud Shell environment without access to the user's credentials, so this repo must not assume ambient auth/project state on launch.
- The docs also say `cloudshell_image` and `ephemeral=true` create a scratch-home temporary environment, which conflicts with the desired convenience-state persistence story for this feature.

## Recommended Phase 1 Pattern

Use the official button with a URL built around:

- `cloudshell_git_repo=<repo-url>`
- `cloudshell_workspace=.`
- `cloudshell_tutorial=docs/openclaw-gcp/cloud-shell-quickstart.md`
- optionally `cloudshell_open_in_editor=README.md` or the quickstart file if that improves orientation
- optionally `show=ide,terminal`

Inside the tutorial, use repo-hosted instructions and command blocks to guide the user into the non-mutating welcome flow. `cloudshell_print` can complement the tutorial if a terminal-first reminder is useful, but the main guided experience should come from the tutorial asset because it is explicitly designed to walk users through a project.

## Constraints To Carry Into Implementation

- Do not rely on undocumented command execution from the launch URL.
- Do not assume Cloud Shell opens with usable Google Cloud credentials for this repo.
- Do not use `cloudshell_image` for Phase 1 just to simulate auto-run behavior; it would create a scratch-home environment and work against the persistence goal.
- The welcome flow should remain non-mutating and should only guide the user into the repo-native `welcome` / `up` path.

## Consequence For The Plan

Story 1 is valid, but its implementation should be framed as “official Cloud Shell button plus tutorial/printed guidance” rather than “button directly auto-executes the repo script.”
