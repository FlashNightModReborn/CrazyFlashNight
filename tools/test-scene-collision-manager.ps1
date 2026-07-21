[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
$managerPath = Join-Path $projectDir 'scripts\类定义\org\flashNight\arki\scene\SceneCollisionManager.as'
$sceneManagerPath = Join-Path $projectDir 'scripts\类定义\org\flashNight\arki\scene\SceneManager.as'
$obstacleRendererPath = Join-Path $projectDir 'scripts\类定义\org\flashNight\arki\unit\UnitComponent\Initializer\ElementComponent\ObstacleRenderer.as'
$suitePath = Join-Path $projectDir 'scripts\类定义\org\flashNight\arki\scene\SceneCollisionManagerTest.as'
$templatePath = Join-Path $projectDir 'scripts\test-runners\scene-collision-manager\TestLoader.as.template'
$runnerPath = Join-Path $projectDir 'scripts\run-scene-collision-manager-tests.ps1'

$passed = 0
$failed = 0

function Test-Check([bool]$Condition, [string]$Message) {
    if ($Condition) {
        $script:passed++
        Write-Host "PASS: $Message"
    } else {
        $script:failed++
        Write-Host "FAIL: $Message"
    }
}

function Test-Utf8Bom([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    return $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and
        $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
}

function Get-MethodBody([string]$Source, [string]$SignaturePattern) {
    $match = [regex]::Match($Source, $SignaturePattern)
    if (-not $match.Success) { return $null }
    $openIndex = $Source.IndexOf('{', $match.Index + $match.Length)
    if ($openIndex -lt 0) { return $null }
    $depth = 0
    for ($i = $openIndex; $i -lt $Source.Length; $i++) {
        if ($Source[$i] -eq '{') { $depth++ }
        elseif ($Source[$i] -eq '}') {
            $depth--
            if ($depth -eq 0) {
                return $Source.Substring($openIndex + 1, $i - $openIndex - 1)
            }
        }
    }
    return $null
}

foreach ($path in @($managerPath, $sceneManagerPath, $obstacleRendererPath,
        $suitePath, $templatePath, $runnerPath)) {
    Test-Check (Test-Path -LiteralPath $path) ("required artifact exists: {0}" -f
        [System.IO.Path]::GetFileName($path))
}

Test-Check (Test-Utf8Bom $managerPath) 'SceneCollisionManager.as is UTF-8 with BOM'
Test-Check (Test-Utf8Bom $sceneManagerPath) 'SceneManager.as remains UTF-8 with BOM'
Test-Check (Test-Utf8Bom $obstacleRendererPath) 'ObstacleRenderer.as remains UTF-8 with BOM'
Test-Check (Test-Utf8Bom $suitePath) 'SceneCollisionManagerTest.as is UTF-8 with BOM'
Test-Check (Test-Utf8Bom $templatePath) 'focused TestLoader template is UTF-8 with BOM'

$manager = [System.IO.File]::ReadAllText($managerPath, [System.Text.Encoding]::UTF8)
$sceneManager = [System.IO.File]::ReadAllText($sceneManagerPath, [System.Text.Encoding]::UTF8)
$obstacleRenderer = [System.IO.File]::ReadAllText(
    $obstacleRendererPath, [System.Text.Encoding]::UTF8)
$suite = [System.IO.File]::ReadAllText($suitePath, [System.Text.Encoding]::UTF8)
$template = [System.IO.File]::ReadAllText($templatePath, [System.Text.Encoding]::UTF8)

Test-Check ($obstacleRenderer -match
    'import\s+org\.flashNight\.arki\.scene\.SceneCollisionManager\s*;') `
    'production ObstacleRenderer explicitly imports the collision authority'

$initBody = Get-MethodBody $manager 'public\s+function\s+init\s*\(\s*\)\s*:\s*Void'
Test-Check ($null -ne $initBody) 'init method is discoverable'
Test-Check ($initBody.IndexOf('dispose();') -ge 0 -and
    $initBody.IndexOf('dispose();') -lt $initBody.IndexOf('this.collisionLayer = _root.collisionLayer')) `
    'init disposes stale state before binding the current layer'
Test-Check ($initBody -match 'this\.collisions\s*=\s*\[\]\s*;' -and
    $initBody -match 'this\.movieClipCollisions\s*=\s*\[\]\s*;') `
    'init creates two independent empty replay collections'

$addBody = Get-MethodBody $manager 'public\s+function\s+addCollisions\s*\('
Test-Check ($null -ne $addBody) 'addCollisions method is discoverable'
Test-Check ($addBody -match 'ObjectUtil\.clone\s*\(\s*_collisions\s*\)' -and
    $addBody -match 'this\.collisions\.push\s*\(') `
    'addCollisions deep-clones and appends incoming polygons'
Test-Check ($addBody -notmatch
    'this\.collisions\s*=\s*ObjectUtil\.toArray\s*\(\s*ObjectUtil\.clone') `
    'addCollisions cannot regress to last-source-wins assignment'

$addMovieBody = Get-MethodBody $manager 'public\s+function\s+addMovieClipCollision\s*\('
Test-Check ($addMovieBody -match 'current\.mc\s*===\s*mc' -and
    $addMovieBody -match 'current\.rect\s*=\s*ObjectUtil\.clone\s*\(\s*rect\s*\)') `
    'MovieClip re-registration updates one stable cloned record'

$updateBody = Get-MethodBody $manager 'public\s+function\s+update\s*\('
Test-Check ($updateBody -match 'mcColli\.mc\s*=\s*null\s*;' -and
    $updateBody -match 'mcColli\.rect\s*=\s*null\s*;' -and
    $updateBody -match 'movieClipCollisions\.splice\s*\(') `
    'unloaded MovieClip pruning severs references before removal'

$redrawBody = Get-MethodBody $manager 'public\s+function\s+redraw\s*\('
Test-Check ($redrawBody.IndexOf('CollisionLayerRenderer.clearAll();') -ge 0 -and
    $redrawBody.IndexOf('CollisionLayerRenderer.clearAll();') -lt
        $redrawBody.IndexOf('CollisionLayerRenderer.drawBoundary(')) `
    'full redraw clears once before replaying registered sources'
Test-Check ($redrawBody -match 'drawPolygons\s*\(' -and
    $redrawBody -match 'drawRect\s*\(') `
    'full redraw still restores polygon and registered MovieClip sources'

$renderObstacleBody = Get-MethodBody $obstacleRenderer `
    'public\s+static\s+function\s+renderObstacle\s*\('
$drawObstacleIndex = $renderObstacleBody.IndexOf(
    'CollisionLayerRenderer.drawObstacle(collisionLayer, rect, true);')
$registerObstacleIndex = $renderObstacleBody.IndexOf(
    'sceneCollisionManager.addMovieClipCollision(target, rect);')
Test-Check ($drawObstacleIndex -ge 0 -and
    $registerObstacleIndex -gt $drawObstacleIndex -and
    $renderObstacleBody -match
        'sceneCollisionManager\.collisionLayer\s*===\s*collisionLayer' -and
    $manager -notmatch 'for\s*\([^\)]*\s+in\s+gameworld\s*\)') `
    'ordinary obstacles register after initial draw; redraw never trusts AVM1 child enumeration'

$disposeBody = Get-MethodBody $manager 'public\s+function\s+dispose\s*\('
Test-Check ($disposeBody -match
    'this\.collisionLayer\s*===\s*_root\.collisionLayer' -and
    $disposeBody -match 'this\.collisionLayer\.clear\s*\(\s*\)') `
    'dispose clears the exact bound layer without assuming the root still points to it'
Test-Check ($disposeBody -match 'mcColli\.mc\s*=\s*null\s*;' -and
    $disposeBody -match 'mcColli\.rect\s*=\s*null\s*;') `
    'dispose explicitly releases retained MovieClip and rect references'
Test-Check ($disposeBody -match 'this\.movieClipCollisions\s*=\s*null\s*;' -and
    $disposeBody -match 'this\.collisions\s*=\s*null\s*;' -and
    $disposeBody -match 'this\.collisionLayer\s*=\s*null\s*;') `
    'dispose ends with zero manager-owned scene data'

$removeBody = Get-MethodBody $sceneManager 'public\s+function\s+removeGameWorld\s*\('
$stopIndex = $removeBody.IndexOf('this.active = false;')
$disposeIndex = $removeBody.IndexOf('SceneCollisionManager.instance.dispose();')
$nullGuardIndex = $removeBody.IndexOf('if (gameworld == null)')
$dispatcherIndex = $removeBody.IndexOf('gameworld.dispatcher.destroy();')
$removeIndex = $removeBody.IndexOf('gameworld.removeMovieClip();')
Test-Check ($stopIndex -ge 0 -and $disposeIndex -gt $stopIndex -and
    $nullGuardIndex -gt $disposeIndex) `
    'SceneManager stops updates and disposes collision state even on idempotent null-world unload'
Test-Check ($dispatcherIndex -gt $disposeIndex -and $removeIndex -gt $dispatcherIndex) `
    'collision cleanup precedes dispatcher destruction and gameworld removal'

Test-Check ($suite -match
    'class\s+org\.flashNight\.arki\.scene\.SceneCollisionManagerTest' -and
    $suite -match 'public\s+static\s+function\s+runAllTests\s*\(') `
    'AS2 regression suite exposes the focused entrypoint'
Test-Check ([regex]::Matches($suite, '(?m)^\s*check\s*\(').Count -eq 21) `
    'AS2 suite fixes the expected assertion count at 21'
Test-Check ($suite -match 'SceneCollisionManagerTest Tests Passed:' -and
    $suite -match 'SceneCollisionManagerTest Tests Failed:' -and
    $suite -match 'SceneCollisionManagerTest Cases Passed: 4/4') `
    'AS2 suite emits machine-verifiable pass/fail/case sentinels'
Test-Check ($suite -match '_hadGameworld\s*=\s*_root\.hasOwnProperty\("gameworld"\)' -and
    $suite -match '_hadCollisionLayer\s*=\s*_root\.hasOwnProperty\("collisionLayer"\)' -and
    $suite -match 'else\s+delete\s+_root\.gameworld\s*;' -and
    $suite -match 'else\s+delete\s+_root\.collisionLayer\s*;') `
    'AS2 suite restores or deletes replaced root properties to their exact prior shape'
Test-Check ($suite -match '(?s)finally\s*\{\s*try\s*\{\s*cleanupScene\(\);\s*\}\s*finally\s*\{\s*//[^\r\n]*\r?\n\s*restoreRootState\(\);') `
    'AS2 suite restores root state even if local cleanup throws'
Test-Check ($suite -match '_root\.collisionLayer\s*=\s*_replacementLayer\s*;' -and
    $suite -match '_replacementLayer\.hitTest\(520,\s*60,\s*true\)') `
    'AS2 suite proves dispose leaves a replacement root layer intact'
Test-Check ([regex]::Matches($template,
    [regex]::Escape('__SCENE_COLLISION_RUN_ID__')).Count -eq 2 -and
    $template -match 'import\s+org\.flashNight\.arki\.scene\.\*\s*;' -and
    $template -match 'SceneCollisionManagerTest\.runAllTests\s*\(\s*\)') `
    'focused frame runner uses wildcard import, exact runId framing, and the real suite'

Write-Host ("Scene collision static tests passed: {0}" -f $passed)
Write-Host ("Scene collision static tests failed: {0}" -f $failed)
if ($failed -ne 0) {
    throw "Scene collision static regression failed: $failed checks"
}
