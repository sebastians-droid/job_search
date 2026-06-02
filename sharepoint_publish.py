"""
Publish scrape results to SharePoint (lists + Excel files).

List upsert / archive diff will be completed when Graph consent is live.
File upload path is implemented for dual-site Excel delivery.
"""

import os
from datetime import date

from sharepoint_config import SharePointTargets
from graph_client import GraphClient


def publish_to_sharepoint(
    milling_output: str,
    grinding_output: str,
    all_dot_names: list[str],
):
    """
    Upload latest + dated Excel copies to each team's site folder.

    Parameters
    ----------
    milling_output : path to bidx_results_milling.xlsx (may not exist)
    grinding_output : path to bidx_results_grinding_grooving.xlsx
    all_dot_names : all DOT display names (for future list sync / empty tabs)
    """
    cfg = SharePointTargets()
    missing = cfg.validate_for_upload()
    if missing:
        raise RuntimeError(
            'SharePoint enabled but missing env vars: ' + ', '.join(missing)
        )

    client = GraphClient(cfg.tenant_id, cfg.client_id, cfg.client_secret)
    today = date.today().isoformat()

    print('\n' + '=' * 80)
    print('SHAREPOINT PUBLISH')
    print('=' * 80)

    if os.path.exists(milling_output):
        milling_site = client.get_site_id(cfg.milling_site_url)
        for name in (f'bidx_milling_latest.xlsx', f'bidx_milling_{today}.xlsx'):
            print(f'  Uploading milling → {name}')
            with open(milling_output, 'rb') as f:
                client.upload_file_to_folder(
                    milling_site, cfg.milling_folder, name, f.read()
                )
    else:
        print('  No milling output file — skip milling upload')

    if os.path.exists(grinding_output):
        grinding_site = client.get_site_id(cfg.grinding_site_url)
        for name in (f'bidx_grinding_latest.xlsx', f'bidx_grinding_{today}.xlsx'):
            print(f'  Uploading grinding → {name}')
            with open(grinding_output, 'rb') as f:
                client.upload_file_to_folder(
                    grinding_site, cfg.grinding_folder, name, f.read()
                )
    else:
        print('  No grinding output file — skip grinding upload')

    # TODO Step 4b: sync rows to Lettings_Milling / Lettings_Grinding (diff logic)
    print('  List sync: not yet enabled in this build (Excel upload only).')
    print('=' * 80 + '\n')
