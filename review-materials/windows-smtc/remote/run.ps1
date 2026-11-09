$ErrorActionPreference = 'Stop'
$repo = (Get-Location).Path
$contextPath = Join-Path $repo 'target/smtc-remote-context.json'
$testRoot = $null
try {
    & python (Join-Path $PSScriptRoot 'prepare.py')
    if ($LASTEXITCODE -ne 0) { throw 'Fixture preparation failed' }
    $context = Get-Content -LiteralPath $contextPath -Raw | ConvertFrom-Json
    $testRoot = [System.IO.Path]::GetFullPath($context.root)
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'acceptance.ps1') -ContextPath $contextPath -OutputPath (Join-Path $PSScriptRoot 'native-result.json') -BuildManifestPath (Join-Path (Split-Path $PSScriptRoot) 'build-capture.json')
    $acceptanceExit = $LASTEXITCODE
} finally {
    if ($testRoot) {
        $allowedParent = [System.IO.Path]::GetFullPath((Join-Path $repo 'target'))
        if ([System.IO.Path]::GetDirectoryName($testRoot) -ine $allowedParent -or [System.IO.Path]::GetFileName($testRoot) -notmatch '^smtc-windows-remote-[a-f0-9]{10}$') { throw 'Unexpected cleanup target' }
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
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'cleanup.json') -Encoding UTF8
if ($acceptanceExit -ne 0) { exit $acceptanceExit }
