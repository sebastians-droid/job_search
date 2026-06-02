# BIDX V1 — Finish checklist (do now vs after Graph consent)

Azure job **Succeeded** ✓ | SharePoint lists + folders ✓ | Graph consent pending.

---

## Part 1 — Power Automate: daily 6:00 AM Eastern start

This only **starts** `bidx-scraper-job`. It does not need SharePoint Graph consent.

### Values you need

| Setting | Value |
|---|---|
| Subscription ID | `50547101-40d2-4e1e-9e39-10546f8ceb2a` |
| Resource group | `swank-bidx` |
| Job name | `bidx-scraper-job` |
| API version | `2024-03-01` |

**Start URL (copy exactly, one line):**

```text
https://management.azure.com/subscriptions/50547101-40d2-4e1e-9e39-10546f8ceb2a/resourceGroups/swank-bidx/providers/Microsoft.App/jobs/bidx-scraper-job/start?api-version=2024-03-01
```

### Create the flow

1. Open [https://make.powerautomate.com](https://make.powerautomate.com) → **Create** → **Scheduled cloud flow**.
2. Name: `BIDX Daily Scraper 6AM`.
3. Run this flow: **Day** → **6:00 AM** → Time zone **(UTC-05:00) Eastern Time (US & Canada)** → **Create**.

### Add the start action (try in order)

#### Option A — Container Apps connector (easiest if you see it)

1. **+ New step** → search **Container Apps**.
2. Pick an action like **Execute job** / **Start job** (wording varies).
3. Subscription: **Analytics** → Resource group: **swank-bidx** → Job: **bidx-scraper-job**.

#### Option B — HTTP + signed-in work account (most common)

1. **+ New step** → **HTTP**.
2. **Method:** `POST`
3. **URI:** paste the Start URL above.
4. **Authentication:** `Active Directory OAuth`
5. **Authority:** `https://login.microsoftonline.com`
6. **Tenant:** your directory ID (Entra → Overview → **Tenant ID**)
7. **Audience:** `https://management.azure.com`
8. **Credential type:** **Shared application** only if IT gave you an app; otherwise choose sign-in as **your work account** when prompted.
9. First save will ask you to **sign in** with the same account that can start the job in Azure (needs **Contributor** on `swank-bidx`, or a role that includes Container Apps Job start).

**Headers (optional):** `Content-Type` = `application/json`  
**Body:** leave empty.

### Test and turn on

1. **Save** → **Test** → **Manually**.
2. In Azure Portal → **Container App Jobs** → **bidx-scraper-job** → **Execution history** → new run should appear within a minute.
3. If test works: **Turn on** the flow.

### If HTTP returns 403

- Your account needs permission on `swank-bidx` (Contributor is typical).
- Or IT creates a small app registration for Power Automate with permission to start jobs on that resource group.

### Failure notification (optional)

1. On the HTTP step → **⋯** → **Configure run after** → check **has failed**.
2. Add **Send an email (V2)** or **Post message in Teams** with error body.

---

## Part 2 — GitHub Actions: auto-build image on push

Rebuilds `bidx-scraper:latest` in ACR when you push to `main`. No SharePoint needed.

### Step 2a — Create service principal (Cloud Shell, Bash)

```bash
az account set --subscription "Analytics"

# Creates SP with Contributor on swank-bidx + AcrPush on your registry
cd ~/job_search/azure
pwsh ./create-github-sp.ps1 -ResourceGroup swank-bidx -AcrName bidxacrswank2026
```

Copy the **entire JSON line** printed after `AZURE_CREDENTIALS`.

If `create-github-sp.ps1` fails on permissions, ask IT for a service principal with:

- **Contributor** on resource group `swank-bidx`
- **AcrPush** on `bidxacrswank2026`

### Step 2b — GitHub secrets and variable

[github.com/sebastians-droid/job_search](https://github.com/sebastians-droid/job_search) → **Settings** → **Secrets and variables** → **Actions**

**Secrets** → New repository secret:

| Name | Value |
|---|---|
| `AZURE_CREDENTIALS` | Full JSON from Step 2a |
| `ACR_NAME` | `bidxacrswank2026` |
| `AZURE_RESOURCE_GROUP` | `swank-bidx` |
| `AZURE_CONTAINER_APP_JOB_NAME` | `bidx-scraper-job` |

**Variables** tab → New repository variable:

| Name | Value |
|---|---|
| `BIDX_DEPLOY_JOB` | `true` |

### Step 2c — Verify

1. **Actions** → **Build and push to ACR** → **Run workflow** → branch `main`.
2. Wait for green checkmark (~15–20 min).
3. Optional: Portal → `bidxacrswank2026` → **Repositories** → `bidx-scraper` tag `latest` updated.

---

## Part 3 — After Graph admin consent (Key Vault + job env)

When your Entra app has **Sites.Selected** + both sites granted, add these secrets to **`bidx-kv-swank`**:

| Secret name | Purpose |
|---|---|
| `GRAPH-CLIENT-ID` | App registration client ID |
| `GRAPH-CLIENT-SECRET` | Client secret value |
| `GRAPH-TENANT-ID` | Tenant ID |
| `SHAREPOINT-MILLING-SITE-URL` | Full milling site URL |
| `SHAREPOINT-GRINDING-SITE-URL` | Full grinding site URL |
| `SHAREPOINT-MILLING-FOLDER-PATH` | e.g. `Shared Documents/YourFolder` |
| `SHAREPOINT-GRINDING-FOLDER-PATH` | e.g. `Shared Documents/YourFolder` |
| `SHAREPOINT-MILLING-LIST` | `Lettings_Milling` (default if omitted) |
| `SHAREPOINT-GRINDING-LIST` | `Lettings_Grinding` (default if omitted) |

Then enable SharePoint on the job (Portal → **bidx-scraper-job** → **Containers** → environment variables):

| Name | Value |
|---|---|
| `SHAREPOINT_ENABLED` | `true` |

Redeploy image after Step 4 code is merged (GitHub Actions or `az acr build`).

---

## Part 4 — What’s already in code (waiting for consent)

- `sharepoint_config.py` / `graph_client.py` / `sharepoint_publish.py`
- Scraper calls SharePoint only when `SHAREPOINT_ENABLED=true`
- Default: **off** (same behavior as your successful run)

---

## Done when

- [ ] Power Automate runs daily 6 AM ET
- [ ] GitHub Actions green on workflow
- [ ] Graph consent + site grants
- [ ] Key Vault Graph + site URL secrets
- [ ] `SHAREPOINT_ENABLED=true` on job
- [ ] One test run → rows in lists + Excel in both folders
