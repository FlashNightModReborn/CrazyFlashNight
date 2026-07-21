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

function Invoke-ChestAudit([string]$Root, [bool]$SkipBaseline) {
    $auditArgs = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $toolPath,
        "-StageRoot", $Root,
        "-Json"
    )
    if ($SkipBaseline) { $auditArgs += "-NoBaseline" }
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
    $current = Invoke-ChestAudit (Join-Path $projectRoot "data\stages") $false
    Assert-Equal $current.exitCode 0 "current baseline exit"
    Assert-Equal $current.payload.branchDeclarations 28 "current declarations"
    Assert-Equal $current.payload.instanceNodes 27 "current instance nodes"
    Assert-Equal $current.payload.logicalIdentities 26 "current logical identities"
    Assert-Equal $current.payload.identityCollapses.Count 1 "current logical identity collapse"
    Assert-Equal $current.payload.caseSwitchBranchDeclarations 2 "current CaseSwitch declarations"
    Assert-Equal $current.payload.modes.修罗.grid 9 "current 修罗 grid"
    Assert-Equal $current.payload.modes.修罗.direct 17 "current 修罗 direct"
    Assert-Equal $current.payload.modes.非修罗.grid 8 "current 非修罗 grid"
    Assert-Equal $current.payload.modes.非修罗.direct 18 "current 非修罗 direct"
    Assert-Equal $current.payload.rockPark.activeDeclarations 1 "摇滚公园 active declarations"
    Assert-Equal $current.payload.rockPark.commentedDeclarationsExcluded 8 "摇滚公园 comments excluded"
    Assert-Equal $current.payload.lootRollouts.Count 1 "current loot rollout count"
    Assert-Equal $current.payload.lootRollouts[0].rolloutId "loot-canary-material-5-0-v1" "current loot rollout id"
    Assert-Equal $current.payload.lootRollouts[0].identifier "装备箱" "current loot rollout type"
    Assert-Equal $current.payload.lootRollouts[0].capacity 8 "current loot rollout capacity"
    Assert-Equal $current.payload.lootRollouts[0].dropRules 2 "current loot rollout drop rules"

    $fixtureRoot = Join-Path $tempRoot "valid"
    [void](New-Item -ItemType Directory -Path $fixtureRoot)
    $fixtureXml = @'
<?xml version="1.0" encoding="UTF-8"?>
<GameStage>
  <!-- <Identifier>装备箱</Identifier> -->
  <SubStage id="0">
    <Instances>
      <Instance id="0"><Identifier>保险柜</Identifier></Instance>
      <Instance id="1">
        <CaseSwitch expression="_root.难度是否达到" params="修罗">
          <Case casevalue="true"><Identifier>装备箱</Identifier></Case>
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

    $fixture = Invoke-ChestAudit $fixtureRoot $true
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
    Assert-Equal $fixture.payload.lootRollouts.Count 0 "fixture has no rollout"

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
    <掉落物><名字>测试物品</名字><最小数量>1</最小数量><最大数量>2</最大数量></掉落物>
  </Parameters>
</Instance></Instances></SubStage></GameStage>
'@
    [System.IO.File]::WriteAllText((Join-Path $rolloutRoot "rollout.xml"), $rolloutXml, (New-Object System.Text.UTF8Encoding($false)))
    $rollout = Invoke-ChestAudit $rolloutRoot $true
    Assert-Equal $rollout.exitCode 0 "valid rollout exit"
    Assert-Equal $rollout.payload.lootRollouts.Count 1 "valid rollout count"
    Assert-Equal $rollout.payload.lootRollouts[0].capacity 16 "valid rollout capacity"

    $badRolloutRoot = Join-Path $tempRoot "bad-rollout"
    [void](New-Item -ItemType Directory -Path $badRolloutRoot)
    $badRolloutXml = @'
<?xml version="1.0" encoding="UTF-8"?>
<GameStage><SubStage id="0"><Instances>
  <Instance id="0"><Identifier>资源箱</Identifier><Parameters>
    <chestRolloutId>duplicate-id</chestRolloutId><lootFlowProfile>web-loot-v1</lootFlowProfile><unlockPolicy>skip</unlockPolicy>
    <掉落物><名字>A</名字><最小数量>1</最小数量><最大数量>1</最大数量></掉落物>
  </Parameters></Instance>
  <Instance id="1"><Identifier>装备箱</Identifier><Parameters>
    <chestRolloutId>duplicate-id</chestRolloutId><lootFlowProfile>wrong</lootFlowProfile><unlockPolicy>silent</unlockPolicy>
    <掉落物><名字>B</名字><最小数量>3</最小数量><最大数量>2</最大数量></掉落物>
  </Parameters></Instance>
  <Instance id="2"><Identifier>保险柜</Identifier><Parameters><lootFlowProfile>web-loot-v1</lootFlowProfile></Parameters></Instance>
</Instances></SubStage></GameStage>
'@
    [System.IO.File]::WriteAllText((Join-Path $badRolloutRoot "bad.xml"), $badRolloutXml, (New-Object System.Text.UTF8Encoding($false)))
    $badRollout = Invoke-ChestAudit $badRolloutRoot $true
    Assert-True ($badRollout.exitCode -ne 0) "bad rollout exit"
    Assert-True (@($badRollout.payload.errors | Where-Object { $_.kind -eq "rollout" }).Count -ge 5) "bad rollout errors"

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
    $unknownSwitch = Invoke-ChestAudit $unknownSwitchRoot $true
    Assert-True ($unknownSwitch.exitCode -ne 0) "unknown CaseSwitch exit"
    Assert-True (@($unknownSwitch.payload.errors | Where-Object { $_.kind -eq "case-switch" }).Count -eq 1) "unknown CaseSwitch audit error"

    $badRoot = Join-Path $tempRoot "malformed"
    [void](New-Item -ItemType Directory -Path $badRoot)
    [System.IO.File]::WriteAllText((Join-Path $badRoot "broken.xml"), "<GameStage><SubStage></GameStage>", (New-Object System.Text.UTF8Encoding($false)))
    $malformed = Invoke-ChestAudit $badRoot $true
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
