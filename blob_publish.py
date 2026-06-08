"""
Upload BIDX Excel output to Azure Blob Storage.

The Container Apps Job managed identity must have Storage Blob Data Contributor
on the storage account (assigned by azure/setup-blob-storage.sh).

Power Automate then picks up the *_latest.xlsx blobs and copies them to
the correct SharePoint Lettings folder using your user connection
(no Sites.Selected / Graph app permission required).

Required env vars (set on the job):
    AZURE_STORAGE_ACCOUNT_NAME   e.g. bidxstoreswank2026
    BLOB_ENABLED                 true
Optional:
    AZURE_STORAGE_CONTAINER_NAME  default: bidx-output
"""

import os
from datetime import date

BLOB_ENABLED_VAR = "BLOB_ENABLED"
STORAGE_ACCOUNT_VAR = "AZURE_STORAGE_ACCOUNT_NAME"
CONTAINER_VAR = "AZURE_STORAGE_CONTAINER_NAME"
DEFAULT_CONTAINER = "bidx-output"


def blob_enabled() -> bool:
    return os.environ.get(BLOB_ENABLED_VAR, "").lower() == "true"


def _service_client():
    from azure.identity import DefaultAzureCredential
    from azure.storage.blob import BlobServiceClient

    account = os.environ.get(STORAGE_ACCOUNT_VAR, "").strip()
    if not account:
        raise RuntimeError(f"Missing env var: {STORAGE_ACCOUNT_VAR}")
    url = f"https://{account}.blob.core.windows.net"
    return BlobServiceClient(url, credential=DefaultAzureCredential())


def publish_to_blob(milling_output: str, grinding_output: str):
    """Upload latest + dated Excel files to Azure Blob Storage."""
    container = os.environ.get(CONTAINER_VAR, DEFAULT_CONTAINER)
    client = _service_client()
    today = date.today().isoformat()

    print("\n" + "=" * 80)
    print("BLOB STORAGE PUBLISH")
    print("=" * 80)

    pairs = [
        (milling_output, "milling", [
            "bidx_milling_latest.xlsx",
            f"bidx_milling_{today}.xlsx",
        ]),
        (grinding_output, "grinding", [
            "bidx_grinding_latest.xlsx",
            f"bidx_grinding_{today}.xlsx",
        ]),
    ]

    for local_path, label, blob_names in pairs:
        if not os.path.exists(local_path):
            print(f"  No {label} output — skip")
            continue
        with open(local_path, "rb") as fh:
            data = fh.read()
        for name in blob_names:
            print(f"  Uploading {label} → {name}")
            blob_client = client.get_blob_client(container=container, blob=name)
            blob_client.upload_blob(data, overwrite=True)
        print(f"  {label.capitalize()} done ({len(data):,} bytes)")

    print("=" * 80 + "\n")
