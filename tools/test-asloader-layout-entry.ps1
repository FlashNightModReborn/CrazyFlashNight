# Exercise the public PowerShell arguments and both native/legacy routes in a
# temporary project. The compiler task and the final child are fixtures.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('cf7-layout-route-' + [Guid]::NewGuid().ToString('N'))
$utf8 = [Text.UTF8Encoding]::new($true)
$publicEntry = Join-Path $fixture 'scripts/compile_test.ps1'
$publisher = Join-Path $fixture 'scripts/publish-asloader-modules.ps1'
$report = Join-Path $fixture 'route.json'
$shell = (Get-Command powershell.exe).Source

function Assert-Route([string]$entry, [string[]]$cli, [string[]]$expected, [switch]$Reject, [switch]$Legacy) {
    if ([IO.File]::Exists($report)) { [IO.File]::Delete($report) }
    $env:CF7_LAYOUT_LEGACY = if ($Legacy) { 'yes' } else { 'no' }
    # Windows PowerShell converts a child's expected stderr into ErrorRecords.
    # Judge the child's actual exit code after collecting the complete diagnostic.
    $savedPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & $shell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $entry @cli 2>&1 | Out-String
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $savedPreference }
    if ($Reject) {
        if ($code -eq 0 -or [IO.File]::Exists($report)) { throw "Expected rejection: $cli" }
        return
    }
    if (-not [IO.File]::Exists($report)) { throw "No route for $cli ($code): $output" }
    $route = [IO.File]::ReadAllText($report) | ConvertFrom-Json
    if ($Legacy) {
        # The fixture assembler stops before the legacy branch could reach CS6.
        if ($code -eq 0 -or $route.kind -ne 'legacy-full') { throw "Expected legacy full publish: $cli" }
    } else {
        $flags = @($route.argv | Select-Object -Skip 6) # common --flash/--loader/--timeout pairs
        if ($code -ne 0 -or $route.kind -ne 'native' -or ($flags -join '|') -cne ($expected -join '|')) {
            throw "Incorrect native arguments for $cli ($code): $flags $output"
        }
    }
}

$oldReport = $env:CF7_LAYOUT_REPORT
$oldLegacy = $env:CF7_LAYOUT_LEGACY
$oldLease = $env:CF7_FLASH_COMPILE_LEASE
try {
    [void][IO.Directory]::CreateDirectory((Join-Path $fixture 'scripts'))
    [void][IO.Directory]::CreateDirectory((Join-Path $fixture 'tools'))
    $env:CF7_LAYOUT_REPORT = $report
    $env:CF7_FLASH_COMPILE_LEASE = $null
    $fakeTasks = @'
function Get-ScheduledTask {
    [CmdletBinding()] param([string]$TaskName)
    $base = Split-Path -Parent $PSScriptRoot
    $flash = Join-Path $base 'Flash.exe'
    $loader = Join-Path $base 'cf7_compile_loader.jsfl'
    $argsText = if ($TaskName -eq 'CompileTriggerTask') { '"' + $loader + '"' } else { '' }
    if ($TaskName -eq 'CompileTriggerTask' -and $env:CF7_LAYOUT_LEGACY -eq 'yes') { $flash = $loader }
    [pscustomobject]@{Actions=@([pscustomobject]@{Execute=$flash;Arguments=$argsText})}
}
'@
    foreach ($file in @('scripts/compile_test.ps1','scripts/publish-asloader-modules.ps1')) {
        $text = [IO.File]::ReadAllText((Join-Path $repo $file))
        $tree = [Management.Automation.Language.Parser]::ParseInput($text,[ref]$null,[ref]$null)
        $at = $tree.ParamBlock.Extent.EndOffset
        [IO.File]::WriteAllText((Join-Path $fixture $file),$text.Insert($at,"$([Environment]::NewLine)$fakeTasks$([Environment]::NewLine)"),$utf8)
        # Copy only the real, named helper files; keep production sources and binaries outside the fixture.
        foreach ($node in $tree.FindAll({param($n) $n -is [Management.Automation.Language.StringConstantExpressionAst] },$true)) {
            $rel = $node.Value
            if ($rel -notmatch '^(scripts|tools)/[^*]+\.(ps1|js|jsfl|py|json)$' -or $rel -in @('scripts/compile_test.ps1','scripts/publish-asloader-modules.ps1')) { continue }
            $source = Join-Path $repo $rel
            if (-not [IO.File]::Exists($source)) { continue }
            $target = Join-Path $fixture $rel
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
            [IO.File]::Copy($source,$target,$true)
        }
    }
    foreach ($name in @('Flash.exe','cf7_compile_loader.jsfl','flash_project_path.cfg')) {
        [IO.File]::WriteAllText((Join-Path $fixture $name),'fixture only')
    }
    $nativeRecorder = "import json,os,sys; open(os.environ['CF7_LAYOUT_REPORT'],'w').write(json.dumps(dict(kind='native',argv=sys.argv[1:])))"
    $legacyRecorder = "require('fs').writeFileSync(process.env.CF7_LAYOUT_REPORT,JSON.stringify({kind:'legacy-full'})); process.exit(88);"
    [IO.File]::WriteAllText((Join-Path $fixture 'tools/publish_asloader_incremental.py'),$nativeRecorder)
    [IO.File]::WriteAllText((Join-Path $fixture 'tools/assemble-collapsed-frame.js'),$legacyRecorder)
    Assert-Route $publicEntry @('-Target','publish') @()
    Assert-Route $publicEntry @('-Target','asloader','-PlanOnly','-ExperimentOutput','default-gate') @('--plan-only','--experiment-output','default-gate')
    Assert-Route $publicEntry @('-Target','publish','-ModuleLayout','Mirror','-ForceFull') @('--force-full','--module-layout','mirror')
    Assert-Route $publicEntry @('-Target','scripts/asLoaderShared/asLoaderShared.xfl','-PublishOnly','-ModuleLayout','Overlay','-ExperimentOutput','direct-check') @('--experiment-output','direct-check','--module-layout','overlay','--force-module','shared')
    Assert-Route $publisher @('-ExperimentLayout','Mirror','-ExperimentOutput','paired') @('--experiment-output','paired','--layout','mirror')
    Assert-Route $publisher @('-ModuleLayout','Mirror','-ExperimentLayout','Overlay','-ExperimentOutput','conflict') @() -Reject
    Assert-Route $publicEntry @('-Target','main','-ModuleLayout','Overlay') @() -Reject
    Assert-Route $publicEntry @('-Target','publish','-ExperimentOutput','../escape') @() -Reject
    Assert-Route $publicEntry @('-Target','publish') @() -Legacy
    Assert-Route $publicEntry @('-Target','publish','-ModuleLayout','Overlay') @() -Legacy -Reject
    Write-Host '[OK] 10 asLoader public and legacy layout routes'
} finally {
    $env:CF7_LAYOUT_REPORT = $oldReport
    $env:CF7_LAYOUT_LEGACY = $oldLegacy
    $env:CF7_FLASH_COMPILE_LEASE = $oldLease
    $full = [IO.Path]::GetFullPath($fixture)
    if ([IO.Path]::GetDirectoryName($full) -ieq [IO.Path]::GetTempPath().TrimEnd('\') -and
            [IO.Path]::GetFileName($full) -match '^cf7-layout-route-[0-9a-f]{32}$' -and [IO.Directory]::Exists($full)) {
        Remove-Item -LiteralPath $full -Recurse -Force
    }
}
