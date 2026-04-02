# Spike Findings: br-b7f

## Question

Can Phase 1 safely treat router and NAT as deterministic companions of a labeled stack anchor even though the current `gcloud` router/NAT path does not expose label flags?

## Result

YES

## Evidence

- Local `gcloud` help confirms `gcloud compute instances create` and `gcloud compute instance-templates create` support `--labels`.
- Local `gcloud compute routers create --help` does not expose `--labels`; it exposes `--resource-manager-tags`, which is a different mechanism and not the label contract used elsewhere in this repo.
- Local `gcloud compute routers update --help` also does not expose label update flags.
- Local `gcloud compute routers nats create --help` does not expose label flags either.
- The repo already has a strong exact-target destroy flow in `scripts/openclaw-gcp/destroy.sh`, and its safety checks already reason about router and NAT by explicit names plus router/network and NAT-mode qualification.

## Safe Phase 1 Ownership Model

Phase 1 can safely use a mixed ownership model:

- durable labeled anchors on resources that support the approved label set
- deterministic stack-derived names for router and NAT
- fail-closed resolution when labeled anchors and deterministic companion names disagree

This keeps the user-facing concept as “one stack,” while avoiding false claims that every managed resource is independently rediscoverable by labels in the current CLI path.

## Constraints To Carry Into Implementation

- Treat the labeled instance/template path as the primary durable anchor for a stack.
- Derive router and NAT names from the stack ID using one canonical helper.
- Do not claim broad router/NAT discovery by labels in Phase 1.
- If stack anchors are missing or inconsistent, `status` and `down` must explain the ambiguity and stop rather than guess.

## Consequence For The Plan

Story 2 and Story 3 remain valid, but they must present router/NAT ownership as deterministic companion resources rather than fully labeled peers.
