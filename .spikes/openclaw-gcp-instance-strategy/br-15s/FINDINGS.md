# Spike Findings: Machine Image Role Versus Baseline Rebuild

Date: 2026-03-24
Bead: `br-15s`
Verdict: YES

## Question

Can machine images be approved as the persistent-clone primitive without replacing the deterministic baseline rebuild path?

## Findings

- Google positions machine images as a strong fit for instance cloning and multi-disk backup.
- Google also distinguishes machine images from base-image replication workflows. That supports using machine images for persistent full-environment clones while keeping instance templates as the deterministic baseline rebuild path.
- This means the planned two-layer model is valid:
  - instance templates plus pinned bootstrap for fresh, reproducible baseline builds
  - machine images for long-lived environment copies and milestone rollback points
- The operator guidance must make the boundary explicit so future workers do not treat machine images as the only source of truth.

## Constraints For Execution

1. Baseline rebuild docs must direct operators to the template-based flow first.
2. Clone docs must say machine images are for persistent full-environment copies of a known-good VM.
3. The README must explain when to choose baseline rebuild versus clone.
4. Machine-image capture should be treated as an intentional checkpoint before major upgrades or before preparing a source VM for cloning.

## Sources

- https://docs.cloud.google.com/compute/docs/machine-images
- https://docs.cloud.google.com/compute/docs/machine-images/create-machine-images
- https://docs.cloud.google.com/compute/docs/machine-images/create-instance-from-machine-image
- https://cloud.google.com/compute/docs/instance-templates/deterministic-instance-templates
