# cloudnap-gcp-setup

Public setup artifacts for connecting a GCP project to [CloudNap](https://cloudnap.io).

## Files

| File | Purpose |
|------|---------|
| [`cloudnap-role.yaml`](./cloudnap-role.yaml) | Compute-only custom role (VM list/start/stop) |
| [`cloudnap-role-dns.yaml`](./cloudnap-role-dns.yaml) | Compute + Cloud DNS record-set management |
| [`cloudnap-role-billing.yaml`](./cloudnap-role-billing.yaml) | Compute + Billing Dashboard (Recommender, Monitoring, Asset Inventory, BigQuery) |
| [`cloudnap-role-dns-billing.yaml`](./cloudnap-role-dns-billing.yaml) | Compute + DNS + Billing (all features) |
| [`setup.sh`](./setup.sh) | Idempotent connector setup script |
| [`TUTORIAL.md`](./TUTORIAL.md) | Interactive Cloud Shell tutorial |

## How to use

### Option A — One-click Cloud Shell (recommended)

Click **Open in Google Cloud Shell** in the CloudNap setup screen. The button opens a Cloud Shell session with the repo cloned and all env vars (including `CLOUDNAP_TOKEN`) pre-filled.

Then run the command shown in the CloudNap UI — it looks like:

```bash
CLOUDNAP_TOKEN=<your-token> ENABLE_DNS=yes ENABLE_BILLING=yes bash setup.sh
```

`CLOUDNAP_TOKEN` is shown pre-filled in the CloudNap UI — always copy it from there.

### Option B — Any terminal with `gcloud` authenticated

```bash
# Paste the full command from CloudNap (token is pre-filled):
CLOUDNAP_TOKEN=<your-token> ENABLE_DNS=yes ENABLE_BILLING=yes \
  bash <(curl -fsSL https://raw.githubusercontent.com/Bhushan21z/cloudnap-gcp-setup/main/cloudnap-gcp/setup.sh)
```

### Flags

| Flag / env var | Default | Effect |
|----------------|---------|--------|
| `CLOUDNAP_TOKEN` | *(required)* | Names the service account `cloudnap-connector-<token>` |
| `ENABLE_DNS` | `no` | Adds Cloud DNS record-set permissions |
| `ENABLE_BILLING` | `yes` | Adds Recommender, Monitoring, Asset Inventory, BigQuery APIs |
| `PROJECT_ID` | active `gcloud` project | Target GCP project |

## What the script creates

1. **Enables APIs** — Compute Engine, IAM Credentials (+ DNS, Recommender, Monitoring, Asset Inventory, BigQuery when opted in)
2. **Creates a custom IAM role** `cloudNapInstanceOperator` with only the permissions CloudNap needs
3. **Creates a service account** `cloudnap-connector-<token>@<project>.iam.gserviceaccount.com`
4. **Binds the role** to that service account
5. **Grants impersonation** — CloudNap's SA gets `roles/iam.serviceAccountTokenCreator` on your SA

No service account keys are generated. No long-lived credentials leave your project.

## What permissions does CloudNap get?

| Feature | Can do | Cannot do |
|---------|--------|-----------|
| **Compute (always)** | List VMs, Start VM, Stop VM, read disk/IP/machine-type info | Delete VMs, modify metadata/SSH keys, change attached SAs, create/delete disks |
| **DNS (opt-in)** | List zones, manage record sets in existing zones | Create or delete DNS zones |
| **Billing (opt-in, default on)** | Read recommendations, CPU utilization, resource inventory, run BQ cost queries | Apply/dismiss recommendations, modify billing account |

## BigQuery billing export (extra step when Billing is enabled)

GCP billing cost data lives in a BigQuery export — there is no Cost Explorer-equivalent API.
The setup script grants `bigquery.jobs.create` at project level, but you also need to grant
dataset-level read access manually:

```bash
# Replace <dataset> with your billing export dataset name
bq add-iam-policy-binding \
  --member="serviceAccount:cloudnap-connector-<token>@<project>.iam.gserviceaccount.com" \
  --role="roles/bigquery.dataViewer" \
  <dataset>
```

Then enter the dataset + table name in CloudNap → Settings → GCP → Billing.

## Re-running later

Safe to re-run with the same `CLOUDNAP_TOKEN`. Changing `ENABLE_DNS` / `ENABLE_BILLING` swaps
the role definition in place — the SA email stays the same, no reconnection needed in CloudNap.

## Disconnect

The setup script prints the exact cleanup commands at the end. In general:

```bash
PROJECT_ID=<your-project>
TOKEN=<your-token>
CLIENT_SA="cloudnap-connector-${TOKEN}@${PROJECT_ID}.iam.gserviceaccount.com"

gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${CLIENT_SA}" \
    --role="projects/${PROJECT_ID}/roles/cloudNapInstanceOperator"

gcloud iam service-accounts delete "${CLIENT_SA}" --project="${PROJECT_ID}"

gcloud iam roles delete cloudNapInstanceOperator --project="${PROJECT_ID}"
```
