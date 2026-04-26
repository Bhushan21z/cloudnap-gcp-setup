#!/usr/bin/env bash
# CloudNap GCP connector setup
# ---------------------------------------------------------------
# Usage (copy the exact command from your CloudNap setup screen):
#
#   CLOUDNAP_TOKEN=<token> ENABLE_DNS=yes ENABLE_BILLING=yes bash setup.sh
#
# CLOUDNAP_TOKEN is required — it uniquely identifies your CloudNap org
# and is used to name the service account:
#   cloudnap-connector-<token>@<project>.iam.gserviceaccount.com
#
# This script:
#   1. Enables the Compute Engine API (+ Cloud DNS / Billing if opted in)
#   2. Creates a least-privilege custom IAM role (CloudNap Instance Operator)
#         - Compute-only by default (list / get / start / stop)
#         - DNS permissions added ONLY when ENABLE_DNS=yes
#         - Billing permissions added ONLY when ENABLE_BILLING=yes
#   3. Creates a dedicated service account cloudnap-connector-<token>
#   4. Binds the custom role to that SA
#   5. Grants CloudNap's SA permission to impersonate it
#
# At the end it prints the values you paste back into CloudNap:
#   - Service account email
#   - Project ID
#
# Safe to re-run — every step is idempotent. Re-running with different
# ENABLE_DNS / ENABLE_BILLING values will swap the role definition in place.
# ---------------------------------------------------------------

set -euo pipefail

# ---- CLOUDNAP_TOKEN: required, uniquely identifies your org ----
# Accept either env var or --token= CLI flag.
CLOUDNAP_TOKEN="${CLOUDNAP_TOKEN:-}"
for arg in "$@"; do
    case "$arg" in
        --token=*) CLOUDNAP_TOKEN="${arg#--token=}" ;;
    esac
done

if [[ -z "$CLOUDNAP_TOKEN" ]]; then
    echo ""
    echo "ERROR: CLOUDNAP_TOKEN is required." >&2
    echo "       Copy the full command from your CloudNap GCP setup screen." >&2
    echo "       It looks like:" >&2
    echo "         CLOUDNAP_TOKEN=<token> ENABLE_DNS=yes ENABLE_BILLING=yes bash setup.sh" >&2
    echo ""
    exit 1
fi

# ---- Configurable: override via env vars if you like ----
CLOUDNAP_SA="${CLOUDNAP_SA:-cloudnap-admin@gen-lang-client-0395474001.iam.gserviceaccount.com}"
ROLE_ID="${ROLE_ID:-cloudNapInstanceOperator}"
# Service account name includes your org token so CloudNap can identify it.
CLIENT_SA_NAME="${CLIENT_SA_NAME:-cloudnap-connector-${CLOUDNAP_TOKEN}}"

# ---- DNS + Billing flags: off/on by default, user can toggle ----
# Accept either an env var or a CLI flag so the Cloud Shell tutorial
# and the fallback one-liner can both toggle them easily.
ENABLE_DNS="${ENABLE_DNS:-no}"
# Billing is ON by default — highest-value optional permission.
ENABLE_BILLING="${ENABLE_BILLING:-yes}"
for arg in "$@"; do
    case "$arg" in
        --enable-dns|--dns)         ENABLE_DNS="yes" ;;
        --no-dns)                   ENABLE_DNS="no" ;;
        --enable-billing|--billing) ENABLE_BILLING="yes" ;;
        --no-billing)               ENABLE_BILLING="no" ;;
    esac
done
case "$(echo "$ENABLE_DNS" | tr '[:upper:]' '[:lower:]')" in
    yes|y|true|1|on) DNS_ENABLED=1 ;;
    *)               DNS_ENABLED=0 ;;
esac
case "$(echo "$ENABLE_BILLING" | tr '[:upper:]' '[:lower:]')" in
    yes|y|true|1|on) BILLING_ENABLED=1 ;;
    *)               BILLING_ENABLED=0 ;;
esac

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

# Human-friendly labels for the header + final summary
if [[ "$DNS_ENABLED" -eq 1 ]]; then
    DNS_LABEL="yes (Cloud DNS API + record-set permissions)"
else
    DNS_LABEL="no (compute-only; re-run with ENABLE_DNS=yes to turn on)"
fi
if [[ "$BILLING_ENABLED" -eq 1 ]]; then
    BILLING_LABEL="yes (Recommender + Monitoring + Asset + Billing APIs, read-only)"
else
    BILLING_LABEL="no (re-run with ENABLE_BILLING=yes to turn on)"
fi

echo ""
echo "==================================================="
echo "  CloudNap GCP connector setup"
echo "==================================================="
echo "  Project:       $PROJECT_ID"
echo "  CloudNap SA:   $CLOUDNAP_SA"
echo "  Custom role:   $ROLE_ID"
echo "  Client SA:     ${CLIENT_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
echo "  DNS:           $DNS_LABEL"
echo "  Billing:       $BILLING_LABEL"
echo "==================================================="
echo ""

# ---- 1. Enable required APIs ----
APIS=(compute.googleapis.com iamcredentials.googleapis.com)
[[ "$DNS_ENABLED" -eq 1 ]] && APIS+=(dns.googleapis.com)
if [[ "$BILLING_ENABLED" -eq 1 ]]; then
    # Recommender, Monitoring, Asset Inventory, Cloud Billing, BigQuery, Resource Manager
    APIS+=(
        recommender.googleapis.com
        monitoring.googleapis.com
        cloudasset.googleapis.com
        cloudbilling.googleapis.com
        bigquery.googleapis.com
        cloudresourcemanager.googleapis.com
        serviceusage.googleapis.com
    )
fi
echo "[1/5] Enabling APIs: ${APIS[*]}"
gcloud services enable "${APIS[@]}" --project="$PROJECT_ID"

# ---- Helper: retry a gcloud command a few times (handles IAM eventual consistency) ----
retry() {
    local -r max_attempts=$1
    local -r sleep_seconds=$2
    local -r label=$3
    shift 3
    local attempt=1
    until "$@" >/dev/null 2>&1; do
        if [[ $attempt -ge $max_attempts ]]; then
            echo "      ERROR: ${label} failed after ${max_attempts} attempts. Re-running:" >&2
            "$@"   # run once more without swallowing output so the real error is visible
            return 1
        fi
        echo "      ${label} attempt ${attempt} failed (propagation lag), retrying in ${sleep_seconds}s..."
        sleep "$sleep_seconds"
        attempt=$((attempt + 1))
    done
}

# ---- 2. Pick the right role YAML (DNS + billing combinations) ----
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ "$DNS_ENABLED" -eq 1 && "$BILLING_ENABLED" -eq 1 ]]; then
    ROLE_BASENAME="cloudnap-role-dns-billing.yaml"
elif [[ "$DNS_ENABLED" -eq 1 ]]; then
    ROLE_BASENAME="cloudnap-role-dns.yaml"
elif [[ "$BILLING_ENABLED" -eq 1 ]]; then
    ROLE_BASENAME="cloudnap-role-billing.yaml"
else
    ROLE_BASENAME="cloudnap-role.yaml"
fi
ROLE_YAML="$SCRIPT_DIR/$ROLE_BASENAME"
# Fallback URL — path includes cloudnap-gcp/ subdir matching the repo workspace
REMOTE_ROLE_YAML="https://raw.githubusercontent.com/Bhushan21z/cloudnap-gcp-setup/main/cloudnap-gcp/$ROLE_BASENAME"

if [[ ! -f "$ROLE_YAML" ]]; then
    echo "[2/5] Downloading role definition from GitHub..."
    ROLE_YAML="/tmp/$(basename "$ROLE_YAML")"
    curl -fsSL "$REMOTE_ROLE_YAML" -o "$ROLE_YAML"
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

    # Wait for the SA to show up in IAM (eventual consistency — can take 5-30s)
    echo "      Waiting for service account to propagate..."
    retry 15 3 "SA describe" \
        gcloud iam service-accounts describe "$CLIENT_SA" --project="$PROJECT_ID"
    sleep 3  # extra buffer before first policy binding
fi

# ---- 4. Bind the custom role to the client SA (with retry) ----
echo "[4/5] Binding custom role to $CLIENT_SA..."
retry 6 5 "Role binding" \
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:${CLIENT_SA}" \
        --role="projects/${PROJECT_ID}/roles/${ROLE_ID}" \
        --condition=None

# ---- 5. Allow CloudNap to impersonate this SA (with retry) ----
echo "[5/5] Granting CloudNap's SA permission to impersonate $CLIENT_SA..."
retry 6 5 "Impersonation binding" \
    gcloud iam service-accounts add-iam-policy-binding "$CLIENT_SA" \
        --project="$PROJECT_ID" \
        --member="serviceAccount:${CLOUDNAP_SA}" \
        --role="roles/iam.serviceAccountTokenCreator"

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
if [[ "$DNS_ENABLED" -eq 1 ]]; then
    echo "  DNS management:  enabled"
else
    echo "  DNS management:  disabled"
    echo "     (re-run with  CLOUDNAP_TOKEN=${CLOUDNAP_TOKEN} ENABLE_DNS=yes bash setup.sh  to turn it on)"
fi
if [[ "$BILLING_ENABLED" -eq 1 ]]; then
    echo "  Billing dashboard: enabled"
    echo ""
    echo "  *** BigQuery billing export (one extra step) ***"
    echo "  The Billing Dashboard reads your GCP billing export from BigQuery."
    echo "  Grant the service account read access to that dataset:"
    echo ""
    echo "    bq add-iam-policy-binding \\"
    echo "      --member=\"serviceAccount:${CLIENT_SA}\" \\"
    echo "      --role=\"roles/bigquery.dataViewer\" \\"
    echo "      <your-billing-export-dataset>"
    echo ""
    echo "  Then enter the dataset + table name in CloudNap's Billing settings."
else
    echo "  Billing dashboard: disabled"
    echo "     (re-run with  CLOUDNAP_TOKEN=${CLOUDNAP_TOKEN} ENABLE_BILLING=yes bash setup.sh  to turn it on)"
fi
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
