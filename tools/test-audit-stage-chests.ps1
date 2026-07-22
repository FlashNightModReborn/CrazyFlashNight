$ErrorActionPreference = "Stop"

if ($args.Count -ne 0) {
    throw "test-audit-stage-chests.ps1 accepts no arguments; received: $($args -join ' ')"
}

$toolPath = Join-Path $PSScriptRoot "audit-stage-chests.ps1"
$projectRoot = Split-Path -Parent $PSScriptRoot
$assertions = 0

function Assert-Equal($Actual, $Expected, [string]$Label) {
    $script:assertions++
    if ($Actual -ne $Expected) {
        throw "$Label expected=$Expected actual=$Actual"
    }
}

function Assert-True([bool]$Condition, [string]$Label) {
    $script:assertions++
    if (-not $Condition) {
        throw "$Label expected true"
    }
}

function Invoke-ChestAudit([string]$Root, [bool]$ValidateItems) {
    $auditArgs = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $toolPath,
        "-StageRoot", $Root,
        "-Json"
    )
    if (-not $ValidateItems) { $auditArgs += "-NoItemCatalog" }
    $output = @(& powershell.exe @auditArgs 2>&1)
    $exitCode = $LASTEXITCODE
    $text = $output -join [Environment]::NewLine
    try {
        $payload = $text | ConvertFrom-Json
    } catch {
        throw "audit did not emit valid JSON (exit=$exitCode): $text"
    }
    return [pscustomobject]@{
        exitCode = $exitCode
        payload = $payload
        raw = $text
    }
}

$tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$tempRoot = Join-Path $tempBase ("cf7-stage-chest-audit-" + [guid]::NewGuid().ToString("N"))
[void](New-Item -ItemType Directory -Path $tempRoot)

try {
    $current = Invoke-ChestAudit (Join-Path $projectRoot "data\stages") $true
    Assert-Equal $current.exitCode 0 "current production audit exit"
    Assert-True ($current.payload.xmlFiles -gt 0) "production audit sees stage XML"
    Assert-True ($current.payload.branchDeclarations -gt 0) "production audit sees chest declarations"
    Assert-True ($current.payload.logicalIdentities -gt 0) "production audit sees logical chest identities"
    Assert-Equal $current.payload.chestRecords.Count $current.payload.branchDeclarations (
        "every production chest declaration has a semantic record")
    Assert-Equal @($current.payload.chestRecords | Where-Object {
        $_.delivery -notin @("grid", "direct")
    }).Count 0 "production records have no unknown delivery"
    foreach ($mode in @("修罗", "非修罗")) {
        $modeSummary = $current.payload.modes.$mode
        Assert-Equal ($modeSummary.grid + $modeSummary.direct) $modeSummary.logicalIdentities (
            "$mode production identities classify exactly once")
        Assert-Equal $modeSummary.ambiguous.Count 0 "$mode production identities are unambiguous"
    }
    Assert-Equal $current.payload.obsoleteLootRolloutMarkers.Count 0 "production XML has no obsolete rollout markers"
    Assert-Equal $current.payload.webGridCapability.maxColumns 8 "runtime Web column capability"
    Assert-Equal $current.payload.webGridCapability.maxCapacity 64 "runtime Web capacity capability"
    Assert-Equal $current.payload.presetShapes.装备箱.delivery "grid" "equipment preset runtime shape"
    Assert-Equal $current.payload.presetShapes.保险柜.delivery "grid" "safe preset runtime shape"
    Assert-Equal $current.payload.presetShapes.生存箱.delivery "grid" "survival preset runtime shape"
    Assert-Equal $current.payload.presetShapes.资源箱.delivery "direct" "resource preset runtime shape"
    Assert-Equal $current.payload.presetShapes.隐藏资源点.delivery "direct" "hidden-resource preset runtime shape"
    Assert-Equal $current.payload.presetShapes.纸箱.delivery "direct" "cardboard preset runtime shape"
    Assert-True ($current.payload.autoRoutedGridDeclarations.Count -gt 0) (
        "production audit sees auto-routed Web grids")
    Assert-Equal @($current.payload.autoRoutedGridDeclarations | Where-Object { $_.hasObsoleteRolloutMarker }).Count 0 "auto-grid records are not marker-gated"
    Assert-Equal @($current.payload.chestRecords | Where-Object { $_.hasShapeOverride }).Count 0 "production stages do not override chest row/col"
    Assert-Equal @($current.payload.chestRecords | Where-Object {
        $_.delivery -eq "grid"
    }).Count $current.payload.autoRoutedGridDeclarations.Count "all grid records are auto-routed"
    Assert-True $current.payload.itemCatalog.enabled "production audit validates item catalog"
    Assert-True ($current.payload.itemCatalog.referencedFiles -gt 0) "item catalog loads referenced files"
    Assert-True ($current.payload.itemCatalog.uniqueNames -gt 0) "item catalog loads item names"

    $fixtureRoot = Join-Path $tempRoot "valid"
    [void](New-Item -ItemType Directory -Path $fixtureRoot)
    $fixtureXml = @'
<?xml version="1.0" encoding="UTF-8"?>
<GameStage>
  <!-- <Identifier>装备箱</Identifier> -->
  <SubStage id="0">
    <Instances>
      <Instance id="0"><Identifier>保险柜</Identifier><Parameters>
        <掉落物><名字>测试保险柜物品</名字><最小数量>1</最小数量><最大数量>1</最大数量></掉落物>
      </Parameters></Instance>
      <Instance id="1">
        <CaseSwitch expression="_root.难度是否达到" params="修罗">
          <Case casevalue="true"><Identifier>装备箱</Identifier><Parameters>
            <掉落物><名字>测试装备箱物品</名字><最小数量>1</最小数量><最大数量>1</最大数量></掉落物>
          </Parameters></Case>
          <Case casevalue="false"><Identifier>资源箱</Identifier></Case>
        </CaseSwitch>
      </Instance>
      <Instance id="2"><Identifier>隐藏资源点</Identifier></Instance>
      <Instance id="2"><Identifier>隐藏资源点</Identifier></Instance>
      <Instance id="3">
        <CaseSwitch expression="_root.难度是否达到" params="修罗">
          <Case casevalue="true"><Identifier>纸箱</Identifier></Case>
          <Case casevalue="false"><Identifier>纸箱</Identifier></Case>
        </CaseSwitch>
      </Instance>
    </Instances>
  </SubStage>
</GameStage>
'@
    [System.IO.File]::WriteAllText((Join-Path $fixtureRoot "fixture.xml"), $fixtureXml, (New-Object System.Text.UTF8Encoding($false)))

    $fixture = Invoke-ChestAudit $fixtureRoot $false
    Assert-Equal $fixture.exitCode 0 "fixture exit"
    Assert-Equal $fixture.payload.branchDeclarations 7 "fixture declarations"
    Assert-Equal $fixture.payload.instanceNodes 5 "fixture instance nodes"
    Assert-Equal $fixture.payload.logicalIdentities 4 "fixture logical identities"
    Assert-Equal $fixture.payload.caseSwitchBranchDeclarations 4 "fixture CaseSwitch declarations"
    Assert-Equal $fixture.payload.sameIdentifierDedupes.Count 2 "fixture same-Identifier dedupes"
    Assert-Equal $fixture.payload.identityCollapses.Count 1 "fixture duplicate-id collapse"
    Assert-Equal $fixture.payload.commentedIdentifierMentionsExcluded 1 "fixture comments excluded"
    Assert-Equal $fixture.payload.modes.修罗.logicalIdentities 4 "fixture 修罗 logical identities"
    Assert-Equal $fixture.payload.modes.修罗.grid 2 "fixture 修罗 grid"
    Assert-Equal $fixture.payload.modes.修罗.direct 2 "fixture 修罗 direct"
    Assert-Equal $fixture.payload.modes.非修罗.logicalIdentities 4 "fixture 非修罗 logical identities"
    Assert-Equal $fixture.payload.modes.非修罗.grid 1 "fixture 非修罗 grid"
    Assert-Equal $fixture.payload.modes.非修罗.direct 3 "fixture 非修罗 direct"
    Assert-Equal $fixture.payload.obsoleteLootRolloutMarkers.Count 0 "fixture has no obsolete rollout marker"

    $rolloutRoot = Join-Path $tempRoot "valid-rollout"
    [void](New-Item -ItemType Directory -Path $rolloutRoot)
    $rolloutXml = @'
<?xml version="1.0" encoding="UTF-8"?>
<GameStage><SubStage id="0"><Instances><Instance id="0">
  <Identifier>生存箱</Identifier>
  <Parameters>
    <chestRolloutId>fixture-loot-1</chestRolloutId>
    <lootFlowProfile>web-loot-v1</lootFlowProfile>
    <unlockPolicy>skip</unlockPolicy>
    <掉落物><CaseSwitch expression="_root.难度是否达到" params="修罗">
      <Case casevalue="true"><名字>修罗测试物品</名字><概率>25</概率><最小数量>1</最小数量><最大数量>2</最大数量><总数>2</总数></Case>
      <Case casevalue="false"><名字>非修罗测试物品</名字><最小数量>3</最小数量><最大数量>4</最大数量></Case>
    </CaseSwitch></掉落物>
  </Parameters>
</Instance></Instances></SubStage></GameStage>
'@
    [System.IO.File]::WriteAllText((Join-Path $rolloutRoot "rollout.xml"), $rolloutXml, (New-Object System.Text.UTF8Encoding($false)))
    $rollout = Invoke-ChestAudit $rolloutRoot $false
    Assert-True ($rollout.exitCode -ne 0) "obsolete rollout marker exit"
    Assert-Equal $rollout.payload.obsoleteLootRolloutMarkers.Count 1 "obsolete rollout marker count"
    Assert-Equal @($rollout.payload.errors | Where-Object { $_.kind -eq "obsolete-rollout-marker" }).Count 1 "obsolete rollout marker error"

    $shapeOverrideRoot = Join-Path $tempRoot "shape-override"
    [void](New-Item -ItemType Directory -Path $shapeOverrideRoot)
    $shapeOverrideXml = @'
<?xml version="1.0" encoding="UTF-8"?>
<GameStage><SubStage id="0"><Instances><Instance id="0">
  <Identifier>资源箱</Identifier>
  <Parameters><row>2</row><col>4</col></Parameters>
</Instance></Instances></SubStage></GameStage>
'@
    [System.IO.File]::WriteAllText((Join-Path $shapeOverrideRoot "shape-override.xml"),
        $shapeOverrideXml, (New-Object System.Text.UTF8Encoding($false)))
    $shapeOverride = Invoke-ChestAudit $shapeOverrideRoot $false
    Assert-True ($shapeOverride.exitCode -ne 0) "stage shape override exit"
    Assert-Equal @($shapeOverride.payload.errors | Where-Object {
        $_.kind -eq "shape-override"
    }).Count 1 "stage shape override audit error"

    $defaultQuantityRoot = Join-Path $tempRoot "default-quantity"
    [void](New-Item -ItemType Directory -Path $defaultQuantityRoot)
    $defaultQuantityXml = @'
<?xml version="1.0" encoding="UTF-8"?>
<GameStage><SubStage id="0"><Instances>
  <Instance id="0"><Identifier>装备箱</Identifier><Parameters>
    <掉落物><名字>A</名字></掉落物>
    <掉落物><名字>B</名字><最小数量>99</最小数量><总数>1</总数></掉落物>
  </Parameters></Instance>
</Instances></SubStage></GameStage>
'@
    [System.IO.File]::WriteAllText((Join-Path $defaultQuantityRoot "default.xml"), $defaultQuantityXml, (New-Object System.Text.UTF8Encoding($false)))
    $defaultQuantity = Invoke-ChestAudit $defaultQuantityRoot $false
    Assert-Equal $defaultQuantity.exitCode 0 "missing quantity fields use legacy 1/1 default"

    $overCapacityRoot = Join-Path $tempRoot "over-capacity"
    [void](New-Item -ItemType Directory -Path $overCapacityRoot)
    $overCapacityXml = @'
<?xml version="1.0" encoding="UTF-8"?>
<GameStage><SubStage id="0"><Instances>
  <Instance id="0"><Identifier>装备箱</Identifier><Parameters>
    <掉落物><名字>A</名字></掉落物>
    <掉落物><名字>B</名字></掉落物>
    <掉落物><名字>C</名字></掉落物>
    <掉落物><名字>D</名字></掉落物>
    <掉落物><名字>E</名字></掉落物>
    <掉落物><名字>F</名字></掉落物>
    <掉落物><名字>G</名字></掉落物>
    <掉落物><名字>H</名字></掉落物>
    <掉落物><名字>I</名字></掉落物>
  </Parameters></Instance>
</Instances></SubStage></GameStage>
'@
    [System.IO.File]::WriteAllText((Join-Path $overCapacityRoot "over-capacity.xml"),
        $overCapacityXml, (New-Object System.Text.UTF8Encoding($false)))
    $overCapacity = Invoke-ChestAudit $overCapacityRoot $false
    Assert-True ($overCapacity.exitCode -ne 0) "drop rule count above preset capacity exit"
    Assert-Equal @($overCapacity.payload.errors | Where-Object {
        $_.kind -eq "grid" -and $_.message -match "规则数 9 超过容器容量 8"
    }).Count 1 "drop rule count above preset capacity audit error"

    $unknownSwitchRoot = Join-Path $tempRoot "unknown-switch"
    [void](New-Item -ItemType Directory -Path $unknownSwitchRoot)
    $unknownSwitchXml = @'
<?xml version="1.0" encoding="UTF-8"?>
<GameStage><SubStage id="0"><Instances><Instance id="0">
  <CaseSwitch expression="_root.someOtherGate" params="x">
    <Case casevalue="true"><Identifier>保险柜</Identifier></Case>
  </CaseSwitch>
</Instance></Instances></SubStage></GameStage>
'@
    [System.IO.File]::WriteAllText((Join-Path $unknownSwitchRoot "unknown.xml"), $unknownSwitchXml, (New-Object System.Text.UTF8Encoding($false)))
    $unknownSwitch = Invoke-ChestAudit $unknownSwitchRoot $false
    Assert-True ($unknownSwitch.exitCode -ne 0) "unknown CaseSwitch exit"
    Assert-True (@($unknownSwitch.payload.errors | Where-Object { $_.kind -eq "case-switch" }).Count -eq 1) "unknown CaseSwitch audit error"

    $unknownItemRoot = Join-Path $tempRoot "unknown-item"
    [void](New-Item -ItemType Directory -Path $unknownItemRoot)
    $unknownItemXml = @'
<?xml version="1.0" encoding="UTF-8"?>
<GameStage><SubStage id="0"><Instances><Instance id="0">
  <Identifier>装备箱</Identifier><Parameters>
    <掉落物><名字>不存在的资源箱审计物品</名字><最小数量>1</最小数量><最大数量>1</最大数量></掉落物>
  </Parameters>
</Instance></Instances></SubStage></GameStage>
'@
    [System.IO.File]::WriteAllText((Join-Path $unknownItemRoot "unknown-item.xml"),
        $unknownItemXml, (New-Object System.Text.UTF8Encoding($false)))
    $unknownItem = Invoke-ChestAudit $unknownItemRoot $true
    Assert-True ($unknownItem.exitCode -ne 0) "unknown item exit"
    Assert-True (@($unknownItem.payload.errors | Where-Object {
        $_.kind -eq "grid" -and $_.message -match "权威物品目录"
    }).Count -eq 1) "unknown item catalog audit error"

    $badRoot = Join-Path $tempRoot "malformed"
    [void](New-Item -ItemType Directory -Path $badRoot)
    [System.IO.File]::WriteAllText((Join-Path $badRoot "broken.xml"), "<GameStage><SubStage></GameStage>", (New-Object System.Text.UTF8Encoding($false)))
    $malformed = Invoke-ChestAudit $badRoot $false
    Assert-True ($malformed.exitCode -ne 0) "malformed XML exit"
    Assert-True (@($malformed.payload.errors | Where-Object { $_.kind -eq "parse" }).Count -eq 1) "malformed XML parse error"

    Write-Output ("[PASS] audit-stage-chests: {0} assertions" -f $assertions)
} finally {
    $resolvedTemp = [System.IO.Path]::GetFullPath($tempRoot)
    if ($resolvedTemp.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase) -and
        [System.IO.Path]::GetFileName($resolvedTemp).StartsWith("cf7-stage-chest-audit-", [System.StringComparison]::Ordinal)) {
        Remove-Item -LiteralPath $resolvedTemp -Recurse -Force
    }
}
