#!/usr/bin/env bash
# CloudNap GCP connector setup
# ---------------------------------------------------------------
# This script:
#   1. Enables the Compute Engine API (+ Cloud DNS if DNS is opted in)
#   2. Creates a least-privilege custom IAM role (CloudNap Instance Operator)
#         - Compute-only by default (list / get / start / stop)
#         - DNS permissions added ONLY when ENABLE_DNS=yes / --enable-dns
#   3. Creates a dedicated service account (cloudnap-connector)
#   4. Binds the custom role to that SA
#   5. Grants CloudNap's SA permission to impersonate it
#
# At the end it prints the values you paste back into CloudNap:
#   - Service account email
#   - Project ID
#   - DNS enabled (yes/no)
#
# Safe to re-run — every step is idempotent. Re-running with a different
# ENABLE_DNS value will swap the role definition in place.
# ---------------------------------------------------------------

set -euo pipefail

# ---- Configurable: override via env vars if you like ----
CLOUDNAP_SA="${CLOUDNAP_SA:-cloudnap-admin@gen-lang-client-0395474001.iam.gserviceaccount.com}"
ROLE_ID="${ROLE_ID:-cloudNapInstanceOperator}"

# ---- Per-account connector token (REQUIRED) ----
# CloudNap generates a unique token per cloud account and bakes it into the
# service-account local-part:
#     cloudnap-connector-<token>@<projectId>.iam.gserviceaccount.com
# This is the GCP-equivalent of AWS's externalId — it stops a third party
# who only knows your project ID from being able to register your project
# under their own CloudNap org.
#
# Pass it as CLOUDNAP_TOKEN=<token> when invoking this script. The token
# must be 11 lowercase alphanumeric characters, starting with a letter.
if [[ -z "${CLOUDNAP_TOKEN:-}" ]]; then
    echo "ERROR: CLOUDNAP_TOKEN is required." >&2
    echo "Copy the token shown in the CloudNap UI and re-run as:" >&2
    echo "    CLOUDNAP_TOKEN=<token> bash setup.sh" >&2
    exit 1
fi
if [[ ! "$CLOUDNAP_TOKEN" =~ ^[a-z][a-z0-9]{10}$ ]]; then
    echo "ERROR: CLOUDNAP_TOKEN must be 11 lowercase alphanumerics, starting with a letter." >&2
    exit 1
fi
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
    DNS_LABEL="no (compute-only; re-run with --enable-dns to turn on)"
fi
if [[ "$BILLING_ENABLED" -eq 1 ]]; then
    BILLING_LABEL="yes (Recommender + Monitoring + Asset + Billing APIs, read-only)"
else
    BILLING_LABEL="no (re-run with --enable-billing to turn on)"
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
    # Recommender, Monitoring, Asset Inventory, Cloud Billing, Resource Manager
    APIS+=(
        recommender.googleapis.com
        monitoring.googleapis.com
        cloudasset.googleapis.com
        cloudbilling.googleapis.com
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
SCRIPT_DIR="$(dirname "$0")"
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
REMOTE_ROLE_YAML="https://raw.githubusercontent.com/Bhushan21z/cloudnap-gcp-setup/main/$ROLE_BASENAME"

if [[ ! -f "$ROLE_YAML" ]]; then
    echo "[2/5] Downloading role definition..."
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
echo "  Setup complete! Paste this into CloudNap:"
echo "==================================================="
echo ""
echo "  Project ID:"
echo "    ${PROJECT_ID}"
echo ""
echo "  (CloudNap already knows your connector token — it"
echo "   computes the service account email automatically.)"
echo ""
echo "  For reference, the SA created was:"
echo "    ${CLIENT_SA}"
echo ""
if [[ "$DNS_ENABLED" -eq 1 ]]; then
    echo "  DNS management:  enabled"
else
    echo "  DNS management:  disabled"
    echo "     (re-run with  ENABLE_DNS=yes bash setup.sh  to turn it on)"
fi
if [[ "$BILLING_ENABLED" -eq 1 ]]; then
    echo "  Billing dashboard: enabled"
else
    echo "  Billing dashboard: disabled"
    echo "     (re-run with  ENABLE_BILLING=yes bash setup.sh  to turn it on)"
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
