# BIDX Scraper — Cloud Migration Plan

> **Purpose of this document.** This is a handoff/context document. It explains where the BIDX scraper is today, where we want it to go, and the concrete steps to get there in two phases. The intended audience is someone (human or AI) helping plan or execute the migration who is coming in cold.

---

## 1. Current State

### What it does
A Python script (`bidx_full_scraper.py`) scrapes [BIDX](https://ui.bidx.com), a state DOT bid-letting portal, for ~25 state DOTs. For each DOT it visits the lettings page, walks every proposal, and extracts line items matching configured keywords or item numbers.

There are two scrape modes per DOT:
- **Milling** — keyword match against item number + description text.
- **Grinding / Grooving** — item-number match against a configured list of codes (tagged as either "Grinding" or "Grooving").

A DOT can have either mode, both, or neither.

### Stack
- **Language**: Python 3
- **Browser automation**: Selenium + headless Chrome
- **Parsing**: BeautifulSoup (lxml preferred)
- **Output**: openpyxl + pandas, with optional `win32com.client` (Excel COM) for autofit on Windows
- **Runs on**: a local Windows machine, manually

### Inputs
- `bidx_login.txt` — plaintext `username|password` credentials.
- `milling_config.xlsx` — per-DOT milling keywords.
- `grinding_grooving_config.xlsx` — per-DOT grinding and grooving item numbers.

### Outputs (today)
- `bidx_results_milling.xlsx` — one sheet per DOT, **new proposals only** (anything not seen in any prior run).
- `bidx_results_grinding_grooving.xlsx` — same structure for grinding/grooving.
- `bidx_milling_<DOT>_archive.xlsx` — per-DOT cumulative archive (every item ever seen).
- `bidx_grinding_<DOT>_archive.xlsx` — same for grinding.

### Key behaviors worth preserving
- Browser restart every 8 DOTs to avoid memory/session issues.
- Per-DOT failure isolation — one DOT failing doesn't kill the run.
- Login retry on failure.
- Excel output groups rows by Proposal ID with merged cells for shared header columns (Letting Date, Proposal ID, District, Project Description).

### Limitations driving the migration
- Runs only on one person's laptop, manually.
- Credentials in plaintext.
- "Current" output only shows **new** items — users can't see the full current letting picture, only the delta.
- No way for users to filter by the DOTs they care about.
- No per-user state (mark as reviewed / interested).
- No analytics on the archive.

---

## 2. Phased Goal

The migration is split into two deliberate phases. V1 ships fast and gives the team a usable daily output. V2 builds the polished UX on top of the foundation V1 puts in place.

### Core data flow (both phases)

```
Scrape → SharePoint Lists (source of truth) → Excel report (V1 consumption)
                                             → Power Apps canvas app (V2 consumption)
```

The SharePoint Lists are the real data store in both phases. The Excel file in V1 is a **generated report** produced from the Lists at the end of each run — not the source of truth. This means V2 is purely additive: point a canvas app at the lists that already exist, add the Reviews list, done. No data migration.

---

## 3. V1 — Excel on SharePoint (target: end of first week)

### What V1 delivers
- Scraper runs automatically at **6am ET daily** with no human involvement.
- Results saved to SharePoint Lists (milling + grinding, with archive logic).
- An Excel file with **one tab per DOT** (always — even if a DOT has zero results that day) generated from the Lists and uploaded to a SharePoint document library.
- A date-stamped copy saved alongside the latest file for a free daily history.
- Credentials secured in Azure Key Vault.
- Code versioned in GitHub with automated deployment to Azure.

### What V1 deliberately defers
- Power Apps canvas app (V2).
- Per-user marking / Reviews list (V2 — nothing to mark against until the app exists).
- Power Automate notifications (V2).
- Power BI dashboard (V2).

### V1 Architecture

```
┌─────────────────┐  GitHub Actions  ┌────────────────────────┐
│  GitHub repo    │ ───────────────▶ │  Azure Container       │
│  (scraper code, │                  │  Registry (image)      │
│   Dockerfile)   │                  └───────────┬────────────┘
└─────────────────┘                              │ pulled by
                                                 ▼
                                  ┌──────────────────────────────┐
        ┌─────────────────────────┤  Azure Container Apps Job    │
        │ pulls secrets           │  cron: 0 11 * * * (UTC)      │
        ▼ via managed identity    │  = 6am ET (EST)              │
┌─────────────────┐               └───────────┬──────────────────┘
│ Azure Key Vault │                           │ writes via Microsoft Graph API
│ (BIDX creds,    │                           ▼
│  Graph app sec) │    ┌──────────────────────────────────────────┐
└─────────────────┘    │  SharePoint Lists                        │
                       │   • Lettings_Milling  (Status col)       │
                       │   • Lettings_Grinding (Status col)       │
                       └──────────────────┬───────────────────────┘
                                          │ queried at end of run
                                          ▼
                       ┌──────────────────────────────────────────┐
                       │  SharePoint Document Library             │
                       │   • bidx_milling_latest.xlsx             │
                       │   • bidx_milling_2026-06-01.xlsx         │
                       │   • bidx_grinding_latest.xlsx            │
                       │   • bidx_grinding_2026-06-01.xlsx        │
                       └──────────────────────────────────────────┘
```

### V1 Excel file behavior
- Two files: `bidx_milling_latest.xlsx` and `bidx_grinding_latest.xlsx`. Both overwritten daily.
- A date-stamped copy written alongside each run (e.g. `bidx_milling_2026-06-01.xlsx`). Free daily snapshot history.
- **Every DOT always gets a tab**, even if it has zero results. Empty tabs are preferable to missing tabs — users build muscle memory around where to find their state.
- Tab order is **consistent day-to-day** — alphabetical by DOT name, or matching the config file order. Decided at implementation time, never changes after.
- Cell merging and column formatting preserved from the current script (grouped by Proposal ID).
- `win32com.client` (Windows-only) is dropped. The openpyxl path handles all formatting.

### V1 diff / archive logic
The Lists are the state. The diff runs per-DOT after each successful scrape:

1. Query the List for all `Status=Current` rows for this DOT.
2. Compare against today's scraped ProposalIDs.
3. **New items** (in today's scrape, not in List): insert with `Status=Current`, `FirstSeenOn=today`.
4. **Returning items** (in both): update `LastSeenOn=today`. No other changes.
5. **Fallen-off items** (in List as `Current`, not in today's scrape): flip to `Status=Archived`, set `ArchivedOn=today`.
6. **If the DOT scrape failed**: do nothing — leave all existing rows untouched. This rule is critical. Without it, a BIDX timeout falsely archives an entire DOT's inventory.

After all DOTs are processed, query for `Status=Current` across all DOTs, generate the Excel, upload.

---

## 4. V2 — Power Apps UX (build after V1 is stable)

### What V2 adds on top of V1
- **Power Apps canvas app**: DOT filter, proposal list, detail pane, mark buttons.
- **Reviews list**: per-user marks (`Interested` / `Not Interested` / `Reviewed`) keyed by ProposalID + AAD user. User state survives daily scrape refreshes.
- **Power Automate notifications**: daily Teams channel digest of new items, grouped by DOT. Optional per-user subscription by DOT.
- **Power BI dashboard** (optional): archive analytics — items per DOT over time, average shelf life, keyword hit rates.

### Why V2 is clean to add
The SharePoint Lists already exist from V1. V2 requires:
- Adding the Reviews list (new).
- Building the canvas app on top of existing lists (no schema change to Lettings lists).
- Adding Power Automate flows (no code change to scraper).
- Power BI connects directly to Lists.

No data migration. No scraper changes. The Excel output can keep running in parallel for users who prefer it.

### V2 Architecture (adds to V1)

```
SharePoint Lists (from V1)
        │
        ├──▶ Power Apps canvas app
        │     • DOT picker (filter to 1 or many)
        │     • Proposal list with user marks shown inline
        │     • Mark as Interested / Not Interested / Reviewed
        │
        ├──▶ Reviews List (new in V2)
        │     • ProposalID + AAD User + Mark + Notes + MarkedOn
        │
        ├──▶ Power Automate
        │     • Daily Teams post: new Current items by DOT
        │     • Optional: per-user DOT subscriptions
        │
        └──▶ Power BI (optional)
              • Archive analytics dashboard
```

---

## 5. Data Model (SharePoint Lists)

### `Lettings_Milling`
| Column | Type | Notes |
|---|---|---|
| ProposalID | Single line, indexed | Natural key |
| DOT | Choice, indexed | One of the ~25 DOTs |
| LettingDate | Date | |
| District | Single line | |
| ProjectDescription | Multi-line | |
| ItemNumber | Single line | |
| Description | Multi-line | |
| Unit | Single line | |
| Quantity | Number | |
| FirstSeenOn | Date | Set on insert |
| LastSeenOn | Date | Updated each run item appears |
| Status | Choice: `Current` / `Archived`, indexed | |
| ArchivedOn | Date | Set when flipped to Archived |

### `Lettings_Grinding`
Same as above plus a `Type` column (`Grinding` or `Grooving`).

### `Reviews` *(V2 only)*
| Column | Type | Notes |
|---|---|---|
| ProposalID | Single line, indexed | Matches Lettings list |
| User | Person | AAD user |
| Mark | Choice: `Interested` / `Not Interested` / `Reviewed` | |
| Notes | Multi-line | Optional |
| MarkedOn | Date | |

### `Config` *(optional — either phase)*
If non-developers need to edit DOT keywords or item numbers without touching the repo, mirror `milling_config.xlsx` and `grinding_grooving_config.xlsx` as a SharePoint list. Otherwise leave them in the repo.

---

## 6. V1 Implementation Steps

### Step 1 — Code prep & repo hygiene
- Confirm `bidx_login.txt` is in `.gitignore` and has never been committed (rewrite history if it has).
- Refactor credential loading to read from environment variables (Key Vault injects these at runtime); keep file fallback for local dev only.
- Remove `win32com.client` import and the COM autofit path entirely — Linux containers can't run it. The openpyxl fallback handles all formatting.
- Write a `Dockerfile`: Python base image, install Chrome + Chromedriver (or Playwright — see open decisions).
- Run the script end-to-end inside the container locally and confirm output matches the current laptop run.

### Step 2 — Azure infrastructure
- Create: Resource Group, Container Registry, Container Apps Environment, Key Vault.
- Store BIDX credentials in Key Vault. Assign managed identity to the Container App; grant it Key Vault Secrets User role.
- GitHub Actions workflow: on push to `main`, build image, push to ACR.
- Define the Container Apps Job with cron `0 11 * * *` (6am ET / EST). Confirm it pulls from ACR and reads secrets.
- Add an HTTP trigger to the job so it can also be invoked on demand (useful for testing and for any future Power Automate button).

### Step 3 — SharePoint lists & Graph API access
- Register an Azure AD app for the scraper. Grant `Sites.ReadWrite.All` (or `Sites.Selected` scoped to the specific site if IT requires it).
- Store the app's client ID and secret in Key Vault.
- Create `Lettings_Milling` and `Lettings_Grinding` lists with the schema above. Index `ProposalID`, `DOT`, `Status`.
- Write a Graph API client module in the scraper: handles auth (client credentials flow), upsert (insert or update by ProposalID), batch status updates, and list queries with OData filters.
- Create the SharePoint document library for Excel output.

### Step 4 — Refactor scraper output
- Replace local Excel writes with the Scrape → List → Excel flow:
  1. Scrape all DOTs (existing logic, unchanged).
  2. Per successfully-scraped DOT: run diff logic against List, write inserts/updates/archives via Graph.
  3. After all DOTs complete: query `Status=Current` across all DOTs, generate both Excel files (one tab per DOT, always, alphabetical tab order), upload to document library as `*_latest.xlsx` and `*_YYYY-MM-DD.xlsx`.
- Preserve merged-cell formatting and column autofit (openpyxl only).
- Confirm the per-DOT failure isolation rule: failed DOTs log a warning and are skipped entirely — no List writes for that DOT that run.

### Step 5 — End-to-end test & go-live
- Run against a single DOT first, verify List rows and Excel output.
- Run against all DOTs, verify tab count (every DOT present), merged formatting, date-stamped file.
- Confirm the archive flip works: manually remove a ProposalID from BIDX test data (or mock it), re-run, verify it moves to `Status=Archived`.
- Schedule the first real 6am run. Share the SharePoint document library link with the team.

---

## 7. Open Decisions

Resolve before starting Step 1:

1. **BIDX terms of service** — confirm scraping is permitted. Check whether they offer an API or RSS feed.
2. **Selenium vs Playwright** — keeping Selenium minimizes code changes. Playwright is cleaner for containerization and long-term maintenance but requires rewriting the browser automation layer (~2–3 extra days).
3. **Config files in repo or SharePoint** — repo is simpler; SharePoint List lets non-developers edit keywords without a deployment. V1 can use repo; migrate in V2 if needed.
4. **IT / AAD access** — who creates the app registration and grants `Sites.ReadWrite.All`? This is usually the biggest schedule risk. Start the request immediately.
5. **Tab order in Excel** — alphabetical by DOT name recommended. Confirm with the team whether they'd prefer the config file order instead.
6. **DST handling for the 6am ET schedule** — `0 11 * * *` UTC = 6am EST (winter). `0 10 * * *` UTC = 6am EDT (summer). Options: run both and let the script no-op on the duplicate, or just accept the 1-hour shift twice a year and use a single cron.

---

## 8. Time Estimates

### V1
| Step | Effort |
|---|---|
| 1. Code prep & Docker | 1–2 days |
| 2. Azure infra & CI/CD | 2–3 days |
| 3. SharePoint lists & Graph auth | 0.5–1 day |
| 4. Refactor output + diff logic | 1–2 days |
| 5. End-to-end test & go-live | 1 day |
| **Total focused work** | **~1 week** |

**End-of-week is achievable if** the AAD app registration is unblocked (you have admin access or IT responds same-day). That single dependency is the only realistic way V1 slips past one week.

### V2
| Step | Effort |
|---|---|
| Power Apps canvas app | 3–5 days |
| Reviews list + integration | 0.5–1 day |
| Power Automate notifications | 1–2 days |
| Power BI dashboard (optional) | 1–2 days |
| **Total focused work** | **~1.5–2 weeks** |

V2 can be built at any pace after V1 is stable — there is no dependency between them other than the Lists existing.

### What stretches either timeline
- **IT/AAD bottlenecks** — the single biggest risk for V1.
- **Power Apps learning curve** — add 2–3 days if it's your first canvas app.
- **Playwright rewrite** — add 2–3 days vs keeping Selenium.
- **BIDX DOM changes mid-migration** — selectors like `cw-bidx-proposal-item` and `data-cy="cont-id"` are tied to BIDX's current markup. A redesign means 1–2 days to re-stabilize the scraper.
