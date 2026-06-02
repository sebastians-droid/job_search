# BIDX Step 2 — Azure setup (two-pass deploy)
#
# Pass 1: ACR, Key Vault, Container Apps Environment (no job yet)
# Pass 2: Placeholder secrets in Key Vault, then deploy the job
#
# Usage:
#   .\deploy.ps1 -ResourceGroup swank-bidx

param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup,

    [string]$Location = "eastus",
    [string]$ParametersFile = "parameters.json",

    [string]$BidxUsername = "",
    [string]$BidxPassword = ""
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ParamsPath = Join-Path $ScriptDir $ParametersFile

if (-not (Test-Path $ParamsPath)) {
    Write-Error "Create $ParametersFile from parameters.example.json and set acrName + keyVaultName."
}

$params = Get-Content $ParamsPath | ConvertFrom-Json
$acrName = $params.parameters.acrName.value
$keyVaultName = $params.parameters.keyVaultName.value
$prefix = $params.parameters.prefix.value
$jobName = "$prefix-scraper-job"
$repoRoot = Resolve-Path (Join-Path $ScriptDir "..")

if ($acrName -notmatch '^[a-z0-9]{5,50}$') {
    Write-Error @"
acrName '$acrName' is invalid.
ACR names must be 5-50 characters, lowercase letters and numbers ONLY (no underscores or hyphens).
Example: bidxacrswank2026
"@
}

$subscriptionName = az account show --query name -o tsv
Write-Host "Subscription: $subscriptionName"
Write-Host "Creating resource group: $ResourceGroup ($Location)"
az group create --name $ResourceGroup --location $Location | Out-Null

function Invoke-BidxDeployment {
    param([bool]$DeployJob)
    Write-Host ""
    Write-Host "Deploying Bicep (deployScraperJob=$DeployJob)..."
    az deployment group create `
        --resource-group $ResourceGroup `
        --template-file (Join-Path $ScriptDir "main.bicep") `
        --parameters "@$ParamsPath" deployScraperJob=$DeployJob `
        --output table
}

# --- Pass 1: infrastructure only ---
Invoke-BidxDeployment -DeployJob $false

Write-Host ""
Write-Host "Seeding Key Vault secrets (required before the job can be created)..."
if ($BidxUsername -and $BidxPassword) {
    $userValue = $BidxUsername
    $passValue = $BidxPassword
    Write-Host "Using BIDX credentials supplied to deploy.ps1."
} else {
    $userValue = "REPLACE-WITH-BIDX-EMAIL"
    $passValue = "REPLACE-WITH-BIDX-PASSWORD"
    Write-Host "No credentials passed — using placeholders. Update in Portal or rerun:"
    Write-Host "  az keyvault secret set --vault-name $keyVaultName --name BIDX-USERNAME --value '<email>'"
    Write-Host "  az keyvault secret set --vault-name $keyVaultName --name BIDX-PASSWORD --value '<password>'"
}

az keyvault secret set --vault-name $keyVaultName --name BIDX-USERNAME --value $userValue | Out-Null
az keyvault secret set --vault-name $keyVaultName --name BIDX-PASSWORD --value $passValue | Out-Null

Write-Host "Waiting 45s for Key Vault RBAC on the job identity to propagate..."
Start-Sleep -Seconds 45

# --- Pass 2: deploy the job ---
Invoke-BidxDeployment -DeployJob $true

Write-Host ""
Write-Host "Importing Python base image to ACR (Microsoft mirror, avoids Docker Hub limits)..."
az acr import `
    --name $acrName `
    --source mcr.microsoft.com/devcontainers/python:3.12-bookworm `
    --image python:3.12-bookworm `
    --force 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Import skipped or failed — build will pull base image from MCR directly."
}

Write-Host ""
Write-Host "Building scraper image in ACR (cloud build — no local Docker)..."
az acr build `
    --registry $acrName `
    --image bidx-scraper:latest `
    --file (Join-Path $repoRoot "Dockerfile") `
    $repoRoot

$acrLogin = az acr show --name $acrName --query loginServer -o tsv

Write-Host "Updating job to use bidx-scraper:latest..."
az containerapp job update `
    --name $jobName `
    --resource-group $ResourceGroup `
    --image "${acrLogin}/bidx-scraper:latest"

Write-Host ""
Write-Host "=== Deploy complete ==="
Write-Host "Resource group : $ResourceGroup"
Write-Host "ACR            : $acrName"
Write-Host "Key Vault      : $keyVaultName"
Write-Host "Job            : $jobName"
Write-Host ""
if (-not ($BidxUsername -and $BidxPassword)) {
    Write-Host "IMPORTANT: Replace placeholder Key Vault secrets with real BIDX credentials before running the job."
}
Write-Host "Test run:"
Write-Host "  az containerapp job start --name $jobName --resource-group $ResourceGroup"
