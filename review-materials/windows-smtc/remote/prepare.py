"""Create a private, empty-artwork-cache fixture using a real cloud queue URL."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import sqlite3
import urllib.parse
import uuid

repo = Path.cwd().resolve()
source = Path(os.environ['APPDATA']) / 'Netodia'
nonce = uuid.uuid4().hex[:10]
root = repo / 'target' / ('smtc-windows-remote-' + nonce)
root.mkdir()
for name in ('settings.json', 'views.json', 'netease-favorites.json'):
    shutil.copy2(source / name, root / name)
with sqlite3.connect((source / 'netodia.db').as_uri() + '?mode=ro', uri=True) as live:
    with sqlite3.connect(root / 'netodia.db') as copied:
        live.backup(copied)
settings = json.loads((root / 'settings.json').read_text(encoding='utf-8-sig'))
settings.update(volume=0, is_muted=False, output_mode='shared', output_hardware_volume=False,
                auto_check_enabled=False, verbose_logging=True, close_to_tray=False,
                tray_enabled=False, shuffle_enabled=False, repeat_mode='off')
(root / 'settings.json').write_text(json.dumps(settings, ensure_ascii=False), encoding='utf-8')
queue = json.loads((source / 'queue.json').read_text(encoding='utf-8-sig'))
tracks = queue['playlist_tracks']
candidates = []
for i in range(1, len(tracks) - 1):
    url = urllib.parse.urlsplit(tracks[i].get('artwork_path') or '')
    if url.scheme in ('http', 'https') and url.hostname and not tracks[i].get('file_path') and tracks[i]['title'] != tracks[0]['title']:
        candidates.append(i)
assert candidates, 'No suitable non-first cloud track with a remote artwork URL'
index = min(candidates, key=lambda i: abs(i - queue['playlist_current_index']))
tracks[index]['last_position'] = 1000
queue['playlist_current_index'] = index
queue['current_position_ms'] = 1000
for name in ('queue.json', 'queue-seed.json'):
    (root / name).write_text(json.dumps(queue, ensure_ascii=False), encoding='utf-8')
assert not (root / 'netease-artwork').exists()
binary = repo / 'target/debug/Netodia.exe'
test_binary = root / ('Netodia-SMTC-remote-' + nonce + '.exe')
shutil.copy2(binary, test_binary)
context = {'root': str(root), 'exe': str(test_binary),
           'binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
           'initial_remote_artwork': True, 'initial_artwork_cache_empty': True}
(repo / 'target/smtc-remote-context.json').write_text(json.dumps(context), encoding='utf-8')
print(json.dumps({'prepared': True, 'non_first_cloud_track': True,
                  'genuine_remote_artwork_preserved': True, 'initial_cache_empty': True,
                  'muted_shared_output': True}))
