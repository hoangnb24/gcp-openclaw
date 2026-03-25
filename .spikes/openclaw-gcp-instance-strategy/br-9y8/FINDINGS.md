# Spike Findings: Secret Handling For Persistent Clones

Date: 2026-03-24
Bead: `br-9y8`
Verdict: YES

## Question

How should credentials and auth state be handled so persistent clones do not silently inherit secrets or stale runtime state?

## Findings

- Google documents that machine images store VM configuration, metadata, permissions, and disk data. That means clone workflows can duplicate more state than operators expect.
- Because of that, the safe default is not to treat secrets as cloneable machine state.
- The best day-1 rule for this feature is:
  - do not store provider secrets in instance-template metadata
  - avoid user-managed service-account keys when a VM service account can be used
  - require post-provision credential injection or re-auth after clone creation
  - include a scrub checklist before capturing a machine image from a source VM
- Secret Manager plus VM service-account access is the preferred future-friendly path when automation is needed. Manual post-clone re-auth is acceptable for day one.

## Constraints For Execution

1. Clone docs must require operators to review and scrub provider tokens, session cookies, SSH material, and any user-managed service-account keys before image capture.
2. Spawn docs must require re-auth or reinjection after clone creation instead of assuming credentials are safe to inherit.
3. Scripts must not encourage passing secrets through flags, template metadata, or committed env files.

## Sources

- https://docs.cloud.google.com/compute/docs/machine-images
- https://docs.cloud.google.com/secret-manager/docs/best-practices
- https://cloud.google.com/iam/docs/best-practices-for-managing-service-account-keys
- https://docs.cloud.google.com/compute/docs/access/authenticate-workloads
