"""SharePoint / Graph settings from environment (Key Vault injects at runtime)."""

import os


def _env(name: str, default: str = '') -> str:
    return os.environ.get(name, default).strip()


def sharepoint_enabled() -> bool:
    return _env('SHAREPOINT_ENABLED', 'false').lower() in ('1', 'true', 'yes')


class SharePointTargets:
    """Dual-site layout: milling site + grinding site."""

    def __init__(self):
        self.tenant_id = _env('GRAPH_TENANT_ID') or _env('GRAPH-TENANT-ID')
        self.client_id = _env('GRAPH_CLIENT_ID') or _env('GRAPH-CLIENT-ID')
        self.client_secret = _env('GRAPH_CLIENT_SECRET') or _env('GRAPH-CLIENT-SECRET')

        self.milling_site_url = _env('SHAREPOINT_MILLING_SITE_URL') or _env('SHAREPOINT-MILLING-SITE-URL')
        self.grinding_site_url = _env('SHAREPOINT_GRINDING_SITE_URL') or _env('SHAREPOINT-GRINDING-SITE-URL')
        self.milling_folder = _env('SHAREPOINT_MILLING_FOLDER_PATH') or _env('SHAREPOINT-MILLING-FOLDER-PATH')
        self.grinding_folder = _env('SHAREPOINT_GRINDING_FOLDER_PATH') or _env('SHAREPOINT-GRINDING-FOLDER-PATH')

        self.milling_list = _env('SHAREPOINT_MILLING_LIST', 'Lettings_Milling')
        self.grinding_list = _env('SHAREPOINT_GRINDING_LIST', 'Lettings_Grinding')

        # SharePoint column for proposal key (Title renamed to Proposal ID, or custom column)
        self.proposal_field = _env('SHAREPOINT_PROPOSAL_FIELD', 'Title')

    def validate_for_upload(self) -> list[str]:
        missing = []
        if not self.client_id:
            missing.append('GRAPH_CLIENT_ID')
        if not self.client_secret:
            missing.append('GRAPH_CLIENT_SECRET')
        if not self.tenant_id:
            missing.append('GRAPH_TENANT_ID')
        if not self.milling_site_url:
            missing.append('SHAREPOINT_MILLING_SITE_URL')
        if not self.grinding_site_url:
            missing.append('SHAREPOINT_GRINDING_SITE_URL')
        if not self.milling_folder:
            missing.append('SHAREPOINT_MILLING_FOLDER_PATH')
        if not self.grinding_folder:
            missing.append('SHAREPOINT_GRINDING_FOLDER_PATH')
        return missing
