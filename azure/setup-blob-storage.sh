#!/bin/bash
# Create Azure Storage account + container, grant job identity access,
# and enable BLOB_ENABLED on the Container Apps Job.
#
# Run once in Azure Cloud Shell (Bash):
#   cd ~/job_search/azure && bash setup-blob-storage.sh

set -euo pipefail

RESOURCE_GROUP="swank-bidx"
STORAGE_ACCOUNT="bidxstoreswank2026"   # must be globally unique, lowercase, 3-24 chars
CONTAINER_NAME="bidx-output"
JOB_NAME="bidx-scraper-job"
IDENTITY_NAME="bidx-job-identity"
SUBSCRIPTION="Analytics"               # change if your subscription has a different name

echo "Setting subscription to: ${SUBSCRIPTION}"
az account set --subscription "${SUBSCRIPTION}"

echo ""
echo "=== Step 1: Create storage account ==="
az storage account create \
    --name "${STORAGE_ACCOUNT}" \
    --resource-group "${RESOURCE_GROUP}" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --access-tier Hot \
    --allow-blob-public-access false \
    --output table

echo ""
echo "=== Step 2: Create blob container ==="
az storage container create \
    --name "${CONTAINER_NAME}" \
    --account-name "${STORAGE_ACCOUNT}" \
    --auth-mode login \
    --output table

echo ""
echo "=== Step 3: Grant job identity Storage Blob Data Contributor ==="
STORAGE_ID=$(az storage account show \
    --name "${STORAGE_ACCOUNT}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query id -o tsv)

IDENTITY_PRINCIPAL=$(az identity show \
    --name "${IDENTITY_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query principalId -o tsv)

az role assignment create \
    --assignee-object-id "${IDENTITY_PRINCIPAL}" \
    --assignee-principal-type ServicePrincipal \
    --role "Storage Blob Data Contributor" \
    --scope "${STORAGE_ID}" \
    --output table

echo ""
echo "=== Step 4: Add storage env vars to job ==="
az containerapp job update \
    --name "${JOB_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --set-env-vars \
        "BLOB_ENABLED=true" \
        "AZURE_STORAGE_ACCOUNT_NAME=${STORAGE_ACCOUNT}" \
        "AZURE_STORAGE_CONTAINER_NAME=${CONTAINER_NAME}" \
    --output table

echo ""
echo "=== Done ==="
echo ""
echo "Storage account : ${STORAGE_ACCOUNT}"
echo "Container       : ${CONTAINER_NAME}"
echo "Job env vars    : BLOB_ENABLED=true, AZURE_STORAGE_ACCOUNT_NAME set"
echo ""
echo "Next steps:"
echo "  1. Push main to rebuild the image (GitHub Actions) — adds blob_publish.py"
echo "  2. az containerapp job start --name ${JOB_NAME} --resource-group ${RESOURCE_GROUP}"
echo "  3. Check storage account > Containers > bidx-output for Excel files"
echo "  4. Build Power Automate flow: blob created → SharePoint Create file"
