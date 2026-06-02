# BIDX Step 2 — one-time Azure setup (run in PowerShell with Azure CLI logged in: az login)
#
# Usage:
#   cd azure
#   Copy-Item parameters.example.json parameters.json
#   # Edit parameters.json — set unique acrName and keyVaultName
#   .\deploy.ps1 -ResourceGroup swank-bidx
#
# Option C: use your analytics subscription (az account set), new RG per tool,
# reuse Log Analytics — set existingLogAnalyticsWorkspaceId in parameters.json.

param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup,

    [string]$Location = "eastus",
    [string]$ParametersFile = "parameters.json"
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not (Test-Path (Join-Path $ScriptDir $ParametersFile))) {
    Write-Error "Create $ParametersFile from parameters.example.json and set acrName + keyVaultName."
}

$subscriptionName = az account show --query name -o tsv
Write-Host "Subscription: $subscriptionName"
Write-Host "Creating resource group: $ResourceGroup ($Location)"
az group create --name $ResourceGroup --location $Location | Out-Null

Write-Host "Deploying Bicep..."
az deployment group create `
    --resource-group $ResourceGroup `
    --template-file (Join-Path $ScriptDir "main.bicep") `
    --parameters "@$(Join-Path $ScriptDir $ParametersFile)" `
    --output table

$acrName = (Get-Content (Join-Path $ScriptDir $ParametersFile) | ConvertFrom-Json).parameters.acrName.value
$repoRoot = Resolve-Path (Join-Path $ScriptDir "..")

Write-Host ""
Write-Host "Building scraper image in ACR (cloud build — no local Docker)..."
az acr build `
    --registry $acrName `
    --image bidx-scraper:latest `
    --file (Join-Path $repoRoot "Dockerfile") `
    $repoRoot

$acrLogin = az acr show --name $acrName --query loginServer -o tsv
$prefix = (Get-Content (Join-Path $ScriptDir $ParametersFile) | ConvertFrom-Json).parameters.prefix.value
$jobName = "$prefix-scraper-job"

Write-Host "Updating job to use bidx-scraper:latest..."
az containerapp job update `
    --name $jobName `
    --resource-group $ResourceGroup `
    --image "${acrLogin}/bidx-scraper:latest"

Write-Host ""
Write-Host "=== Next steps ==="
Write-Host "1. Store credentials in Key Vault:"
Write-Host "   az keyvault secret set --vault-name <keyVaultName> --name BIDX-USERNAME --value '<email>'"
Write-Host "   az keyvault secret set --vault-name <keyVaultName> --name BIDX-PASSWORD --value '<password>'"
Write-Host ""
Write-Host "2. Create GitHub Actions service principal and add secrets (see azure/README.md)"
Write-Host ""
Write-Host "3. Test run:"
Write-Host "   az containerapp job start --name $jobName --resource-group $ResourceGroup"
Write-Host ""
Write-Host "4. Power Automate: daily 6am flow -> start job via Azure Resource Manager API"
