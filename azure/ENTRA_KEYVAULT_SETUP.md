# Entra app + Key Vault secrets (SharePoint)

Complete these before Graph admin consent is granted. Site grants run **after** consent.

---

## Part A — Entra app registration

1. [https://entra.microsoft.com](https://entra.microsoft.com) → **Applications** → **App registrations** → **New registration**
2. Name: `BIDX Scraper (Production)` → **Register**
3. Copy from **Overview**:
   - **Application (client) ID** → Key Vault `GRAPH-CLIENT-ID`
   - **Directory (tenant) ID** → Key Vault `GRAPH-TENANT-ID`
4. **API permissions** → **Add** → **Microsoft Graph** → **Application permissions** → **Sites.Selected** → **Add**
5. **Grant admin consent** — if you can; if not, IT must (app still created)
6. **Certificates & secrets** → **New client secret** → copy **Value** once → Key Vault `GRAPH-CLIENT-SECRET`

---

## Part B — Key Vault secrets (`bidx-kv-swank`)

Portal → **Key vaults** → **bidx-kv-swank** → **Secrets** → **Generate/Import**

| Secret name | Value |
|---|---|
| `GRAPH-CLIENT-ID` | From Entra Overview |
| `GRAPH-CLIENT-SECRET` | From client secret Value |
| `GRAPH-TENANT-ID` | From Entra Overview |
| `SHAREPOINT-MILLING-SITE-URL` | Full URL, e.g. `https://tenant.sharepoint.com/sites/MillingSite` |
| `SHAREPOINT-GRINDING-SITE-URL` | Full URL, e.g. `https://tenant.sharepoint.com/sites/GrindingSite` |
| `SHAREPOINT-MILLING-FOLDER-PATH` | e.g. `Shared Documents/BIDX` (your folder) |
| `SHAREPOINT-GRINDING-FOLDER-PATH` | e.g. `Shared Documents/BIDX` |
| `SHAREPOINT-MILLING-LIST` | `Lettings_Milling` (optional if default) |
| `SHAREPOINT-GRINDING-LIST` | `Lettings_Grinding` (optional) |
| `SHAREPOINT-PROPOSAL-FIELD` | `Title` if you renamed Title column; else `ProposalID` |

---

## Part C — After admin consent (site grants)

Edit and run in Cloud Shell:

```bash
cd ~/job_search/azure
nano grant-sharepoint-sites.sh   # set URLs + APP_CLIENT_ID
bash grant-sharepoint-sites.sh
```

---

## Part D — Wire secrets into the job (after consent + KV secrets exist)

Portal → **Container App Jobs** → **bidx-scraper-job** → **Secrets** / **Environment variables**

Add Key Vault references for each Graph/SharePoint secret (same pattern as BIDX login), plus:

| Env variable | Value |
|---|---|
| `SHAREPOINT_ENABLED` | `true` |

Until Part D is done, the job ignores SharePoint even if Key Vault has secrets.
