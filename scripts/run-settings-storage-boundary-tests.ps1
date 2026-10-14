[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=240)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$projectRoot=Split-Path -Parent $PSScriptRoot
if(@(Get-Process -Name Flash -ErrorAction SilentlyContinue).Count -ne 0) {
    throw 'The serial storage run requires a fresh editor; an existing editor is preserved.'
}
# CS6 does not topologically order all class cycles in a combined TestLoader.
# Keep independent suite roots, complete assertions and raw artifacts.
$runRoot=Join-Path $projectRoot ('tmp/focus-sol-20261013/storage-serial-'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ'))
[void](New-Item -ItemType Directory -Path $runRoot)
$report=[ordered]@{status='running';startedUtc=[DateTime]::UtcNow.ToString('o');stages=@();evidenceKind='independent CS6 suite closures; not a full game journey'}
function Save-Report {
    [IO.File]::WriteAllText((Join-Path $runRoot 'report.json'),($report | ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
}
function Invoke-Stage([string]$Name,[string]$Script,[string[]]$Arguments) {
    $stageRoot=Join-Path $runRoot $Name
    [void](New-Item -ItemType Directory -Path $stageRoot)
    $started=[DateTime]::UtcNow
    $oldError=$ErrorActionPreference
    try {
        $ErrorActionPreference='Continue'
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $Script) @Arguments *> (Join-Path $stageRoot 'run.log')
        $code=$LASTEXITCODE
    } finally { $ErrorActionPreference=$oldError }
    $artifacts=@()
    foreach($artifactName in @('TestLoader.swf','compiler_errors.txt','compile_output.txt','flashlog.txt')) {
        $source=Join-Path $PSScriptRoot $artifactName
        if(Test-Path -LiteralPath $source) {
            Copy-Item -LiteralPath $source -Destination $stageRoot
            $item=Get-Item -LiteralPath $source
            $artifacts+=@{name=$artifactName;sha256=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash;modifiedUtc=$item.LastWriteTimeUtc.ToString('o')}
        }
    }
    $report.stages+=@{name=$Name;exit=$code;startedUtc=$started.ToString('o');completedUtc=[DateTime]::UtcNow.ToString('o');artifacts=$artifacts}
    Save-Report
    Get-Content -LiteralPath (Join-Path $stageRoot 'run.log') -Tail 8
    if($code -ne 0){throw ('Independent stage failed; preserve its editor and evidence: '+$stageRoot)}
}
try {
    Save-Report
    Invoke-Stage 'storage' 'run-save-storage-tests.ps1' @('-TimeoutSeconds',[string]$TimeoutSeconds)
    $owned=@(Get-Process -Name Flash -ErrorAction SilentlyContinue)
    if($owned.Count -ne 1){throw 'Storage stage did not leave its unique editor'}
    $ownedId=$owned[0].Id;$ownedBirth=$owned[0].StartTime.Ticks
    $report.editor=@{pid=$ownedId;startTicks=$ownedBirth};Save-Report
    Invoke-Stage 'reward' 'run-reward-stash-tests.ps1' @('-TimeoutSeconds',[string]$TimeoutSeconds)
    $current=@(Get-Process -Name Flash -ErrorAction SilentlyContinue)
    if($current.Count -ne 1 -or $current[0].Id -ne $ownedId -or $current[0].StartTime.Ticks -ne $ownedBirth) {
        throw 'Editor ownership changed; no process was stopped'
    }
    # Successful native suite closures precede the supported, exact-document exit.
    Invoke-Stage 'editor-close' 'compile_test.ps1' @('-QuitOwnedTestHost')
    Invoke-Stage 'native-sol' 'run-settings-sol-boundary-tests.ps1' @('-TimeoutSeconds',[string]$TimeoutSeconds)
    $report.status='passed'
} catch {
    $report.status='failed';$report.error=$_.Exception.Message
    throw
} finally {
    $report.completedUtc=[DateTime]::UtcNow.ToString('o');Save-Report
    Write-Host ('Serial storage evidence: '+$runRoot)
}
