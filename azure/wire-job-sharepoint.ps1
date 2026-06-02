# Wire SharePoint / Graph Key Vault secrets into bidx-scraper-job and enable SHAREPOINT_ENABLED.
# Run in Cloud Shell after grant-sharepoint-sites.sh succeeds.
#
# Usage: pwsh ./wire-job-sharepoint.ps1 -ResourceGroup swank-bidx

param(
    [string]$ResourceGroup = "swank-bidx",
    [string]$JobName = "bidx-scraper-job",
    [string]$KeyVaultName = "bidx-kv-swank",
    [string]$IdentityName = "bidx-job-identity"
)

$ErrorActionPreference = "Stop"

$identityId = az identity show --resource-group $ResourceGroup --name $IdentityName --query id -o tsv
$kvUri = az keyvault show --name $KeyVaultName --query properties.vaultUri -o tsv
$kvUri = $kvUri.TrimEnd('/')

$secretDefs = @(
    "graph-client-id=keyvaultref:${kvUri}/secrets/GRAPH-CLIENT-ID,identityref:${identityId}",
    "graph-client-secret=keyvaultref:${kvUri}/secrets/GRAPH-CLIENT-SECRET,identityref:${identityId}",
    "graph-tenant-id=keyvaultref:${kvUri}/secrets/GRAPH-TENANT-ID,identityref:${identityId}",
    "sp-milling-site-url=keyvaultref:${kvUri}/secrets/SHAREPOINT-MILLING-SITE-URL,identityref:${identityId}",
    "sp-grinding-site-url=keyvaultref:${kvUri}/secrets/SHAREPOINT-GRINDING-SITE-URL,identityref:${identityId}",
    "sp-milling-folder=keyvaultref:${kvUri}/secrets/SHAREPOINT-MILLING-FOLDER-PATH,identityref:${identityId}",
    "sp-grinding-folder=keyvaultref:${kvUri}/secrets/SHAREPOINT-GRINDING-FOLDER-PATH,identityref:${identityId}"
)

Write-Host "Adding Key Vault secret references to job..."
az containerapp job secret set `
    --name $JobName `
    --resource-group $ResourceGroup `
    --secrets $secretDefs

Write-Host "Updating environment variables..."
az containerapp job update `
    --name $JobName `
    --resource-group $ResourceGroup `
    --set-env-vars `
        "SHAREPOINT_ENABLED=true" `
        "GRAPH-CLIENT-ID=secretref:graph-client-id" `
        "GRAPH-CLIENT-SECRET=secretref:graph-client-secret" `
        "GRAPH-TENANT-ID=secretref:graph-tenant-id" `
        "SHAREPOINT-MILLING-SITE-URL=secretref:sp-milling-site-url" `
        "SHAREPOINT-GRINDING-SITE-URL=secretref:sp-grinding-site-url" `
        "SHAREPOINT-MILLING-FOLDER-PATH=secretref:sp-milling-folder" `
        "SHAREPOINT-GRINDING-FOLDER-PATH=secretref:sp-grinding-folder" `
        "SHAREPOINT-PROPOSAL-FIELD=Title"

Write-Host ""
Write-Host "Done. Start a test run:"
Write-Host "  az containerapp job start --name $JobName --resource-group $ResourceGroup"
