# Spike Findings: br-1qh

## Question

Can the destroy flow reliably inspect and enforce this rule before deletion in both GCP and the shell test harness: template metadata matches the current startup contract, router belongs to the requested network, and NAT exists under that router with auto-allocated IPs and all-subnets NAT mode?

## Verdict

YES

## Why

The create-side contracts already define stable expected values for template startup metadata, router network ownership, and NAT mode. GCP describe commands expose all of the fields needed to enforce these predicates exactly, and the shell harness can mock those outputs deterministically.

## Validated Inspection Surface

Template startup contract:

```bash
gcloud compute instance-templates describe "$TEMPLATE_NAME" \
  --project "$PROJECT_ID" \
  --region "$REGION" \
  --flatten='properties.metadata.items[]' \
  --format='value(properties.metadata.items.key,properties.metadata.items.value)'
```

Required key/value matches:

- `startup_script_source=embedded-vm-prereqs-v1`
- `startup_profile=vm-prereqs-v1`
- `startup_contract_version=startup-ready-v1`
- `startup_ready_sentinel=/var/lib/openclaw/startup-ready-v1`

Router network ownership:

```bash
gcloud compute routers describe "$ROUTER_NAME" \
  --project "$PROJECT_ID" \
  --region "$REGION" \
  --format='value(network.basename())'
```

Must equal the requested network name.

NAT parent + mode:

```bash
gcloud compute routers nats describe "$NAT_NAME" \
  --project "$PROJECT_ID" \
  --router "$ROUTER_NAME" \
  --region "$REGION" \
  --format='value(natIpAllocateOption,sourceSubnetworkIpRangesToNat)'
```

Must equal `AUTO_ONLY<TAB>ALL_SUBNETWORKS_ALL_IP_RANGES`.

## Destroy Implication

- `destroy.sh` can run a fail-closed qualification gate for template/router/NAT ownership before any delete command runs.
- Any command error, empty output, or value mismatch should abort qualification and print which predicate failed.

## Constraints Added

- `br-1gf` must implement exact-name describe checks with fail-closed handling on empty or ambiguous outputs.
- `br-k26` must extend the mock harness for template metadata pairs, router network, and NAT mode, then add drift fixtures asserting no delete commands run on qualification failure.

## Sources

- https://cloud.google.com/compute/docs/reference/rest/v1/instanceTemplates
- https://cloud.google.com/compute/docs/reference/rest/v1/routers
- https://docs.cloud.google.com/nat/docs/set-up-manage-network-address-translation
- https://docs.cloud.google.com/sdk/gcloud/reference/compute/instance-templates/describe
- https://docs.cloud.google.com/sdk/gcloud/reference/compute/routers/nats/describe
