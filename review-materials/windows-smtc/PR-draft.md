## Summary

On Windows, an unreadable artwork file can make souvlaki reject a metadata update before publishing the current track's text and duration. The media panel can consequently retain a previous track, including the first track restored from the queue.

Retry a rejected artwork-bearing update once without artwork. Record metadata as published only when the update succeeds, and explicitly clear absent text fields instead of leaving the previous values in place. Windows accepts absolute local artwork paths; cloud artwork continues through the existing bounded download and local cache before publication.

```text
metadata + local artwork → SMTC
  artwork-bearing update fails → try text once
  text / clear update fails → keep snapshot pending for a later state emit
```

The Windows-only pending state limits attempts for the same rejected snapshot to one per five seconds when subsequent state emits occur. Changed metadata can publish immediately. This is event-driven retry, not a scheduled recovery timer.

## Related issue

No issue is linked yet. If an issue is opened, link it through the Development sidebar.

## Checklist

- [x] `cargo clippy --all-targets --locked --workspace -- -D warnings` passes
- [x] `cargo test --locked --workspace` passes
- [x] Docs updated where behaviour or conventions changed (`CLAUDE.md`, the relevant `.claude/rules/*.md`, `README.md`) — the local publication and retry contract is documented at its function/state anchors; no repository-wide convention changed.
- [x] A change that moves an architectural seam names the ADR it follows, or adds one under `docs/adr/` — not applicable; no architectural seam or dependency changed.
- [x] New or changed user-facing strings are wrapped in `@tr(...)`, `scripts/update-translations.sh` was run, and every catalogue's new `msgstr`s are filled in — not applicable; no user-facing string changed.

## Notes for review

Validation was performed on Windows 11 with Rust 1.97.0. Linux/macOS runtime paths and platform-specific tests are unchanged; no native validation on those platforms is claimed.

- `cargo test --locked --workspace --jobs 1 --config 'profile.test.package.netodia-views.debug=1'`: **3530 passed, 0 failed, 0 ignored, 0 filtered out**, across 52 test targets. This includes 22 media-control tests, all 112 `netodia-net` tests, both `net_primitives` protections and `headless_scan_persists_track` on this machine's audio device.
- `cargo clippy --all-targets --locked --workspace --jobs 1 -- -D warnings`: passed.
- `cargo fmt --all -- --check`: passed.

The first workspace attempt exhausted Windows commit/pagefile capacity while mapping the large `netodia_ui` debug library (`E0786`, underlying OS error 1455), before any test ran. Repeating with `--jobs 1` completed the entire suite. Debug information was reduced for `netodia-views` only through the command-local override above; no tests were skipped and assertions remain enabled. No system pagefile, repository/global build settings or protection tests were changed.

Native Windows SMTC validation used a separate executable name and private copies of the queue/database, with muted shared output. A six-checkpoint run compared the actual title, artist, album, duration, playback status and timeline with fixture expectations while restoring a non-first track, playing, skipping, pausing, resuming and returning. All comparisons passed. An unreadable local artwork path produced two observed artwork-failure log lines; the current track's text and duration were independently checked through WinRT. Log counts are not assertions of the producer's `set_metadata()` return value.

The final-build matrix initially timed out on Pause sent immediately after the first observation of the next track's metadata/Playing state. The failed run is retained. One rerun required the next track's native timeline to advance by more than 1000 ms before ordinary Pause; all six checkpoints then passed without relaxing the metadata, status or paused-position assertions. The unchanged event handler treats Pause during cloud loading as cancellation, which is a plausible timing explanation, but the failed run did not capture that internal branch and its causal attribution remains unverified. Loading-time rapid controls were not investigated further in this metadata fix.

A further native cloud-artwork run started with a genuine remote artwork URL and an empty private cache. At paused restore there was no cached artwork and no native thumbnail. After Play, one cache file appeared and the thumbnail bytes read through Windows WinRT had exactly the same SHA-256 as that file. Metadata and advancing position were also checked. No further transport command was sent before the thumbnail check. The final integrated build passed this cloud-artwork check. Historical pre-integration evidence separately retains a WinRT stream-reader harness failure and its corrected passing run.

Known limits: a complete text/clear publication failure was not induced in the native run. The pending-state unit tests do not establish automatic recovery in an idle player: the regular position tick updates playback only, so another state emit is required to call `sync()`. Artwork download failure is separate from publication failure and remains handled by the existing cloud path. The dependency's existing behavior of retaining a thumbnail when no artwork is supplied is unchanged.

The default full-debug Windows application link failed with unresolved symbols while `netodia_views`'s static library was approximately 4.37 GB. A command-local per-package `debug=1` override reduced that library to approximately 249 MB and allowed the application and protection tests to link. No repository/global build configuration, assertions or protection tests were changed. Native validation used that Debug build; Release behavior is not claimed.

The sanitized evidence includes the complete `source.patch`, source/build hashes, executed scripts, anonymous WinRT assertions, log-count definitions and cleanup records. The final patch is based on `d08a2d3584c59a87ba899fb6330c0910590579e3`, with the complete fix in commit `fdd2bc728ecd37ddb6b962fc59a3c70089309f22`. Historical evidence is retained separately from the final records under `final/`. [Evidence and reproduction scripts](https://github.com/CaramelizedCUDA/Netodia/tree/codex/windows-smtc-evidence/review-materials/windows-smtc) · [Complete sanitized archive](https://github.com/CaramelizedCUDA/Netodia/raw/refs/heads/codex/windows-smtc-evidence/review-materials/windows-smtc-evidence.zip). Evidence is kept on a separate fork branch so this PR remains a five-file code/test change.
