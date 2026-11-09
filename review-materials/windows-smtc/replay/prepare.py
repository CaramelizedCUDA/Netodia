import hashlib
import json
import os
from pathlib import Path
import shutil
import sqlite3
import struct
import uuid
import zlib

repo = Path.cwd().resolve()
source = Path(os.environ['APPDATA']) / 'Netodia'
root = repo / 'target' / ('smtc-windows-acceptance-' + uuid.uuid4().hex[:10])
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

def chunk(kind, data):
    return struct.pack('!I', len(data)) + kind + data + struct.pack('!I', zlib.crc32(kind + data))

png = b'\x89PNG\r\n\x1a\n'
png += chunk(b'IHDR', struct.pack('!2I5B', 32, 32, 8, 2, 0, 0, 0))
png += chunk(b'IDAT', zlib.compress((b'\0' + b'\x25\x80\xc0' * 32) * 32))
png += chunk(b'IEND', b'')
(root / 'cover.png').write_bytes(png)
queue = json.loads((source / 'queue.json').read_text(encoding='utf-8-sig'))
tracks = queue['playlist_tracks']
assert len(tracks) >= 3
candidate_indices = [i for i in range(1, len(tracks) - 1)
                     if tracks[i]['title'] != tracks[0]['title']
                     and tracks[i + 1]['title'] not in (tracks[0]['title'], tracks[i]['title'])]
assert candidate_indices, 'Need two different non-first tracks for acceptance'
saved_index = queue['playlist_current_index']
index = min(candidate_indices, key=lambda i: abs(i - saved_index))
for track in tracks:
    track['artwork_path'] = str(root / 'cover.png')
tracks[index]['artwork_path'] = str(root / 'missing-cover.png')
tracks[index]['last_position'] = 1000
queue['playlist_current_index'] = index
queue['current_position_ms'] = 1000
(root / 'queue.json').write_text(json.dumps(queue, ensure_ascii=False), encoding='utf-8')
(root / 'queue-seed.json').write_text(json.dumps(queue, ensure_ascii=False), encoding='utf-8')
binary = repo / 'target' / 'debug' / 'Netodia.exe'
test_binary = root / 'Netodia-SMTC-acceptance.exe'
shutil.copy2(binary, test_binary)
context = {'root': str(root), 'exe': str(test_binary),
           'binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest()}
(repo / 'target' / 'smtc-acceptance-context.json').write_text(json.dumps(context), encoding='utf-8')
print(json.dumps({'prepared': True, 'root': str(root), 'selected_non_first': index > 0,
                  'copied_database': True, 'muted_shared_output': True}))
