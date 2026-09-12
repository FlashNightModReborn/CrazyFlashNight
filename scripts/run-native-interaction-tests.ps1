[CmdletBinding()]
param(
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 240,
    [switch]$SkipCompile
)

$ErrorActionPreference = 'Stop'
$commonRunner = Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1'

$repoRoot = Split-Path -Parent $PSScriptRoot

# native_interaction 迁移静态门（tmp/native-interaction-migration-20260912/COMMON.md 桥协议 v1）。
$menuBridgePath = Join-Path $repoRoot 'scripts\类定义\org\flashNight\arki\interaction\NativeMenuBridge.as'
$menuBridgeSource = Get-Content -LiteralPath $menuBridgePath -Raw -Encoding UTF8
if ([regex]::Matches($menuBridgeSource,
        '_root\.gameCommands\["nativeInteraction(Action|Cancel)"\]').Count -ne 2 -or
    $menuBridgeSource -notmatch 'sendTaskToNode\("native_interaction"' -or
    $menuBridgeSource -notmatch 'NativeInteractionContext\.nextRequestId\(' -or
    $menuBridgeSource -notmatch 'NativeInteractionContext\.getSceneId\(') {
    throw 'NativeMenuBridge must register nativeInteractionAction/Cancel and publish via sendTaskToNode("native_interaction") with shared context identity.'
}

$contextPath = Join-Path $repoRoot 'scripts\类定义\org\flashNight\arki\interaction\NativeInteractionContext.as'
$contextSource = Get-Content -LiteralPath $contextPath -Raw -Encoding UTF8
if ($contextSource -notmatch '"ni:"\s*\+' -or
    $contextSource -notmatch 'public\s+static\s+function\s+getSceneId\s*\(' -or
    $contextSource -notmatch 'public\s+static\s+function\s+nextRequestId\s*\(') {
    throw 'NativeInteractionContext must expose getSceneId/nextRequestId with the exact ni:<n> requestId format.'
}

$tooltipBridgePath = Join-Path $repoRoot 'scripts\类定义\org\flashNight\gesh\tooltip\NativeTooltipBridge.as'
$tooltipBridgeSource = Get-Content -LiteralPath $tooltipBridgePath -Raw -Encoding UTF8
if ($tooltipBridgeSource -notmatch 'KIND_TOOLTIP[^=]*=\s*"tooltip"' -or
    $tooltipBridgeSource -notmatch 'native_interaction' -or
    $tooltipBridgeSource -notmatch 'sendTaskToNode\(') {
    throw 'NativeTooltipBridge must publish kind:"tooltip" via sendTaskToNode on the native_interaction task.'
}

$bootPath = Join-Path $repoRoot 'scripts\类定义\org\flashNight\boot\BootSequencer.as'
$bootSource = Get-Content -LiteralPath $bootPath -Raw -Encoding UTF8
if ([regex]::Matches($bootSource,
        'org\.flashNight\.arki\.interaction\.NativeMenuBridge\.install\(\)').Count -ne 1) {
    throw 'BootSequencer S_SYNCLOGIC must call NativeMenuBridge.install() exactly once.'
}

# 头注释只列对外 API 契约；物品图标容器 attachMovie 已退役为恒空兼容占位（无生产者）。
$cursorProxyPath = Join-Path $repoRoot 'scripts\展现\UI交互\UI交互_lsy_鼠标代理.as'
$cursorProxySource = Get-Content -LiteralPath $cursorProxyPath -Raw -Encoding UTF8
if ($cursorProxySource -notmatch 'MouseProxy\.install\(\)') {
    throw 'UI交互_lsy_鼠标代理.as must keep the MouseProxy.install() bootstrap call.'
}

$focusedRun = @{
    DomainId = 'native-interaction'
    TemplateRelativePath = 'scripts\test-runners\native-interaction\TestLoader.as.template'
    SuiteRelativePaths = @(
        'scripts\类定义\org\flashNight\gesh\tooltip\test\NativeTooltipDocumentTest.as'
        'scripts\类定义\org\flashNight\gesh\tooltip\test\NativeTooltipBridgeTest.as'
        'scripts\类定义\org\flashNight\arki\merc\MercSpawnerTest.as'
        'scripts\类定义\org\flashNight\arki\cursor\MouseProxyTest.as'
        'scripts\类定义\org\flashNight\arki\interaction\NativeMenuBridgeTest.as'
        'scripts\类定义\org\flashNight\arki\interaction\NativeInteractionContextTest.as'
        'scripts\类定义\org\flashNight\arki\item\InventoryTooltipProjectionTest.as'
    )
    SuiteFqns = @(
        'org.flashNight.gesh.tooltip.test.NativeTooltipDocumentTest'
        'org.flashNight.gesh.tooltip.test.NativeTooltipBridgeTest'
        'org.flashNight.arki.merc.MercSpawnerTest'
        'org.flashNight.arki.cursor.MouseProxyTest'
        'org.flashNight.arki.interaction.NativeMenuBridgeTest'
        'org.flashNight.arki.interaction.NativeInteractionContextTest'
        'org.flashNight.arki.item.InventoryTooltipProjectionTest'
    )
    AdditionalAsRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\interaction\NativeMenuBridge.as'
        'scripts\类定义\org\flashNight\arki\interaction\NativeInteractionContext.as'
        'scripts\类定义\org\flashNight\arki\merc\MercSpawner.as'
        'scripts\类定义\org\flashNight\arki\cursor\MouseProxy.as'
        'scripts\类定义\org\flashNight\gesh\tooltip\NativeTooltipDocument.as'
        'scripts\类定义\org\flashNight\gesh\tooltip\NativeTooltipBridge.as'
        'scripts\类定义\org\flashNight\boot\BootSequencer.as'
        'scripts\类定义\org\flashNight\gesh\tooltip\TooltipComposer.as'
        'scripts\展现\UI交互\UI交互_lsy_鼠标代理.as'
    )
    ExpectedTracePatterns = @(
        '(?m)^InventoryTooltipProjectionTest Tests Passed: [1-9]\d*\r?$'
        '(?m)^InventoryTooltipProjectionTest Tests Failed: 0\r?$'
        '(?m)^NativeInteractionContextTest Tests Passed: [1-9]\d*\r?$'
        '(?m)^NativeInteractionContextTest Tests Failed: 0\r?$'
        '(?m)^MercSpawnerTest Tests Passed: [1-9]\d*\r?$'
        '(?m)^MercSpawnerTest Tests Failed: 0\r?$'
        '(?m)^MouseProxyTest Tests Passed: [1-9]\d*\r?$'
        '(?m)^MouseProxyTest Tests Failed: 0\r?$'
        '(?m)^NativeMenuBridgeTest Tests Passed: [1-9]\d*\r?$'
        '(?m)^NativeMenuBridgeTest Tests Failed: 0\r?$'
        '(?m)^--- NativeTooltipDocumentTest: [1-9]\d*/\d+ passed, 0 failed ---\r?$'
        '(?m)^--- NativeTooltipBridgeTest: [1-9]\d*/\d+ passed, 0 failed ---\r?$'
    )
    SuccessSummary = 'native-interaction 七套件全部通过'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& $commonRunner @focusedRun
