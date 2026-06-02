# BIDX Step 2 — Azure + GitHub Actions

Deploy the scraper to Azure Container Apps **Job** (no Docker Desktop on your PC).  
GitHub Actions builds the image in **Azure Container Registry** using `az acr build`.

Power Automate triggers the job at 6am (manual trigger mode — no built-in cron unless you enable it).

---

## Prerequisites

- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-windows) — `az login`
- Contributor (or equivalent) on a subscription
- GitHub repo: [sebastians-droid/job_search](https://github.com/sebastians-droid/job_search)

---

## 1. Configure names

```powershell
cd azure
Copy-Item parameters.example.json parameters.json
```

Edit `parameters.json`:

| Parameter | Rule |
|---|---|
| `acrName` | Globally unique, alphanumeric only, e.g. `bidxacrswank001` |
| `keyVaultName` | Globally unique, e.g. `bidx-kv-swank001` |
| `enableSchedule` | Keep `false` if Power Automate runs the job |
| `containerImage` | Leave placeholder until first `az acr build` |

Pick a resource group name, e.g. `bidx-rg`.

---

## 2. Deploy Azure resources

```powershell
.\deploy.ps1 -ResourceGroup bidx-rg
```

This creates:

- Log Analytics + Container Apps Environment
- Azure Container Registry (ACR)
- Key Vault (RBAC)
- Managed identity for the job
- Container Apps Job (`bidx-scraper-job`) — **Manual** trigger by default

Then builds `bidx-scraper:latest` in ACR and updates the job image.

---

## 3. Store BIDX credentials in Key Vault

```powershell
az keyvault secret set --vault-name <keyVaultName> --name BIDX-USERNAME --value "contractbidding@example.com"
az keyvault secret set --vault-name <keyVaultName> --name BIDX-PASSWORD --value "your-password"
```

Secret names must match exactly: `BIDX-USERNAME`, `BIDX-PASSWORD`.

---

## 4. Test a manual run

```powershell
az containerapp job start --name bidx-scraper-job --resource-group bidx-rg
az containerapp job execution list --name bidx-scraper-job --resource-group bidx-rg -o table
```

View logs in Azure Portal → Container Apps → Jobs → Executions, or:

```powershell
az containerapp job logs show --name bidx-scraper-job --resource-group bidx-rg
```

---

## 5. Wire GitHub Actions

```powershell
.\create-github-sp.ps1 -ResourceGroup bidx-rg -AcrName <yourAcrName>
```

In GitHub → **Settings → Secrets and variables → Actions**:

| Secret | Value |
|---|---|
| `AZURE_CREDENTIALS` | Full JSON from the script |
| `ACR_NAME` | Your registry name |
| `AZURE_RESOURCE_GROUP` | e.g. `bidx-rg` |
| `AZURE_CONTAINER_APP_JOB_NAME` | `bidx-scraper-job` |

| Variable | Value |
|---|---|
| `BIDX_DEPLOY_JOB` | `true` (after first Azure deploy) |

Push to `main` — workflow `.github/workflows/build-push-acr.yml` rebuilds the image on each push.

---

## 6. Power Automate — daily 6am Eastern

**Trigger:** Recurrence — Daily 6:00 AM — Time zone **Eastern Time (US & Canada)**

**Action:** Azure Resource Manager — HTTP or managed connector

Start the job:

```
POST https://management.azure.com/subscriptions/{subscriptionId}/resourceGroups/{resourceGroup}/providers/Microsoft.App/jobs/bidx-scraper-job/start?api-version=2024-03-01
```

Authentication: **Active Directory OAuth** (your account or a dedicated app with permission to start jobs on the resource group).

Subscription ID: `az account show --query id -o tsv`

---

## Optional: Azure cron instead of Power Automate

Redeploy with `"enableSchedule": true` in `parameters.json` (cron `0 11 * * *` UTC ≈ 6am EST).

---

## Cost note

Rough monthly (varies by region/usage):

- ACR Basic — ~$5
- Container Apps Job — pay per execution (~1–2 vCPU-hours/day)
- Key Vault — minimal

---

## Troubleshooting

| Issue | Fix |
|---|---|
| Job fails immediately | Check Key Vault secrets exist; job identity has **Key Vault Secrets User** |
| Image pull error | Run `deploy.ps1` again or push to `main` to rebuild ACR image |
| GitHub workflow fails | Verify `AZURE_CREDENTIALS`, `ACR_NAME`, `az login` subscription matches RG |
| Scraper timeout | Job timeout is 3 hours (`jobReplicaTimeout` in Bicep) |

---

## What Step 3 adds

SharePoint Lists + Microsoft Graph API in the scraper (no Azure infra changes required beyond Graph app secrets in Key Vault).
