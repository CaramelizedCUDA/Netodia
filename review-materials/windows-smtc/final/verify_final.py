"""Check final exported evidence consistency; not third-party execution attestation."""
import hashlib
import json
from pathlib import Path

here = Path(__file__).resolve().parent
bundle = here.parent


def read(relative):
    return json.loads((here / relative).read_text(encoding='utf-8-sig'))


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


source = read('source-capture.json')
build = read('build-capture.json')
checks = read('checks.json')
assert build['source_patch_sha256'] == source['source_patch_sha256'] == digest(here / 'source.patch')
assert build['source_snapshot_sha256'] == source['source_snapshot_sha256']
assert build['local_head_commit'] == source['local_head_commit']
assert build['base_commit'] == source['base_commit']
assert build['build_exit_code'] == 0
assert len(source['patch_roundtrip']) == 5
assert all(row['matches_worktree_bytes'] for row in source['patch_roundtrip'])
assert all(row['status'] == 'completed' and row['exit_code'] == 0 for row in checks.values())
assert all(row['head_commit'] == source['local_head_commit'] for row in checks.values())
tests = checks['test']
assert tests['totals']['failed'] == 0 and tests['test_binary_result_count'] > 0
assert tests['failed_test_names'] == []
scope = read('scope-review.json')
assert scope['commits_ahead'] == 1 and scope['changed_source_files'] == 5
assert scope['all_reviewed_smtc_files_byte_identical']
assert scope['new_commit_author_and_committer_use_verified_account_noreply']
assert scope['private_email_in_new_commit_metadata'] is False
for case, script, count in [('bad_cover', 'final/acceptance.bad_cover.ps1', 6),
                            ('remote_cover', 'remote/acceptance.ps1', 2)]:
    result = read(case + '.json')
    assert result['passed'] and result['failure'] is None
    assert result['source_patch_sha256'] == build['source_patch_sha256']
    assert result['source_snapshot_sha256'] == build['source_snapshot_sha256']
    assert result['binary_sha256'] == build['binary_sha256']
    assert result['acceptance_script_sha256'] == digest(bundle / script)
    assert len(result['checks']) == count
    for row in result['checks']:
        assert all(row[key] for key in ('title_matches', 'artist_matches', 'album_matches',
                                       'duration_matches', 'status_matches', 'title_is_not_first',
                                       'expected_track_match'))
    assert all(row['winrt_return_value'] for row in result['transport_returns'])
    assert result['test_instance_exited']
    assert result['metadata_native_return_values_captured'] is False
    cleanup = read(case + '.cleanup.json')
    assert cleanup['private_copy_removed'] and cleanup['context_file_removed']
bad = read('bad_cover.json')
assert all(bad[key] for key in ('saved_position_matches', 'position_advanced',
                               'paused_position_stable', 'good_local_cover_has_thumbnail',
                               'original_instance_still_running', 'next_track_position_advanced_before_pause'))
remote = read('remote_cover.json')
assert remote['original_instance_count_at_start'] >= 1
assert remote['original_instances_still_running']
assert remote['observations']['native_thumbnail_sha256_matches_one_cached_file']
assert remote['observations']['playing_position_advanced']
assert remote['full_text_publication_failure_induced'] is False
assert remote['retry_scheduler_validated'] is False
first = read('bad_cover-attempt1/bad_cover.json')
assert first['passed'] is False and first['failure']['phase'] == 'pause'
assert first['binary_sha256'] == build['binary_sha256']
assert first['acceptance_script_sha256'] == digest(here / 'bad_cover-attempt1/acceptance.ps1')
first_cleanup = read('bad_cover-attempt1/bad_cover.cleanup.json')
assert first_cleanup['private_copy_removed'] and first_cleanup['context_file_removed']
print(json.dumps({'final_evidence_consistent': True, 'head_commit': source['local_head_commit'],
                  'workspace_test_totals': tests['totals'], 'native_checkpoints': 8,
                  'meaning': 'File and recorded-result consistency; not independent execution attestation'}))
