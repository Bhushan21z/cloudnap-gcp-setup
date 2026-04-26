# Connect your GCP project to CloudNap

This tutorial creates a **least-privilege** connection between your GCP project and CloudNap. It takes about 30 seconds.

## What it does

Running `setup.sh` will:

1. **Enable APIs**: Compute Engine + IAM Credentials (plus Cloud DNS / Recommender / Monitoring / Asset / Billing only if you opt in)
2. **Create a custom IAM role** called `CloudNap Instance Operator` containing only:
   - Compute: `instances.list`, `instances.get`, `instances.start`, `instances.stop`, `zones.list`, `zoneOperations.get/list`
   - DNS *(only when DNS is enabled)*: `managedZones.list/get`, `resourceRecordSets.list/get/create/update/delete`, `changes.create/get`
   - Billing *(only when Billing is enabled)*: read-only Recommender, Monitoring, Asset Inventory, Cloud Billing
   - **CloudNap cannot delete VMs, modify metadata, or change service accounts.**
3. **Create a dedicated service account** `cloudnap-connector-<token>@<PROJECT>.iam.gserviceaccount.com` — the `<token>` is a per-account secret CloudNap generated for you (this is GCP's equivalent of AWS's external ID)
4. **Bind the custom role** to that service account
5. **Grant CloudNap's SA permission** to impersonate your service account (Service Account Token Creator)

No service account keys are created. No long-lived credentials leave your project.

## Run the setup

CloudNap shows you a single command to copy and paste — it already has your unique token and your DNS / Billing choices baked in. It looks like:

```bash
CLOUDNAP_TOKEN=<your-token> ENABLE_DNS=yes ENABLE_BILLING=yes bash setup.sh
```

Just paste that in Cloud Shell and press Enter.

> The `CLOUDNAP_TOKEN` is required. It binds this setup to a specific account inside CloudNap, so a leaked project ID alone is not enough for anyone else to register your project.

## Paste the result into CloudNap

When the script finishes, go back to CloudNap and enter:

- **Project ID** (the project you ran the script in)

That's it. CloudNap already knows your token and computes the service account email automatically.

## Changing your mind later

Safe to re-run with the same token. Toggling `ENABLE_DNS` or `ENABLE_BILLING` will swap the role definition in place — your SA keeps the same email so no reconnection is needed on the CloudNap side, just re-verify the account.

## Disconnecting later

The script prints a 3-line cleanup command you can run any time to fully remove CloudNap's access.

## Customising

You can override defaults before running:

```bash
export PROJECT_ID="my-other-project"         # Target a different project
export ROLE_ID="customRoleName"              # Change role ID
export ENABLE_DNS=yes                        # Opt in to DNS management
export ENABLE_BILLING=yes                    # Opt in to billing dashboard
CLOUDNAP_TOKEN=<your-token> bash setup.sh
```
