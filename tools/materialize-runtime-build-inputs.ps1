param(
    [string]$ProjectRoot
)

$ErrorActionPreference = 'Stop'
if (-not $ProjectRoot) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
. (Join-Path $ProjectRoot 'tools\runtime-build-v2-common.ps1')

$paths = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
foreach ($domain in @('artifactSource','producerRecipe','toolchainLock','policy')) {
    foreach ($path in Get-Cf7RuntimeV2DomainFiles -ProjectRoot $ProjectRoot -Domain $domain -Mode Index) {
        if (-not $path -or $path -match '^[A-Za-z]:' -or $path -match '(^|/)\.\.(/|$)') {
            throw "Unsafe runtime sparse-checkout path: $path"
        }
        [void]$paths.Add(([string]$path).Replace('\', '/'))
    }
}

$ordered = [string[]]$paths
[Array]::Sort($ordered, [StringComparer]::Ordinal)
$sparsePatterns = @($ordered | ForEach-Object { '/' + $_ })
$previousOutputEncoding = $OutputEncoding
try {
    # Windows PowerShell 5.1 otherwise encodes native-pipeline stdin as ASCII. That
    # silently turns a tracked path such as 本地开发启动.cmd into question marks on a
    # pristine hosted runner, even though the JSON and Git index both contain it.
    $OutputEncoding = New-Object Text.UTF8Encoding($false)
    $sparsePatterns | & git -C $ProjectRoot sparse-checkout set --no-cone --stdin
    if ($LASTEXITCODE -ne 0) { throw 'Failed to materialize the runtime identity sparse checkout.' }
} finally {
    $OutputEncoding = $previousOutputEncoding
}
# Git for Windows can defer root-file vivification while non-cone patterns are
# replaced through stdin. Reapply makes the index/worktree transition explicit
# before any producer or identity reader touches those files.
& git -C $ProjectRoot sparse-checkout reapply
if ($LASTEXITCODE -ne 0) { throw 'Failed to reapply the runtime identity sparse checkout.' }

$totalBytes = 0L
foreach ($relativePath in $ordered) {
    $fullPath = Join-Path $ProjectRoot $relativePath.Replace('/', '\')
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "Sparse checkout did not materialize a runtime identity file: $relativePath"
    }
    $totalBytes += (Get-Item -LiteralPath $fullPath).Length
}
& git -C $ProjectRoot diff --quiet --exit-code
if ($LASTEXITCODE -ne 0) { throw 'Runtime sparse materialization changed tracked worktree bytes.' }
& git -C $ProjectRoot diff --cached --quiet --exit-code
if ($LASTEXITCODE -ne 0) { throw 'Runtime sparse materialization changed the Git index.' }

Write-Host "[RuntimeSparseCheckout] OK files=$($ordered.Count) bytes=$totalBytes" -ForegroundColor Green
return [pscustomobject]@{ files=$ordered.Count; bytes=$totalBytes }
