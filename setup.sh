#!/usr/bin/env bash
#
# DEPRECATED shim.
#
# CloudNap's GCP installer is now backend-rendered per-tenant at
#   GET /api/setup/gcp/setup.sh?token=<per-tenant-token>
# so each organization gets a unique service-account name and the
# canonical role YAML is served from CloudNap's backend rather than
# github.com. See the backend templates in
#   backend/src/templates/gcp-setup.sh.template
#   backend/src/templates/gcp-roles/*.yaml
# for the authoritative versions.
#
# This file is kept only so existing bookmarks print a clear pointer.
#
set -euo pipefail
echo ""
echo "CloudNap GCP setup has moved to the backend-rendered installer."
echo ""
echo "1. Open your CloudNap dashboard → Connect GCP."
echo "2. Copy the one-liner shown on the setup page (it carries the"
echo "   per-tenant token and your project id)."
echo "3. Paste it into Cloud Shell."
echo ""
echo "Reviewing the exact script we will run:"
echo "   \${PUBLIC_API_URL}/api/setup/gcp/setup.sh?token=<your-token>"
echo ""
exit 2
