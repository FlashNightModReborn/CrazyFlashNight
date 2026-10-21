#Requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$EvidenceDirectory,
      [ValidateRange(1,3600)][int]$TimeoutSeconds=180, [string]$GuardSource)
$ErrorActionPreference='Stop'
$projectDir=Split-Path -Parent $PSScriptRoot
$debugger='C:/Users/fs/Downloads/adboeflash cs6(1)/Adobe Flash CS6/Players/Debug/FlashPlayerDebugger.exe'
if(-not (Test-Path -LiteralPath $debugger)){throw 'CS6 standalone debug player is unavailable'}
if(Get-Process -Name FlashPlayerDebugger,FlashPlayer -ErrorAction SilentlyContinue){throw 'Another standalone Flash player is active; preserve it'}
$prepareArgs=@('--output',$EvidenceDirectory)
if($GuardSource){$prepareArgs+=@('--guard-source',$GuardSource)}
$bindingText=& python (Join-Path $projectDir 'tools/warlord-dog-assets/prepare_bite_probe.py') @prepareArgs
if($LASTEXITCODE -ne 0){throw 'Native probe generation failed'}
$binding=$bindingText | ConvertFrom-Json
$evidence=$binding.evidence
& (Join-Path $PSScriptRoot 'compile_test.ps1') -Target $binding.target -VerifySwf $binding.swf -TimeoutSeconds $TimeoutSeconds
if($LASTEXITCODE -ne 0){throw 'Native probe CS6 test compilation failed'}
foreach($name in @('compiler_errors.txt','compile_output.txt')){Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $evidence}
& (Join-Path $PSScriptRoot 'compile_test.ps1') -StopTestPlayers -TimeoutSeconds 60
if($LASTEXITCODE -ne 0){throw 'Native test player cleanup was not confirmed'}
$swf=Join-Path $projectDir $binding.swf
Copy-Item -LiteralPath $swf -Destination (Join-Path $evidence 'probe.swf')
$rawTrace=Join-Path $env:APPDATA 'Macromedia/Flash Player/Logs/flashlog.txt'
function Read-SharedTrace([string]$Path) {
    $stream=$null
    try {
        $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        $buffer=[IO.MemoryStream]::new();$stream.CopyTo($buffer);return ,$buffer.ToArray()
    } catch [IO.IOException] { return $null }
    finally {if($null -ne $stream){$stream.Dispose()}}
}
$startedAt=[DateTime]::UtcNow
$player=$null
try {
    $player=Start-Process -FilePath $debugger -ArgumentList ('"'+$swf+'"') -WindowStyle Hidden -PassThru
    $deadline=[DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $complete='FocusedTestRunId warlord-dog-bite Complete: '+$binding.nonce
    do {
        Start-Sleep -Milliseconds 250
        $rawBytes=Read-SharedTrace $rawTrace
        $text=if($null -ne $rawBytes){[Text.Encoding]::ASCII.GetString($rawBytes)}else{''}
        if($text.Contains($complete)){break}
    } while([DateTime]::UtcNow -lt $deadline)
    if(-not $text.Contains($complete)){throw 'Standalone native probe did not complete'}
    [IO.File]::WriteAllBytes((Join-Path $evidence 'flashlog.raw'),$rawBytes)
    if(([regex]::Matches($text,[regex]::Escape('FocusedTestRunId warlord-dog-bite Start: '+$binding.nonce))).Count -ne 1 -or
       ([regex]::Matches($text,[regex]::Escape($complete))).Count -ne 1 -or
       $text -notmatch 'WarlordDogBiteArtTest Tests Failed: 0' -or
       $text -notmatch 'WarlordDogBiteArtTest Captures: 96'){throw 'Native probe closure/assertions failed'}
    $identity=@{nonce=$binding.nonce;runtime=$debugger;playerPid=$player.Id;startedAtUtc=$startedAt.ToString('o');
        completedAtUtc=[DateTime]::UtcNow.ToString('o');swfSha256=(Get-FileHash -LiteralPath $swf -Algorithm SHA256).Hash;
        rawTraceSha256=(Get-FileHash -LiteralPath (Join-Path $evidence 'flashlog.raw') -Algorithm SHA256).Hash;
        runtimeSha256=(Get-FileHash -LiteralPath $debugger -Algorithm SHA256).Hash;captures=96;failed=0;scope=$binding.scope}
    [IO.File]::WriteAllText((Join-Path $evidence 'identity.json'),($identity | ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
    Write-Host ('[OK] Real CS6 + standalone AVM1 native bite capture: '+$evidence)
} finally {
    if($null -ne $player){
        $owned=Get-CimInstance Win32_Process -Filter ('ProcessId='+$player.Id)
        if($null -ne $owned){
            if($owned.ExecutablePath -ne $debugger.Replace('/','\') -or
               [Math]::Abs(($owned.CreationDate.ToUniversalTime()-$startedAt).TotalSeconds) -gt 3){throw 'Owned debug player identity drift; do not stop'}
            Stop-Process -Id $player.Id
        }
    }
}
