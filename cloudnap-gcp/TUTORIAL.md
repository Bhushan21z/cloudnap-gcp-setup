# Connect your GCP project to CloudNap

This tutorial creates a **least-privilege** connection between your GCP project and CloudNap. It takes about 30 seconds.

## What it does

Running `setup.sh` will:

1. **Enable APIs**: Compute Engine, Cloud DNS, IAM Credentials
2. **Create a custom IAM role** called `CloudNap Instance Operator` containing only these permissions:
   - Compute: `instances.list`, `instances.get`, `instances.start`, `instances.stop`, `zones.list`, `zoneOperations.get/list`
   - DNS: `managedZones.list/get`, `resourceRecordSets.list/get/create/update/delete`, `changes.create/get`
   - **CloudNap cannot delete VMs, modify metadata, or change service accounts.**
3. **Create a dedicated service account** `cloudnap-connector@<PROJECT>.iam.gserviceaccount.com`
4. **Bind the custom role** to that service account
5. **Grant CloudNap's SA permission** to impersonate your service account (Service Account Token Creator)

No service account keys are created. No long-lived credentials leave your project.

## Run the setup

In the Cloud Shell prompt below, run:

```bash
bash setup.sh
```

<walkthrough-editor-open-file filePath="setup.sh">Open setup.sh</walkthrough-editor-open-file> to review it first if you'd like.

## Paste the result into CloudNap

When the script finishes, it prints two values:

- **Service account email** (like `cloudnap-connector@my-project.iam.gserviceaccount.com`)
- **Project ID**

Copy both into the CloudNap setup screen and click **Connect GCP Account**.

## Disconnecting later

The script prints a 3-line cleanup command you can run any time to fully remove CloudNap's access.

## Customising

You can override defaults before running:

```bash
export PROJECT_ID="my-other-project"         # Target a different project
export ROLE_ID="customRoleName"              # Change role ID
export CLIENT_SA_NAME="custom-connector"     # Change SA name
bash setup.sh
```
