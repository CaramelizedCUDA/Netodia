param([string]$ContextPath, [string]$OutputPath, [string]$BuildManifestPath)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$context = Get-Content -LiteralPath $ContextPath -Raw | ConvertFrom-Json
$build = Get-Content -LiteralPath $BuildManifestPath -Raw | ConvertFrom-Json
$actualBinaryHash = (Get-FileHash -LiteralPath $context.exe -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualBinaryHash -ne $context.binary_sha256 -or $actualBinaryHash -ne $build.binary_sha256) {
    throw 'Acceptance binary does not match the recorded build'
}
foreach ($entry in $build.source_files) {
    if ((Get-FileHash -LiteralPath $entry.path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $entry.sha256) {
        throw 'Source snapshot changed after the recorded build'
    }
}
$seed = Get-Content -LiteralPath (Join-Path $context.root 'queue-seed.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$currentIndex = [int]$seed.playlist_current_index
$currentTrack = $seed.playlist_tracks[$currentIndex]
$nextTrack = $seed.playlist_tracks[$currentIndex + 1]
$originalProcesses = @(Get-CimInstance Win32_Process -Filter "Name = 'Netodia.exe'")
$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
    $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
})[0]
function Await($operation, $resultType) {
    $task = $asTaskGeneric.MakeGenericMethod($resultType).Invoke($null, @($operation))
    if (-not $task.Wait(10000)) { throw 'WinRT read timed out' }
    $task.Result
}
$managerType = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager,Windows.Media.Control,ContentType=WindowsRuntime]
$propertiesType = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties,Windows.Media.Control,ContentType=WindowsRuntime]
$manager = Await ($managerType::RequestAsync()) $managerType
function SessionList {
    $manager.GetSessions() | ForEach-Object { $_ }
}
$clock = [System.Diagnostics.Stopwatch]::StartNew()
$logEvents = New-Object 'System.Collections.Generic.List[object]'
$transportResults = New-Object 'System.Collections.Generic.List[object]'
function LogCounts {
    $text = (@(Get-ChildItem (Join-Path $context.root 'logs') -Filter '*.log' -ErrorAction SilentlyContinue | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n")
    $hresults = @{}
    foreach ($line in ($text -split "`n")) {
        if ($line.Contains('Failed to set media metadata with artwork:')) {
            $code = [regex]::Match($line, '0x[0-9A-Fa-f]{8}')
            if ($code.Success) {
                $key = $code.Value.ToUpperInvariant()
                $hresults[$key] = 1 + $hresults[$key]
            }
        }
    }
    [pscustomobject]@{
        artwork_attempt_failure_lines = [regex]::Matches($text, 'Failed to set media metadata with artwork:').Count
        text_or_clear_failure_lines = [regex]::Matches($text, 'Failed to set media metadata:|Failed to clear media metadata:').Count
        artwork_failure_hresult_counts = $hresults
    }
}
$initialCounts = LogCounts
$script:lastCounts = $initialCounts
function ObserveLogs([string]$label) {
    $counts = LogCounts
    $logEvents.Add([pscustomobject]@{
        observation = $label
        elapsed_ms = $clock.ElapsedMilliseconds
        artwork_attempt_failure_lines_total = $counts.artwork_attempt_failure_lines
        artwork_attempt_failure_lines_since_previous_observation = $counts.artwork_attempt_failure_lines - $script:lastCounts.artwork_attempt_failure_lines
        text_or_clear_failure_lines_total = $counts.text_or_clear_failure_lines
        text_or_clear_failure_lines_since_previous_observation = $counts.text_or_clear_failure_lines - $script:lastCounts.text_or_clear_failure_lines
    })
    $script:lastCounts = $counts
}
function Transport([string]$label, $operation) {
    $accepted = [bool](Await $operation ([bool]))
    $transportResults.Add([pscustomobject]@{ command = $label; winrt_return_value = $accepted })
    if (-not $accepted) { throw 'Transport command was refused' }
}
function WaitFor([string]$label, [scriptblock]$condition, [int]$seconds = 30) {
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    do {
        if (& $condition) { return }
        Start-Sleep -Milliseconds 250
    } while ($timer.Elapsed.TotalSeconds -lt $seconds)
    throw "Timed out: $label"
}
function Properties { Await ($script:targetSession.TryGetMediaPropertiesAsync()) $propertiesType }
function Matches($properties, $track) {
    $timeline = $script:targetSession.GetTimelineProperties()
    ($properties.Title -ceq $track.title) -and
    ($properties.Artist -ceq ([string]$track.artist).Trim()) -and
    ($properties.AlbumTitle -ceq ([string]$track.album).Trim()) -and
    ($timeline.EndTime.TotalMilliseconds -eq $track.duration_ms)
}
$checks = New-Object 'System.Collections.Generic.List[object]'
function Checkpoint([string]$label, $track, [string]$status, [string]$alias) {
    $properties = Properties
    $timeline = $script:targetSession.GetTimelineProperties()
    $actualStatus = $script:targetSession.GetPlaybackInfo().PlaybackStatus.ToString()
    $check = [pscustomobject]@{
        step = $label
        evidence_kind = 'native_winrt_state_assertion'
        expected_track_alias = $alias
        expected_source = 'private queue-seed.json / playlist_tracks'
        actual_source = 'SMTC TryGetMediaPropertiesAsync and GetTimelineProperties'
        expected_playback_status = $status
        actual_playback_status = $actualStatus
        title_matches = ($properties.Title -ceq $track.title)
        artist_matches = ($properties.Artist -ceq ([string]$track.artist).Trim())
        album_matches = ($properties.AlbumTitle -ceq ([string]$track.album).Trim())
        duration_matches = ($timeline.EndTime.TotalMilliseconds -eq $track.duration_ms)
        status_matches = ($actualStatus -eq $status)
        title_is_not_first = ($properties.Title -cne $seed.playlist_tracks[0].title)
    }
    $check | Add-Member -NotePropertyName expected_track_match -NotePropertyValue ($check.title_matches -and $check.artist_matches -and $check.album_matches -and $check.duration_matches)
    $checks.Add($check)
    if (-not ($check.title_matches -and $check.artist_matches -and $check.album_matches -and
              $check.duration_matches -and $check.status_matches -and $check.title_is_not_first)) {
        throw "Checkpoint mismatch: $label"
    }
    ObserveLogs $label
    Write-Output ("passed: " + $label)
}
$candidateProcess = $null
$failure = $null
$phase = 'launch'
$positionAdvanced = $false
$pausedPositionStable = $false
$thumbnailAvailable = $false
try {
    $savedDataDir = [Environment]::GetEnvironmentVariable('NETODIA_DATA_DIR', 'Process')
    [Environment]::SetEnvironmentVariable('NETODIA_DATA_DIR', $context.root, 'Process')
    try {
        $candidateProcess = Start-Process -FilePath $context.exe -WorkingDirectory $context.root -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $context.root 'stdout.txt') -RedirectStandardError (Join-Path $context.root 'stderr.txt')
    } finally {
        [Environment]::SetEnvironmentVariable('NETODIA_DATA_DIR', $savedDataDir, 'Process')
    }
    $phase = 'session_selection'
    WaitFor 'isolated SMTC session' {
        $sessions = @(SessionList)
        $candidates = @($sessions | Where-Object { $_.SourceAppUserModelId -ieq (Split-Path $context.exe -Leaf) })
        if ($candidates.Count -eq 1) { $script:targetSession = $candidates[0]; return $true }
        return $false
    }
    $phase = 'startup_restore_bad_cover'
    WaitFor $phase { (Matches (Properties) $currentTrack) -and $script:targetSession.GetPlaybackInfo().PlaybackStatus.ToString() -eq 'Paused' }
    Checkpoint $phase $currentTrack 'Paused' 'A'
    $restoredPositionMatches = [math]::Abs($script:targetSession.GetTimelineProperties().Position.TotalMilliseconds - $seed.current_position_ms) -le 100
    if (-not $restoredPositionMatches) { throw 'Saved position mismatch' }

    $phase = 'play_and_progress'
    Transport 'play_A' ($script:targetSession.TryPlayAsync())
    WaitFor $phase { (Matches (Properties) $currentTrack) -and $script:targetSession.GetPlaybackInfo().PlaybackStatus.ToString() -eq 'Playing' }
    $startPosition = $script:targetSession.GetTimelineProperties().Position.TotalMilliseconds
    WaitFor 'position advances' { $script:targetSession.GetTimelineProperties().Position.TotalMilliseconds -gt $startPosition + 1000 } 15
    $positionAdvanced = $true
    Checkpoint $phase $currentTrack 'Playing' 'A'

    $phase = 'next_good_cover'
    Transport 'next_to_B' ($script:targetSession.TrySkipNextAsync())
    WaitFor $phase { (Matches (Properties) $nextTrack) -and $script:targetSession.GetPlaybackInfo().PlaybackStatus.ToString() -eq 'Playing' }
    Checkpoint $phase $nextTrack 'Playing' 'B'
    WaitFor 'local thumbnail' { $null -ne (Properties).Thumbnail } 10
    $thumbnailAvailable = $true

    $phase = 'pause'
    Transport 'pause_B' ($script:targetSession.TryPauseAsync())
    WaitFor $phase { $script:targetSession.GetPlaybackInfo().PlaybackStatus.ToString() -eq 'Paused' }
    Checkpoint $phase $nextTrack 'Paused' 'B'
    $pausedPosition = $script:targetSession.GetTimelineProperties().Position.TotalMilliseconds
    Start-Sleep -Milliseconds 1200
    $pausedPositionStable = [math]::Abs($script:targetSession.GetTimelineProperties().Position.TotalMilliseconds - $pausedPosition) -le 100
    if (-not $pausedPositionStable) { throw 'Paused position moved' }

    $phase = 'resume'
    Transport 'resume_B' ($script:targetSession.TryPlayAsync())
    WaitFor $phase { (Matches (Properties) $nextTrack) -and $script:targetSession.GetPlaybackInfo().PlaybackStatus.ToString() -eq 'Playing' }
    Checkpoint $phase $nextTrack 'Playing' 'B'

    $phase = 'previous_bad_cover'
    Transport 'previous_to_A' ($script:targetSession.TrySkipPreviousAsync())
    WaitFor $phase { (Matches (Properties) $currentTrack) -and $script:targetSession.GetPlaybackInfo().PlaybackStatus.ToString() -eq 'Playing' }
    Checkpoint $phase $currentTrack 'Playing' 'A'
} catch {
    $failure = [pscustomobject]@{ phase = $phase; error_type = $_.Exception.GetType().FullName }
    Write-Output ("failed: " + $phase)
} finally {
    if ($candidateProcess -and -not $candidateProcess.HasExited) {
        $closed = $candidateProcess.CloseMainWindow()
        if (-not $candidateProcess.WaitForExit(8000)) { $candidateProcess.Kill(); $candidateProcess.WaitForExit() }
    }
}
ObserveLogs 'after_test_process_exit'
$finalCounts = LogCounts
$fallbackCount = $finalCounts.artwork_attempt_failure_lines - $initialCounts.artwork_attempt_failure_lines
$textFailureCount = $finalCounts.text_or_clear_failure_lines - $initialCounts.text_or_clear_failure_lines
$originalStillRunning = @($originalProcesses | Where-Object { Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue }).Count -eq $originalProcesses.Count
$report = [pscustomobject]@{
    schema_version = 2
    source_patch_sha256 = $build.source_patch_sha256
    source_snapshot_sha256 = $build.source_snapshot_sha256
    binary_sha256 = $context.binary_sha256
    acceptance_script_sha256 = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
    checks = $checks.ToArray()
    transport_returns = $transportResults.ToArray()
    saved_position_matches = $restoredPositionMatches
    position_advanced = $positionAdvanced
    paused_position_stable = $pausedPositionStable
    good_local_cover_has_thumbnail = $thumbnailAvailable
    artwork_attempt_failure_log_count = $fallbackCount
    text_or_clear_failure_log_count = $textFailureCount
    transport_return_meaning = 'SMTC command accepted, not set_metadata return value or audible output'
    log_observations = [pscustomobject]@{
        evidence_kind = 'log_line_counts_not_metadata_return_values'
        initial = $initialCounts
        final_after_process_exit = $finalCounts
        boundaries = $logEvents.ToArray()
        caveat = 'Buffered log delivery may shift a line across observation boundaries; counts do not prove text-only publication returned success.'
    }
    position_assertions = [pscustomobject]@{
        expected_restore_source = 'private queue-seed.json / current_position_ms, set by fixture preparation'
        synthetic_expected_restore_ms = $seed.current_position_ms
        restore_tolerance_ms = 100
        restore_match = $restoredPositionMatches
        minimum_advance_ms = 1000
        advance_timeout_seconds = 15
        advance_match = $positionAdvanced
        paused_sample_interval_ms = 1200
        paused_tolerance_ms = 100
        paused_stability_match = $pausedPositionStable
    }
    metadata_native_return_values_captured = $false
    audio_audibility_or_exclusive_output_asserted = $false
    original_instance_still_running = $originalStillRunning
    test_instance_exited = ($null -ne $candidateProcess -and $candidateProcess.HasExited)
    failure = $failure
    passed = ($null -eq $failure -and $fallbackCount -ge 1 -and $textFailureCount -eq 0)
}
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
$report | ConvertTo-Json -Depth 8 -Compress
if (-not $report.passed) { exit 1 }
