[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [Parameter(Mandatory = $true)]
    [string]$CandidateRoot,
    [string]$ReportPath
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
$CandidateRoot = (Resolve-Path -LiteralPath $CandidateRoot).Path.TrimEnd('\')

$buildEnvironmentGate = Join-Path $ProjectRoot 'tools\check-runtime-build-env.ps1'
$qualificationProject = Join-Path $ProjectRoot 'tools\player-info-hud\renderer-qualification\RendererQualification.csproj'
if (-not (Test-Path -LiteralPath $buildEnvironmentGate -PathType Leaf)) {
    throw "Pinned build-environment gate is missing: $buildEnvironmentGate"
}
if (-not (Test-Path -LiteralPath $qualificationProject -PathType Leaf)) {
    throw "PlayerInfo qualification project is missing: $qualificationProject"
}

# A caller cannot substitute an arbitrary host. The repository build-environment
# gate supplies CF7_DOTNET_EXE only after the exact SDK and toolchain bytes pass.
[Environment]::SetEnvironmentVariable('CF7_DOTNET_EXE', $null, 'Process')
[Environment]::SetEnvironmentVariable('CF7_RUNTIME_BASELINE', $null, 'Process')
. $buildEnvironmentGate -ProjectRoot $ProjectRoot -Mode Validate
$dotnet = $env:CF7_DOTNET_EXE
if ([string]::IsNullOrWhiteSpace($dotnet) -or -not (Test-Path -LiteralPath $dotnet -PathType Leaf)) {
    throw 'Pinned build-environment validation did not provide CF7_DOTNET_EXE.'
}
$dotnet = [IO.Path]::GetFullPath($dotnet)

Push-Location -LiteralPath $ProjectRoot
try {
    & $dotnet restore $qualificationProject --locked-mode -r win-x64
    if ($LASTEXITCODE -ne 0) {
        throw "PlayerInfo production-contract locked restore failed with exit code $LASTEXITCODE."
    }

    & $dotnet build $qualificationProject --no-restore -c Release -r win-x64
    if ($LASTEXITCODE -ne 0) {
        throw "PlayerInfo production-contract build failed with exit code $LASTEXITCODE."
    }

    $runArguments = @(
        'run',
        '--project', $qualificationProject,
        '--no-build',
        '--no-restore',
        '-c', 'Release',
        '-r', 'win-x64',
        '--',
        '--production-contract-only',
        '--project-root', $ProjectRoot,
        '--candidate-root', $CandidateRoot
    )
    if (-not [string]::IsNullOrWhiteSpace($ReportPath)) {
        $runArguments += @('--report', [IO.Path]::GetFullPath($ReportPath))
    }

    & $dotnet @runArguments
    if ($LASTEXITCODE -ne 0) {
        throw "PlayerInfo production contract failed with exit code $LASTEXITCODE."
    }
} finally {
    Pop-Location
}
