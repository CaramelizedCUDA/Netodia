param([string]$ContextPath)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$context = Get-Content -LiteralPath $ContextPath -Raw | ConvertFrom-Json
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
$oldSessionIds = @(SessionList | ForEach-Object { $_.SourceAppUserModelId })
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
function Checkpoint([string]$label, $track, [string]$status) {
    $properties = Properties
    $timeline = $script:targetSession.GetTimelineProperties()
    $actualStatus = $script:targetSession.GetPlaybackInfo().PlaybackStatus.ToString()
    $check = [pscustomobject]@{
        step = $label
        title_matches = ($properties.Title -ceq $track.title)
        artist_matches = ($properties.Artist -ceq ([string]$track.artist).Trim())
        album_matches = ($properties.AlbumTitle -ceq ([string]$track.album).Trim())
        duration_matches = ($timeline.EndTime.TotalMilliseconds -eq $track.duration_ms)
        status_matches = ($actualStatus -eq $status)
        title_is_not_first = ($properties.Title -cne $seed.playlist_tracks[0].title)
    }
    $checks.Add($check)
    if (-not ($check.title_matches -and $check.artist_matches -and $check.album_matches -and
              $check.duration_matches -and $check.status_matches -and $check.title_is_not_first)) {
        throw "Checkpoint mismatch: $label"
    }
    Write-Output ("passed: " + $label)
}
$candidateProcess = $null
$failure = $null
$phase = 'launch'
$positionAdvanced = $false
$pausedPositionStable = $false
$thumbnailAvailable = $false
$initialLogText = (@(Get-ChildItem (Join-Path $context.root 'logs') -Filter '*.log' -ErrorAction SilentlyContinue | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n")
$initialFallbackCount = [regex]::Matches($initialLogText, 'Failed to set media metadata with artwork:').Count
$initialTextFailureCount = [regex]::Matches($initialLogText, 'Failed to set media metadata:|Failed to clear media metadata:').Count
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
        if ($candidates.Count -eq 0) {
            $candidates = @($sessions | Where-Object { $_.SourceAppUserModelId -notin $oldSessionIds })
        }
        if ($candidates.Count -eq 1) { $script:targetSession = $candidates[0]; return $true }
        return $false
    }
    $phase = 'startup_restore_bad_cover'
    WaitFor $phase { (Matches (Properties) $currentTrack) -and $script:targetSession.GetPlaybackInfo().PlaybackStatus.ToString() -eq 'Paused' }
    Checkpoint $phase $currentTrack 'Paused'
    $restoredPositionMatches = [math]::Abs($script:targetSession.GetTimelineProperties().Position.TotalMilliseconds - 1000) -le 100
    if (-not $restoredPositionMatches) { throw 'Saved position mismatch' }

    $phase = 'play_and_progress'
    if (-not (Await ($script:targetSession.TryPlayAsync()) ([bool]))) { throw 'Play was refused' }
    WaitFor $phase { (Matches (Properties) $currentTrack) -and $script:targetSession.GetPlaybackInfo().PlaybackStatus.ToString() -eq 'Playing' }
    $startPosition = $script:targetSession.GetTimelineProperties().Position.TotalMilliseconds
    WaitFor 'position advances' { $script:targetSession.GetTimelineProperties().Position.TotalMilliseconds -gt $startPosition + 1000 } 15
    $positionAdvanced = $true
    Checkpoint $phase $currentTrack 'Playing'

    $phase = 'next_good_cover'
    if (-not (Await ($script:targetSession.TrySkipNextAsync()) ([bool]))) { throw 'Next was refused' }
    WaitFor $phase { (Matches (Properties) $nextTrack) -and $script:targetSession.GetPlaybackInfo().PlaybackStatus.ToString() -eq 'Playing' }
    Checkpoint $phase $nextTrack 'Playing'
    WaitFor 'local thumbnail' { $null -ne (Properties).Thumbnail } 10
    $thumbnailAvailable = $true

    $phase = 'pause'
    if (-not (Await ($script:targetSession.TryPauseAsync()) ([bool]))) { throw 'Pause was refused' }
    WaitFor $phase { $script:targetSession.GetPlaybackInfo().PlaybackStatus.ToString() -eq 'Paused' }
    Checkpoint $phase $nextTrack 'Paused'
    $pausedPosition = $script:targetSession.GetTimelineProperties().Position.TotalMilliseconds
    Start-Sleep -Milliseconds 1200
    $pausedPositionStable = [math]::Abs($script:targetSession.GetTimelineProperties().Position.TotalMilliseconds - $pausedPosition) -le 100
    if (-not $pausedPositionStable) { throw 'Paused position moved' }

    $phase = 'resume'
    if (-not (Await ($script:targetSession.TryPlayAsync()) ([bool]))) { throw 'Resume was refused' }
    WaitFor $phase { (Matches (Properties) $nextTrack) -and $script:targetSession.GetPlaybackInfo().PlaybackStatus.ToString() -eq 'Playing' }
    Checkpoint $phase $nextTrack 'Playing'

    $phase = 'previous_bad_cover'
    if (-not (Await ($script:targetSession.TrySkipPreviousAsync()) ([bool]))) { throw 'Previous was refused' }
    WaitFor $phase { (Matches (Properties) $currentTrack) -and $script:targetSession.GetPlaybackInfo().PlaybackStatus.ToString() -eq 'Playing' }
    Checkpoint $phase $currentTrack 'Playing'
} catch {
    $failure = [pscustomobject]@{ phase = $phase; error_type = $_.Exception.GetType().FullName; message = $_.Exception.Message }
    Write-Output ("failed: " + $phase)
} finally {
    if ($candidateProcess -and -not $candidateProcess.HasExited) {
        $closed = $candidateProcess.CloseMainWindow()
        if (-not $candidateProcess.WaitForExit(8000)) { $candidateProcess.Kill(); $candidateProcess.WaitForExit() }
    }
}
$logText = (@(Get-ChildItem (Join-Path $context.root 'logs') -Filter '*.log' -ErrorAction SilentlyContinue | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n")
$fallbackCount = [regex]::Matches($logText, 'Failed to set media metadata with artwork:').Count - $initialFallbackCount
$textFailureCount = [regex]::Matches($logText, 'Failed to set media metadata:|Failed to clear media metadata:').Count - $initialTextFailureCount
$originalStillRunning = @($originalProcesses | Where-Object { Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue }).Count -eq $originalProcesses.Count
$report = [pscustomobject]@{
    binary_sha256 = $context.binary_sha256
    checks = $checks.ToArray()
    saved_position_matches = $restoredPositionMatches
    position_advanced = $positionAdvanced
    paused_position_stable = $pausedPositionStable
    good_local_cover_has_thumbnail = $thumbnailAvailable
    artwork_fallback_count = $fallbackCount
    text_or_clear_failure_count = $textFailureCount
    original_instance_still_running = $originalStillRunning
    test_instance_exited = ($null -ne $candidateProcess -and $candidateProcess.HasExited)
    failure = $failure
    passed = ($null -eq $failure -and $fallbackCount -ge 1 -and $textFailureCount -eq 0)
}
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path (Split-Path $ContextPath) 'smtc-windows-acceptance-result.json') -Encoding UTF8
$report | ConvertTo-Json -Depth 6 -Compress
if (-not $report.passed) { exit 1 }
