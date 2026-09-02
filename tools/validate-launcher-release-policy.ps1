# Read-only product-policy validation for a prepared Launcher release tree.
# Binary producers must not run these checks as part of the payload identity: policy
# evolves independently and is bound to the validation receipt by policyHash.

[CmdletBinding()]
param(
    [string]$ProjectRoot,
    [string]$ReleaseTreeOid,
    [ValidateSet('Worktree','Index')][string]$IdentityMode = 'Worktree',
    [string]$CandidateRoot,
    [string]$ReceiptPath,
    [string]$TestCheckManifestPath,
    [switch]$AllowTestManifest
)

$ErrorActionPreference = 'Stop'
if (-not $ProjectRoot) {
    $ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
}
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')

function Get-Cf7Sha256Text {
    param([string]$Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-', '')
    } finally { $sha.Dispose() }
}

function Resolve-Cf7Executable {
    param([string[]]$Names)
    foreach ($name in $Names) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command) { return $command.Source }
    }
    # Keep the requested executable name in the check so a missing tool becomes a
    # normal failed receipt entry instead of preventing receipt construction.
    return [string]$Names[0]
}

function Resolve-Cf7PinnedPolicyDotnet {
    $buildEnvGate = Join-Path $ProjectRoot 'tools\check-runtime-build-env.ps1'
    if (-not (Test-Path -LiteralPath $buildEnvGate -PathType Leaf)) {
        throw "Pinned runtime build-environment gate is missing: $buildEnvGate"
    }

    # Never trust a caller-provided host path.  The gate selects a dotnet.exe only
    # after the SDK, host and the rest of the locked runtime toolchain match.  Its
    # Validate mode returns without setting CF7_DOTNET_EXE on any mismatch, which
    # lets this policy entry point fail closed without terminating before it can
    # explain the setup error.
    [Environment]::SetEnvironmentVariable('CF7_DOTNET_EXE', $null, 'Process')
    [Environment]::SetEnvironmentVariable('CF7_RUNTIME_BASELINE', $null, 'Process')
    . $buildEnvGate -ProjectRoot $ProjectRoot -Mode Validate

    $dotnet = $env:CF7_DOTNET_EXE
    if ([string]::IsNullOrWhiteSpace($dotnet) -or -not (Test-Path -LiteralPath $dotnet -PathType Leaf)) {
        throw 'Pinned runtime build-environment validation did not provide CF7_DOTNET_EXE; candidate policy validation is forbidden.'
    }
    return [IO.Path]::GetFullPath($dotnet)
}

function Expand-Cf7PolicyToken {
    param([string]$Value)
    if ($null -eq $Value) { return $null }
    return $Value.Replace('${PROJECT_ROOT}', $ProjectRoot).Replace('${CANDIDATE_ROOT}', [string]$CandidateRoot)
}

function Get-Cf7TrackedStateFingerprint {
    param([string]$ReferenceTree)
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $rows = @(& git -C $ProjectRoot -c core.quotepath=false diff --binary --full-index --no-ext-diff $ReferenceTree -- 2>&1)
        $gitExit = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousPreference }
    if ($gitExit -ne 0) { throw "Cannot fingerprint tracked worktree state: $($rows -join ' ')" }
    return Get-Cf7Sha256Text -Text (([string]::Join("`n", [string[]]$rows)) + "`n")
}

function New-Cf7RequiredPathsCheck {
    param([string]$Name, [string]$Root, [string[]]$Paths)
    return [pscustomobject]@{ Name = $Name; Kind = 'requiredPaths'; Root = $Root; Paths = @($Paths) }
}

function New-Cf7CommandCheck {
    param([string]$Name, [string]$FilePath, [string[]]$Arguments, [string]$WorkingDirectory)
    return [pscustomobject]@{
        Name = $Name
        Kind = 'command'
        FilePath = $FilePath
        Arguments = @($Arguments)
        WorkingDirectory = $WorkingDirectory
    }
}

function Invoke-Cf7PolicyCheck {
    param([Parameter(Mandatory=$true)]$Check)

    $watch = [Diagnostics.Stopwatch]::StartNew()
    $exitCode = 0
    $detail = $null
    $displayCommand = $null
    try {
        if ($Check.Kind -eq 'requiredPaths') {
            $root = Expand-Cf7PolicyToken -Value ([string]$Check.Root)
            $missing = @()
            foreach ($relative in @($Check.Paths)) {
                $expanded = Expand-Cf7PolicyToken -Value ([string]$relative)
                $path = if ([IO.Path]::IsPathRooted($expanded)) { $expanded } else { Join-Path $root $expanded }
                if (-not (Test-Path -LiteralPath $path)) { $missing += $expanded }
            }
            if ($missing.Count -gt 0) {
                $exitCode = 1
                $detail = 'missing: ' + ($missing -join ', ')
            } else {
                $detail = "$(@($Check.Paths).Count) path(s) present"
            }
        } elseif ($Check.Kind -eq 'command') {
            $filePath = Expand-Cf7PolicyToken -Value ([string]$Check.FilePath)
            $workingDirectory = Expand-Cf7PolicyToken -Value ([string]$Check.WorkingDirectory)
            $arguments = @($Check.Arguments | ForEach-Object { Expand-Cf7PolicyToken -Value ([string]$_) })
            $displayCommand = $filePath + ' ' + ($arguments -join ' ')
            if (-not $filePath -or -not (Get-Command $filePath -ErrorAction SilentlyContinue)) {
                throw "executable missing: $filePath"
            }
            if (-not (Test-Path -LiteralPath $workingDirectory -PathType Container)) {
                throw "working directory missing: $workingDirectory"
            }
            Push-Location $workingDirectory
            try {
                $previousPreference = $ErrorActionPreference
                $ErrorActionPreference = 'Continue'
                try {
                    # A child gate's stdout/stderr belongs in the human/CI log, not
                    # in this function's success-output stream.  Letting it escape
                    # would make PowerShell append arbitrary strings to checks[] and
                    # then misclassify an otherwise green receipt as failed.
                    $nativeExit = $null
                    & $filePath @arguments 2>&1 | ForEach-Object { Write-Host ([string]$_) }
                    $nativeExit = $LASTEXITCODE
                } finally {
                    $ErrorActionPreference = $previousPreference
                }
            } finally { Pop-Location }
            $exitCode = if ($null -eq $nativeExit) { 0 } else { [int]$nativeExit }
            if ($exitCode -ne 0) { $detail = "command exited $exitCode" }
        } else {
            throw "unsupported check kind: $($Check.Kind)"
        }
    } catch {
        $exitCode = 1
        $detail = $_.Exception.Message
    } finally { $watch.Stop() }

    return [pscustomobject]@{
        name = [string]$Check.Name
        kind = [string]$Check.Kind
        passed = ($exitCode -eq 0)
        exitCode = $exitCode
        durationMs = [int64]$watch.ElapsedMilliseconds
        command = $displayCommand
        detail = $detail
    }
}

function Get-Cf7ProductionChecks {
    $powershell = Resolve-Cf7Executable -Names @('powershell.exe', 'powershell')
    $node = Resolve-Cf7Executable -Names @('node.exe', 'node')
    $npm = Resolve-Cf7Executable -Names @('npm.cmd', 'npm')
    $python = Resolve-Cf7Executable -Names @('python.exe', 'python3.exe', 'python')
    $checks = @()

    $checks += New-Cf7CommandCheck -Name 'pet-roster-types' -FilePath $powershell `
        -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $ProjectRoot 'tools\audit-pet-roster-types.ps1'), '-ProjectRoot', $ProjectRoot) `
        -WorkingDirectory $ProjectRoot
    $checks += New-Cf7CommandCheck -Name 'task-condition-regression' -FilePath $node `
        -Arguments @((Join-Path $ProjectRoot 'tools\test-derive-task-conditions.js')) -WorkingDirectory $ProjectRoot
    $checks += New-Cf7CommandCheck -Name 'panel-cross-layer-contracts' -FilePath $node `
        -Arguments @((Join-Path $ProjectRoot 'tools\validate-panel-contracts.js')) -WorkingDirectory $ProjectRoot
    $checks += New-Cf7CommandCheck -Name 'web-item-icon-closure' -FilePath $node `
        -Arguments @((Join-Path $ProjectRoot 'tools\audit-web-item-icon-closure.js')) -WorkingDirectory $ProjectRoot
    $checks += New-Cf7CommandCheck -Name 'web-icon-render-entrypoints' -FilePath $node `
        -Arguments @((Join-Path $ProjectRoot 'tools\audit-web-icon-render-entrypoints.js')) -WorkingDirectory $ProjectRoot
    $checks += New-Cf7CommandCheck -Name 'equipment-mod-ui' -FilePath $node `
        -Arguments @((Join-Path $ProjectRoot 'tools\validate-equipment-mod-ui.js')) -WorkingDirectory $ProjectRoot
    $checks += New-Cf7CommandCheck -Name 'material-catalog-current' -FilePath $python `
        -Arguments @((Join-Path $ProjectRoot 'tools\derive-material-catalog.py'), '--check') -WorkingDirectory $ProjectRoot
    $checks += New-Cf7CommandCheck -Name 'material-enemy-portrait-coverage' -FilePath $python `
        -Arguments @((Join-Path $ProjectRoot 'tools\test-material-enemy-portrait-coverage.py')) -WorkingDirectory $ProjectRoot
    $checks += New-Cf7CommandCheck -Name 'shop-portrait-assets' -FilePath $python `
        -Arguments @((Join-Path $ProjectRoot 'tools\test-shop-portrait-assets.py')) -WorkingDirectory $ProjectRoot
    $checks += New-Cf7CommandCheck -Name 'enemy-portrait-resolver-runtime' -FilePath $node `
        -Arguments @((Join-Path $ProjectRoot 'tools\test-portrait-resolver-runtime.js')) -WorkingDirectory $ProjectRoot
    $checks += New-Cf7CommandCheck -Name 'shop-portrait-resolver-runtime' -FilePath $node `
        -Arguments @((Join-Path $ProjectRoot 'tools\test-shop-portrait-resolver-runtime.js')) -WorkingDirectory $ProjectRoot
    $checks += New-Cf7CommandCheck -Name 'workbench-lazy-portrait-closure' -FilePath $node `
        -Arguments @((Join-Path $ProjectRoot 'tools\test-inventory-workbench-lazy-closure.js')) -WorkingDirectory $ProjectRoot
    $checks += New-Cf7CommandCheck -Name 'npc-shop-catalogs' -FilePath $node `
        -Arguments @((Join-Path $ProjectRoot 'tools\validate-npc-shops.js')) -WorkingDirectory $ProjectRoot
    $checks += New-Cf7CommandCheck -Name 'item-set-metadata' -FilePath $node `
        -Arguments @((Join-Path $ProjectRoot 'tools\validate-item-sets.js')) -WorkingDirectory $ProjectRoot
    $checks += New-Cf7CommandCheck -Name 'font-catalog-schema-and-assets' -FilePath $node `
        -Arguments @((Join-Path $ProjectRoot 'tools\fontctl\cli.js'), 'validate', '--json') `
        -WorkingDirectory $ProjectRoot
    $checks += New-Cf7CommandCheck -Name 'font-catalog-generated-current' -FilePath $node `
        -Arguments @((Join-Path $ProjectRoot 'tools\fontctl\cli.js'), 'generate', '--check', '--json') `
        -WorkingDirectory $ProjectRoot
    $checks += New-Cf7CommandCheck -Name 'arena-meta-teams-current' -FilePath $node `
        -Arguments @((Join-Path $ProjectRoot 'tools\derive-arena-meta-teams.js'), '--check') -WorkingDirectory $ProjectRoot
    $checks += New-Cf7CommandCheck -Name 'arena-factions-current' -FilePath $node `
        -Arguments @((Join-Path $ProjectRoot 'tools\derive-arena-factions.js'), '--check') -WorkingDirectory $ProjectRoot
    $checks += New-Cf7CommandCheck -Name 'arena-drop-rules-current' -FilePath $node `
        -Arguments @((Join-Path $ProjectRoot 'tools\validate-arena-drop-rules.js')) -WorkingDirectory $ProjectRoot
    $checks += New-Cf7RequiredPathsCheck -Name 'required-arena-authority-assets' `
        -Root (Join-Path $ProjectRoot 'data\arena') `
        -Paths @('arena_calibrated_rosters.json', 'arena_config.xml', 'arena_drop_rules.xml', 'arena_factions.json', 'meta_teams.json')
    $checks += New-Cf7RequiredPathsCheck -Name 'required-arena-unit-catalog' `
        -Root (Join-Path $ProjectRoot 'data\units') `
        -Paths @('units.json')

    $requiredWebPaths = @(
        'bootstrap.html', 'bootstrap-main.js', 'overlay.html', 'config\version.js',
        'css\bootstrap.css', 'css\game-ui-behavior.css', 'css\welcome.css', 'css\overlay.css',
        'css\panels.css', 'css\panels\foundation-top.css', 'css\workbench\tokens.css',
        'css\panels\foundation-rest.css', 'css\workbench\core.css', 'css\workbench\profiles.css',
        'css\panels\features.css',
        'css\workbench\inventory.css', 'css\workbench\skins.css', 'css\workbench\entities.css',
        'css\workbench\crafting.css', 'css\workbench\skills.css', 'css\workbench\equipment-tuning.css',
        'css\workbench\components.css', 'css\workbench\character-build.css',
        'css\workbench\character-build-stats.css',
        'css\workbench\states.css', 'css\workbench\motion.css',
        'css\hairdresser.css', 'css\task_panel.css', 'css\workbench\team.css',
        'lib\marked.min.js', 'help\controls.md', 'help\worldview.md', 'help\easter-eggs.md',
        'icons\manifest.json', 'data\lockbox-variants.json', 'assets\bg\manifest.json',
        'assets\cursor\native\manifest.json', 'assets\cursor\native\normal.png',
        'assets\cursor\native\click.png', 'assets\cursor\native\hoverGrab.png',
        'assets\cursor\native\grab.png', 'assets\cursor\native\attack.png',
        'assets\cursor\native\openDoor.png', 'assets\logos\cf7me-title.png',
        'assets\logos\steam.svg', 'assets\intro.mp4', 'assets\map\page-base.webp',
        'assets\map\page-faction.webp', 'modules\audio.js', 'modules\game-ui-behavior.js',
        'modules\factions.js', 'modules\archive-schema.js', 'modules\archive-editor.js',
        'modules\diagnostic-log.js', 'modules\display.js', 'modules\about.js', 'modules\bridge.js',
        'modules\uidata.js', 'modules\toast.js',
        'modules\perf-frame-limiter.js', 'modules\cursor-feedback.js',
        'modules\lazy-loader.js', 'modules\panels.js',
        'modules\panel-scale.js', 'modules\panels-lazy-registry.js', 'modules\tooltip.js',
        'modules\icons.js', 'modules\panel-runtime.js', 'modules\workbench-lifecycle.js',
        'modules\workbench-focus.js', 'modules\workbench-primitives.js',
        'modules\workbench-profile.js', 'modules\workbench.js',
        'modules\workbench-components.js', 'modules\workbench-inspection-viewport.js',
        'modules\character-build\character-build-mutation.js',
        'modules\character-build\character-build-drug-layout.js',
        'modules\character-build\character-build-session-contract.js',
        'modules\character-build-session.js',
        'modules\loadout-picker\loadout-picker-action-view.js',
        'modules\character-build\character-build-tuning-adapter.js',
        'modules\character-build\character-build-tuning-ports.js',
        'modules\character-build\character-build-candidate-eligibility.js',
        'modules\character-build\character-build-candidate-tooltip.js',
        'modules\loadout-picker\loadout-picker-candidate-state.js',
        'modules\character-build\character-build-facet-counts.js',
        'modules\character-build\character-build-stats-view.js',
        'modules\character-build\character-build-doll-preview.js',
        'modules\character-build\character-build-template.js',
        'modules\character-build\character-build-loadout-presenter.js',
        'modules\loadout-picker\loadout-picker-slot-grid.js',
        'modules\loadout-picker\loadout-picker-drop-policy.js',
        'modules\loadout-picker\loadout-picker-candidate-drag.js',
        'modules\loadout-picker\loadout-picker-candidate-pane.js',
        'modules\loadout-picker\loadout-picker.js',
        'modules\character-build-view.js', 'modules\character-build\character-build-tuning.js',
        'modules\character-build\character-build-slot-transition.js',
        'modules\character-build\character-build-pose.js',
        'modules\character-build\character-build-projection.js',
        'modules\character-build\character-build-transport.js',
        'modules\character-build\character-build-item-use.js',
        'modules\character-build\character-build-item-use-channel.js',
        'modules\character-build\character-build-candidate-channel.js',
        'modules\character-build.js',
        'modules\item-filter.js', 'modules\kshop-runtime.js',
        'modules\inventory-runtime.js', 'modules\inventory-ui.js', 'modules\equipment-tuning-runtime.js',
        'modules\equipment-tuning-model.js', 'modules\equipment-tuning-decision-presenter.js',
        'modules\equipment-tuning-render.js', 'modules\equipment-tuning-interaction.js',
        'modules\equipment-tuning-write-lifecycle.js',
        'modules\equipment-tuning-loadout-lifecycle.js',
        'modules\equipment-tuning-source-marker.js',
        'modules\equipment-tuning-view.js', 'modules\inventory-tuning-scope.js',
        'modules\inventory-storage-workbench.js',
        'modules\inventory-workbench-feature-loader.js',
        'modules\crafting-inventory-organizer.js',
        'modules\inventory-workbench.js', 'modules\kshop.js',
        'modules\kshop-views.js', 'modules\kshop-cart-controller.js',
        'modules\kshop-catalog-presenter.js', 'modules\kshop-owned-inventory-presenter.js',
        'modules\kshop-tooltip-presenter.js', 'modules\kshop-procurement-navigation.js',
        'modules\inventory-workbench-config.js',
        'modules\inventory-workbench-preparation-menu.js',
        'modules\equipment-tuning-confirmation.js', 'modules\inventory-workbench-navigation.js',
        'modules\inventory-workbench-header.js', 'modules\inventory-workbench-quick-transfer.js',
        'modules\inventory-workbench-owned-view.js', 'modules\npcshop-runtime.js',
        'modules\npcshop-material-navigation.js', 'modules\npcshop-secondary-pages.js',
        'modules\npcshop.js', 'modules\crafting-runtime.js',
        'modules\crafting-detail-presenter.js', 'modules\crafting.js',
        'modules\hairdresser-runtime.js', 'modules\hairdresser.js',
        'modules\skills-runtime.js', 'modules\skills-library.js',
        'modules\skills-trainer.js', 'modules\skills-loadout.js', 'modules\skills-interactions.js',
        'modules\skills-render.js', 'modules\skills-diagnostics.js', 'modules\skills.js',
        'modules\help-panel.js', 'modules\intelligence-components.js', 'modules\font-pack-banner.js',
        'modules\intelligence-panel.js', 'modules\jukebox\jukebox-panel.js',
        'modules\map-avatar-source-data.js', 'modules\map-panel-data.js', 'modules\map-fit-presets.js',
        'modules\map-scale-policy.js', 'modules\map-canvas-stage-renderer.js', 'modules\map-panel.js',
        'modules\stage-select-data.js', 'modules\stage-select-panel.js',
        'modules\pet-panel.js', 'modules\merc-data.js', 'modules\merc-panel.js',
        'modules\merc\merc-loadout-drop-policy.js', 'modules\merc\merc-loadout-channel.js',
        'modules\merc\merc-loadout-picker.js',
        'modules\team\team-shared.js', 'modules\team\team-panel.js', 'modules\arena-meta-rosters.js', 'modules\arena-factions.js',
        'modules\arena-unit-catalog.js', 'modules\arena-unit-param-presets.js',
        'modules\arena-custom-presets.js', 'modules\arena-custom-match-code.js', 'modules\arena-panel.js',
        'modules\tasks\task-panel.js', 'modules\tasks\task-catalog.json',
        'modules\tasks\achievement-catalog.json', 'modules\tasks\achievement-tab.js',
        'assets\pets\pet_locked.png', 'modules\tasks\assets\finish_npc.png',
        'modules\tasks\assets\item_bg.png', 'modules\tasks\assets\requirement_contain.png',
        'modules\tasks\assets\requirement_stage.png', 'modules\tasks\assets\requirement_submit.png',
        'modules\tasks\assets\task_icon_bg.png', 'modules\tasks\assets\task_main_bg.png',
        'modules\tasks\assets\task_scroll.png', 'assets\stage-select\backgrounds\waste-city.png',
        'assets\stage-select\backgrounds\wormhole-cave.jpg',
        'assets\stage-select\backgrounds\snow-interior.jpg',
        'assets\stage-select\backgrounds\wide-sky-1024x768.jpg',
        'assets\stage-select\backgrounds\crashed-warship.jpg',
        'assets\stage-select\backgrounds\trial-depth.jpg',
        'assets\stage-select\previews\_missing-preview.svg', 'modules\overlay-audio-bindings.js',
        'modules\minigames\shared\host-bridge.js', 'modules\minigames\shared\minigame-shell.css',
        'modules\minigames\lockbox\lockbox.css', 'modules\minigames\lockbox\lockbox-panel.js',
        'modules\loot\loot-runtime.js', 'modules\loot\loot-state.js',
        'modules\loot\loot-view.js', 'modules\loot\loot-organizer.js',
        'modules\loot\loot-panel.js',
        'modules\minigames\pinalign\pinalign.css', 'modules\minigames\pinalign\pinalign-panel.js',
        'modules\minigames\gobang\gobang.css', 'modules\minigames\gobang\gobang-panel.js',
        'modules\minigames\gobang\gobang-audio.js', 'modules\minigames\gobang\core\index.js',
        'modules\asset-timeline.js', 'modules\dressup-doll-renderer.js',
        'modules\dressup\dressup-panel.js', 'assets\dressup\manifest.json',
        'modules\portrait-resolver.js', 'assets\enemy-portraits\manifest.json',
        'modules\shop-portrait-resolver.js', 'assets\shop-portraits\manifest.json',
        'modules\dialogue\dialogue-view.js', 'assets\dialogue-portraits\manifest.json',
        'generated\font-catalog.json', 'generated\font-catalog.css', 'generated\font-catalog.js',
        'assets\fonts\font-pack-manifest.json'
    )
    $checks += New-Cf7RequiredPathsCheck -Name 'required-web-runtime-assets' `
        -Root (Join-Path $ProjectRoot 'launcher\web') -Paths $requiredWebPaths
    $checks += New-Cf7CommandCheck -Name 'workbench-css-closure' -FilePath $node `
        -Arguments @((Join-Path $ProjectRoot 'tools\check-workbench-css-bundle.js')) -WorkingDirectory $ProjectRoot
    $checks += New-Cf7CommandCheck -Name 'workbench-ui-ratchet-regression' -FilePath $node `
        -Arguments @((Join-Path $ProjectRoot 'tools\test-workbench-ui-ratchet.js')) -WorkingDirectory $ProjectRoot
    $checks += New-Cf7CommandCheck -Name 'workbench-ui-release-tree-audit' -FilePath $node `
        -Arguments @((Join-Path $ProjectRoot 'tools\audit-workbench-ui.js'), '--release-tree', '--text', '--strict-warnings') `
        -WorkingDirectory $ProjectRoot
    $checks += New-Cf7CommandCheck -Name 'workbench-inspection-viewport' -FilePath $node `
        -Arguments @((Join-Path $ProjectRoot 'tools\test-workbench-inspection-viewport.js')) -WorkingDirectory $ProjectRoot
    $checks += New-Cf7CommandCheck -Name 'inventory-preparation-menu' -FilePath $node `
        -Arguments @((Join-Path $ProjectRoot 'tools\test-inventory-workbench-preparation-menu.js')) -WorkingDirectory $ProjectRoot
    $checks += New-Cf7CommandCheck -Name 'map-lossless-webp-closure' -FilePath $node `
        -Arguments @((Join-Path $ProjectRoot 'tools\audit-map-webp-assets.js')) -WorkingDirectory $ProjectRoot
    $checks += New-Cf7CommandCheck -Name 'map-scale-experience' -FilePath $node `
        -Arguments @((Join-Path $ProjectRoot 'tools\audit-map-scale-experience.js')) -WorkingDirectory $ProjectRoot
    $checks += New-Cf7CommandCheck -Name 'native-cursor-contract' -FilePath $node `
        -Arguments @((Join-Path $ProjectRoot 'tools\audit-native-cursor-assets.js')) -WorkingDirectory $ProjectRoot
    $checks += New-Cf7RequiredPathsCheck -Name 'required-launcher-data-assets' `
        -Root (Join-Path $ProjectRoot 'launcher\data') `
        -Paths @('map_hud_data.json', 'save_repair_dict.json', 'save_schema.json')
    $checks += New-Cf7RequiredPathsCheck -Name 'required-font-runtime-assets' `
        -Root (Join-Path $ProjectRoot 'fonts') `
        -Paths @(
            'README.md', 'fonts.xml', 'fonts.xsd',
            'licenses\JetBrainsMono-OFL-1.1.txt', 'licenses\SourceHanSerif-OFL-1.1.txt',
            'permanent\runtime\jetbrains-mono.woff2',
            'permanent\runtime\source-han-serif-cn-regular.otf'
        )
    $checks += New-Cf7CommandCheck -Name 'save-repair-dictionary-current' -FilePath $npm `
        -Arguments @('run', 'verify', '--silent') `
        -WorkingDirectory (Join-Path $ProjectRoot 'tools\cf7-save-repair-dict-build')

    if (-not [string]::IsNullOrWhiteSpace($CandidateRoot)) {
        $resolvedCandidate = [IO.Path]::GetFullPath($CandidateRoot).TrimEnd('\')
        $dotnet = Resolve-Cf7PinnedPolicyDotnet
        $checks += New-Cf7RequiredPathsCheck -Name 'candidate-required-artifacts' -Root $resolvedCandidate `
            -Paths @('CRAZYFLASHER7MercenaryEmpire.exe', 'runtime\CRAZYFLASHER7MercenaryEmpire.Core.dll')
        $checks += New-Cf7CommandCheck -Name 'candidate-player-info-svg-contract' -FilePath $powershell `
            -Arguments @(
                '-NoProfile',
                '-ExecutionPolicy', 'Bypass',
                '-File', (Join-Path $ProjectRoot 'tools\validate-player-info-svg-production-contract.ps1'),
                '-ProjectRoot', $ProjectRoot,
                '-CandidateRoot', $resolvedCandidate
            ) `
            -WorkingDirectory $ProjectRoot
        $checks += New-Cf7CommandCheck -Name 'candidate-managed-optimized' -FilePath $dotnet `
            -Arguments @('run', (Join-Path $ProjectRoot 'tools\assert-optimized.cs'), '--', (Join-Path $resolvedCandidate 'runtime\CRAZYFLASHER7MercenaryEmpire.Core.dll')) `
            -WorkingDirectory $ProjectRoot
        $checks += New-Cf7CommandCheck -Name 'candidate-runtime-bundle' -FilePath $powershell `
            -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $ProjectRoot 'tools\verify-runtime-bundle-v2.ps1'), '-ProjectRoot', $ProjectRoot, '-DeploymentRoot', $resolvedCandidate) `
            -WorkingDirectory $ProjectRoot
    }

    return @($checks)
}

function Get-Cf7TestChecks {
    param([string]$ManifestPath)
    if (-not $AllowTestManifest) {
        throw '-TestCheckManifestPath is test-only and requires -AllowTestManifest.'
    }
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        throw "Test check manifest missing: $ManifestPath"
    }
    $manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $ManifestPath | ConvertFrom-Json
    if ($manifest.schema -ne 'cf7-runtime-policy-test-manifest.v1') {
        throw 'Unsupported test check manifest schema.'
    }
    $checks = @()
    foreach ($entry in @($manifest.checks)) {
        if ($entry.kind -eq 'requiredPaths') {
            $checks += New-Cf7RequiredPathsCheck -Name ([string]$entry.name) `
                -Root ([string]$entry.root) -Paths @($entry.paths | ForEach-Object { [string]$_ })
        } elseif ($entry.kind -eq 'command') {
            $checks += New-Cf7CommandCheck -Name ([string]$entry.name) `
                -FilePath ([string]$entry.filePath) `
                -Arguments @($entry.arguments | ForEach-Object { [string]$_ }) `
                -WorkingDirectory ([string]$entry.workingDirectory)
        } else {
            throw "Unsupported test check kind: $($entry.kind)"
        }
    }
    if ($checks.Count -eq 0) { throw 'Test check manifest must contain at least one check.' }
    return @($checks)
}

$v2Common = Join-Path $ProjectRoot 'tools\runtime-build-v2-common.ps1'
if (-not (Test-Path -LiteralPath $v2Common -PathType Leaf)) {
    Write-Host "[RuntimePolicy] FAIL: v2 identity common is missing: $v2Common" -ForegroundColor Red
    Write-Host 'Land tools/runtime-build-v2-common.ps1 before invoking the release policy validator.' -ForegroundColor Yellow
    exit 2
}

try {
    . $v2Common
    foreach ($functionName in @('Get-Cf7RuntimeV2Identity', 'Get-Cf7RuntimeV2ReleaseTreeOid', 'Get-Cf7RuntimePayloadClosureV2')) {
        if (-not (Get-Command $functionName -CommandType Function -ErrorAction SilentlyContinue)) {
            throw "v2 identity common does not export required function: $functionName"
        }
    }
    $computedReleaseTree = [string](Get-Cf7RuntimeV2ReleaseTreeOid -ProjectRoot $ProjectRoot -Mode $IdentityMode)
    if (-not [string]::IsNullOrWhiteSpace($ReleaseTreeOid)) {
        $resolved = @(& git -C $ProjectRoot rev-parse --verify "$ReleaseTreeOid`^{tree}" 2>&1)
        if ($LASTEXITCODE -ne 0 -or $resolved.Count -ne 1) {
            throw "Cannot resolve requested release tree: $ReleaseTreeOid"
        }
        $requestedReleaseTree = ([string]$resolved[0]).Trim().ToLowerInvariant()
        if ($requestedReleaseTree -ne $computedReleaseTree.ToLowerInvariant()) {
            throw "ReleaseTreeOid does not match $IdentityMode identity tree: requested=$requestedReleaseTree actual=$computedReleaseTree"
        }
    }
    $releaseTree = $computedReleaseTree.ToLowerInvariant()
    $identity = Get-Cf7RuntimeV2Identity -ProjectRoot $ProjectRoot -Mode $IdentityMode
    foreach ($field in @('artifactSourceHash', 'producerRecipeHash', 'toolchainLockHash', 'policyHash', 'buildIdentityHash')) {
        if ([string]$identity.$field -notmatch '^[0-9A-Fa-f]{64}$') {
            throw "v2 identity returned invalid field: $field"
        }
    }
    $resolvedCandidateRoot = $null
    $candidatePayloadClosureHash = $null
    if (-not [string]::IsNullOrWhiteSpace($CandidateRoot)) {
        $resolvedCandidateRoot = (Resolve-Path -LiteralPath $CandidateRoot).Path.TrimEnd('\')
        # Candidate bytes always live on disk even when the release identity is bound to
        # an alternate/staged Git index. The tracked-tree materialization invariant below
        # still prevents policy commands from auditing worktree bytes that differ from it.
        $candidateClosure = Get-Cf7RuntimePayloadClosureV2 `
            -ProjectRoot $ProjectRoot -DeploymentRoot $resolvedCandidateRoot -Mode Worktree
        $candidatePayloadClosureHash = ([string]$candidateClosure.payloadClosureHash).ToUpperInvariant()
        if ($candidatePayloadClosureHash -notmatch '^[0-9A-F]{64}$') {
            throw 'Candidate payload closure returned an invalid SHA-256.'
        }
    }
} catch {
    Write-Host "[RuntimePolicy] FAIL: cannot establish v2 release identity: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}

if ([string]::IsNullOrWhiteSpace($ReceiptPath)) {
    $ReceiptPath = Join-Path $ProjectRoot ("tmp\runtime-policy-receipts\{0}\cf7-runtime-policy-validation.v2.json" -f $releaseTree.Substring(0, 16))
}
$ReceiptPath = [IO.Path]::GetFullPath($ReceiptPath)
$relativeReceipt = $null
if ($ReceiptPath.StartsWith($ProjectRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    $relativeReceipt = $ReceiptPath.Substring($ProjectRoot.Length + 1).Replace('\', '/')
    $trackedReceipt = @(& git -C $ProjectRoot ls-files -- $relativeReceipt)
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[RuntimePolicy] FAIL: cannot inspect receipt tracking state: $relativeReceipt" -ForegroundColor Red
        exit 2
    }
    if (@($trackedReceipt | Where-Object { ([string]$_).Replace('\', '/') -eq $relativeReceipt }).Count -gt 0) {
        Write-Host "[RuntimePolicy] FAIL: receipt path must not overwrite a tracked file: $relativeReceipt" -ForegroundColor Red
        exit 2
    }
}

try {
    $checks = if ([string]::IsNullOrWhiteSpace($TestCheckManifestPath)) {
        Get-Cf7ProductionChecks
    } else {
        Get-Cf7TestChecks -ManifestPath ([IO.Path]::GetFullPath($TestCheckManifestPath))
    }
} catch {
    Write-Host "[RuntimePolicy] FAIL: cannot create policy checks: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}

$startedAt = [DateTime]::UtcNow
$beforeFingerprint = Get-Cf7TrackedStateFingerprint -ReferenceTree $releaseTree
$emptyTrackedFingerprint = Get-Cf7Sha256Text -Text "`n"
$materialized = $beforeFingerprint -eq $emptyTrackedFingerprint
$results = @(
    [pscustomobject]@{
        name = 'release-tree-materialized'
        kind = 'invariant'
        passed = $materialized
        exitCode = $(if ($materialized) { 0 } else { 1 })
        durationMs = 0
        command = $null
        detail = $(if ($materialized) { 'tracked worktree exactly materializes releaseTreeOid' } else { 'tracked worktree differs from releaseTreeOid; product checks were not run on an immutable target' })
    }
)
if ($materialized) {
    foreach ($check in $checks) {
        Write-Host "[RuntimePolicy] $($check.Name)..." -ForegroundColor Yellow
        $result = Invoke-Cf7PolicyCheck -Check $check
        $results += $result
        if ($result.passed) {
            Write-Host "  OK ($($result.durationMs) ms)" -ForegroundColor Green
        } else {
            Write-Host "  FAIL exit=$($result.exitCode) $($result.detail)" -ForegroundColor Red
        }
    }
} else {
    Write-Host '[RuntimePolicy] FAIL: worktree does not materialize the bound release tree; skipping product checks.' -ForegroundColor Red
    foreach ($check in $checks) {
        $results += [pscustomobject]@{
            name = [string]$check.Name
            kind = [string]$check.Kind
            passed = $false
            exitCode = 1
            durationMs = 0
            command = $null
            detail = 'skipped because release-tree-materialized failed'
        }
    }
}
$afterFingerprint = Get-Cf7TrackedStateFingerprint -ReferenceTree $releaseTree
$readOnlyPassed = $beforeFingerprint -eq $afterFingerprint
$results += [pscustomobject]@{
    name = 'tracked-tree-readonly'
    kind = 'invariant'
    passed = $readOnlyPassed
    exitCode = $(if ($readOnlyPassed) { 0 } else { 1 })
    durationMs = 0
    command = $null
    detail = $(if ($readOnlyPassed) { 'tracked worktree state unchanged' } else { "tracked state changed: before=$beforeFingerprint after=$afterFingerprint" })
}
if ($resolvedCandidateRoot) {
    $candidateReadOnlyPassed = $false
    $candidateReadOnlyDetail = $null
    try {
        $candidateClosureAfter = Get-Cf7RuntimePayloadClosureV2 `
            -ProjectRoot $ProjectRoot -DeploymentRoot $resolvedCandidateRoot -Mode Worktree
        $candidateClosureAfterHash = ([string]$candidateClosureAfter.payloadClosureHash).ToUpperInvariant()
        $candidateReadOnlyPassed = $candidateClosureAfterHash -eq $candidatePayloadClosureHash
        $candidateReadOnlyDetail = if ($candidateReadOnlyPassed) {
            "candidate payload closure unchanged: $candidatePayloadClosureHash"
        } else {
            "candidate payload closure changed: before=$candidatePayloadClosureHash after=$candidateClosureAfterHash"
        }
    } catch {
        $candidateReadOnlyDetail = "cannot re-read candidate payload closure: $($_.Exception.Message)"
    }
    $results += [pscustomobject]@{
        name = 'candidate-payload-readonly'
        kind = 'invariant'
        passed = $candidateReadOnlyPassed
        exitCode = $(if ($candidateReadOnlyPassed) { 0 } else { 1 })
        durationMs = 0
        command = $null
        detail = $candidateReadOnlyDetail
    }
}

$passed = @($results | Where-Object { -not $_.passed }).Count -eq 0
$completedAt = [DateTime]::UtcNow
$receipt = [ordered]@{
    schema = 'cf7-runtime-policy-validation.v2'
    profile = $(if ([string]::IsNullOrWhiteSpace($TestCheckManifestPath)) { 'production' } else { 'test' })
    passed = $passed
    releaseTreeOid = $releaseTree
    policyHash = ([string]$identity.policyHash).ToUpperInvariant()
    artifactSourceHash = ([string]$identity.artifactSourceHash).ToUpperInvariant()
    producerRecipeHash = ([string]$identity.producerRecipeHash).ToUpperInvariant()
    toolchainLockHash = ([string]$identity.toolchainLockHash).ToUpperInvariant()
    toolchainHash = ([string]$identity.toolchainLockHash).ToUpperInvariant()
    buildIdentityHash = ([string]$identity.buildIdentityHash).ToUpperInvariant()
    candidateRoot = $resolvedCandidateRoot
    candidatePayloadClosureHash = $candidatePayloadClosureHash
    startedAtUtc = $startedAt.ToString('o')
    completedAtUtc = $completedAt.ToString('o')
    trackedStateBefore = $beforeFingerprint
    trackedStateAfter = $afterFingerprint
    checks = @($results)
}

$receiptDir = Split-Path -Parent $ReceiptPath
New-Item -ItemType Directory -Path $receiptDir -Force | Out-Null
$temporaryReceipt = Join-Path $receiptDir ('.' + [IO.Path]::GetFileName($ReceiptPath) + '.' + [Guid]::NewGuid().ToString('N') + '.tmp')
$utf8NoBom = New-Object Text.UTF8Encoding($false)
try {
    [IO.File]::WriteAllText($temporaryReceipt, (($receipt | ConvertTo-Json -Depth 12) + "`n"), $utf8NoBom)
    Move-Item -LiteralPath $temporaryReceipt -Destination $ReceiptPath -Force
} finally {
    if (Test-Path -LiteralPath $temporaryReceipt) { Remove-Item -LiteralPath $temporaryReceipt -Force }
}

if (-not $passed) {
    Write-Host "[RuntimePolicy] FAIL receipt=$ReceiptPath" -ForegroundColor Red
    exit 1
}
Write-Host "[RuntimePolicy] OK receipt=$ReceiptPath" -ForegroundColor Green
