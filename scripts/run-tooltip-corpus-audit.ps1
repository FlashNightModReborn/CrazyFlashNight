[CmdletBinding()]
param(
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 300,
    [string]$OutputRelativePath = 'tmp/tooltip-audit/tooltip-corpus.trace',
    [switch]$SkipCompile
)

$ErrorActionPreference = 'Stop'
$scriptsDir = $PSScriptRoot
$projectDir = Split-Path -Parent $scriptsDir
$runnerPath = Join-Path $scriptsDir 'TestLoader.as'
$templatePath = Join-Path $scriptsDir 'test-runners/tooltip-corpus/TestLoader.as.template'
$suitePath = Join-Path $scriptsDir '类定义/org/flashNight/gesh/tooltip/test/TooltipCorpusDump.as'
$compilePath = Join-Path $scriptsDir 'compile_test.ps1'
$outputPath = Join-Path $scriptsDir 'compile_output.txt'
$errorsPath = Join-Path $scriptsDir 'compiler_errors.txt'
$uncertainMarker = Join-Path $scriptsDir 'compile_state_uncertain.marker'
$scratchMarker = Join-Path $scriptsDir 'testloader_scratch_inflight.marker'
$liveTracePath = Join-Path $env:APPDATA 'Macromedia/Flash Player/Logs/flashlog.txt'
. (Join-Path $scriptsDir 'test-runners/testloader-scratch-transaction.ps1')

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

function Read-SharedUtf8Text([string]$Path) {
    $stream = [System.IO.FileStream]::new(
        $Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::ReadWrite)
    try {
        $reader = [System.IO.StreamReader]::new(
            $stream, [System.Text.Encoding]::UTF8, $true, 4096, $true)
        try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
    } finally {
        $stream.Dispose()
    }
}

function Write-TooltipCorpusUncertain([string]$Reason) {
    $prior = if (Test-Path -LiteralPath $uncertainMarker) {
        [System.IO.File]::ReadAllText($uncertainMarker, [System.Text.Encoding]::UTF8)
    } else { '' }
    $body = '{0:o} | tooltip corpus: {1}' -f [System.DateTime]::UtcNow, $Reason
    if (-not [string]::IsNullOrWhiteSpace($prior)) {
        $body += "`nprevious_marker:`n" + $prior
    }
    [System.IO.File]::WriteAllText(
        $uncertainMarker, $body, [System.Text.UTF8Encoding]::new($false))
}

foreach ($path in @($templatePath, $suitePath)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Required AS2 source is missing: $path" }
    if (-not (Test-Utf8Bom $path)) { throw "Required AS2 source lacks UTF-8 BOM: $path" }
}
$templateSource = Get-Content -LiteralPath $templatePath -Raw -Encoding UTF8
if ([regex]::Matches($templateSource, '__FOCUSED_RUN_ID__').Count -ne 2 -or
    [regex]::Matches($templateSource,
        '(?m)^\s*org\.flashNight\.gesh\.tooltip\.test\.TooltipCorpusDump\.runAllTests\s*\(\s*"__FOCUSED_RUN_ID__"\s*\)\s*;\s*$').Count -ne 1) {
    throw 'Tooltip corpus template must contain one start marker and one runAllTests(runId) call.'
}
$suiteSource = Get-Content -LiteralPath $suitePath -Raw -Encoding UTF8
if ($suiteSource -notmatch 'class\s+org\.flashNight\.gesh\.tooltip\.test\.TooltipCorpusDump\s*\{' -or
    $suiteSource -notmatch 'public\s+static\s+function\s+runAllTests\s*\(\s*runId:String\s*\)') {
    throw 'TooltipCorpusDump class or runAllTests(runId) entry is missing.'
}

$relativeOutput = [System.IO.Path]::GetFullPath((Join-Path $projectDir $OutputRelativePath))
$normalizedProject = [System.IO.Path]::GetFullPath($projectDir).TrimEnd('\') + '\'
if (-not $relativeOutput.StartsWith($normalizedProject, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'OutputRelativePath must stay inside the repository.'
}

$normalizedRoot = [System.IO.Path]::GetFullPath($projectDir).TrimEnd('\').ToUpperInvariant()
$repoHasher = [System.Security.Cryptography.SHA256]::Create()
try {
    $repoHash = ([System.BitConverter]::ToString(
        $repoHasher.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($normalizedRoot)))).
        Replace('-', '').Substring(0, 24)
} finally {
    $repoHasher.Dispose()
}
$compileMutex = [System.Threading.Mutex]::new($false, 'Local\CF7_FlashCompile_' + $repoHash)
$compileMutexAcquired = $false
$compileLease = $null
$runId = [System.Guid]::NewGuid().ToString('N')
$installedHash = $null
$scratchTransaction = $null
$childCompileSucceeded = $false
$behaviorTerminalObserved = $false

try {
    try {
        $compileMutexAcquired = $compileMutex.WaitOne(0)
    } catch [System.Threading.AbandonedMutexException] {
        $compileMutexAcquired = $true
        Write-TooltipCorpusUncertain 'abandoned compile mutex observed'
        throw 'A previous compile abandoned the repository mutex; inspect compile state before retrying.'
    }
    if (-not $compileMutexAcquired) {
        throw 'Another Flash compile is using this repository; refusing to install a temporary TestLoader.'
    }
    if (Test-Path -LiteralPath $uncertainMarker) {
        throw 'Compile state is uncertain. Inspect and resolve scripts/compile_state_uncertain.marker first.'
    }

    $compileLease = 'v1:{0}:{1}:{2}' -f $repoHash, $PID, [System.Guid]::NewGuid().ToString('N')
    $scratchTransaction = New-Cf7TestLoaderScratchTransaction `
        -MarkerPath $scratchMarker -RunnerPath $runnerPath -RepoHash $repoHash `
        -CompileLease $compileLease -OwnerKind 'focused:tooltip-corpus'
    Assert-Cf7TestLoaderScratchReadyToInstall -Transaction $scratchTransaction

    Copy-Item -LiteralPath $templatePath -Destination $runnerPath -Force
    $runnerText = [System.IO.File]::ReadAllText($runnerPath, [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText(
        $runnerPath, $runnerText.Replace('__FOCUSED_RUN_ID__', $runId),
        [System.Text.UTF8Encoding]::new($true))
    $installedHash = (Get-FileHash -LiteralPath $runnerPath -Algorithm SHA256).Hash

    if ($SkipCompile) {
        Write-Host '[OK] tooltip-corpus tracked runner static validation passed; compile skipped.'
    } else {
        $beforeOutput = Get-EvidenceIdentity $outputPath
        $beforeErrors = Get-EvidenceIdentity $errorsPath
        $started = [System.DateTime]::UtcNow
        $previousCompileLease = $env:CF7_FLASH_COMPILE_LEASE
        try {
            $env:CF7_FLASH_COMPILE_LEASE = $compileLease
            & powershell -NoProfile -ExecutionPolicy Bypass -File $compilePath `
                -Target test -TimeoutSeconds $TimeoutSeconds
        } finally {
            if ($null -eq $previousCompileLease) {
                Remove-Item Env:CF7_FLASH_COMPILE_LEASE -ErrorAction SilentlyContinue
            } else {
                $env:CF7_FLASH_COMPILE_LEASE = $previousCompileLease
            }
        }
        if ($LASTEXITCODE -ne 0) { throw "Tooltip corpus TestLoader exited $LASTEXITCODE." }
        $childCompileSucceeded = $true

        foreach ($evidence in @(
            @{Path=$outputPath;Before=$beforeOutput},
            @{Path=$errorsPath;Before=$beforeErrors}
        )) {
            if (-not (Test-Path -LiteralPath $evidence.Path)) {
                throw "Compile evidence is missing: $($evidence.Path)"
            }
            $item = Get-Item -LiteralPath $evidence.Path
            if ((Get-EvidenceIdentity $evidence.Path) -eq $evidence.Before -or
                $item.LastWriteTimeUtc -lt $started.AddSeconds(-1)) {
                throw "Compile evidence was not freshly replaced: $($evidence.Path)"
            }
        }

        $errors = Get-Content -LiteralPath $errorsPath -Raw -Encoding UTF8
        if ($errors -notmatch '^\s*0\s+[^,\r\n]+,\s*0\s+[^,\r\n]+\s*$') {
            throw 'Tooltip corpus compiler diagnostics are not 0 errors / 0 warnings.'
        }
        $compileOutput = Get-Content -LiteralPath $outputPath -Raw -Encoding UTF8
        if ([regex]::Matches($compileOutput, 'ASO 32K branch detected').Count -ne 0) {
            throw 'Tooltip corpus compile required the 32K retry.'
        }

        $escapedRunId = [regex]::Escape($runId)
        $deadline = [System.DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        $trace = ''
        while ([System.DateTime]::UtcNow -lt $deadline) {
            if (Test-Path -LiteralPath $liveTracePath) {
                $trace = Read-SharedUtf8Text $liveTracePath
                if ($trace -match "(?m)^TOOLTIP_CORPUS_FAILED\|$escapedRunId\|") {
                    throw 'Tooltip corpus AS2 loader/composer reported failure.'
                }
                if ($trace -match "(?m)^TOOLTIP_CORPUS_END\|$escapedRunId\r?$") { break }
            }
            Start-Sleep -Milliseconds 200
        }

        $startPattern = "(?m)^FocusedTestRunId tooltip-corpus Start: $escapedRunId\r?$"
        $beginPattern = "(?m)^TOOLTIP_CORPUS_BEGIN\|$escapedRunId\r?$"
        $donePattern = "(?m)^TOOLTIP_CORPUS_DONE\|$escapedRunId\|records=(?<records>\d+)\|composeFailures=(?<failures>\d+)\r?$"
        $endPattern = "(?m)^TOOLTIP_CORPUS_END\|$escapedRunId\r?$"
        $blockPattern = "(?ms)^FocusedTestRunId tooltip-corpus Start: $escapedRunId\r?`n(?<body>.*?)^TOOLTIP_CORPUS_END\|$escapedRunId\r?$"
        $done = [regex]::Matches($trace, $donePattern)
        $blocks = [regex]::Matches($trace, $blockPattern)
        if ([regex]::Matches($trace, $startPattern).Count -ne 1 -or
            [regex]::Matches($trace, $beginPattern).Count -ne 1 -or
            $done.Count -ne 1 -or [regex]::Matches($trace, $endPattern).Count -ne 1 -or
            $blocks.Count -ne 1) {
            throw 'Tooltip corpus did not reach one exact asynchronous trace closure before timeout.'
        }
        $behaviorTerminalObserved = $true
        if ([int]$done[0].Groups['failures'].Value -ne 0) {
            throw 'Tooltip corpus contains composition failures.'
        }
        $body = $blocks[0].Groups['body'].Value
        if ($body -match '(?m)^TC_COMPOSE_ERROR\|' -or
            $body -match '(?m)^TOOLTIP_CORPUS_FAILED\|') {
            throw 'Tooltip corpus trace contains a failure sentinel.'
        }
        $total = [regex]::Match($body,
            '(?m)^TC_TOTAL\|records=(?<records>\d+)\|base=(?<base>\d+)\|equipment=(?<equipment>\d+)\|tiers=(?<tiers>\d+)\|mods1=(?<mods1>\d+)\|mods3=(?<mods3>\d+)\|modCoverage=(?<modCoverage>\d+)\|modDefinitions=(?<modDefinitions>\d+)\|modsCovered=(?<modsCovered>\d+)\|composeFailures=(?<failures>\d+)\r?$')
        $modCoverage = [regex]::Match($body,
            '(?m)^TC_MOD_COVERAGE\|definitions=(?<definitions>\d+)\|covered=(?<covered>\d+)\|records=(?<records>\d+)\|uncovered=(?<uncovered>\d+)\|names=(?<names>[^\r\n]*)\r?$')
        if (-not $total.Success -or [int]$total.Groups['records'].Value -le 0 -or
            [int]$total.Groups['base'].Value -le 0 -or
            [int]$total.Groups['equipment'].Value -le 0 -or
            [int]$total.Groups['tiers'].Value -le 0 -or
            [int]$total.Groups['mods1'].Value -le 0 -or
            [int]$total.Groups['mods3'].Value -le 0 -or
            [int]$total.Groups['modCoverage'].Value -le 0 -or
            [int]$total.Groups['modDefinitions'].Value -le 0 -or
            [int]$total.Groups['modsCovered'].Value -ne [int]$total.Groups['modDefinitions'].Value -or
            -not $modCoverage.Success -or
            [int]$modCoverage.Groups['definitions'].Value -ne [int]$total.Groups['modDefinitions'].Value -or
            [int]$modCoverage.Groups['covered'].Value -ne [int]$total.Groups['modsCovered'].Value -or
            [int]$modCoverage.Groups['records'].Value -ne [int]$total.Groups['modCoverage'].Value -or
            [int]$modCoverage.Groups['uncovered'].Value -ne 0 -or
            -not [string]::IsNullOrEmpty($modCoverage.Groups['names'].Value) -or
            [int]$total.Groups['failures'].Value -ne 0) {
            throw 'Tooltip corpus coverage summary is missing or incomplete.'
        }

        $parent = Split-Path -Parent $relativeOutput
        if (-not (Test-Path -LiteralPath $parent)) {
            [void](New-Item -ItemType Directory -Path $parent)
        }
        [System.IO.File]::WriteAllText(
            $relativeOutput, $blocks[0].Value, [System.Text.UTF8Encoding]::new($false))
        Write-Host ('[OK] tooltip-corpus: records={0}, base={1}, equipment={2}, tiers={3}, mods1={4}, mods3={5}, modCoverage={6}/{7}; 32K retry=0, compiler 0/0.' -f
            $total.Groups['records'].Value, $total.Groups['base'].Value,
            $total.Groups['equipment'].Value, $total.Groups['tiers'].Value,
            $total.Groups['mods1'].Value, $total.Groups['mods3'].Value,
            $total.Groups['modsCovered'].Value, $total.Groups['modDefinitions'].Value)
        Write-Host ("[OK] corpus trace: $relativeOutput")
    }
} finally {
    try {
        if ($childCompileSucceeded -and -not $behaviorTerminalObserved) {
            Write-TooltipCorpusUncertain (
                "child compile succeeded but exact async closure was not observed; runId=$runId")
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
            if ($scratchTransaction -and (Test-Path -LiteralPath $scratchTransaction.MarkerPath)) {
                Write-Warning ("TestLoader scratch transaction remains blocked; recovery backup: {0}" -f
                    $scratchTransaction.BackupPath)
            }
        }
    }
}
