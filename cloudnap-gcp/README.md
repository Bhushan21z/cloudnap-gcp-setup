# cloudnap/gcp-setup

Public setup artifacts for connecting a GCP project to [CloudNap](https://cloudnap.io).

## Files

- [`cloudnap-role.yaml`](./cloudnap-role.yaml) — IAM custom role definition (least-privilege)
- [`setup.sh`](./setup.sh) — idempotent connector setup script
- [`TUTORIAL.md`](./TUTORIAL.md) — Cloud Shell tutorial

## Quick use

Click **Open in Cloud Shell** inside the CloudNap UI, or paste this:

```
https://shell.cloud.google.com/cloudshell/editor?cloudshell_git_repo=https://github.com/cloudnap/gcp-setup&cloudshell_tutorial=TUTORIAL.md
```

Then in Cloud Shell:

```bash
bash setup.sh
```

The script prints the two values (service account email + project ID) to paste back into CloudNap.

## What permissions does CloudNap get?

See [`cloudnap-role.yaml`](./cloudnap-role.yaml). Highlights:

- Can: list VMs, start/stop VMs, manage DNS record sets
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
