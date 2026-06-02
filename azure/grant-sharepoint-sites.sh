#!/bin/bash
# Grant BIDX app write access to milling + grinding SharePoint sites (run AFTER Sites.Selected admin consent).
#
# Edit the three variables below, then:  bash grant-sharepoint-sites.sh

MILLING_SITE_URL="https://YOUR-TENANT.sharepoint.com/sites/YOUR-MILLING-SITE"
GRINDING_SITE_URL="https://YOUR-TENANT.sharepoint.com/sites/YOUR-GRINDING-SITE"
APP_CLIENT_ID="PASTE-GRAPH-CLIENT-ID-FROM-ENTRA"

set -euo pipefail

grant_site() {
  local SITE_URL="$1"
  echo "Granting app on: $SITE_URL"

  local ENCODED
  ENCODED=$(python3 -c "import urllib.parse; print(urllib.parse.quote('''${SITE_URL}''', safe=''))")

  local SITE_ID
  SITE_ID=$(az rest --method GET \
    --uri "https://graph.microsoft.com/v1.0/sites/${ENCODED}" \
    --query id -o tsv)

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

grant_site "${MILLING_SITE_URL}"
grant_site "${GRINDING_SITE_URL}"
echo "Done. Both sites should authorize the app."
