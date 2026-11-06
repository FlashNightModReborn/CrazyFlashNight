[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$EvidenceRoot,[string]$ProbeSwf)
$ErrorActionPreference='Stop'
$project=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$evidence=(Resolve-Path -LiteralPath $EvidenceRoot).Path
$swf=Join-Path $project 'Cf6SoldierLootColdProbe.swf'
if($ProbeSwf){
    $candidate=(Resolve-Path -LiteralPath $ProbeSwf).Path
    if((Get-FileHash -LiteralPath $candidate).Hash -cne (Get-FileHash -LiteralPath $swf).Hash){throw 'Probe SWF copy differs from the freshly compiled artifact'}
    $swf=$candidate
}
$player=Join-Path $project 'Adobe Flash Player 20.exe'
$coreDirectory=Join-Path $project 'runtime'
$desktop=Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'Microsoft/dotnet/shared/Microsoft.WindowsDesktop.App') -Directory |
    Where-Object {$_.Name -like '10.*'} | Sort-Object {[version]$_.Name} -Descending | Select-Object -First 1
foreach($dll in @('System.Drawing.Common.dll','System.Windows.Forms.Primitives.dll','System.Windows.Forms.dll')) {
    [void][Reflection.Assembly]::LoadFrom((Join-Path $desktop.FullName $dll))
}
[void][Reflection.Assembly]::LoadFrom((Join-Path $coreDirectory 'Newtonsoft.Json.dll'))
$corePath=Join-Path $coreDirectory 'CRAZYFLASHER7MercenaryEmpire.Core.dll'
$core=[Reflection.Assembly]::LoadFrom($corePath)
$environmentType=$core.GetType('CF7Launcher.Config.FlashStorageEnvironment',$true)
$prepare=$environmentType.GetMethod('Prepare',[Reflection.BindingFlags]'Static,NonPublic')
$results=@()
$files=@()
foreach($kind in @('longgun','sidearm_pair','none')) {
    $nonce=[guid]::NewGuid().ToString('N').Substring(0,16)
    $slot='cf7_env_cf6_loot_'+$nonce
    foreach($phase in @('decide','admit','claim','read')) {
        $request=[ordered]@{phase=$phase;nonce=$nonce;slot=$slot;kind=$kind}
        [IO.File]::WriteAllText((Join-Path $evidence 'request.json'),($request | ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
        $resultFile=Join-Path $evidence 'result.json'
        if(Test-Path -LiteralPath $resultFile){Remove-Item -LiteralPath $resultFile}
        $start=[Diagnostics.ProcessStartInfo]::new($player)
        $start.UseShellExecute=$false
        $start.Arguments='"'+$swf+'"'
        $start.WorkingDirectory=$project
        $start.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
        [void]$prepare.Invoke($null,[object[]]@($start,$null))
        $process=[Diagnostics.Process]::Start($start)
        try {
            $deadline=[DateTime]::UtcNow.AddSeconds(40)
            while(!(Test-Path -LiteralPath $resultFile) -and [DateTime]::UtcNow -lt $deadline) {
                if($process.HasExited){throw 'Owned Flash probe exited without a result'}
                Start-Sleep -Milliseconds 100
            }
            if(!(Test-Path -LiteralPath $resultFile)){throw 'Owned cold probe did not report before deadline'}
            $response=Get-Content -LiteralPath $resultFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if($response.phase -cne $phase -or $response.nonce -cne $nonce -or $response.slot -cne $slot -or $response.kind -cne $kind){throw 'Cold probe response identity mismatch'}
            $results+=[ordered]@{phase=$phase;kind=$kind;slot=$slot;pid=$process.Id;outcome=$response.outcome;rolls=$response.rolls}
            [IO.File]::WriteAllText((Join-Path $evidence 'progress.json'),($results | ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
            if($response.outcome -cne 'ok'){throw ('Owned cold probe failed: '+$kind+'/'+$phase+' '+$response.outcome)}
            if($response.rolls -ne $(if($phase -eq 'decide'){1}else{0})){throw 'Cold probe gate-count mismatch'}
        } finally {
            if(!$process.HasExited){[void]$process.CloseMainWindow();if(!$process.WaitForExit(2000)){$process.Kill();[void]$process.WaitForExit(2000)}}
            $process.Dispose()
        }
        $storageRoot=Join-Path $env:APPDATA 'Macromedia/Flash Player/#SharedObjects'
        $matches=@(Get-ChildItem -LiteralPath $storageRoot -Filter ($slot+'.sol') -File -Recurse -Force)
        if($matches.Count -ne 1){throw 'Owned SOL path is missing or ambiguous'}
        $owned=$matches[0].FullName
        if(!([IO.Path]::GetFullPath($owned).StartsWith([IO.Path]::GetFullPath($storageRoot)+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase))){throw 'Owned SOL escaped storage root'}
        Copy-Item -LiteralPath $owned -Destination (Join-Path $evidence ($kind+'-'+$phase+'.sol'))
        $files+=[ordered]@{kind=$kind;phase=$phase;sha256=(Get-FileHash -LiteralPath $owned -Algorithm SHA256).Hash;bytes=(Get-Item -LiteralPath $owned).Length}
        if($phase -eq 'read') {
            # This exact random slot was created and verified by the four
            # processes above. Only its own single SOL is removed.
            Remove-Item -LiteralPath $owned
        }
    }
}
if(@($results.pid | Select-Object -Unique).Count -ne 12){throw 'Cold read did not use twelve distinct processes'}
$report=[ordered]@{schema='cf6-fixed-loot.cold-native.v1';cases=$results;files=$files;
    swfSha256=(Get-FileHash -LiteralPath $swf).Hash;playerSha256=(Get-FileHash -LiteralPath $player).Hash;
    coreSha256=(Get-FileHash -LiteralPath $corePath).Hash;productionStorageEnvironment=$true;
    freshProcessReadback=$true;playerSavesOpened=$false;controlledGateAndEquipment=$true;
    scope='Real standalone SaveManager, staging, claim and cold-read components; not production Launcher SafeExit UI acceptance'}
[IO.File]::WriteAllText((Join-Path $evidence 'report.json'),($report | ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
Write-Host '[OK] Three exclusive loot results survived twelve independent Flash processes without reroll or duplication.'
