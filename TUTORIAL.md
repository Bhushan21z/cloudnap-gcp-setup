# Connect your GCP project to CloudNap

This tutorial creates a **least-privilege** connection between your GCP project and CloudNap. It takes about 30 seconds.

## What it does

Running `setup.sh` will:

1. **Enable APIs**: Compute Engine + IAM Credentials (plus Cloud DNS only if you opt in)
2. **Create a custom IAM role** called `CloudNap Instance Operator` containing only:
   - Compute: `instances.list`, `instances.get`, `instances.start`, `instances.stop`, `zones.list`, `zoneOperations.get/list`
   - DNS *(only when `--enable-dns` is passed)*: `managedZones.list/get`, `resourceRecordSets.list/get/create/update/delete`, `changes.create/get`
   - **CloudNap cannot delete VMs, modify metadata, or change service accounts.**
3. **Create a dedicated service account** `cloudnap-connector@<PROJECT>.iam.gserviceaccount.com`
4. **Bind the custom role** to that service account
5. **Grant CloudNap's SA permission** to impersonate your service account (Service Account Token Creator)

No service account keys are created. No long-lived credentials leave your project.

## Run the setup

**Compute-only (default — VM start/stop only):**

```bash
bash setup.sh
```

**Compute + DNS (also let CloudNap manage Cloud DNS record sets):**

```bash
ENABLE_DNS=yes bash setup.sh
# or equivalently:
bash setup.sh --enable-dns
```

<walkthrough-editor-open-file filePath="setup.sh">Open setup.sh</walkthrough-editor-open-file> to review it first if you'd like.

## Paste the result into CloudNap

When the script finishes, it prints:

- **Service account email** (like `cloudnap-connector@my-project.iam.gserviceaccount.com`)
- **Project ID**
- **DNS management: enabled / disabled**

Copy the first two into the CloudNap setup screen, tick the **Enable DNS management** box if you ran the script with DNS turned on, and click **Connect GCP Account**.

## Changing your mind later

Safe to re-run. Passing (or dropping) `--enable-dns` will swap the role definition in place — your SA keeps the same email so no reconnection is needed on the CloudNap side, just re-verify the account.

## Disconnecting later

The script prints a 3-line cleanup command you can run any time to fully remove CloudNap's access.

## Customising

You can override defaults before running:

```bash
export PROJECT_ID="my-other-project"         # Target a different project
export ROLE_ID="customRoleName"              # Change role ID
export CLIENT_SA_NAME="custom-connector"     # Change SA name
export ENABLE_DNS=yes                        # Opt in to DNS management
bash setup.sh
```
