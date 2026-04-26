# cloudnap/gcp-setup

Public setup artifacts for connecting a GCP project to [CloudNap](https://cloudnap.io).

## Files

- [`cloudnap-role.yaml`](./cloudnap-role.yaml) — compute-only custom role (default)
- [`cloudnap-role-dns.yaml`](./cloudnap-role-dns.yaml) — compute + DNS custom role (opt-in)
- [`setup.sh`](./setup.sh) — idempotent connector setup script
- [`TUTORIAL.md`](./TUTORIAL.md) — Cloud Shell tutorial

## Quick use

Click **Open in Cloud Shell** inside the CloudNap UI, or paste this:

```
https://shell.cloud.google.com/cloudshell/editor?cloudshell_git_repo=https://github.com/cloudnap/gcp-setup&cloudshell_tutorial=TUTORIAL.md
```

Then in Cloud Shell:

```bash
# Compute-only (default)
bash setup.sh

# Or with DNS record-set management
ENABLE_DNS=yes bash setup.sh
# equivalent:
bash setup.sh --enable-dns
```

The script prints the values (service account email + project ID + DNS flag) to paste back into CloudNap.

## What permissions does CloudNap get?

See [`cloudnap-role.yaml`](./cloudnap-role.yaml) (base) and [`cloudnap-role-dns.yaml`](./cloudnap-role-dns.yaml) (with DNS). Highlights:

- Can: list VMs, start/stop VMs *(plus manage DNS record sets when DNS is enabled)*
- **Cannot**: delete VMs, modify VM metadata/SSH keys, change attached service accounts, create/delete disks, create/delete DNS zones

## Disconnect

```bash
PROJECT_ID=<your-project>
CLIENT_SA=cloudnap-connector@${PROJECT_ID}.iam.gserviceaccount.com

gcloud projects remove-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${CLIENT_SA}" \
    --role="projects/${PROJECT_ID}/roles/cloudNapInstanceOperator"
gcloud iam service-accounts delete $CLIENT_SA --project=$PROJECT_ID
gcloud iam roles delete cloudNapInstanceOperator --project=$PROJECT_ID
```
