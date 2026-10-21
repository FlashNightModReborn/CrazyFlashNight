$ErrorActionPreference = 'Stop'
chcp.com 65001 > $null
$lfRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$lfTokens=$null;$lfErrors=$null
$lfAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $lfRoot 'launcher/build-runtime-candidate.ps1'),[ref]$lfTokens,[ref]$lfErrors)
if($lfErrors.Count){throw 'Producer parse failed'}
$lfFunction=@($lfAst.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Copy-Cf7CanonicalLfFile'},$false))
if($lfFunction.Count -ne 1){throw 'Canonical materializer is not unique'}
Invoke-Expression $lfFunction[0].Extent.Text
$lfDirectory=Join-Path $lfRoot ('tmp/issue-152-acceptance/lf-equivalence-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($lfDirectory)
$lfRandom=[Random]::new(152)
$lfRandomBytes=[byte[]]::new(8192);$lfRandom.NextBytes($lfRandomBytes)
$lfVectors=@([byte[]]@(),[byte[]]@(13),[byte[]]@(10),[byte[]]@(13,10),[byte[]]@(13,13,10,13),[byte[]]@(239,187,191,228,184,173,13,10,255,0),$lfRandomBytes)
$lfOrdinal=0
foreach($lfBytes in $lfVectors){
    $lfExpected=[Collections.Generic.List[byte]]::new()
    for($lfIndex=0;$lfIndex -lt $lfBytes.Length;$lfIndex++){
        if($lfBytes[$lfIndex] -eq 13){
            if($lfIndex+1 -lt $lfBytes.Length -and $lfBytes[$lfIndex+1] -eq 10){continue}
            $lfExpected.Add(10)
        }else{$lfExpected.Add($lfBytes[$lfIndex])}
    }
    $lfSource=Join-Path $lfDirectory ($lfOrdinal.ToString()+'.source')
    $lfDestination=Join-Path $lfDirectory ($lfOrdinal.ToString()+'.normalized')
    [IO.File]::WriteAllBytes($lfSource,$lfBytes)
    Copy-Cf7CanonicalLfFile -Source $lfSource -Destination $lfDestination
    if([Convert]::ToBase64String([IO.File]::ReadAllBytes($lfDestination)) -cne [Convert]::ToBase64String($lfExpected.ToArray())){throw 'LF output changed'}
    $lfOrdinal++
}
$lfNativeSource=Join-Path $lfRoot 'launcher/native/miniaudio.h'
$lfClock=[Diagnostics.Stopwatch]::StartNew()
Copy-Cf7CanonicalLfFile -Source $lfNativeSource -Destination (Join-Path $lfDirectory 'miniaudio.normalized.h')
$lfClock.Stop()
[ordered]@{passed=$lfOrdinal;failed=0;largeSourceBytes=(Get-Item -LiteralPath $lfNativeSource).Length;largeFileMilliseconds=$lfClock.ElapsedMilliseconds;outputSha256=(Get-FileHash -LiteralPath (Join-Path $lfDirectory 'miniaudio.normalized.h')).Hash;directory=$lfDirectory}|ConvertTo-Json
