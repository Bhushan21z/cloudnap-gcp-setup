#!/usr/bin/env bash
# CloudNap GCP connector setup
# ---------------------------------------------------------------
# This script:
#   1. Enables the Compute Engine + Cloud DNS APIs
#   2. Creates a least-privilege custom IAM role (CloudNap Instance Operator)
#   3. Creates a dedicated service account (cloudnap-connector)
#   4. Binds the custom role to that SA
#   5. Grants CloudNap's SA permission to impersonate it
#
# At the end it prints the two values you paste back into CloudNap:
#   - Service account email
#   - Project ID
#
# Safe to re-run — every step is idempotent.
# ---------------------------------------------------------------

set -euo pipefail

# ---- Configurable: override via env vars if you like ----
CLOUDNAP_SA="${CLOUDNAP_SA:-cloudnap-admin@gen-lang-client-0395474001.iam.gserviceaccount.com}"
ROLE_ID="${ROLE_ID:-cloudNapInstanceOperator}"
CLIENT_SA_NAME="${CLIENT_SA_NAME:-cloudnap-connector}"

# ---- Resolve project ----
if [[ -z "${PROJECT_ID:-}" ]]; then
    PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
fi

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
    echo ""
    echo "No GCP project selected."
    read -rp "Enter the project ID you want CloudNap to manage: " PROJECT_ID
fi

if [[ -z "$PROJECT_ID" ]]; then
    echo "ERROR: project ID is required." >&2
    exit 1
fi

gcloud config set project "$PROJECT_ID" >/dev/null

echo ""
echo "==================================================="
echo "  CloudNap GCP connector setup"
echo "==================================================="
echo "  Project:       $PROJECT_ID"
echo "  CloudNap SA:   $CLOUDNAP_SA"
echo "  Custom role:   $ROLE_ID"
echo "  Client SA:     ${CLIENT_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
echo "==================================================="
echo ""

# ---- 1. Enable required APIs ----
echo "[1/5] Enabling Compute Engine + Cloud DNS + IAM Credentials APIs..."
gcloud services enable \
    compute.googleapis.com \
    dns.googleapis.com \
    iamcredentials.googleapis.com \
    --project="$PROJECT_ID"

# ---- 2. Create or update the custom role ----
ROLE_YAML="$(dirname "$0")/cloudnap-role.yaml"
if [[ ! -f "$ROLE_YAML" ]]; then
    echo "[2/5] Downloading role definition..."
    ROLE_YAML="/tmp/cloudnap-role.yaml"
    curl -fsSL "https://raw.githubusercontent.com/cloudnap/gcp-setup/main/cloudnap-role.yaml" \
        -o "$ROLE_YAML"
fi

if gcloud iam roles describe "$ROLE_ID" --project="$PROJECT_ID" >/dev/null 2>&1; then
    echo "[2/5] Updating existing custom role '$ROLE_ID'..."
    gcloud iam roles update "$ROLE_ID" \
        --project="$PROJECT_ID" \
        --file="$ROLE_YAML" >/dev/null
else
    echo "[2/5] Creating custom role '$ROLE_ID'..."
    gcloud iam roles create "$ROLE_ID" \
        --project="$PROJECT_ID" \
        --file="$ROLE_YAML" >/dev/null
fi

# ---- 3. Create the client-side service account ----
CLIENT_SA="${CLIENT_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

if gcloud iam service-accounts describe "$CLIENT_SA" --project="$PROJECT_ID" >/dev/null 2>&1; then
    echo "[3/5] Service account '$CLIENT_SA' already exists — reusing."
else
    echo "[3/5] Creating service account '$CLIENT_SA'..."
    gcloud iam service-accounts create "$CLIENT_SA_NAME" \
        --project="$PROJECT_ID" \
        --display-name="CloudNap Connector" \
        --description="Impersonated by CloudNap SaaS for VM + DNS management" >/dev/null
fi

# ---- 4. Bind the custom role to the client SA ----
echo "[4/5] Binding custom role to $CLIENT_SA..."
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${CLIENT_SA}" \
    --role="projects/${PROJECT_ID}/roles/${ROLE_ID}" \
    --condition=None \
    >/dev/null

# ---- 5. Allow CloudNap to impersonate this SA ----
echo "[5/5] Granting CloudNap's SA permission to impersonate $CLIENT_SA..."
gcloud iam service-accounts add-iam-policy-binding "$CLIENT_SA" \
    --project="$PROJECT_ID" \
    --member="serviceAccount:${CLOUDNAP_SA}" \
    --role="roles/iam.serviceAccountTokenCreator" \
    >/dev/null

# ---- Done. Print what the user needs to paste. ----
echo ""
echo "==================================================="
echo "  Setup complete! Paste these into CloudNap:"
echo "==================================================="
echo ""
echo "  Service account email:"
echo "    ${CLIENT_SA}"
echo ""
echo "  Project ID:"
echo "    ${PROJECT_ID}"
echo ""
echo "==================================================="
echo ""
echo "To disconnect CloudNap later, run:"
echo "  gcloud projects remove-iam-policy-binding $PROJECT_ID \\"
echo "      --member=\"serviceAccount:${CLIENT_SA}\" \\"
echo "      --role=\"projects/${PROJECT_ID}/roles/${ROLE_ID}\""
echo "  gcloud iam service-accounts delete ${CLIENT_SA} --project=${PROJECT_ID}"
echo "  gcloud iam roles delete ${ROLE_ID} --project=${PROJECT_ID}"
echo ""
