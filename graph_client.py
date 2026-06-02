"""Microsoft Graph client (app-only) for SharePoint lists and file upload."""

import json
import urllib.parse
import urllib.request
import urllib.error

TOKEN_URL_TMPL = 'https://login.microsoftonline.com/{tenant}/oauth2/v2.0/token'
GRAPH_BASE = 'https://graph.microsoft.com/v1.0'


class GraphClient:
    def __init__(self, tenant_id: str, client_id: str, client_secret: str):
        self.tenant_id = tenant_id
        self.client_id = client_id
        self.client_secret = client_secret
        self._token = None

    def _get_token(self) -> str:
        if self._token:
            return self._token
        data = urllib.parse.urlencode({
            'client_id': self.client_id,
            'client_secret': self.client_secret,
            'scope': 'https://graph.microsoft.com/.default',
            'grant_type': 'client_credentials',
        }).encode()
        url = TOKEN_URL_TMPL.format(tenant=self.tenant_id)
        req = urllib.request.Request(url, data=data, method='POST')
        with urllib.request.urlopen(req, timeout=60) as resp:
            body = json.loads(resp.read().decode())
        self._token = body['access_token']
        return self._token

    def _request(self, method: str, path: str, payload=None, raw: bytes = None):
        url = path if path.startswith('http') else f'{GRAPH_BASE}{path}'
        headers = {'Authorization': f'Bearer {self._get_token()}'}
        body = None
        if payload is not None:
            body = json.dumps(payload).encode()
            headers['Content-Type'] = 'application/json'
        elif raw is not None:
            body = raw
            headers['Content-Type'] = 'application/octet-stream'
        req = urllib.request.Request(url, data=body, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                if resp.status == 204:
                    return None
                data = resp.read()
                return json.loads(data.decode()) if data else None
        except urllib.error.HTTPError as e:
            err_body = e.read().decode() if e.fp else ''
            raise RuntimeError(f'Graph {method} {path} failed ({e.code}): {err_body}') from e

    def get_site_id(self, site_url: str) -> str:
        encoded = urllib.parse.quote(site_url, safe='')
        data = self._request('GET', f'/sites/{encoded}')
        return data['id']

    def get_list_id(self, site_id: str, list_name: str) -> str:
        data = self._request('GET', f'/sites/{site_id}/lists?$filter=displayName eq \'{list_name}\'')
        items = data.get('value', [])
        if not items:
            raise RuntimeError(f'List not found: {list_name}')
        return items[0]['id']

    def upload_file_to_folder(self, site_id: str, folder_path: str, filename: str, content: bytes):
        """Upload or replace a file under a document library path (e.g. Shared Documents/Reports)."""
        parts = [p for p in folder_path.split('/') if p]
        if not parts:
            raise ValueError('folder_path is empty')
        library = parts[0]
        subfolders = '/'.join(parts[1:]) if len(parts) > 1 else ''
        base = f'/sites/{site_id}/drives'
        drives = self._request('GET', f'{base}')
        drive_id = None
        for d in drives.get('value', []):
            if d.get('name', '').lower() == library.lower().replace('%20', ' '):
                drive_id = d['id']
                break
        if not drive_id and drives.get('value'):
            drive_id = drives['value'][0]['id']
        if not drive_id:
            raise RuntimeError(f'Could not resolve document library: {library}')
        path = f"{subfolders}/{filename}" if subfolders else filename
        encoded_path = urllib.parse.quote(path, safe='/')
        self._request(
            'PUT',
            f'{GRAPH_BASE}/drives/{drive_id}/root:/{encoded_path}:/content',
            raw=content,
        )
