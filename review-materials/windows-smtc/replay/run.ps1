$ErrorActionPreference = 'Stop'
$repo = (Get-Location).Path
$bundle = Split-Path $PSScriptRoot
$contextPath = Join-Path $repo 'target/smtc-acceptance-context.json'
$testRoot = $null
try {
    & python (Join-Path $PSScriptRoot 'prepare.py')
    if ($LASTEXITCODE -ne 0) { throw 'Fixture preparation failed' }
    $context = Get-Content -LiteralPath $contextPath -Raw | ConvertFrom-Json
    $testRoot = [System.IO.Path]::GetFullPath($context.root)
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'acceptance.ps1') -ContextPath $contextPath -OutputPath (Join-Path $bundle 'native-result.replay.json') -BuildManifestPath (Join-Path $bundle 'build-capture.json')
    $acceptanceExit = $LASTEXITCODE
} finally {
    if ($testRoot) {
        $allowedParent = [System.IO.Path]::GetFullPath((Join-Path $repo 'target'))
        if ([System.IO.Path]::GetDirectoryName($testRoot) -ine $allowedParent -or [System.IO.Path]::GetFileName($testRoot) -notmatch '^smtc-windows-acceptance-[a-f0-9]{10}$') { throw 'Unexpected cleanup target' }
        $liveTest = @(Get-CimInstance Win32_Process -Filter "Name = 'Netodia-SMTC-acceptance.exe'")
        if ($liveTest.Count -ne 0) { throw 'Test process is still running; private data retained for local cleanup' }
        Remove-Item -LiteralPath $testRoot -Recurse -Force
        Remove-Item -LiteralPath $contextPath
    }
}
$cleanup = [pscustomobject]@{ private_copy_removed = -not (Test-Path -LiteralPath $testRoot); context_file_removed = -not (Test-Path -LiteralPath $contextPath); assertion_scope = 'Verified test-copy cleanup, not systemwide write tracing' }
$cleanup | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $bundle 'cleanup.replay.json') -Encoding UTF8
if ($acceptanceExit -ne 0) { exit $acceptanceExit }
