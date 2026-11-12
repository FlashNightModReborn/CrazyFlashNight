[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=360,[string]$EvidenceDirectory)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$root=Split-Path -Parent $PSScriptRoot
$relative='scripts/类定义/org/flashNight/arki/render/EquipmentLightBridge.as'
$baseline='0224e1627e'
$generated=Join-Path $PSScriptRoot '类定义/org/flashNight/arki/render/LegacyLightBenchmarkBridge.as'
if(Test-Path -LiteralPath $generated){throw 'The comparison source is already in use.'}
$old=[string[]](& git -C $root show ("{0}:{1}" -f $baseline,$relative))
if($LASTEXITCODE -ne 0){throw 'The fixed pre-migration source is unavailable.'}
$source=([string]::Join([Environment]::NewLine,$old) -replace '\bEquipmentLightBridge\b','LegacyLightBenchmarkBridge')
if(-not $source.Contains('class org.flashNight.arki.render.LegacyLightBenchmarkBridge')){throw 'Unexpected baseline source.'}
$stream=[IO.File]::Open($generated,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try {
    $encoding=[Text.UTF8Encoding]::new($true)
    $prefix=$encoding.GetPreamble();$body=$encoding.GetBytes($source)
    $stream.Write($prefix,0,$prefix.Length);$stream.Write($body,0,$body.Length)
} finally {$stream.Dispose()}
$hash=(Get-FileHash -LiteralPath $generated).Hash
try {
    $run=@{
        DomainId='projectile-light-comparison'
        TemplateRelativePath='scripts/test-runners/projectile-light-comparison/TestLoader.as.template'
        SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/render/ProjectileLightBenchmark.as')
        SuiteFqns=@('org.flashNight.arki.render.ProjectileLightBenchmark')
        ExpectedTracePatterns=@('(?m)^LightBenchmarkComparison complete\r?$')
        SuccessSummary='旧版与候选在同一个播放器内执行五类负载'
        TimeoutSeconds=$TimeoutSeconds
    }
    & (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @run
    $code=$LASTEXITCODE
} finally {
    if((Get-FileHash -LiteralPath $generated).Hash -ne $hash){throw 'The generated comparison class changed during execution.'}
    Remove-Item -LiteralPath $generated
}
if($code -ne 0){ exit $code }
if(-not $EvidenceDirectory){$EvidenceDirectory=Join-Path $root ('tmp/projectile-light-comparison/'+[guid]::NewGuid().ToString('N'))}
& python -B -X utf8 (Join-Path $root 'tools/combat-fx-assets/verify_light_authoring.py') --benchmark `
    --test-swf (Join-Path $PSScriptRoot 'TestLoader.swf') --compile-trace (Join-Path $PSScriptRoot 'flashlog.txt') --output $EvidenceDirectory
exit $LASTEXITCODE
