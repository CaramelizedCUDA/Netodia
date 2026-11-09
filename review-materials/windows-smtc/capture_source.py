"""Capture a reviewable source patch and a locally rebuilt Windows artifact."""

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


base = git('rev-parse', '7c86a143').decode().strip()
tracked = git('diff', '--name-only', base, '--', 'crates').decode().splitlines()
untracked = git('ls-files', '--others', '--exclude-standard', '--', '*.rs').decode().splitlines()
added = git('diff', '--diff-filter=A', '--name-only', base, '--', 'crates').decode().splitlines()
paths = sorted(set(tracked + untracked))
assert len(paths) == 5
assert all(path.startswith('crates/netodia-integrations/src/services/integrations/media_controls/')
           for path in paths)
patch = git('diff', '--binary', '--full-index', '--no-ext-diff', base, '--', *tracked)
for path in untracked:
    addition = subprocess.run(
        ['git', 'diff', '--no-index', '--binary', '--full-index', '--no-ext-diff',
         '--', '/dev/null', path], cwd=repo, capture_output=True)
    assert addition.returncode == 1, 'Could not capture an untracked source file'
    patch += addition.stdout
patch_path = bundle / 'source.patch'
patch_path.write_bytes(patch)

scratch = Path(tempfile.mkdtemp(prefix='smtc-patch-check-', dir=repo / 'target')).resolve()
assert scratch.parent == repo / 'target'
try:
    for path in paths:
        original = subprocess.run(['git', 'show', f'{base}:{path}'], cwd=repo, capture_output=True)
        if original.returncode == 0:
            destination = scratch / path
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(original.stdout)
        else:
            assert path in untracked or path in added, 'Unexpected missing baseline file'
    prefix = scratch.relative_to(repo).as_posix()
    subprocess.run(['git', 'apply', '--check', f'--directory={prefix}', str(patch_path)],
                   cwd=repo, check=True)
    subprocess.run(['git', 'apply', f'--directory={prefix}', str(patch_path)],
                   cwd=repo, check=True)
    roundtrip = [{'path': path, 'matches_worktree_bytes': (scratch / path).read_bytes() == (repo / path).read_bytes()}
                 for path in paths]
    assert all(entry['matches_worktree_bytes'] for entry in roundtrip)
finally:
    assert scratch.parent == repo / 'target' and scratch.name.startswith('smtc-patch-check-')
    shutil.rmtree(scratch)

inputs = paths + ['Cargo.toml', 'Cargo.lock', '.cargo/config.toml', 'rust-toolchain.toml']
source_files = [{'path': path, 'sha256': digest((repo / path).read_bytes())} for path in sorted(inputs)]
snapshot = digest(json.dumps(source_files, sort_keys=True, separators=(',', ':')).encode())
command = ['cargo', 'build', '--locked', '-p', 'netodia', '--config',
           'profile.dev.package.netodia-views.debug=1']
print('Building the recorded source snapshot...', flush=True)
build = subprocess.run(command, cwd=repo, capture_output=True)
for entry in source_files:
    assert digest((repo / entry['path']).read_bytes()) == entry['sha256'], 'Source changed during build'
assert build.returncode == 0, 'Recorded build failed; inspect the local build environment'
binary = repo / 'target/debug/Netodia.exe'
record = {
    'base_commit': base,
    'local_head_commit': git('rev-parse', 'HEAD').decode().strip(),
    'source_patch_sha256': digest(patch),
    'source_snapshot_sha256': snapshot,
    'source_files': source_files,
    'patch_roundtrip': roundtrip,
    'build_command': command,
    'build_exit_code': build.returncode,
    'binary_sha256': digest(binary.read_bytes()),
    'rustc_version': subprocess.check_output(['rustc', '--version']).decode().strip(),
    'cargo_version': subprocess.check_output(['cargo', '--version']).decode().strip(),
    'provenance': 'Captured in the evidence-supplement turn, before the instrumented replay; not a retroactive original-run build attestation.'
}
(bundle / 'build-capture.json').write_text(json.dumps(record, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'build_exit_code': build.returncode, 'binary_sha256': record['binary_sha256'],
                  'source_patch_sha256': record['source_patch_sha256'], 'patch_roundtrip_files': len(roundtrip)}))
