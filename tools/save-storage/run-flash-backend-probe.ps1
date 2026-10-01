[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    [Parameter(Mandatory=$true)][string]$CoreDirectory,
    [Parameter(Mandatory=$true)][string]$EvidenceRoot,
    [string]$ParentTempDirectory
)
$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$CoreDirectory = (Resolve-Path -LiteralPath $CoreDirectory).Path
$EvidenceRoot = (Resolve-Path -LiteralPath $EvidenceRoot).Path
$corePath = Join-Path $CoreDirectory 'CRAZYFLASHER7MercenaryEmpire.Core.dll'
$probeSwf = Join-Path $ProjectRoot 'scripts/TestLoader.swf'
$flashExe = Join-Path $ProjectRoot 'Adobe Flash Player 20.exe'
foreach($required in @($corePath,$probeSwf,$flashExe)) { if(!(Test-Path -LiteralPath $required)){throw "Missing probe input: $required"} }
# PowerShell 7 的 .NET 10 宿主加载同版本 Desktop 类型；不安装或修改机器运行时。
$desktopRoot = Join-Path $env:LOCALAPPDATA 'Microsoft/dotnet/shared/Microsoft.WindowsDesktop.App'
$desktop = Get-ChildItem -LiteralPath $desktopRoot -Directory | Where-Object {$_.Name -like '10.*'} | Sort-Object {[version]$_.Name} -Descending | Select-Object -First 1
foreach($dll in @('System.Drawing.Common.dll','System.Windows.Forms.Primitives.dll','System.Windows.Forms.dll')) {
    [void][Reflection.Assembly]::LoadFrom((Join-Path $desktop.FullName $dll))
}
[void][Reflection.Assembly]::LoadFrom((Join-Path $CoreDirectory 'Newtonsoft.Json.dll'))
$core = [Reflection.Assembly]::LoadFrom($corePath)
$managerType = $core.GetType('CF7Launcher.Guardian.ProcessManager', $true)
$locatorType = $core.GetType('CF7Launcher.Save.SolFileLocator', $true)
$locator = [Activator]::CreateInstance($locatorType)
$parentTemp = [Environment]::GetEnvironmentVariable('TEMP')
$parentTmp = [Environment]::GetEnvironmentVariable('TMP')
$aliasRoot = Join-Path $EvidenceRoot 'drive-alias'
New-Item -ItemType Directory -Path $aliasRoot -Force | Out-Null
$aliasRoot = [IO.Path]::GetFullPath($aliasRoot)
if(!$aliasRoot.StartsWith($EvidenceRoot + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Alias escaped evidence root'}
$subst = Join-Path $env:WINDIR 'System32/subst.exe'
$aliasLetter = $null
if($ParentTempDirectory){$aliasTemp=(Resolve-Path -LiteralPath $ParentTempDirectory).Path}
else{
    $aliasLetter = @('W','X','Y','Z') | Where-Object { !(Test-Path -LiteralPath ($_+':\')) } | Select-Object -First 1
    if(!$aliasLetter){throw 'No unused drive letter for isolated path-letter control'}
    & $subst ($aliasLetter+':') $aliasRoot
    if($LASTEXITCODE -ne 0){throw 'Could not create owned temporary drive alias'}
    $aliasTemp = $aliasLetter+':\'
}
$results = @()
$ownedSlots = @()
function Invoke-FlashProbe([string]$phase,[string]$nonce,[bool]$guarded) {
    $slot = 'cf7_env_probe_'+$nonce
    $request = @{phase=$phase;nonce=$nonce;slot=$slot}|ConvertTo-Json -Compress
    [IO.File]::WriteAllText((Join-Path $EvidenceRoot 'request.json'),$request,[Text.UTF8Encoding]::new($false))
    $resultPath = Join-Path $EvidenceRoot 'result.json'
    if(Test-Path -LiteralPath $resultPath){Remove-Item -LiteralPath $resultPath}
    $manager = $null
    $process = $null
    try {
        if($guarded){
            $constructor = $managerType.GetConstructor([type[]]@([string],[string]))
            $manager = $constructor.Invoke([object[]]@([string]$flashExe,[string]$probeSwf))
            if(!$manager.Start()){throw 'Production ProcessManager failed to prepare/start probe'}
            $process = $manager.FlashProcess
        }else{
            $start = [Diagnostics.ProcessStartInfo]::new($flashExe)
            $start.UseShellExecute=$false
            $start.Arguments='"'+$probeSwf+'"'
            $start.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
            $process=[Diagnostics.Process]::Start($start)
        }
        $probePid=$process.Id
        $deadline=[DateTime]::UtcNow.AddSeconds(25)
        while(!(Test-Path -LiteralPath $resultPath) -and [DateTime]::UtcNow -lt $deadline){
            if($process.HasExited){throw 'Flash probe exited before reporting'}
            Start-Sleep -Milliseconds 100
        }
        if(!(Test-Path -LiteralPath $resultPath)){throw 'Flash probe did not return a bound outcome'}
        $response=Get-Content -LiteralPath $resultPath -Encoding UTF8 -Raw|ConvertFrom-Json
        if($response.phase -ne $phase -or $response.nonce -ne $nonce -or $response.slot -ne $slot){throw 'Probe response identity mismatch'}
        return [ordered]@{phase=$phase;nonce=$nonce;slot=$slot;pid=$probePid;guarded=$guarded;outcome=$response.outcome}
    }finally{
        if($manager){$manager.KillFlash();$manager.Dispose()}
        elseif($process){
            if(!$process.HasExited){[void]$process.CloseMainWindow();if(!$process.WaitForExit(2000)){$process.Kill();[void]$process.WaitForExit(2000)}}
            $process.Dispose()
        }
    }
}
try {
    [Environment]::SetEnvironmentVariable('TEMP',$aliasTemp,'Process')
    [Environment]::SetEnvironmentVariable('TMP',$aliasTemp,'Process')
    $rawNonce=[Guid]::NewGuid().ToString('N').Substring(0,16)
    $ownedSlots+='cf7_env_probe_'+$rawNonce
    $results+=Invoke-FlashProbe 'write' $rawNonce $false
    $safeNonce=[Guid]::NewGuid().ToString('N').Substring(0,16)
    $ownedSlots+='cf7_env_probe_'+$safeNonce
    $results+=Invoke-FlashProbe 'write' $safeNonce $true
    $results+=Invoke-FlashProbe 'read' $safeNonce $true
    if($results[1].outcome -ne 'true' -or $results[2].outcome -ne $safeNonce -or $results[1].pid -eq $results[2].pid){throw 'Guarded write/fresh-process readback failed'}
    $sol=$locator.FindSolFile('cf7_env_probe_'+$safeNonce,$probeSwf)
    if(!$sol){throw 'Committed probe SOL was not found'}
    Copy-Item -LiteralPath $sol -Destination (Join-Path $EvidenceRoot 'isolated-probe.sol')
    $report=[ordered]@{
        kind='real_flash_standalone_backend';coreSha256=(Get-FileHash -LiteralPath $corePath -Algorithm SHA256).Hash;
        flashSha256=(Get-FileHash -LiteralPath $flashExe -Algorithm SHA256).Hash;swfSha256=(Get-FileHash -LiteralPath $probeSwf -Algorithm SHA256).Hash;
        parentTemp=$aliasTemp;controlKind=$(if($ParentTempDirectory){'caller-owned isolated volume'}else{'SUBST alias; same volume'});cases=$results;
        solSha256=(Get-FileHash -LiteralPath $sol -Algorithm SHA256).Hash;freshProcessReadback=$true;
        limits=@('Standalone component proof does not replace the production Launcher business journey.','Alias control does not prove an independent physical-volume matrix.')
    }
    [IO.File]::WriteAllText((Join-Path $EvidenceRoot 'report.json'),($report|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
    $report|ConvertTo-Json -Depth 8 -Compress
}finally{
    [Environment]::SetEnvironmentVariable('TEMP',$parentTemp,'Process')
    [Environment]::SetEnvironmentVariable('TMP',$parentTmp,'Process')
    foreach($slot in $ownedSlots){if($slot -match '^cf7_env_probe_[a-f0-9]{16}$'){[void]$locator.DeleteAllSolFiles($slot,$probeSwf)}}
    if($aliasLetter){
        $mapping=(& $subst)|Out-String
        if($mapping.Contains($aliasRoot)){& $subst ($aliasLetter+':') /D}else{throw 'Owned drive mapping drifted; refuse to remove another mapping'}
    }
}
