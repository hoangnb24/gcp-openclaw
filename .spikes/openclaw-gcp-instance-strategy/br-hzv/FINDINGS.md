# Spike Findings: Deterministic Bootstrap Inputs

Date: 2026-03-24
Bead: `br-hzv`
Verdict: YES

## Question

Can the baseline provisioning flow stay deterministic enough on GCP if we use instance templates plus startup/bootstrap scripts?

## Findings

- Google recommends making instance templates as explicit and deterministic as possible, especially when startup scripts install third-party software.
- Using an image family alone is not deterministic enough for this feature because the family can advance over time. The safer pattern is to resolve a specific Debian 12 image at template-creation time and record that resolved image in the generated template or script output.
- Startup/bootstrap behavior must also pin non-OS inputs:
  - the startup script source
  - Docker/OpenClaw image tags
  - any remote artifacts fetched during bootstrap
- Startup scripts remain a valid fit for the baseline path as long as the inputs above are explicit and versioned.

## Constraints For Execution

1. `create-template.sh` must resolve and record a specific Debian image, not rely on a drifting family at instance launch time.
2. Script defaults must expose explicit values for machine type, disk type, disk size, region, and zone.
3. Bootstrap logic must avoid secret values in metadata or committed files.
4. If runtime secrets are needed, they must be injected after boot or retrieved with the VM service account from a system such as Secret Manager.

## Sources

- https://cloud.google.com/compute/docs/instance-templates/deterministic-instance-templates
- https://docs.cloud.google.com/compute/docs/images/image-families-best-practices
- https://docs.cloud.google.com/compute/docs/instances/startup-scripts
