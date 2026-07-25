[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z0-9-]+$')]
    [string]$DomainId,
    [Parameter(Mandatory = $true)]
    [string]$TemplateRelativePath,
    [Parameter(Mandatory = $true)]
    [string[]]$SuiteRelativePaths,
    [Parameter(Mandatory = $true)]
    [string[]]$SuiteFqns,
    [string[]]$AdditionalAsRelativePaths = @(),
    [Parameter(Mandatory = $true)]
    [string[]]$ExpectedTracePatterns,
    [Parameter(Mandatory = $true)]
    [string]$SuccessSummary,
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 240,
    [switch]$SkipCompile
)

$ErrorActionPreference = 'Stop'
$scriptsDir = Split-Path -Parent $PSScriptRoot
$projectDir = Split-Path -Parent $scriptsDir
$runnerPath = Join-Path $scriptsDir 'TestLoader.as'
$templatePath = Join-Path $projectDir $TemplateRelativePath
$compilePath = Join-Path $scriptsDir 'compile_test.ps1'
$tracePath = Join-Path $scriptsDir 'flashlog.txt'
$outputPath = Join-Path $scriptsDir 'compile_output.txt'
$errorsPath = Join-Path $scriptsDir 'compiler_errors.txt'
$uncertainMarker = Join-Path $scriptsDir 'compile_state_uncertain.marker'
$scratchMarker = Join-Path $scriptsDir 'testloader_scratch_inflight.marker'
. (Join-Path $PSScriptRoot 'testloader-scratch-transaction.ps1')

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

function Write-FocusedBehaviorUncertain {
    param([Parameter(Mandatory = $true)][string]$Reason)

    $prior = if (Test-Path -LiteralPath $uncertainMarker) {
        [System.IO.File]::ReadAllText(
            $uncertainMarker, [System.Text.Encoding]::UTF8)
    } else {
        ''
    }
    $body = '{0:o} | focused TestLoader: {1}' -f
        [System.DateTime]::UtcNow, $Reason
    if (-not [string]::IsNullOrWhiteSpace($prior)) {
        $body += "`nprevious_marker:`n" + $prior
    }
    [System.IO.File]::WriteAllText(
        $uncertainMarker, $body, [System.Text.UTF8Encoding]::new($false))
}

if ($SuiteRelativePaths.Count -ne $SuiteFqns.Count) {
    throw 'SuiteRelativePaths and SuiteFqns must have the same number of entries.'
}

$suitePaths = @($SuiteRelativePaths | ForEach-Object { Join-Path $projectDir $_ })
$additionalPaths = @($AdditionalAsRelativePaths | ForEach-Object { Join-Path $projectDir $_ })
$requiredPaths = @($templatePath) + $suitePaths + $additionalPaths
foreach ($path in $requiredPaths) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required AS2 source is missing: $path"
    }
    if (-not (Test-Utf8Bom $path)) {
        throw "Required AS2 source lacks UTF-8 BOM: $path"
    }
}

$templateSource = Get-Content -LiteralPath $templatePath -Raw -Encoding UTF8
if ([regex]::Matches($templateSource, '__FOCUSED_RUN_ID__').Count -ne 2) {
    throw 'Focused TestLoader template must contain exactly two runId placeholders.'
}
for ($suiteIndex = 0; $suiteIndex -lt $SuiteFqns.Count; $suiteIndex++) {
    $fqn = $SuiteFqns[$suiteIndex]
    $callPattern = '(?m)^\s*' + [regex]::Escape($fqn) +
        '\.runAllTests\s*\(\s*\)\s*;\s*$'
    if ([regex]::Matches($templateSource, $callPattern).Count -ne 1) {
        throw "Template must call exactly once: $fqn.runAllTests();"
    }

    $suiteSource = Get-Content -LiteralPath $suitePaths[$suiteIndex] -Raw -Encoding UTF8
    if ($suiteSource -notmatch ('class\s+' + [regex]::Escape($fqn) + '\s*\{')) {
        throw "Suite source does not define expected class: $fqn"
    }
    if ($suiteSource -notmatch 'public\s+static\s+function\s+runAllTests\s*\(') {
        throw "Suite source lacks public static runAllTests(): $fqn"
    }
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
$compileMutex = [System.Threading.Mutex]::new(
    $false, 'Local\CF7_FlashCompile_' + $repoHash)
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
        Write-FocusedBehaviorUncertain `
            -Reason 'focused runner observed abandoned compile mutex'
        throw 'A previous compile abandoned the repository mutex. Confirm Flash/JSFL stopped and clear late markers before retrying.'
    }
    if (-not $compileMutexAcquired) {
        throw 'Another Flash compile is using this repository; refusing to install a temporary TestLoader.'
    }
    if (Test-Path -LiteralPath $uncertainMarker) {
        throw 'Compile state is uncertain. Confirm Flash/JSFL stopped, inspect late evidence, then remove scripts/compile_state_uncertain.marker.'
    }
    $compileLease = 'v1:{0}:{1}:{2}' -f $repoHash, $PID,
        [System.Guid]::NewGuid().ToString('N')

    # The single repository compile mutex and persistent marker remain held
    # through evidence consumption and byte-exact scratch recovery.
    $scratchTransaction = New-Cf7TestLoaderScratchTransaction `
        -MarkerPath $scratchMarker -RunnerPath $runnerPath -RepoHash $repoHash `
        -CompileLease $compileLease -OwnerKind ('focused:' + $DomainId)
    Assert-Cf7TestLoaderScratchReadyToInstall -Transaction $scratchTransaction

    Copy-Item -LiteralPath $templatePath -Destination $runnerPath -Force
    $runnerText = [System.IO.File]::ReadAllText(
        $runnerPath, [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText(
        $runnerPath,
        $runnerText.Replace('__FOCUSED_RUN_ID__', $runId),
        [System.Text.UTF8Encoding]::new($true))
    $installedHash = (Get-FileHash -LiteralPath $runnerPath -Algorithm SHA256).Hash

    if ($SkipCompile) {
        Write-Host ("[OK] {0} tracked runner static validation passed; compile skipped." -f
            $DomainId)
    } else {
        $evidencePaths = @($tracePath, $outputPath, $errorsPath)
        $beforeIdentity = @{}
        foreach ($path in $evidencePaths) {
            $beforeIdentity[$path] = Get-EvidenceIdentity $path
        }
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
        if ($LASTEXITCODE -ne 0) {
            throw "$DomainId TestLoader exited $LASTEXITCODE."
        }
        $childCompileSucceeded = $true

        foreach ($path in $evidencePaths) {
            if (-not (Test-Path -LiteralPath $path)) {
                throw "TestLoader evidence is missing: $path"
            }
            $item = Get-Item -LiteralPath $path
            $afterIdentity = Get-EvidenceIdentity $path
            if ($afterIdentity -eq $beforeIdentity[$path] -or
                $item.LastWriteTimeUtc -lt $started.AddSeconds(-1)) {
                throw "TestLoader evidence was not freshly replaced: $path"
            }
        }

        $trace = Get-Content -LiteralPath $tracePath -Raw -Encoding UTF8
        $escapedDomain = [regex]::Escape($DomainId)
        $escapedRunId = [regex]::Escape($runId)
        $startPattern = "(?m)^FocusedTestRunId $escapedDomain Start: $escapedRunId\r?$"
        $completePattern = "(?m)^FocusedTestRunId $escapedDomain Complete: $escapedRunId\r?$"
        $blockPattern = "(?ms)^FocusedTestRunId $escapedDomain Start: $escapedRunId\r?`n" +
            "(?<body>.*?)^FocusedTestRunId $escapedDomain Complete: $escapedRunId\r?$"
        $startCount = [regex]::Matches($trace, $startPattern).Count
        $completeCount = [regex]::Matches($trace, $completePattern).Count
        $blocks = [regex]::Matches($trace, $blockPattern)
        # A healthy focused run never accepts the compile_action 32K retry path.
        if ($startCount -ne 1 -or $completeCount -ne 1 -or $blocks.Count -ne 1) {
            throw ("Focused trace marker set is invalid: starts={0}, completes={1}, blocks={2}." -f
                $startCount, $completeCount, $blocks.Count)
        }
        # Only this exact one-start/one-complete ordered block proves the test
        # player is terminal. Content assertions run after that lifecycle proof.
        $behaviorTerminalObserved = $true
        foreach ($block in $blocks) {
            $body = $block.Groups['body'].Value
            foreach ($pattern in $ExpectedTracePatterns) {
                $count = [regex]::Matches($body, $pattern).Count
                if ($count -ne 1) {
                    throw "Focused trace pattern must occur exactly once (found $count): $pattern"
                }
            }
            if ($body -match '\[TEST_FAIL\]' -or
                $body -match '(^|[\r\n])\s*\[FAIL\]' -or
                $body -match 'Tests Failed:\s*[1-9]') {
                throw 'Focused trace contains a failure sentinel.'
            }
        }

        $errors = Get-Content -LiteralPath $errorsPath -Raw -Encoding UTF8
        if ($errors -notmatch '^\s*0\s+[^,\r\n]+,\s*0\s+[^,\r\n]+\s*$') {
            throw 'Focused compiler diagnostics are not 0 errors / 0 warnings.'
        }
        $compileOutput = Get-Content -LiteralPath $outputPath -Raw -Encoding UTF8
        $retryCount = [regex]::Matches(
            $compileOutput, 'ASO 32K branch detected').Count
        if ($retryCount -ne 0) {
            throw 'Focused compile required the 32K retry; diagnostics were preserved, but this is not a healthy pass.'
        }
        Write-Host ("[OK] {0}: {1}; blocks=1, 32K retry=0, compiler 0/0, fresh trace/output/errors." -f
            $DomainId, $SuccessSummary)
    }
} finally {
    try {
        if ($childCompileSucceeded -and -not $behaviorTerminalObserved) {
            Write-FocusedBehaviorUncertain (
                "child compile succeeded but exact behavior closure was not observed; " +
                "domain=$DomainId; runId=$runId; the old test player may still append late evidence")
        }
    } finally {
        try {
            # Transaction creation precedes runner installation. If readiness,
            # copy, rewrite, or hashing fails, the installed identity is not
            # proven; keep the marker/backup for fail-closed manual recovery
            # instead of masking the original error with an empty hash bind.
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
