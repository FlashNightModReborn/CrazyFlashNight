param(
    [Parameter(Mandatory=$true)]
    [ValidatePattern('^c-[0-9a-f]{12}-[0-9a-f]{10}-[a-z0-9][a-z0-9-]{0,31}$')]
    [string]$CandidateId,
    [string]$OutputName = 'played-save-readback.json'
)
$ErrorActionPreference = 'Stop'
chcp.com 65001 > $null
if($OutputName -cnotmatch '^[a-z0-9][a-z0-9-]*\.json$'){throw 'OutputName must be a simple task-owned JSON filename'}
$playedRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
if(@(Get-CimInstance Win32_Process -Filter "Name='CRAZYFLASHER7MercenaryEmpire.Core.exe'" | Where-Object {
    $_.ExecutablePath -and $_.ExecutablePath.StartsWith($playedRoot + '\',[StringComparison]::OrdinalIgnoreCase)
}).Count){throw 'Run only after all game/runner processes from this resources directory exited normally'}
$playedBundle = Join-Path $playedRoot 'tmp/issue-152-acceptance'
$playedManifest = Get-Content -LiteralPath (Join-Path $playedBundle 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$playedRuntime = Join-Path $playedRoot ('tmp/runtime-candidates/v2/' + $CandidateId + '/runtime')
Add-Type -Path (Join-Path $playedRuntime 'Newtonsoft.Json.dll')
Add-Type -Path (Join-Path $playedRuntime 'CRAZYFLASHER7MercenaryEmpire.Core.dll')
# A fresh PowerShell process loads the selected candidate parser explicitly.
[void][Runtime.InteropServices.NativeLibrary]::Load((Join-Path $playedRuntime 'sol_parser.dll'))
$playedParserModule = @((Get-Process -Id $PID).Modules | Where-Object ModuleName -eq 'sol_parser.dll')
if($playedParserModule.Count -ne 1 -or $playedParserModule[0].FileName -ine (Join-Path $playedRuntime 'sol_parser.dll')){
    throw 'SOL parser is not bound to the selected candidate'
}
$playedArchive = [CF7Launcher.Tasks.ArchiveTask]::new($playedRoot)
$playedLocator = [CF7Launcher.Save.SolFileLocator]::new()
# No shadow writer: production resolution/normalization remains in memory.
$playedResolver = [CF7Launcher.Save.SolResolver]::new($playedLocator,$playedArchive,[CF7Launcher.Save.NativeSolParser]::new(),$null)
$playedSwf = Join-Path $playedRoot 'CRAZYFLASHER7MercenaryEmpire.swf'
$playedExpected = @{
    cf7_agent_152_a28=@(500000,0,0);cf7_agent_152_b29=@(494000,1,0);cf7_agent_152_c68=@(500000,0,0)
    cf7_agent_152_d69=@(480000,0,1);cf7_agent_152_e69=@(494000,1,0)
}
if($playedManifest.slots.Count -ne 5 -or
    ((@($playedManifest.slots.slot|Sort-Object) -join ',') -cne (@($playedExpected.Keys|Sort-Object) -join ','))){
    throw 'Prepared manifest is not the exact five-slot test cohort'
}
$playedEntries = foreach($playedEntry in $playedManifest.slots){
    if(-not $playedExpected.ContainsKey($playedEntry.slot)){throw 'Unexpected fixture slot'}
    $playedResolved = $playedResolver.Resolve($playedEntry.slot,$playedSwf)
    if($playedResolved.WireDecision -cne 'snapshot' -or -not [CF7Launcher.Save.SaveMigrator]::ValidateResolvedSnapshot($playedResolved.Snapshot)){
        throw ('Production loader rejected ' + $playedEntry.slot)
    }
    $playedSnapshot = $playedResolved.Snapshot
    $playedMoney = [int]$playedSnapshot['0'][2].ToString()
    $playedGlue = if($null -ne $playedSnapshot['collection']['材料']['强力胶']){[int]$playedSnapshot['collection']['材料']['强力胶'].ToString()}else{0}
    $playedCloth = if($null -ne $playedSnapshot['collection']['材料']['军用帆布']){[int]$playedSnapshot['collection']['材料']['军用帆布'].ToString()}else{0}
    $playedScarf = @($playedSnapshot['inventory']['背包'].Properties() | Where-Object { $null -ne $_.Value['name'] -and $_.Value['name'].ToString() -ceq '黑铁死士围巾' }).Count
    $playedMain = [int]$playedSnapshot['tasks']['task_chains_progress']['主线'].ToString()
    $playedMotorcycle = [int]$playedSnapshot['infrastructure']['摩托车'].ToString()
    $playedBookToken = $playedSnapshot['ext']['bookRun']
    $playedBookRun = if($null -eq $playedBookToken -or $playedBookToken.Type -eq [Newtonsoft.Json.Linq.JTokenType]::Null){$null}else{
        $playedBookToken.ToString([Newtonsoft.Json.Formatting]::None)|ConvertFrom-Json
    }
    $playedActual = @($playedMoney,$playedGlue,$playedScarf)
    $playedMatches = ($playedActual -join ',') -ceq ($playedExpected[$playedEntry.slot] -join ',') -and
        $playedSnapshot['0'][0].ToString() -ceq $playedEntry.name -and $playedMain -eq $playedEntry.main -and
        $playedMotorcycle -eq $playedEntry.motorcycle -and $null -eq $playedBookRun
    [ordered]@{slot=$playedEntry.slot;name=$playedSnapshot['0'][0].ToString();decision=$playedResolved.WireDecision;
        source=$playedResolved.Source;solPath=$playedLocator.FindSolFile($playedEntry.slot,$playedSwf);
        money=$playedMoney;glue=$playedGlue;scarf=$playedScarf;militaryCloth=$playedCloth;
        main=$playedMain;motorcycle=$playedMotorcycle;expectedMatches=$playedMatches;bookRun=$playedBookRun}
}
$playedPreserved = Get-Content -LiteralPath (Join-Path $playedBundle 'preexisting-saves.sha256.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$playedDeltas = @(foreach($playedRecord in $playedPreserved){
    $playedCurrentHash = if(Test-Path -LiteralPath $playedRecord.path){(Get-FileHash -LiteralPath $playedRecord.path -Algorithm SHA256).Hash}else{$null}
    if($playedCurrentHash -cne $playedRecord.sha256){
        [ordered]@{path=$playedRecord.path;before=$playedRecord.sha256;after=$playedCurrentHash;
            launcherMarker=([IO.Path]::GetFullPath($playedRecord.path) -ieq (Join-Path $playedRoot 'saves/.launcher-version-marker.json'))}
    }
})
$playedSuccess = @($playedEntries|Where-Object {-not $_.expectedMatches -or $_.militaryCloth -ne 0}).Count -eq 0 -and @($playedDeltas|Where-Object {-not $_.launcherMarker}).Count -eq 0
$playedReport = [ordered]@{schema='issue152-played-save-readback.v1';createdAtUtc=[datetime]::UtcNow.ToString('o');
    candidateId=$CandidateId;coreDllSha256=(Get-FileHash -LiteralPath (Join-Path $playedRuntime 'CRAZYFLASHER7MercenaryEmpire.Core.dll')).Hash;
    parserPath=$playedParserModule[0].FileName;slots=@($playedEntries);preexistingFileDeltas=$playedDeltas;success=$playedSuccess;
    evidence='offline production SOL/shadow resolver and schema readback; combine with actual runtime session audits';
    humanAccepted=$false;promoted=$false}
$playedDestination = Join-Path $playedBundle $OutputName
$playedStream = [IO.File]::Open($playedDestination,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try{$playedBytes=[Text.Encoding]::UTF8.GetBytes(($playedReport|ConvertTo-Json -Depth 12)+"`n");$playedStream.Write($playedBytes,0,$playedBytes.Length)}finally{$playedStream.Dispose()}
$playedReport|ConvertTo-Json -Depth 12
if(-not $playedSuccess){exit 1}
