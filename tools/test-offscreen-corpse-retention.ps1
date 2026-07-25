param()

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$rendererPath = Join-Path $repoRoot `
    'scripts\类定义\org\flashNight\arki\corpse\DeathEffectRenderer.as'
$suitePath = Join-Path $repoRoot `
    'scripts\类定义\org\flashNight\arki\corpse\DeathEffectRendererTest.as'
$templatePath = Join-Path $repoRoot `
    'scripts\test-runners\offscreen-corpse-retention\TestLoader.as.template'
$runnerPath = Join-Path $repoRoot `
    'scripts\run-offscreen-corpse-retention-tests.ps1'
$stagePath = Join-Path $repoRoot 'data\stages\黑铁会总部\黑铁会总堂.xml'

$passed = 0
$failed = 0

function Assert-OffscreenCorpseRetention {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if ($Condition) {
        $script:passed++
        Write-Host "[PASS] $Message"
    } else {
        $script:failed++
        Write-Host "[FAIL] $Message"
    }
}

function Test-Utf8Bom([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    return $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and
        $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
}

$requiredPaths = @(
    $rendererPath, $suitePath, $templatePath, $runnerPath, $stagePath
)
foreach ($path in $requiredPaths) {
    Assert-OffscreenCorpseRetention (Test-Path -LiteralPath $path) `
        ("必需产物存在：{0}" -f [System.IO.Path]::GetFileName($path))
}

Assert-OffscreenCorpseRetention (Test-Utf8Bom $rendererPath) `
    'DeathEffectRenderer.as 保持 UTF-8 BOM'
Assert-OffscreenCorpseRetention (Test-Utf8Bom $suitePath) `
    'DeathEffectRendererTest.as 保持 UTF-8 BOM'
Assert-OffscreenCorpseRetention (Test-Utf8Bom $templatePath) `
    'TestLoader 专项模板保持 UTF-8 BOM'

$renderer = [System.IO.File]::ReadAllText(
    $rendererPath, [System.Text.Encoding]::UTF8)
$suite = [System.IO.File]::ReadAllText(
    $suitePath, [System.Text.Encoding]::UTF8)
$template = [System.IO.File]::ReadAllText(
    $templatePath, [System.Text.Encoding]::UTF8)
$stageText = [System.IO.File]::ReadAllText(
    $stagePath, [System.Text.Encoding]::UTF8)

Assert-OffscreenCorpseRetention ($renderer -match
    'RETAIN_OFFSCREEN_CORPSE_PARAM:String\s*=\s*"保留屏外尸体"') `
    '渲染器使用单一实例参数名'
Assert-OffscreenCorpseRetention (
    [regex]::Matches(
        $renderer,
        'DeathEffectRenderer\.enableCulling\s*&&\s*!retainOffscreenCorpse'
    ).Count -eq 2) `
    '普通与旋转尸体入口都只对标记实例绕过离屏裁剪'
Assert-OffscreenCorpseRetention (
    [regex]::Matches(
        $renderer,
        'var restoreHidden:Boolean\s*=\s*retainOffscreenCorpse\s*&&\s*!target\._visible'
    ).Count -eq 2) `
    '两个入口都仅为已隐藏的标记实例打开临时可见度'
Assert-OffscreenCorpseRetention (
    [regex]::Matches($renderer, 'if \(restoreHidden\) target\._visible = true;').Count -eq 2 -and
    [regex]::Matches($renderer, 'if \(restoreHidden\) target\._visible = false;').Count -eq 2) `
    '两个入口都在同步 draw 后恢复原隐藏状态'
Assert-OffscreenCorpseRetention ($renderer -notmatch '火凤|兵种67') `
    '通用渲染器不硬编码验收怪物身份'
Assert-OffscreenCorpseRetention ($suite -match
    'DeathEffectRendererTest Tests Passed: " \+ _passed') `
    '专项套件输出可机读断言汇总'
Assert-OffscreenCorpseRetention (
    [regex]::Matches($template, '__FOCUSED_RUN_ID__').Count -eq 2 -and
    $template -match
        'org\.flashNight\.arki\.corpse\.DeathEffectRendererTest\.runAllTests\(\);') `
    'tracked TestLoader 模板精确调用尸体保留专项'

[xml]$stage = $stageText
$firePhoenixNodes = $stage.SelectNodes(
    '/GameStage/SubStage[@id="1"]/Wave/SubWave[@id="0"]' +
    '/EnemyGroup/Enemy[Type="兵种67"]')
Assert-OffscreenCorpseRetention ($firePhoenixNodes.Count -eq 1) `
    '总堂第二图首波恰有一只兵种67火凤验收实例'
if ($firePhoenixNodes.Count -eq 1) {
    $parameters = [string]$firePhoenixNodes[0].Parameters
    Assert-OffscreenCorpseRetention ($parameters -match
        '(^|,)保留屏外尸体:true(,|$)') `
        '总堂第二图火凤显式启用屏外尸体保留'
    Assert-OffscreenCorpseRetention (
        [string]$firePhoenixNodes[0].Quantity -eq '1') `
        '验收实例数量固定为一只'
}
Assert-OffscreenCorpseRetention (
    [regex]::Matches($stageText, '保留屏外尸体:true').Count -eq 1) `
    '当前关卡仅验收火凤实例启用标记'

Write-Host ("Offscreen corpse retention checks: {0} passed, {1} failed" -f
    $passed, $failed)
if ($failed -gt 0) {
    throw "$failed offscreen corpse retention checks failed."
}
