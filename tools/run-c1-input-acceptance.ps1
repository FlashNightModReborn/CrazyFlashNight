[CmdletBinding()]
param([switch]$VerifyOnly)
$ErrorActionPreference = 'Stop'
chcp.com 65001 | Out-Null
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$selectorPath = Join-Path $repo 'tmp\c1-input-human\current.json'
if (-not (Test-Path -LiteralPath $selectorPath)) { throw '本机 C1 人验候选尚未冻结，请先完成候选构建与自动检查。' }
$selector = Get-Content -LiteralPath $selectorPath -Raw -Encoding UTF8 | ConvertFrom-Json
$candidate = [IO.Path]::GetFullPath((Join-Path $repo $selector.candidate))
$allowedRoot = [IO.Path]::GetFullPath((Join-Path $repo 'tmp')) + '\'
if (-not $candidate.StartsWith($allowedRoot, [StringComparison]::OrdinalIgnoreCase)) { throw '候选必须位于本仓 tmp 目录。' }
$manifestPath = Join-Path $candidate 'manifest.json'
if ((Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash -ne $selector.manifestSha256) { throw '候选清单已改变，拒绝使用旧的人验入口。' }
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.status -ne 'READY_FOR_HUMAN') { throw '候选尚未通过自动检查。' }
foreach ($item in $manifest.files.PSObject.Properties) {
    $path = [IO.Path]::GetFullPath((Join-Path $candidate $item.Name))
    if (-not $path.StartsWith($candidate + '\', [StringComparison]::OrdinalIgnoreCase)) { throw '候选路径越界。' }
    if (-not (Test-Path -LiteralPath $path) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $item.Value) { throw "候选文件缺失或改变：$($item.Name)" }
}
Write-Host "C1 只读验收候选校验通过：$($manifest.closure)"
if ($VerifyOnly) { exit 0 }
. (Join-Path $repo 'launcher\resolve-dotnet.ps1')
$cf7Dotnet = Resolve-Cf7Dotnet -ProjectRoot $repo
$run = (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8)
$evidence = Join-Path $repo ('logs\c1-input-acceptance\' + $run)
New-Item -ItemType Directory -Path $evidence | Out-Null
Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $evidence 'candidate-manifest.json')
Write-Host '只操作 CF7 C1 主窗口。本候选不加载玩家存档，不支持付费提交。'
Write-Host '外部返回时，第一击只激活；等标题显示“可操作”后开始新的点击。'
Write-Host '关闭主窗口后自动保存采样日志；这不代表人验通过。'
Set-Location -LiteralPath $repo
$exitCode = 2
try {
    & $cf7Dotnet (Join-Path $candidate 'bin\C1IslandHost.dll') $repo $evidence --interactive
    $exitCode = $LASTEXITCODE
} finally {
    $records = @(Get-ChildItem -LiteralPath $evidence -File | Where-Object { $_.Extension -in '.json','.jsonl','.txt' })
    if ($records.Count -gt 0) { Compress-Archive -LiteralPath $records.FullName -DestinationPath ($evidence + '.zip') }
    Write-Host "采样日志：$evidence"
}
if ($exitCode -ne 0) { Write-Host '候选因检查失败或连接中断而退出；日志已保留。' }
exit $exitCode
