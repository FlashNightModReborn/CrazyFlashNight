[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$taskRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$taskHash=[Security.Cryptography.SHA256]::Create()
$taskHex=[BitConverter]::ToString($taskHash.ComputeHash([Text.Encoding]::UTF8.GetBytes($taskRoot.TrimEnd('\').ToUpperInvariant()))).Replace('-','').Substring(0,24)
$taskMutex=[Threading.Mutex]::new($false,('Local\CF7_FlashCompile_'+$taskHex))
if(-not $taskMutex.WaitOne(0)){throw 'CS6 compile mutex is busy'}
$taskToken=[guid]::NewGuid().ToString('N')
$taskMarker=Join-Path $taskRoot 'scripts/compile_state_uncertain.marker'
$taskBody=$null
$taskTerminal=$false
try {
 foreach($taskGate in @('scripts/compile_state_uncertain.marker','scripts/testloader_scratch_inflight.marker')) {
  if(Test-Path -LiteralPath (Join-Path $taskRoot $taskGate)){throw ('CS6 recovery required: '+$taskGate)}
 }
 if((Get-ScheduledTask -TaskName CompileTriggerTask).State -eq 'Running'){throw 'Compile trigger is running'}
 $taskFlash=(Get-ScheduledTask -TaskName FlashCS6Task).Actions.Execute
 if(-not (Test-Path -LiteralPath $taskFlash)){throw 'Registered CS6 executable is unavailable'}
 $taskOutput=Join-Path $taskRoot ('tmp/newcomer-rescue/bitmap-import-'+$taskToken)
 New-Item -ItemType Directory -Path $taskOutput | Out-Null
 $taskInput=Join-Path $taskRoot 'flashswf/backgrounds/70002/ambush/LIBRARY/bitmap45.png'
 $taskReceipt=Join-Path $taskOutput 'receipt.txt'
 $taskFla=Join-Path $taskOutput 'native.fla'
 $taskJsfl=Join-Path $taskOutput 'import.jsfl'
 $taskScript=@'
// Authoring only. No publish(), testMovie(), SWF edits or other-document changes.
var owned = null;
var receipt = FLfile.platformPathToURI(__RECEIPT__);
try {
    owned = fl.createDocument();
    if (!owned) throw new Error("createDocument failed");
    owned.importFile(FLfile.platformPathToURI(__INPUT__), true);
    var bitmaps = [];
    for (var i=0; i<owned.library.items.length; i++) {
        var item=owned.library.items[i];
        if (item.itemType=="bitmap") bitmaps.push(item);
    }
    if (bitmaps.length!=1) throw new Error("expected one imported bitmap");
    bitmaps[0].compressionType="lossless";
    if (!fl.saveDocument(owned, FLfile.platformPathToURI(__FLA__))) throw new Error("save failed");
    fl.closeDocument(owned, false);
    owned=null;
    FLfile.write(receipt,"__TOKEN__\nOK");
} catch (error) {
    if (owned) fl.closeDocument(owned,false);
    FLfile.write(receipt,"__TOKEN__\nERROR: "+error);
}
'@
 $taskScript=$taskScript.Replace('__RECEIPT__',($taskReceipt | ConvertTo-Json -Compress)).Replace('__INPUT__',($taskInput | ConvertTo-Json -Compress)).Replace('__FLA__',($taskFla | ConvertTo-Json -Compress)).Replace('__TOKEN__',$taskToken)
 [IO.File]::WriteAllText($taskJsfl,$taskScript,[Text.UTF8Encoding]::new($false))
 $taskBody=(Get-Date).ToUniversalTime().ToString('o')+' | token='+$taskToken+' | native bitmap import in-flight; output='+$taskOutput
 [IO.File]::WriteAllText($taskMarker,$taskBody,[Text.UTF8Encoding]::new($false))
 Start-Process -FilePath $taskFlash -ArgumentList ('"'+$taskJsfl+'"') -WindowStyle Hidden | Out-Null
 $taskTimer=[Diagnostics.Stopwatch]::StartNew()
 while(-not (Test-Path -LiteralPath $taskReceipt)) {
  if($taskTimer.Elapsed.TotalSeconds -gt 90){throw ('Authoring result unknown; inspect CS6 and preserve recovery marker: '+$taskOutput)}
  Start-Sleep -Milliseconds 250
 }
 $taskResult=[IO.File]::ReadAllText($taskReceipt)
 if(-not $taskResult.StartsWith($taskToken+"`n")){throw 'Authoring receipt token mismatch'}
 $taskTerminal=$true
 if($taskResult -ne ($taskToken+"`nOK")){throw $taskResult}
 Write-Output ('CS6 native bitmap import saved: '+$taskFla)
 Write-Output ('Original SHA256: '+(Get-FileHash -LiteralPath $taskInput -Algorithm SHA256).Hash)
 & python (Join-Path $PSScriptRoot 'repair_caches.py') --native-fla $taskFla
 if($LASTEXITCODE -ne 0){throw 'Native bitmap cache ingestion failed'}
} finally {
 if($taskTerminal -and $taskBody -ne $null -and (Test-Path -LiteralPath $taskMarker) -and [IO.File]::ReadAllText($taskMarker) -ceq $taskBody){Remove-Item -LiteralPath $taskMarker}
 $taskMutex.ReleaseMutex();$taskMutex.Dispose()
}
