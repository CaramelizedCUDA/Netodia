"""Read-only consistency checks for the exported evidence, not execution attestation."""

import hashlib
import json
from pathlib import Path

bundle = Path(__file__).resolve().parent


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


manifest = json.loads((bundle / 'evidence-manifest.json').read_text(encoding='utf-8'))
for entry in manifest['files']:
    assert digest(bundle / entry['path']) == entry['sha256'], entry['path']
linked_report = bundle.parent.parent / manifest['linked_report']['path_from_repo_root']
assert digest(linked_report) == manifest['linked_report']['sha256'], 'Linked validation report'
for line in (bundle / 'SHA256SUMS').read_text(encoding='utf-8').splitlines():
    expected, relative = line.split('  ', 1)
    assert digest(bundle / relative) == expected, relative

build = json.loads((bundle / 'build-capture.json').read_text(encoding='utf-8'))
replay = json.loads((bundle / 'native-result.replay.json').read_text(encoding='utf-8-sig'))
assert digest(bundle / 'source.patch') == build['source_patch_sha256'] == replay['source_patch_sha256']
assert build['source_snapshot_sha256'] == replay['source_snapshot_sha256']
assert build['binary_sha256'] == replay['binary_sha256']
assert digest(bundle / 'replay/acceptance.ps1') == replay['acceptance_script_sha256']
assert build['build_exit_code'] == 0
assert len(build['patch_roundtrip']) == 5
assert all(row['matches_worktree_bytes'] for row in build['patch_roundtrip'])
assert replay['passed'] and len(replay['checks']) == 6
for check in replay['checks']:
    assert all(check[key] for key in ('title_matches', 'artist_matches', 'album_matches',
                                     'duration_matches', 'status_matches', 'title_is_not_first',
                                     'expected_track_match'))
assert len(replay['transport_returns']) == 5
assert all(command['winrt_return_value'] for command in replay['transport_returns'])
assert all(replay[key] for key in ('saved_position_matches', 'position_advanced', 'paused_position_stable'))
assert replay['metadata_native_return_values_captured'] is False
assert replay['audio_audibility_or_exclusive_output_asserted'] is False

original = bundle / 'original/native-result.original.json'
summary = json.loads((bundle / 'original/assertions.summary.json').read_text(encoding='utf-8'))
assert digest(original) == summary['original_json_sha256']
for entry in manifest['original_artifact_copies']:
    assert digest(bundle / entry['export_path']) == entry['sha256']
cleanup = json.loads((bundle / 'cleanup.replay.json').read_text(encoding='utf-8-sig'))
assert cleanup['private_copy_removed'] and cleanup['context_file_removed']
remote = json.loads((bundle / 'remote/native-result.json').read_text(encoding='utf-8-sig'))
assert remote['passed'] and remote['failure'] is None
assert remote['source_patch_sha256'] == build['source_patch_sha256']
assert remote['source_snapshot_sha256'] == build['source_snapshot_sha256']
assert remote['binary_sha256'] == build['binary_sha256']
assert digest(bundle / 'remote/acceptance.ps1') == remote['acceptance_script_sha256']
assert len(remote['checks']) == 2
for check in remote['checks']:
    assert all(check[key] for key in ('title_matches', 'artist_matches', 'album_matches',
                                     'duration_matches', 'status_matches', 'title_is_not_first',
                                     'expected_track_match'))
assert remote['preparation']['real_queue_remote_artwork_preserved']
assert remote['preparation']['private_artwork_cache_initially_empty']
observations = remote['observations']
assert observations['local_cache_files_at_paused_restore'] == 0
assert observations['native_thumbnail_at_paused_restore'] is False
assert observations['local_cache_files_after_play'] == 1
assert all(observations[key] for key in ('native_thumbnail_sha256_matches_one_cached_file',
                                       'matching_cache_path_is_absolute', 'playing_position_advanced',
                                       'no_additional_transport_commands_between_play_and_thumbnail_check'))
assert observations['thumbnail_hash_or_user_metadata_exported'] is False
assert len(remote['transport_returns']) == 1 and remote['transport_returns'][0]['winrt_return_value']
assert remote['original_instance_count_at_start'] >= 1
assert remote['original_instances_still_running'] and remote['test_instance_exited']
assert remote['metadata_native_return_values_captured'] is False
assert remote['full_text_publication_failure_induced'] is False
assert remote['retry_scheduler_validated'] is False
first = json.loads((bundle / 'remote/attempt1/native-result.json').read_text(encoding='utf-8-sig'))
assert first['passed'] is False and first['failure'] is not None
assert digest(bundle / 'remote/attempt1/acceptance.ps1') == first['acceptance_script_sha256']
for relative in ('remote/cleanup.json', 'remote/attempt1/cleanup.json'):
    cleaned = json.loads((bundle / relative).read_text(encoding='utf-8-sig'))
    assert cleaned['private_copy_removed'] and cleaned['context_file_removed']
print(json.dumps({'integrity_checks_passed': True, 'manifest_files': len(manifest['files']),
                  'native_checkpoints': len(replay['checks']), 'real_cdn_native_checkpoints': len(remote['checks']),
                  'meaning': 'Exported-file and recorded-result consistency; not third-party execution attestation'}))
