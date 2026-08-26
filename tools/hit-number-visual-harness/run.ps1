param(
    [string]$OutputRoot,
    [switch]$NoVideo
)

$ErrorActionPreference = 'Stop'
chcp.com 65001 | Out-Null

$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
. (Join-Path $projectRoot 'launcher\resolve-dotnet.ps1')
$dotnetHost = Resolve-Cf7Dotnet -ProjectRoot $projectRoot
$project = Join-Path $PSScriptRoot 'HitNumberVisualHarness.csproj'

$appArgs = @('--project-root', $projectRoot)
if (-not [string]::IsNullOrWhiteSpace($OutputRoot)) {
    $appArgs += @('--output', [IO.Path]::GetFullPath($OutputRoot))
}
if ($NoVideo) { $appArgs += '--no-video' }

Push-Location -LiteralPath $projectRoot
try {
    & $dotnetHost run --project $project --configuration Release -- @appArgs
    if ($LASTEXITCODE -ne 0) {
        throw "hit-number visual harness failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}
