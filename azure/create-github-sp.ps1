# Creates an Entra ID app registration + service principal for GitHub Actions.
# Grants AcrPush on your ACR and Contributor on the resource group.
#
# Usage: .\create-github-sp.ps1 -ResourceGroup bidx-rg -AcrName bidxacr12345

param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $true)]
    [string]$AcrName,

    [string]$SpName = "github-bidx-scraper"
)

$ErrorActionPreference = "Stop"
$subId = az account show --query id -o tsv
$acrId = az acr show --name $AcrName --resource-group $ResourceGroup --query id -o tsv
$rgId = az group show --name $ResourceGroup --query id -o tsv

Write-Host "Creating service principal: $SpName"
$sp = az ad sp create-for-rbac `
    --name $SpName `
    --role contributor `
    --scopes $rgId `
    --sdk-auth | ConvertFrom-Json

az role assignment create `
    --assignee $sp.clientId `
    --role AcrPush `
    --scope $acrId | Out-Null

Write-Host ""
Write-Host "=== Add this JSON as GitHub secret: AZURE_CREDENTIALS ==="
Write-Host ($sp | ConvertTo-Json -Compress)
Write-Host ""
Write-Host "=== Add these GitHub secrets ==="
Write-Host "ACR_NAME = $AcrName"
Write-Host "AZURE_RESOURCE_GROUP = $ResourceGroup"
Write-Host "AZURE_CONTAINER_APP_JOB_NAME = bidx-scraper-job"
Write-Host ""
Write-Host "=== After first deploy, set repository variable ==="
Write-Host "BIDX_DEPLOY_JOB = true   (Settings -> Secrets and variables -> Actions -> Variables)"
