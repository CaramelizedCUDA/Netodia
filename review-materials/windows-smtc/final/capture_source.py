"""Bind the final upstream-integrated commit to its complete five-file patch."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

repo = Path.cwd().resolve()
bundle = Path(__file__).resolve().parent


def git(*args):
    return subprocess.check_output(['git', *args], cwd=repo)


def digest(data):
    return hashlib.sha256(data).hexdigest()


base = git('rev-parse', 'origin/main').decode().strip()
head = git('rev-parse', 'HEAD').decode().strip()
paths = git('diff', '--name-only', f'{base}...{head}').decode().splitlines()
assert len(paths) == 5
assert all(p.startswith('crates/netodia-integrations/src/services/integrations/media_controls/')
           for p in paths)
assert not git('diff', '--name-only', 'HEAD', '--', 'crates').decode().strip()
patch = git('diff', '--binary', '--full-index', '--no-ext-diff', base, head)
(bundle / 'source.patch').write_bytes(patch)
added = git('diff', '--diff-filter=A', '--name-only', base, head).decode().splitlines()
scratch = Path(tempfile.mkdtemp(prefix='smtc-final-patch-', dir=repo / 'target')).resolve()
try:
    for path in paths:
        original = subprocess.run(['git', 'show', f'{base}:{path}'], cwd=repo, capture_output=True)
        if original.returncode == 0:
            destination = scratch / path
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(original.stdout)
        else:
            assert path in added
    prefix = scratch.relative_to(repo).as_posix()
    for options in (['--check'], []):
        subprocess.run(['git', 'apply', *options, f'--directory={prefix}',
                        str(bundle / 'source.patch')], cwd=repo, check=True)
    roundtrip = [{'path': p, 'matches_worktree_bytes': (scratch / p).read_bytes() == (repo / p).read_bytes()}
                 for p in paths]
    assert all(x['matches_worktree_bytes'] for x in roundtrip)
finally:
    assert scratch.parent == repo / 'target' and scratch.name.startswith('smtc-final-patch-')
    shutil.rmtree(scratch)
inputs = paths + ['Cargo.toml', 'Cargo.lock', '.cargo/config.toml', 'rust-toolchain.toml']
source_files = [{'path': p, 'sha256': digest((repo / p).read_bytes())} for p in sorted(inputs)]
record = {
    'base_commit': base,
    'local_head_commit': head,
    'source_tree_sha': git('rev-parse', 'HEAD^{tree}').decode().strip(),
    'source_patch_sha256': digest(patch),
    'source_snapshot_sha256': digest(json.dumps(source_files, sort_keys=True, separators=(',', ':')).encode()),
    'source_files': source_files,
    'patch_roundtrip': roundtrip,
    'integration': 'Five SMTC files byte-identical to previously reviewed worktree; upstream taskbar changes inherited through the new base.',
}
(bundle / 'source-capture.json').write_text(json.dumps(record, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'head_commit': head, 'base_commit': base,
                  'patch_roundtrip_files': len(roundtrip), 'source_patch_sha256': record['source_patch_sha256']}))
