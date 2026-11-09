"""Derive an anonymous index without adding observations to the original result."""

import hashlib
import json
from pathlib import Path

bundle = Path(__file__).resolve().parent
raw_path = bundle / 'original/native-result.original.json'
raw = json.loads(raw_path.read_text(encoding='utf-8-sig'))
aliases = {
    'startup_restore_bad_cover': ('A', 'Paused'),
    'play_and_progress': ('A', 'Playing'),
    'next_good_cover': ('B', 'Playing'),
    'pause': ('B', 'Paused'),
    'resume': ('B', 'Playing'),
    'previous_bad_cover': ('A', 'Playing'),
}
cases = []
for check in raw['checks']:
    alias, status = aliases[check['step']]
    cases.append({
        'case': check['step'],
        'expected_track_alias_from_script': alias,
        'expected_playback_status_from_script': status,
        'expected_track_match_derived': all(check[key] for key in
                                            ('title_matches', 'artist_matches', 'album_matches', 'duration_matches')),
        **{key: value for key, value in check.items() if key != 'step'},
    })
summary = {
    'evidence_kind': 'derived_index_of_existing_original_artifact_not_a_new_execution',
    'original_json_sha256': hashlib.sha256(raw_path.read_bytes()).hexdigest(),
    'expected_metadata_source': 'Private queue-seed.json / playlist_tracks; not database reads or manual visual judgement',
    'actual_metadata_source': 'Windows SMTC WinRT properties and timeline',
    'cases': cases,
    'original_position_booleans': {key: raw[key] for key in
                                   ('saved_position_matches', 'position_advanced', 'paused_position_stable')},
    'position_rules_from_script': {
        'restore_expected_ms': 1000, 'restore_tolerance_ms': 100,
        'minimum_advance_ms': 1000, 'advance_timeout_seconds': 15,
        'paused_sample_interval_ms': 1200, 'paused_tolerance_ms': 100,
    },
    'original_log_observations': {
        'artwork_attempt_failure_lines_delta': raw['artwork_fallback_count'],
        'text_or_clear_failure_lines_delta': raw['text_or_clear_failure_count'],
        'per_event_log_timestamps_retained': False,
        'per_event_hresult_codes_retained': False,
        'native_set_metadata_return_values_recorded': False,
        'zero_failure_lines_means': 'No matching failure log lines observed, not a complete native return-value trace',
    },
    'original_transport_return_values_recorded_as_fields': False,
}
(bundle / 'original/assertions.summary.json').write_text(
    json.dumps(summary, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
