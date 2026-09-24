[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$CandidatePath)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$candidate=[IO.Path]::GetFullPath($CandidatePath)
$allowed=(Join-Path $repo 'tmp')+[IO.Path]::DirectorySeparatorChar
if(-not $candidate.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Candidate must be under repository tmp'}
if(Get-Process CRAZYFLASHER7MercenaryEmpire.Core -ErrorAction SilentlyContinue){throw '已有游戏进程，请正常退出后再启动本轮候选。'}
$sourceSnapshot=Join-Path $candidate 'diagnostic-source-snapshot.json'
if(Test-Path -LiteralPath $sourceSnapshot){
    $snapshot=Get-Content -LiteralPath $sourceSnapshot -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach($entry in $snapshot.sources){
        if((Get-FileHash -LiteralPath $entry.path -Algorithm SHA256).Hash -ne $entry.sha256){throw ('配套源码已变化，请先核对：'+$entry.path)}
    }
}
$run=Join-Path $repo ('tmp/world-input-run-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $run | Out-Null
Copy-Item -LiteralPath (Join-Path $candidate 'development-pair.json') -Destination $run
if(Test-Path -LiteralPath $sourceSnapshot){Copy-Item -LiteralPath $sourceSnapshot -Destination $run}
$started=[DateTime]::UtcNow
[pscustomobject]@{startedUtc=$started.ToString('o');candidate=$candidate;inputTestCap=0;humanAcceptance='NOT_RECORDED'} |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $run 'run.json') -Encoding UTF8
$launchExit=$null
try {
    # The child shell isolates run-game's exit statement. Its GUI process is
    # explicitly waited for; collection must never race ahead of the session.
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'run-game.ps1') -CandidatePath $candidate -FocusTrace
    $launchExit=$LASTEXITCODE
} finally {
    $contextPath=Join-Path $repo 'logs/focus-trace/recording-context.json'
    $context=$null;$matched=$false
    if(Test-Path -LiteralPath $contextPath){
        $context=Get-Content -LiteralPath $contextPath -Raw -Encoding UTF8 | ConvertFrom-Json
        # FocusTrace stores escaped path text. Normalize before exact comparison.
        $actual=[IO.Path]::GetFullPath(($context.process.path -replace '\\\\','\'))
        $matched=$actual -eq (Join-Path $candidate 'CRAZYFLASHER7MercenaryEmpire.Core.exe') -and
            [DateTime]::Parse($context.process.startedAtUtc).ToUniversalTime() -ge $started
    }
    if($matched){
        foreach($name in @('launcher.log','perf-latest.jsonl')){
            $path=Join-Path $repo ('logs/'+$name)
            if(Test-Path -LiteralPath $path){Copy-Item -LiteralPath $path -Destination $run}
        }
        Copy-Item -LiteralPath (Join-Path $repo 'logs/focus-trace') -Destination (Join-Path $run 'focus-trace') -Recurse
        Get-ChildItem -LiteralPath (Join-Path $repo 'logs/focus-diagnostic') -Filter ('*'+$context.session+'*.zip') -ErrorAction SilentlyContinue |
            ForEach-Object {Copy-Item -LiteralPath $_.FullName -Destination $run}
        & node (Join-Path $PSScriptRoot 'analyze-input-trace.cjs') (Join-Path $run 'launcher.log') (Join-Path $run 'pointer-observed.json')
        if($LASTEXITCODE -ne 0){throw '输入证据分析失败；原始日志仍保留。'}
    }
    [pscustomobject]@{launchExit=$launchExit;identityMatched=$matched;session=$context.session;process=$context.process;
        humanAcceptance='NOT_RECORDED';note='未匹配本次进程时不复制旧日志；端点返回不等于 AS2 按钮成功。'} |
        ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $run 'collection.json') -Encoding UTF8
    Get-ChildItem -LiteralPath $run -File -Recurse | ForEach-Object {
        [pscustomobject]@{path=$_.FullName.Substring($run.Length+1);sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $run 'evidence-sha256.json') -Encoding UTF8
    Write-Output "本轮日志：$run"
}
