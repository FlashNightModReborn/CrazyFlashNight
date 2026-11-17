param([int]$TimeoutSeconds = 300, [int]$AsyncBehaviorTimeoutSeconds = 180, [switch]$Capture)
$ErrorActionPreference = 'Stop'
if ($Capture -and -not $PSBoundParameters.ContainsKey('TimeoutSeconds')) { $TimeoutSeconds = 900 }
if ($Capture -and -not $PSBoundParameters.ContainsKey('AsyncBehaviorTimeoutSeconds')) { $AsyncBehaviorTimeoutSeconds = 900 }
$template = if ($Capture) { 'scripts/test-runners/cf2-tank-boss/TestLoader-capture.as.template' } else { 'scripts/test-runners/cf2-tank-boss/TestLoader.as.template' }
$root = Split-Path -Parent $PSScriptRoot
$swf = Join-Path $root 'flashswf/arts/new/Codex大机器人素材.swf'
$before = (Get-FileHash -LiteralPath $swf -Algorithm SHA256).Hash
$evidence = Join-Path $root ('tmp/cf2-boss/evidence/native-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $evidence)
foreach ($relative in @('tools/cf2-boss-assets/native-manifest.json','tools/cf2-boss-assets/spec.json',
    'tools/cf2-boss-assets/TankBossAI.as','scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf2TankBossAssetTest.as',$template)) {
    Copy-Item -LiteralPath (Join-Path $root $relative) -Destination (Join-Path $evidence ([IO.Path]::GetFileName($relative)))
}
$result = 1
$failure = $null
try {
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId cf2-tank-boss `
    -TemplateRelativePath $template `
    -SuiteRelativePaths 'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf2TankBossAssetTest.as' `
    -SuiteFqns 'org.flashNight.arki.unit.Action.Melee.Cf2TankBossAssetTest' `
    -ExpectedTracePatterns @('Cf2TankBossAssetTest: \d+ passed, 0 failed; native tank actions') `
    -SuccessSummary '闪2大机器人原生动作、循环、锁向、死亡和伤害结算检查通过' `
    -TimeoutSeconds $TimeoutSeconds -AsyncBehaviorTimeoutSeconds $AsyncBehaviorTimeoutSeconds
$result = $LASTEXITCODE
} catch {
    $failure = $_
} finally {
foreach ($name in @('flashlog.txt','compile_output.txt','compiler_errors.txt','TestLoader.swf')) {
    $source = Join-Path $PSScriptRoot $name
    if (Test-Path -LiteralPath $source) { Copy-Item -LiteralPath $source -Destination (Join-Path $evidence $name) }
}
$after = (Get-FileHash -LiteralPath $swf -Algorithm SHA256).Hash
$record = @{sourceSwf='flashswf/arts/new/Codex大机器人素材.swf';before=$before;after=$after;exitCode=$result;capture=[bool]$Capture;utc=[DateTime]::UtcNow.ToString('o')}
[IO.File]::WriteAllText((Join-Path $evidence 'identity.json'),($record | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
Write-Host "[CF2 tank evidence] $evidence"
}
if ($before -cne $after) { throw 'Tank resource changed during its native regression.' }
if ($null -ne $failure) { throw $failure }
if ($result -ne 0) { exit $result }
