#!/bin/bash
# Grant BIDX app write access to milling + grinding SharePoint sites (run AFTER Sites.Selected admin consent).
#
# Prerequisite: Cloud Shell must be logged into the SAME Entra tenant as SharePoint:
#   az login --tenant YOUR-TENANT-ID
#   (Use Directory (tenant) ID from bidx-scraper app Overview — same as GRAPH-TENANT-ID in Key Vault.)
#
# Edit the three variables below, then:  bash grant-sharepoint-sites.sh

MILLING_SITE_URL="https://YOUR-TENANT.sharepoint.com/sites/YOUR-MILLING-SITE"
GRINDING_SITE_URL="https://YOUR-TENANT.sharepoint.com/sites/YOUR-GRINDING-SITE"
APP_CLIENT_ID="PASTE-GRAPH-CLIENT-ID-FROM-ENTRA"

set -euo pipefail

# Graph expects: GET /sites/{hostname}:/{path}  e.g. swankco.sharepoint.com:/sites/Milling
site_graph_uri() {
  local SITE_URL="$1"
  python3 - << PY
import urllib.parse
u = urllib.parse.urlparse("""${SITE_URL}""")
host = u.hostname
path = u.path.strip("/")
if not host or not path:
    raise SystemExit("Bad site URL (need https://host.sharepoint.com/sites/SiteName): ${SITE_URL}")
print(f"https://graph.microsoft.com/v1.0/sites/{host}:/{path}")
PY
}

grant_site() {
  local SITE_URL="$1"
  echo "Granting app on: $SITE_URL"

  local GRAPH_URI
  GRAPH_URI=$(site_graph_uri "${SITE_URL}")
  echo "  Graph: ${GRAPH_URI}"

  local SITE_ID
  SITE_ID=$(az rest --method GET --uri "${GRAPH_URI}" --query id -o tsv)

  echo "  Site ID: ${SITE_ID}"

  az rest --method POST \
    --uri "https://graph.microsoft.com/v1.0/sites/${SITE_ID}/permissions" \
    --headers "Content-Type=application/json" \
    --body "{
      \"roles\": [\"write\"],
      \"grantedToIdentities\": [{
        \"application\": {
          \"id\": \"${APP_CLIENT_ID}\",
          \"displayName\": \"BIDX Scraper (Production)\"
        }
      }]
    }"

  echo "  OK"
}

echo "Azure account (must match SharePoint tenant):"
az account show --query "{subscription:name, tenantId:tenantId, user:user.name}" -o table
echo ""

grant_site "${MILLING_SITE_URL}"
grant_site "${GRINDING_SITE_URL}"
echo "Done. Both sites should authorize the app."
