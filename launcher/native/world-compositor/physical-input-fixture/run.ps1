[CmdletBinding()]
param([string]$CandidateRoot)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'))
if([string]::IsNullOrEmpty($CandidateRoot)){$CandidateRoot=Join-Path $repo 'tmp/r9-physical-input-candidate-20260923-v2'}
$CandidateRoot=[IO.Path]::GetFullPath($CandidateRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
$manifestPath=Join-Path $CandidateRoot 'candidate.json'
$manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$expectedRunner=$manifest.sources.'launcher/native/world-compositor/physical-input-fixture/run.ps1'
if((Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash -ne $expectedRunner){throw 'Candidate runner changed; rebuild/freeze the matching candidate first'}
foreach($entry in $manifest.files){
    $path=[IO.Path]::GetFullPath((Join-Path $CandidateRoot $entry.path))
    if(-not $path.StartsWith($CandidateRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Candidate manifest escaped its root'}
    if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $entry.sha256){throw ('Candidate identity mismatch: '+$entry.path)}
}
. (Join-Path $repo 'launcher/resolve-dotnet.ps1')
$dotnet=Resolve-Cf7Dotnet -ProjectRoot $repo
$run=Join-Path $CandidateRoot ('evidence/'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $run -Force | Out-Null
$previousRoot=$env:DOTNET_ROOT_X64
try {
    $env:DOTNET_ROOT_X64=Split-Path $dotnet -Parent
    Write-Host ('只读输入采样；关闭观察窗口后完成。证据目录：'+$run)
    $process=Start-Process -FilePath (Join-Path $CandidateRoot 'bin/PhysicalInputProbe.exe') -ArgumentList ('"'+$run+'"') -Wait -PassThru -WindowStyle Normal
    $result=$process.ExitCode
} finally {$env:DOTNET_ROOT_X64=$previousRoot}
if($result -ne 0){throw ('Probe failed: '+$result)}
Write-Host '采样结束。此结果不是 C1 或普通游戏验收通过。'
