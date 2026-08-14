[CmdletBinding()]
param(
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 240,
    [ValidateRange(1, 300)]
    [int]$BehaviorTimeoutSeconds = 45,
    [switch]$SkipCompile
)

$ErrorActionPreference = 'Stop'
$scriptsDir = $PSScriptRoot
$projectDir = Split-Path -Parent $scriptsDir
$runnerPath = Join-Path $scriptsDir 'TestLoader.as'
$templatePath = Join-Path $projectDir `
    'scripts\test-runners\material-catalog-loader\TestLoader.as.template'
$testSourcePath = Join-Path $projectDir `
    'scripts\类定义\org\flashNight\gesh\xml\LoadXml\MaterialCatalogLoaderTest.as'
$catalogLoaderPath = Join-Path $projectDir `
    'scripts\类定义\org\flashNight\gesh\xml\LoadXml\MaterialCatalogLoader.as'
$legacyLoaderPath = Join-Path $projectDir `
    'scripts\类定义\org\flashNight\gesh\xml\LoadXml\MaterialDictionaryLoader.as'
$catalogXmlPath = Join-Path $projectDir `
    'data\dictionaries\material_catalog.xml'
$legacyXmlPath = Join-Path $projectDir `
    'data\dictionaries\material_dictionary.xml'
$compilePath = Join-Path $scriptsDir 'compile_test.ps1'
$tracePath = Join-Path $scriptsDir 'flashlog.txt'
$outputPath = Join-Path $scriptsDir 'compile_output.txt'
$errorsPath = Join-Path $scriptsDir 'compiler_errors.txt'
$uncertainMarker = Join-Path $scriptsDir 'compile_state_uncertain.marker'
$scratchMarker = Join-Path $scriptsDir 'testloader_scratch_inflight.marker'
. (Join-Path $scriptsDir 'test-runners\testloader-scratch-transaction.ps1')

function Test-Utf8Bom([string]$Path) {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    return $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and
        $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
}

function Get-EvidenceIdentity([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $item = Get-Item -LiteralPath $Path
    $digest = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    return '{0}|{1}|{2}' -f $item.LastWriteTimeUtc.Ticks, $item.Length, $digest
}

function Get-XmlChildText($Node, [string]$ChildName) {
    $child = $Node.SelectSingleNode($ChildName)
    if ($null -eq $child) { return $null }
    return [string]$child.InnerText
}

function Write-MaterialCatalogBehaviorUncertain {
    param([Parameter(Mandatory = $true)][string]$Reason)

    $prior = if (Test-Path -LiteralPath $uncertainMarker) {
        [System.IO.File]::ReadAllText(
            $uncertainMarker, [System.Text.Encoding]::UTF8)
    } else {
        ''
    }
    $body = '{0:o} | material catalog loader TestLoader: {1}' -f
        [System.DateTime]::UtcNow, $Reason
    if (-not [string]::IsNullOrWhiteSpace($prior)) {
        $body += "`nprevious_marker:`n" + $prior
    }
    [System.IO.File]::WriteAllText(
        $uncertainMarker, $body, [System.Text.UTF8Encoding]::new($false))
}

# Static source closure. This gate owns its asynchronous terminal wait because
# testMovie() can return before XML.onLoad fires.
$requiredBomPaths = @(
    $templatePath,
    $testSourcePath,
    $catalogLoaderPath,
    $legacyLoaderPath
)
foreach ($path in $requiredBomPaths) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required AS2 source is missing: $path"
    }
    if (-not (Test-Utf8Bom $path)) {
        throw "Required AS2 source lacks UTF-8 BOM: $path"
    }
}
foreach ($path in @($catalogXmlPath, $legacyXmlPath, $compilePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required loader-gate input is missing: $path"
    }
}

$placeholder = '__MATERIAL_CATALOG_RUN_ID__'
$templateSource = Get-Content -LiteralPath $templatePath -Raw -Encoding UTF8
if ([regex]::Matches(
        $templateSource, [regex]::Escape($placeholder)).Count -ne 2) {
    throw 'Async TestLoader template must contain exactly two runId placeholders.'
}
if ([regex]::Matches($templateSource,
        '(?m)^trace\("FocusedTestRunId material-catalog-loader Start: ' +
        [regex]::Escape($placeholder) + '"\);\r?$').Count -ne 1) {
    throw 'Async TestLoader template must emit exactly one Start marker.'
}
if ([regex]::Matches($templateSource,
        'MaterialCatalogLoaderTest\.runActualFiles\s*\(').Count -ne 1) {
    throw 'Async TestLoader template must call runActualFiles() exactly once.'
}
$compactTemplate = [regex]::Replace($templateSource, '\s+', '')
$expectedCompactTemplate =
    'trace("FocusedTestRunIdmaterial-catalog-loaderStart:' + $placeholder + '");' +
    'org.flashNight.gesh.xml.LoadXml.MaterialCatalogLoaderTest.runActualFiles("' +
    $placeholder + '");'
if ($compactTemplate -cne $expectedCompactTemplate) {
    throw 'Async TestLoader template must contain only Start + runActualFiles; terminal markers belong to the callback test class.'
}

$testSource = Get-Content -LiteralPath $testSourcePath -Raw -Encoding UTF8
if ([regex]::Matches($testSource,
        'class\s+org\.flashNight\.gesh\.xml\.LoadXml\.MaterialCatalogLoaderTest\s*\{').Count -ne 1 -or
    $testSource -match
        'class\s+org\.flashNight\.gesh\.xml\.LoadXml\.MaterialCatalogLoader\s') {
    throw 'Test source must define only MaterialCatalogLoaderTest, never a second production loader class.'
}
if ([regex]::Matches($testSource,
        '(?m)^import org\.flashNight\.gesh\.xml\.LoadXml\.MaterialCatalogLoader;\r?$').Count -ne 1 -or
    [regex]::Matches($testSource,
        '(?m)^import org\.flashNight\.gesh\.xml\.LoadXml\.MaterialDictionaryLoader;\r?$').Count -ne 1) {
    throw 'Test class must explicitly import both production loaders; AS2 does not resolve these sibling classes implicitly.'
}
if ([regex]::Matches($testSource,
        'MaterialCatalogLoader\.getInstance\(\)\.reload\s*\(').Count -ne 1 -or
    [regex]::Matches($testSource,
        'MaterialDictionaryLoader\.getInstance\(\)\.reload\s*\(').Count -ne 1) {
    throw 'Test source must actual-reload catalog and legacy loaders exactly once each.'
}
if ([regex]::Matches($testSource,
        'FocusedTestRunId material-catalog-loader Complete:').Count -ne 1 -or
    [regex]::Matches($testSource,
        'FocusedTestRunId material-catalog-loader Failed:').Count -ne 1 -or
    [regex]::Matches($testSource, '\[TEST_FAIL\]').Count -lt 1) {
    throw 'Test source must own one success terminal and one explicit failure terminal.'
}
foreach ($sentinel in @(
        'EXPECTED_CATALOG_COUNT:Number = 224',
        'EXPECTED_LEGACY_COUNT:Number = 58',
        'EXPECTED_NON_LEGACY_COUNT:Number = 166',
        'EXPECTED_DIRECT_PURPOSE_COUNT:Number = 2',
        'EXPECTED_AUTHORED_PURPOSE_REFS:Number = 27',
        'EXPECTED_TUNING_PURPOSE_REFS:Number = 6',
        'EXPECTED_INFRASTRUCTURE_PURPOSE_REFS:Number = 21',
        'purpose.order === 0',
        'purpose.order === 1',
        'nonLegacy=166',
        'authoredPurposeRefs=6/21',
        'legacyPrefix=58/58')) {
    if ($testSource.IndexOf($sentinel, [StringComparison]::Ordinal) -lt 0) {
        throw "Material loader test is missing exact source sentinel: $sentinel"
    }
}

$catalogLoaderSource = Get-Content -LiteralPath $catalogLoaderPath -Raw -Encoding UTF8
$legacyLoaderSource = Get-Content -LiteralPath $legacyLoaderPath -Raw -Encoding UTF8
if ($catalogLoaderSource -notmatch
        'super\("data/dictionaries/material_catalog\.xml"\)' -or
    $legacyLoaderSource -notmatch
        'super\("data/dictionaries/material_dictionary\.xml"\)') {
    throw 'Production loader path binding has drifted from the actual XML files.'
}

# XML preflight keeps hard-coded AS2 assertions bound to current tracked data.
[xml]$catalogXml = [System.IO.File]::ReadAllText(
    $catalogXmlPath, [System.Text.Encoding]::UTF8)
[xml]$legacyXml = [System.IO.File]::ReadAllText(
    $legacyXmlPath, [System.Text.Encoding]::UTF8)
$catalogMaterials = @($catalogXml.DocumentElement.SelectNodes('Material'))
$legacyMaterials = @($legacyXml.DocumentElement.SelectNodes('Material'))
$directPurposes = @($catalogXml.DocumentElement.SelectNodes('DirectPurpose'))
if ((Get-XmlChildText $catalogXml.DocumentElement 'schemaVersion') -cne '1' -or
    $catalogMaterials.Count -ne 224 -or
    $legacyMaterials.Count -ne 58 -or
    ($catalogMaterials.Count - $legacyMaterials.Count) -ne 166 -or
    $directPurposes.Count -ne 2) {
    throw 'Tracked XML preflight expected schema/catalog/legacy/nonLegacy/purpose = 1/224/58/166/2.'
}
$purpose = $directPurposes[0]
if ((Get-XmlChildText $purpose 'id') -cne 'system:equipment_tuning' -or
    (Get-XmlChildText $purpose 'label') -cne '装备改装' -or
    (Get-XmlChildText $purpose 'order') -cne '0' -or
    (Get-XmlChildText $purpose 'consumerEvidence') -cne 'EquipmentTuningService') {
    throw 'Tracked DirectPurpose registry is not the exact current row/order.'
}
$purpose = $directPurposes[1]
if ((Get-XmlChildText $purpose 'id') -cne 'system:infrastructure_upgrade' -or
    (Get-XmlChildText $purpose 'label') -cne '基建升级' -or
    (Get-XmlChildText $purpose 'order') -cne '1' -or
    (Get-XmlChildText $purpose 'consumerEvidence') -cne 'InfrastructureUpgradeUI') {
    throw 'Tracked DirectPurpose registry is not the exact current row/order.'
}
$authoredPurposeIds = @($catalogMaterials | ForEach-Object {
        @($_.SelectNodes('authoredDirectPurposeId')) | ForEach-Object {
            [string]$_.InnerText
        }
    })
$tuningPurposeRefs = @($authoredPurposeIds | Where-Object {
        $_ -ceq 'system:equipment_tuning'
    }).Count
$infrastructurePurposeRefs = @($authoredPurposeIds | Where-Object {
        $_ -ceq 'system:infrastructure_upgrade'
    }).Count
if ($authoredPurposeIds.Count -ne 27 -or
    $tuningPurposeRefs -ne 6 -or
    $infrastructurePurposeRefs -ne 21) {
    throw 'Tracked authored direct-purpose refs expected total/tuning/infrastructure = 27/6/21.'
}
for ($i = 0; $i -lt $legacyMaterials.Count; $i++) {
    $catalogName = Get-XmlChildText $catalogMaterials[$i] 'Name'
    $legacyName = Get-XmlChildText $legacyMaterials[$i] 'Name'
    if ($catalogName -cne $legacyName) {
        throw "Tracked legacy prefix physical order mismatch at index $i."
    }
    if ((Get-XmlChildText $catalogMaterials[$i] 'legacyVisible') -cne 'true') {
        throw "Tracked catalog legacy prefix visibility mismatch at index $i."
    }
}
for ($i = $legacyMaterials.Count; $i -lt $catalogMaterials.Count; $i++) {
    if ((Get-XmlChildText $catalogMaterials[$i] 'legacyVisible') -cne 'false') {
        throw "Tracked catalog non-legacy omission mismatch at index $i."
    }
}
$names = @($catalogMaterials | ForEach-Object { Get-XmlChildText $_ 'Name' })
if (@($names | Group-Object -CaseSensitive | Where-Object Count -gt 1).Count -ne 0) {
    throw 'Tracked material catalog contains duplicate exact Names.'
}
$anchorContract = @(
    @(0, '军用帆布', 'equipment_mod', 'true'),
    @(57, '毒素样本', 'equipment_mod', 'true'),
    @(58, '神铁碎片', 'general', 'false'),
    @(178, '等离子射线弹-强化', 'equipment_mod', 'false'),
    @(179, '食用油', 'food', 'false'),
    @(223, '蚝油', 'food', 'false')
)
foreach ($anchor in $anchorContract) {
    $row = $catalogMaterials[[int]$anchor[0]]
    if ((Get-XmlChildText $row 'Name') -cne [string]$anchor[1] -or
        (Get-XmlChildText $row 'typeId') -cne [string]$anchor[2] -or
        (Get-XmlChildText $row 'legacyVisible') -cne [string]$anchor[3]) {
        throw "Tracked material archive anchor drifted at index $($anchor[0])."
    }
}
$typeCounts = @{}
foreach ($row in $catalogMaterials) {
    $typeId = Get-XmlChildText $row 'typeId'
    $typeCounts[$typeId] = 1 + [int]$typeCounts[$typeId]
}
if ($typeCounts.Count -ne 3 -or
    $typeCounts['equipment_mod'] -ne 105 -or
    $typeCounts['general'] -ne 74 -or
    $typeCounts['food'] -ne 45) {
    throw 'Tracked material type counts expected equipment_mod/general/food = 105/74/45.'
}

$normalizedRoot = [System.IO.Path]::GetFullPath($projectDir).
    TrimEnd('\').ToUpperInvariant()
$repoHasher = [System.Security.Cryptography.SHA256]::Create()
try {
    $repoHash = ([System.BitConverter]::ToString(
        $repoHasher.ComputeHash(
            [System.Text.Encoding]::UTF8.GetBytes($normalizedRoot)))).
        Replace('-', '').Substring(0, 24)
} finally {
    $repoHasher.Dispose()
}
$compileMutex = [System.Threading.Mutex]::new(
    $false, 'Local\CF7_FlashCompile_' + $repoHash)
$compileMutexAcquired = $false
$compileLease = $null
$runId = [System.Guid]::NewGuid().ToString('N')
$installedHash = $null
$scratchTransaction = $null
$behaviorStarted = $false
$behaviorTerminalObserved = $false

try {
    try {
        $compileMutexAcquired = $compileMutex.WaitOne(0)
    } catch [System.Threading.AbandonedMutexException] {
        $compileMutexAcquired = $true
        Write-MaterialCatalogBehaviorUncertain `
            -Reason 'runner observed abandoned compile mutex'
        throw 'A previous compile abandoned the repository mutex. Confirm Flash/JSFL stopped before retrying.'
    }
    if (-not $compileMutexAcquired) {
        throw 'Another Flash compile is using this repository; refusing to install a temporary TestLoader.'
    }
    if (Test-Path -LiteralPath $uncertainMarker) {
        throw 'Compile state is uncertain. Inspect late evidence before retrying.'
    }
    $compileLease = 'v1:{0}:{1}:{2}' -f $repoHash, $PID,
        [System.Guid]::NewGuid().ToString('N')

    $scratchTransaction = New-Cf7TestLoaderScratchTransaction `
        -MarkerPath $scratchMarker -RunnerPath $runnerPath `
        -RepoHash $repoHash -CompileLease $compileLease `
        -OwnerKind 'focused:material-catalog-loader'
    Assert-Cf7TestLoaderScratchReadyToInstall -Transaction $scratchTransaction

    Copy-Item -LiteralPath $templatePath -Destination $runnerPath -Force
    $runnerText = [System.IO.File]::ReadAllText(
        $runnerPath, [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText(
        $runnerPath,
        $runnerText.Replace($placeholder, $runId),
        [System.Text.UTF8Encoding]::new($true))
    $installedHash = (Get-FileHash -LiteralPath $runnerPath -Algorithm SHA256).Hash
    $installedText = Get-Content -LiteralPath $runnerPath -Raw -Encoding UTF8
    if (-not (Test-Utf8Bom $runnerPath) -or
        $installedText.IndexOf($placeholder, [StringComparison]::Ordinal) -ge 0 -or
        [regex]::Matches($installedText, [regex]::Escape($runId)).Count -ne 2) {
        throw 'Installed async TestLoader failed BOM/runId identity validation.'
    }

    if ($SkipCompile) {
        Write-Host '[OK] material-catalog-loader static/BOM/XML/scratch validation passed; compile skipped.'
    } else {
        if ([string]::IsNullOrWhiteSpace($env:APPDATA)) {
            throw 'APPDATA is unavailable; cannot follow the asynchronous global Flash log.'
        }
        $globalFlashLog = Join-Path $env:APPDATA `
            'Macromedia\Flash Player\Logs\flashlog.txt'
        $beforeIdentity = @{}
        foreach ($path in @($outputPath, $errorsPath)) {
            $beforeIdentity[$path] = Get-EvidenceIdentity $path
        }
        $compileStartedUtc = [System.DateTime]::UtcNow
        $previousCompileLease = $env:CF7_FLASH_COMPILE_LEASE
        try {
            $env:CF7_FLASH_COMPILE_LEASE = $compileLease
            & powershell -NoProfile -ExecutionPolicy Bypass -File $compilePath `
                -Target test -TimeoutSeconds $TimeoutSeconds
            $compileExit = $LASTEXITCODE
        } finally {
            if ($null -eq $previousCompileLease) {
                Remove-Item Env:CF7_FLASH_COMPILE_LEASE -ErrorAction SilentlyContinue
            } else {
                $env:CF7_FLASH_COMPILE_LEASE = $previousCompileLease
            }
        }

        $freshEvidence = $true
        foreach ($path in @($outputPath, $errorsPath)) {
            if (-not (Test-Path -LiteralPath $path) -or
                (Get-EvidenceIdentity $path) -eq $beforeIdentity[$path] -or
                (Get-Item -LiteralPath $path).LastWriteTimeUtc -lt
                    $compileStartedUtc.AddSeconds(-1)) {
                $freshEvidence = $false
            }
        }
        if (-not $freshEvidence) {
            throw 'Material catalog compile output/diagnostics were not freshly replaced.'
        }
        $errors = Get-Content -LiteralPath $errorsPath -Raw -Encoding UTF8
        $compilerClean = $errors -match
            '^\s*0\s+[^,\r\n]+,\s*0\s+[^,\r\n]+\s*$'
        if (-not $compilerClean) {
            throw 'Material catalog compiler diagnostics are not 0 errors / 0 warnings.'
        }
        $behaviorStarted = $true
        $compileOutput = Get-Content -LiteralPath $outputPath -Raw -Encoding UTF8
        if ([regex]::Matches(
                $compileOutput, 'ASO 32K branch detected').Count -ne 0) {
            throw 'Material catalog compile required the 32K retry; refusing duplicate behavior evidence.'
        }

        $escapedRunId = [regex]::Escape($runId)
        $startPattern = '(?m)^FocusedTestRunId material-catalog-loader Start: ' +
            $escapedRunId + '\r?$'
        $completePattern = '(?m)^FocusedTestRunId material-catalog-loader Complete: ' +
            $escapedRunId + '\r?$'
        $failedPattern = '(?m)^FocusedTestRunId material-catalog-loader Failed: ' +
            $escapedRunId + '\r?$'
        $successBlockPattern =
            '(?ms)^FocusedTestRunId material-catalog-loader Start: ' +
            $escapedRunId + '\r?\n(?<body>.*?)' +
            '^FocusedTestRunId material-catalog-loader Complete: ' +
            $escapedRunId + '\r?$'
        $failureBlockPattern =
            '(?ms)^FocusedTestRunId material-catalog-loader Start: ' +
            $escapedRunId + '\r?\n(?<body>.*?)' +
            '^FocusedTestRunId material-catalog-loader Failed: ' +
            $escapedRunId + '\r?$'
        $deadline = [System.DateTime]::UtcNow.AddSeconds($BehaviorTimeoutSeconds)
        $successBlock = $null
        $failureBlock = $null
        while ([System.DateTime]::UtcNow -lt $deadline) {
            if (Test-Path -LiteralPath $globalFlashLog) {
                try {
                    $globalTrace = [System.IO.File]::ReadAllText(
                        $globalFlashLog, [System.Text.Encoding]::UTF8)
                    $successBlocks = [regex]::Matches(
                        $globalTrace, $successBlockPattern)
                    $failureBlocks = [regex]::Matches(
                        $globalTrace, $failureBlockPattern)
                    if ($successBlocks.Count -gt 0 -or $failureBlocks.Count -gt 0) {
                        $startCount = [regex]::Matches(
                            $globalTrace, $startPattern).Count
                        $completeCount = [regex]::Matches(
                            $globalTrace, $completePattern).Count
                        $failedCount = [regex]::Matches(
                            $globalTrace, $failedPattern).Count
                        if ($startCount -ne 1 -or
                            ($completeCount + $failedCount) -ne 1 -or
                            ($successBlocks.Count + $failureBlocks.Count) -ne 1) {
                            throw "Async terminal marker set is invalid: starts=$startCount, completes=$completeCount, failed=$failedCount."
                        }
                        if ($successBlocks.Count -eq 1) {
                            $successBlock = $successBlocks[0]
                        } else {
                            $failureBlock = $failureBlocks[0]
                        }
                        $behaviorTerminalObserved = $true
                        break
                    }
                } catch [System.IO.IOException] {
                    # Flash Player may be appending while the runner reads; retry.
                }
            }
            Start-Sleep -Milliseconds 200
        }

        if (-not $behaviorTerminalObserved) {
            throw "Material catalog async behavior did not reach a terminal marker within $BehaviorTimeoutSeconds seconds."
        }
        $closedBlock = if ($null -ne $successBlock) {
            $successBlock.Value
        } else {
            $failureBlock.Value
        }
        [System.IO.File]::WriteAllText(
            $tracePath, $closedBlock.TrimEnd() + "`r`n",
            [System.Text.UTF8Encoding]::new($false))

        if ($null -ne $failureBlock) {
            $failureBody = $failureBlock.Groups['body'].Value.Trim()
            throw "MaterialCatalogLoaderTest emitted its explicit failure terminal: $failureBody"
        }
        $body = $successBlock.Groups['body'].Value
        $summaryPattern = '(?m)^MaterialCatalogLoaderTest PASS: catalog=224, legacy=58, nonLegacy=166, directPurposes=2, directPurposeOrder=0/1, authoredPurposeRefs=6/21, types=105/74/45, legacyPrefix=58/58\r?$'
        if ([regex]::Matches($body, $summaryPattern).Count -ne 1) {
            throw 'Async success block lacks the exact material catalog summary.'
        }
        if ($body -match '\[TEST_FAIL\]' -or
            $body -match '(^|[\r\n])\s*\[FAIL\]' -or
            $body -match 'Tests Failed:\s*[1-9]') {
            throw 'Async success block contains a failure sentinel.'
        }
        if ($compileExit -ne 0) {
            throw "Material catalog TestLoader compile exited $compileExit despite an observed behavior terminal."
        }
        Write-Host '[OK] material-catalog-loader: actual async XML reload 224/58/166, DirectPurpose order 0/1, authored refs 6/21, unique/order/type shape; compiler 0/0, 32K retry=0.'
    }
} finally {
    try {
        if ($behaviorStarted -and -not $behaviorTerminalObserved) {
            Write-MaterialCatalogBehaviorUncertain (
                "compile reached TestLoader but no exact async terminal was observed; " +
                "runId=$runId; the old test player may still append late evidence")
        }
    } finally {
        try {
            if ($scratchTransaction -and $installedHash) {
                Restore-Cf7TestLoaderScratchTransaction `
                    -Transaction $scratchTransaction -InstalledHash $installedHash
            }
        } finally {
            if ($compileMutexAcquired) { $compileMutex.ReleaseMutex() }
            $compileMutex.Dispose()
            if ($scratchTransaction -and
                (Test-Path -LiteralPath $scratchTransaction.MarkerPath)) {
                Write-Warning ("TestLoader scratch transaction remains blocked; recovery backup: {0}" -f
                    $scratchTransaction.BackupPath)
            }
        }
    }
}
