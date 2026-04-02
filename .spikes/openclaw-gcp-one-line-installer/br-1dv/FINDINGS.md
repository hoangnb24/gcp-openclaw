# Spike Findings: Local Prerequisite Matrix

## Question
What exact local prerequisite matrix can `install.sh` prove before provisioning?

## Result
YES, with a narrower contract than the original wording implied.

## Findings
- The installer should guarantee all **locally knowable** prerequisites before mutation, not literally everything required for eventual end-to-end success.
- Safe local checks:
  - `command -v gcloud`
  - `gcloud --version`
  - `gcloud auth list --filter='status:ACTIVE' --format='value(account)'`
  - `gcloud config get-value project`
  - `gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)'`
  - `gcloud services list --enabled --project "$PROJECT_ID" --filter='config.name=compute.googleapis.com' --format='value(config.name)'`
  - `gcloud services list --enabled --project "$PROJECT_ID" --filter='config.name=iap.googleapis.com' --format='value(config.name)'`
  - `gcloud compute zones describe "$ZONE" --project "$PROJECT_ID" --format='value(name,region.basename())'`
  - `gcloud compute firewall-rules list --project "$PROJECT_ID" --filter='direction=INGRESS AND sourceRanges:(35.235.240.0/20)'`
- The installer cannot fully prove, before a VM exists, that IAM inheritance, conditional bindings, firewall target tags/service accounts, guest SSH readiness, or final IAP reachability will succeed.
- That gap should be surfaced explicitly in UX: pre-provision fail-fast for local checks, then a post-provision readiness or `gcloud compute ssh --troubleshoot --tunnel-through-iap` stage for runtime reachability.

## Sources
- https://cloud.google.com/sdk/gcloud/reference/compute/ssh
- https://cloud.google.com/compute/docs/connect/ssh-using-iap
- https://cloud.google.com/iap/docs/using-tcp-forwarding
- https://cloud.google.com/compute/docs/api/prereqs

## Decision
The plan is viable if `br-ect` treats preflight as a guarantee over locally knowable prerequisites only and documents the post-provision reachability boundary.
