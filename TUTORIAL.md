# Connect your GCP project to CloudNap

This tutorial creates a **least-privilege** connection between your GCP project and CloudNap. It takes about 30 seconds.

## What it does

Running `setup.sh` will:

1. **Enable APIs**: Compute Engine + IAM Credentials (plus Cloud DNS / Billing only if you opt in)
2. **Create a custom IAM role** called `CloudNap Instance Operator` containing only:
   - Compute: `instances.list`, `instances.get`, `instances.start`, `instances.stop`, `zones.list`, `zoneOperations.get/list`
   - DNS *(only when `ENABLE_DNS=yes`)*: `managedZones.list/get`, `resourceRecordSets.list/get/create/update/delete`, `changes.create/get`
   - Billing *(only when `ENABLE_BILLING=yes`)*: read-only Recommender, Cloud Monitoring, Cloud Asset Inventory. No write access.
   - **CloudNap cannot delete VMs, modify metadata, or change service accounts.**
3. **Create a dedicated service account** `cloudnap-connector-<TOKEN>@<PROJECT>.iam.gserviceaccount.com`
4. **Bind the custom role** to that service account
5. **Grant CloudNap's SA permission** to impersonate your service account (Service Account Token Creator)

No service account keys are created. No long-lived credentials leave your project.

## Run the setup

**Copy the exact command from your CloudNap GCP setup screen** — it has your token pre-filled:

```bash
CLOUDNAP_TOKEN=<your-token> ENABLE_DNS=yes ENABLE_BILLING=yes bash setup.sh
```

`CLOUDNAP_TOKEN` is required. It uniquely identifies your CloudNap organisation and is used to name
the service account, so CloudNap can look it up on the other end.

**Compute-only (no DNS, no Billing):**

```bash
CLOUDNAP_TOKEN=<your-token> bash setup.sh
```

**Compute + DNS + Billing (recommended):**

```bash
CLOUDNAP_TOKEN=<your-token> ENABLE_DNS=yes ENABLE_BILLING=yes bash setup.sh
```

<walkthrough-editor-open-file filePath="setup.sh">Open setup.sh</walkthrough-editor-open-file> to review it first if you'd like.

## Paste the result into CloudNap

When the script finishes, it prints:

- **Service account email** (like `cloudnap-connector-<token>@my-project.iam.gserviceaccount.com`)
- **Project ID**

Copy both values into the CloudNap setup screen and click **Connect GCP Account**.

## Changing your mind later

Safe to re-run with the same `CLOUDNAP_TOKEN`. Passing or dropping `ENABLE_DNS` / `ENABLE_BILLING`
will swap the role definition in place — your SA keeps the same email so no reconnection is needed
on the CloudNap side, just re-verify the account.

```bash
# Turn DNS on later
CLOUDNAP_TOKEN=<your-token> ENABLE_DNS=yes ENABLE_BILLING=yes bash setup.sh

# Turn Billing off
CLOUDNAP_TOKEN=<your-token> ENABLE_BILLING=no bash setup.sh
```

## Disconnecting later

The script prints a 3-line cleanup command you can run any time to fully remove CloudNap's access.

## Customising

You can override defaults before running:

```bash
export PROJECT_ID="my-other-project"         # Target a different project
export ROLE_ID="customRoleName"              # Change role ID
export CLOUDNAP_TOKEN="mytoken"             # Your CloudNap org token
export ENABLE_DNS=yes                        # Opt in to DNS management
export ENABLE_BILLING=yes                    # Opt in to Billing dashboard
bash setup.sh
```
