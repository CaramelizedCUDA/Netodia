param([ValidateSet('bad_cover', 'remote_cover')][string]$Case)
$ErrorActionPreference = 'Stop'
$repo = (Get-Location).Path
$bundle = Split-Path $PSScriptRoot
if ($Case -eq 'bad_cover') {
    $harness = Join-Path $bundle 'replay'
    $contextPath = Join-Path $repo 'target/smtc-acceptance-context.json'
    $cleanupPattern = '^smtc-windows-acceptance-[a-f0-9]{10}$'
    $acceptanceScript = Join-Path $PSScriptRoot 'acceptance.bad_cover.ps1'
} else {
    $harness = Join-Path $bundle 'remote'
    $contextPath = Join-Path $repo 'target/smtc-remote-context.json'
    $cleanupPattern = '^smtc-windows-remote-[a-f0-9]{10}$'
    $acceptanceScript = Join-Path $harness 'acceptance.ps1'
}
$testRoot = $null
try {
    & python (Join-Path $harness 'prepare.py')
    if ($LASTEXITCODE -ne 0) { throw 'Fixture preparation failed' }
    $context = Get-Content -LiteralPath $contextPath -Raw | ConvertFrom-Json
    $testRoot = [System.IO.Path]::GetFullPath($context.root)
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $acceptanceScript -ContextPath $contextPath -OutputPath (Join-Path $PSScriptRoot ($Case + '.json')) -BuildManifestPath (Join-Path $PSScriptRoot 'build-capture.json')
    $acceptanceExit = $LASTEXITCODE
} finally {
    if ($testRoot) {
        $allowedParent = [System.IO.Path]::GetFullPath((Join-Path $repo 'target'))
        if ([System.IO.Path]::GetDirectoryName($testRoot) -ine $allowedParent -or [System.IO.Path]::GetFileName($testRoot) -notmatch $cleanupPattern) { throw 'Unexpected cleanup target' }
        $liveTest = @(Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -ieq $context.exe })
        if ($liveTest.Count -ne 0) { throw 'Test process remains alive; retain the private copy for local cleanup' }
        Remove-Item -LiteralPath $testRoot -Recurse -Force
        Remove-Item -LiteralPath $contextPath
    }
}
[pscustomobject]@{
    private_copy_removed = -not (Test-Path -LiteralPath $testRoot)
    context_file_removed = -not (Test-Path -LiteralPath $contextPath)
    assertion_scope = 'Test-copy cleanup only; not systemwide write tracing'
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot ($Case + '.cleanup.json')) -Encoding UTF8
if ($acceptanceExit -ne 0) { exit $acceptanceExit }
