[CmdletBinding()]
param(
    [string]$ProjectRoot,
    [string]$ReportPath,
    [ValidateRange(30, 900)]
    [int]$TestTimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function ConvertTo-ProcessArgument {
    param([AllowEmptyString()][string]$Value)

    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') {
        return $Value
    }
    $builder = [System.Text.StringBuilder]::new()
    [void]$builder.Append('"')
    $backslashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') {
            $backslashes++
            continue
        }
        if ($character -eq '"') {
            [void]$builder.Append(('\' * (($backslashes * 2) + 1)))
            [void]$builder.Append('"')
            $backslashes = 0
            continue
        }
        if ($backslashes -gt 0) {
            [void]$builder.Append(('\' * $backslashes))
            $backslashes = 0
        }
        [void]$builder.Append($character)
    }
    if ($backslashes -gt 0) {
        [void]$builder.Append(('\' * ($backslashes * 2)))
    }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function Invoke-ProcessWithTimeout {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,
        [Parameter(Mandatory)]
        [string[]]$Arguments,
        [Parameter(Mandatory)]
        [int]$TimeoutSeconds,
        [Parameter(Mandatory)]
        [string]$Label
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.Arguments = (($Arguments | ForEach-Object {
        ConvertTo-ProcessArgument -Value $_
    }) -join ' ')

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            throw "Unable to start $Label."
        }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $timeoutMilliseconds = $TimeoutSeconds * 1000
        if (-not $process.WaitForExit($timeoutMilliseconds)) {
            try {
                & taskkill.exe /PID $process.Id /T /F 2>&1 | Out-Null
            } catch {
                # Preserve the primary timeout failure.
            }
            [void]$process.WaitForExit(10000)
            $stdout = $stdoutTask.GetAwaiter().GetResult()
            $stderr = $stderrTask.GetAwaiter().GetResult()
            if (-not [string]::IsNullOrEmpty($stdout)) {
                Write-Host $stdout -NoNewline
            }
            if (-not [string]::IsNullOrEmpty($stderr)) {
                Write-Host $stderr -NoNewline
            }
            throw "$Label exceeded the hard timeout of $TimeoutSeconds seconds."
        }

        $process.WaitForExit()
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        if (-not [string]::IsNullOrEmpty($stdout)) {
            Write-Host $stdout -NoNewline
        }
        if (-not [string]::IsNullOrEmpty($stderr)) {
            Write-Host $stderr -NoNewline
        }
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            StdOut = $stdout
            StdErr = $stderr
        }
    } finally {
        $process.Dispose()
    }
}

function Get-Sha256Hex {
    param([Parameter(Mandatory)][string]$LiteralPath)

    $stream = [System.IO.File]::OpenRead($LiteralPath)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $digest = $sha256.ComputeHash($stream)
        return ([System.BitConverter]::ToString($digest)).Replace('-', '')
    } finally {
        $sha256.Dispose()
        $stream.Dispose()
    }
}

function Get-BytesSha256Hex {
    param([Parameter(Mandatory)][byte[]]$Bytes)

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $digest = $sha256.ComputeHash($Bytes)
        return ([System.BitConverter]::ToString($digest)).Replace('-', '')
    } finally {
        $sha256.Dispose()
    }
}

function Invoke-GitText {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [switch]$AllowFailure
    )

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        # Windows PowerShell 5.1 may promote native stderr to a terminating
        # NativeCommandError while the script-level preference is Stop.  Some
        # probes intentionally expect a non-zero git exit (for example, a new
        # untracked closure file), so capture that result before enforcing the
        # caller's AllowFailure contract below.
        $ErrorActionPreference = 'Continue'
        $output = @(& git -C $ProjectRoot @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    $text = (($output | ForEach-Object { $_.ToString() }) -join "`n")
    if ($exitCode -ne 0 -and -not $AllowFailure) {
        throw "git $($Arguments -join ' ') failed ($exitCode): $text"
    }
    return [pscustomobject]@{
        ExitCode = $exitCode
        Text = $text
    }
}

function Get-IndexBlob {
    param([string]$StageOutput)

    if ([string]::IsNullOrEmpty($StageOutput)) {
        return $null
    }
    if ($StageOutput -notmatch '^\d+\s+([0-9a-f]{40})\s+\d+\t') {
        throw "Unexpected git ls-files --stage output: $StageOutput"
    }
    return $Matches[1]
}

function Assert-ContractEqual {
    param(
        $Actual,
        $Expected,
        [Parameter(Mandatory)][string]$Label
    )

    if ($null -eq $Actual -and $null -eq $Expected) {
        return
    }
    if ($null -eq $Actual -or $null -eq $Expected -or
        -not [object]::Equals($Actual, $Expected)) {
        throw "$Label mismatch: expected='$Expected' actual='$Actual'"
    }
}

function Assert-ExactStringSet {
    param(
        [Parameter(Mandatory)][string[]]$Actual,
        [Parameter(Mandatory)][string[]]$Expected,
        [Parameter(Mandatory)][string]$Label
    )

    $seen = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal)
    foreach ($item in $Actual) {
        if (-not $seen.Add($item)) {
            throw "$Label contains duplicate '$item'."
        }
    }
    [string[]]$actualSorted = @($Actual)
    [string[]]$expectedSorted = @($Expected)
    [System.Array]::Sort($actualSorted, [System.StringComparer]::Ordinal)
    [System.Array]::Sort($expectedSorted, [System.StringComparer]::Ordinal)
    if ($actualSorted.Count -ne $expectedSorted.Count -or
        @(Compare-Object -ReferenceObject $expectedSorted `
            -DifferenceObject $actualSorted -CaseSensitive).Count -ne 0) {
        throw "$Label is incomplete or contains extras."
    }
}

function Get-RequiredGate {
    param(
        [Parameter(Mandatory)]$Gates,
        [Parameter(Mandatory)][string]$Id
    )

    $matches = @($Gates | Where-Object { [string]$_.id -ceq $Id })
    if ($matches.Count -ne 1) {
        throw "Expected exactly one qualification gate '$Id'."
    }
    return $matches[0]
}

function Assert-ExactStringSequence {
    param(
        [Parameter(Mandatory)][string[]]$Actual,
        [Parameter(Mandatory)][string[]]$Expected,
        [Parameter(Mandatory)][string]$Label
    )

    if ($Actual.Count -ne $Expected.Count) {
        throw "$Label count mismatch: expected=$($Expected.Count) actual=$($Actual.Count)"
    }
    for ($index = 0; $index -lt $Expected.Count; $index++) {
        if (-not [string]::Equals(
                $Actual[$index],
                $Expected[$index],
                [System.StringComparison]::Ordinal)) {
            throw (
                "$Label[$index] mismatch: expected='$($Expected[$index])' " +
                "actual='$($Actual[$index])'")
        }
    }
}

function Assert-ExactPropertySet {
    param(
        [Parameter(Mandatory)]$Value,
        [Parameter(Mandatory)][string[]]$Expected,
        [Parameter(Mandatory)][string]$Label
    )

    [string[]]$actual = @($Value.PSObject.Properties.Name)
    Assert-ExactStringSet -Actual $actual -Expected $Expected -Label $Label
}

function Test-IsNumericValue {
    param($Value)

    return (
        $Value -is [byte] -or
        $Value -is [sbyte] -or
        $Value -is [int16] -or
        $Value -is [uint16] -or
        $Value -is [int32] -or
        $Value -is [uint32] -or
        $Value -is [int64] -or
        $Value -is [uint64] -or
        $Value -is [single] -or
        $Value -is [double] -or
        $Value -is [decimal])
}

function ConvertTo-NonNegativeFiniteDouble {
    param(
        $Value,
        [Parameter(Mandatory)][string]$Label
    )

    if (-not (Test-IsNumericValue -Value $Value)) {
        throw "$Label must be a JSON number."
    }
    $number = [double]$Value
    if ([double]::IsNaN($number) -or
        [double]::IsInfinity($number) -or
        $number -lt 0) {
        throw "$Label must be finite and non-negative."
    }
    return $number
}

function ConvertTo-FiniteDouble {
    param(
        $Value,
        [Parameter(Mandatory)][string]$Label
    )

    if (-not (Test-IsNumericValue -Value $Value)) {
        throw "$Label must be a JSON number."
    }
    $number = [double]$Value
    if ([double]::IsNaN($number) -or [double]::IsInfinity($number)) {
        throw "$Label must be finite."
    }
    return $number
}

function ConvertTo-ExactInt64 {
    param(
        $Value,
        [Parameter(Mandatory)][string]$Label,
        [switch]$NonNegative
    )

    if (-not (Test-IsNumericValue -Value $Value)) {
        throw "$Label must be a JSON integer."
    }
    $number = [double]$Value
    if ([double]::IsNaN($number) -or
        [double]::IsInfinity($number) -or
        [math]::Truncate($number) -ne $number -or
        $number -lt [long]::MinValue -or
        $number -gt [long]::MaxValue) {
        throw "$Label must be an exact Int64 value."
    }
    $integer = [long]$number
    if ($NonNegative -and $integer -lt 0) {
        throw "$Label must be non-negative."
    }
    return $integer
}

function Get-RecomputedTimingSummary {
    param(
        [Parameter(Mandatory)][double[]]$Values,
        [Parameter(Mandatory)][string]$Label
    )

    if ($Values.Count -eq 0) {
        throw "$Label must contain at least one timing sample."
    }
    [double[]]$ordered = @($Values)
    [System.Array]::Sort($ordered)
    $sum = 0.0
    foreach ($value in $ordered) {
        $sum += $value
    }
    $p50Index = [math]::Max(
        1,
        [int][math]::Ceiling(0.50 * $ordered.Count)) - 1
    $p95Index = [math]::Max(
        1,
        [int][math]::Ceiling(0.95 * $ordered.Count)) - 1
    $p99Index = [math]::Max(
        1,
        [int][math]::Ceiling(0.99 * $ordered.Count)) - 1
    return [pscustomobject]@{
        Count = [int]$ordered.Count
        Mean = [math]::Round(
            $sum / $ordered.Count,
            6,
            [System.MidpointRounding]::AwayFromZero)
        P50 = [math]::Round(
            $ordered[$p50Index],
            6,
            [System.MidpointRounding]::AwayFromZero)
        P95 = [math]::Round(
            $ordered[$p95Index],
            6,
            [System.MidpointRounding]::AwayFromZero)
        P99 = [math]::Round(
            $ordered[$p99Index],
            6,
            [System.MidpointRounding]::AwayFromZero)
        Max = [math]::Round(
            $ordered[$ordered.Count - 1],
            6,
            [System.MidpointRounding]::AwayFromZero)
    }
}

function Assert-TimingSummary {
    param(
        [Parameter(Mandatory)]$Reported,
        [Parameter(Mandatory)]$Recomputed,
        [Parameter(Mandatory)][string]$Label
    )

    Assert-ExactPropertySet `
        -Value $Reported `
        -Expected @('count', 'mean', 'p50', 'p95', 'p99', 'max') `
        -Label "$Label properties"
    $reportedCount = ConvertTo-ExactInt64 `
        -Value $Reported.count -Label "$Label.count" -NonNegative
    Assert-ContractEqual $reportedCount ([long]$Recomputed.Count) `
        "$Label.count"
    foreach ($property in @('mean', 'p50', 'p95', 'p99', 'max')) {
        $reportedValue = ConvertTo-NonNegativeFiniteDouble `
            -Value $Reported.$property -Label "$Label.$property"
        Assert-ContractEqual $reportedValue `
            ([double]$Recomputed.$property) "$Label.$property"
    }
}

function Test-AndRecomputeTimingBlock {
    param(
        [Parameter(Mandatory)]$Samples,
        [Parameter(Mandatory)][object[]]$ExpectedRows,
        [Parameter(Mandatory)]$ReportedSummary,
        [Parameter(Mandatory)][string]$Label
    )

    $actualSamples = @($Samples)
    if ($actualSamples.Count -ne $ExpectedRows.Count) {
        throw (
            "$Label sample count mismatch: expected=$($ExpectedRows.Count) " +
            "actual=$($actualSamples.Count)")
    }

    $values = [System.Collections.Generic.List[double]]::new()
    for ($index = 0; $index -lt $ExpectedRows.Count; $index++) {
        $sample = $actualSamples[$index]
        $expected = $ExpectedRows[$index]
        Assert-ExactPropertySet `
            -Value $sample `
            -Expected @('phase', 'scenario', 'milliseconds', 'result') `
            -Label "$Label.samples[$index] properties"
        Assert-ContractEqual ([string]$sample.phase) `
            ([string]$expected.Phase) "$Label.samples[$index].phase"
        Assert-ContractEqual ([string]$sample.scenario) `
            ([string]$expected.Scenario) "$Label.samples[$index].scenario"
        Assert-ContractEqual $sample.result $expected.Result `
            "$Label.samples[$index].result"
        $milliseconds = ConvertTo-NonNegativeFiniteDouble `
            -Value $sample.milliseconds `
            -Label "$Label.samples[$index].milliseconds"
        $values.Add($milliseconds)
    }

    $recomputed = Get-RecomputedTimingSummary `
        -Values $values.ToArray() -Label $Label
    Assert-TimingSummary `
        -Reported $ReportedSummary `
        -Recomputed $recomputed `
        -Label "$Label.summary"
    return $recomputed
}

function Assert-TimingSampleBlocksEqual {
    param(
        [Parameter(Mandatory)]$Actual,
        [Parameter(Mandatory)]$Expected,
        [Parameter(Mandatory)][string]$Label
    )

    $actualSamples = @($Actual)
    $expectedSamples = @($Expected)
    if ($actualSamples.Count -ne $expectedSamples.Count) {
        throw "$Label sample count mismatch."
    }
    for ($index = 0; $index -lt $actualSamples.Count; $index++) {
        foreach ($property in @('phase', 'scenario', 'result')) {
            Assert-ContractEqual $actualSamples[$index].$property `
                $expectedSamples[$index].$property `
                "$Label.samples[$index].$property"
        }
        $actualMs = ConvertTo-NonNegativeFiniteDouble `
            -Value $actualSamples[$index].milliseconds `
            -Label "$Label.actual[$index].milliseconds"
        $expectedMs = ConvertTo-NonNegativeFiniteDouble `
            -Value $expectedSamples[$index].milliseconds `
            -Label "$Label.expected[$index].milliseconds"
        Assert-ContractEqual $actualMs $expectedMs `
            "$Label.samples[$index].milliseconds"
    }
}

function Get-ContractGate {
    param(
        [Parameter(Mandatory)]$Gates,
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Phase,
        [Parameter(Mandatory)][string]$Comparison,
        [Parameter(Mandatory)][string]$Unit
    )

    $gate = Get-RequiredGate -Gates $Gates -Id $Id
    Assert-ContractEqual ([string]$gate.phase) $Phase "$Id.phase"
    Assert-ContractEqual ([string]$gate.comparison) `
        $Comparison "$Id.comparison"
    Assert-ContractEqual ([string]$gate.unit) $Unit "$Id.unit"
    Assert-ContractEqual $gate.passed $true "$Id.passed"
    return $gate
}

function Assert-UpperBoundGate {
    param(
        [Parameter(Mandatory)]$Gates,
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Phase,
        [Parameter(Mandatory)][string]$Unit,
        [Parameter(Mandatory)][double]$Actual,
        [Parameter(Mandatory)][double]$Expected
    )

    $gate = Get-ContractGate `
        -Gates $Gates `
        -Id $Id `
        -Phase $Phase `
        -Comparison 'less_than_or_equal' `
        -Unit $Unit
    $reportedActual = ConvertTo-NonNegativeFiniteDouble `
        -Value $gate.actual -Label "$Id.actual"
    $reportedExpected = ConvertTo-NonNegativeFiniteDouble `
        -Value $gate.expected -Label "$Id.expected"
    Assert-ContractEqual $reportedActual $Actual "$Id.actual"
    Assert-ContractEqual $reportedExpected $Expected "$Id.expected"
    if ($Actual -gt $Expected) {
        throw "$Id exceeds its independently verified upper bound."
    }
}

function Assert-RectangleContract {
    param(
        [Parameter(Mandatory)]$Rectangle,
        [Parameter(Mandatory)][int]$X,
        [Parameter(Mandatory)][int]$Y,
        [Parameter(Mandatory)][int]$Width,
        [Parameter(Mandatory)][int]$Height,
        [Parameter(Mandatory)][string]$Label
    )

    Assert-ExactPropertySet `
        -Value $Rectangle `
        -Expected @(
            'x', 'y', 'width', 'height',
            'left', 'top', 'right', 'bottom') `
        -Label "$Label properties"
    $expectedValues = [ordered]@{
        x = $X
        y = $Y
        width = $Width
        height = $Height
        left = $X
        top = $Y
        right = $X + $Width
        bottom = $Y + $Height
    }
    foreach ($entry in $expectedValues.GetEnumerator()) {
        $actual = ConvertTo-ExactInt64 `
            -Value $Rectangle.($entry.Key) `
            -Label "$Label.$($entry.Key)"
        Assert-ContractEqual $actual ([long]$entry.Value) `
            "$Label.$($entry.Key)"
    }
}

function Assert-JsonEquivalent {
    param(
        $Actual,
        $Expected,
        [Parameter(Mandatory)][string]$Label
    )

    $actualJson = $Actual | ConvertTo-Json -Compress -Depth 50
    $expectedJson = $Expected | ConvertTo-Json -Compress -Depth 50
    Assert-ContractEqual ([string]$actualJson) `
        ([string]$expectedJson) $Label
}

function Test-IsRendererFamilyBinaryFileName {
    param([Parameter(Mandatory)][string]$FileName)

    if (-not $FileName.EndsWith(
            '.dll',
            [System.StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }
    foreach ($prefix in @(
            'Svg',
            'Skia',
            'libSkia',
            'HarfBuzz',
            'libHarfBuzz',
            'ExCSS',
            'ShimSkia')) {
        if ($FileName.StartsWith(
                $prefix,
                [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function Get-RendererOutputClosurePaths {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$TargetRoot
    )

    $absoluteRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd('\')
    $absoluteTargetRoot = [System.IO.Path]::GetFullPath($TargetRoot)
    $rootPrefix = $absoluteRoot + '\'
    if (-not $absoluteTargetRoot.StartsWith(
            $rootPrefix,
            [System.StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-Path -LiteralPath $absoluteTargetRoot -PathType Container)) {
        throw "Renderer output root is missing/outside project: $TargetRoot"
    }

    $paths = [System.Collections.Generic.List[string]]::new()
    $pending = [System.Collections.Generic.Stack[string]]::new()
    $pending.Push($absoluteTargetRoot)
    while ($pending.Count -ne 0) {
        $directory = $pending.Pop()
        foreach ($file in [System.IO.Directory]::EnumerateFiles(
                $directory,
                '*',
                [System.IO.SearchOption]::TopDirectoryOnly)) {
            if (Test-IsRendererFamilyBinaryFileName `
                    -FileName ([System.IO.Path]::GetFileName($file))) {
                $absoluteFile = [System.IO.Path]::GetFullPath($file)
                if (-not $absoluteFile.StartsWith(
                        $rootPrefix,
                        [System.StringComparison]::OrdinalIgnoreCase)) {
                    throw "Renderer output file escaped project root: $file"
                }
                $paths.Add(
                    $absoluteFile.Substring($rootPrefix.Length).
                        Replace('\', '/'))
            }
        }
        foreach ($child in [System.IO.Directory]::EnumerateDirectories(
                $directory,
                '*',
                [System.IO.SearchOption]::TopDirectoryOnly)) {
            $attributes = [System.IO.File]::GetAttributes($child)
            if (($attributes -band
                    [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Renderer output closure refuses reparse directory: $child"
            }
            $pending.Push($child)
        }
    }
    [string[]]$result = $paths.ToArray()
    [System.Array]::Sort($result, [System.StringComparer]::Ordinal)
    return $result
}

function Test-AndVerifySourceClosure {
    param([Parameter(Mandatory)]$Report)

    [string[]]$expectedClosurePaths = @(
        'global.json'
        'launcher/CRAZYFLASHER7MercenaryEmpire.csproj'
        'launcher/Directory.Packages.props'
        'launcher/packages.lock.json'
        'launcher/resolve-dotnet.ps1'
        'launcher/src/Guardian/NativeHudOverlay.cs'
        'launcher/src/Guardian/OverlayBase.cs'
        'launcher/src/Guardian/Hud/LayeredWindowCommit.cs'
        'launcher/src/Guardian/Hud/NativeHudTheme.cs'
        'launcher/src/Guardian/Hud/NativeHudTopologyProbe.cs'
        'launcher/src/Guardian/Hud/RightHudLayout.cs'
        'launcher/src/Guardian/Hud/WidgetScaler.cs'
        'launcher/src/Guardian/Hud/PlayerInfo/PlayerInfoStrictSvg.cs'
        'launcher/src/Guardian/Hud/PlayerInfo/PlayerInfoSvgAssetCatalog.cs'
        'launcher/src/Guardian/Hud/PlayerInfo/PlayerInfoRasterPlan.cs'
        'launcher/src/Guardian/Hud/PlayerInfo/PlayerInfoSvgRasterizer.cs'
        'launcher/src/Guardian/Hud/PlayerInfo/PlayerInfoRasterPipeline.cs'
        'launcher/src/Guardian/Hud/PlayerInfo/Assets/player-info.manifest.json'
        'launcher/src/Guardian/Hud/PlayerInfo/Assets/hp/backplate.svg'
        'launcher/src/Guardian/Hud/PlayerInfo/Assets/hp/fill.svg'
        'launcher/src/Guardian/Hud/PlayerInfo/Assets/hp/rim.svg'
        'launcher/src/Guardian/Hud/PlayerInfo/Assets/mp/backplate.svg'
        'launcher/src/Guardian/Hud/PlayerInfo/Assets/mp/fill.svg'
        'launcher/src/Guardian/Hud/PlayerInfo/Assets/mp/rim.svg'
        'launcher/src/Guardian/Hud/PlayerInfo/Assets/mp/rim-vf70.svg'
        'launcher/src/Guardian/Hud/PlayerInfo/Assets/mp/rim-vf91.svg'
        'launcher/tests/Launcher.Tests.csproj'
        'launcher/tests/Guardian/Hud/PlayerInfo/PlayerInfoB005RuntimeQualificationTests.cs'
        'launcher/tests/Guardian/Hud/PlayerInfo/PlayerInfoManifestRuntimeContractTests.cs'
        'launcher/tests/Guardian/Hud/PlayerInfo/PlayerInfoPArgbBridgeTests.cs'
        'launcher/tests/Guardian/Hud/PlayerInfo/PlayerInfoRasterPipelineTests.cs'
        'launcher/tests/Guardian/Hud/PlayerInfo/PlayerInfoRasterPlannerTests.cs'
        'launcher/tests/Guardian/Hud/PlayerInfo/PlayerInfoSvgProductionTests.cs'
        'launcher/tests/Guardian/Hud/PlayerInfo/PlayerInfoSvgRasterizerTests.cs'
        'launcher/tests/Guardian/LayeredWindowCommitTests.cs'
        'launcher/tests/Guardian/NativeHudTopologyProbeTests.cs'
        'tools/player-info-hud/run-b0-05-runtime-qualification.ps1'
    )
    [System.Array]::Sort(
        $expectedClosurePaths,
        [System.StringComparer]::Ordinal)

    $reportFiles = @($Report.sourceClosure.files)
    [string[]]$reportedPaths = @(
        $reportFiles | ForEach-Object { [string]$_.path })
    [System.Array]::Sort(
        $reportedPaths,
        [System.StringComparer]::Ordinal)
    if (@(Compare-Object -ReferenceObject $expectedClosurePaths `
            -DifferenceObject $reportedPaths -CaseSensitive).Count -ne 0) {
        throw 'B0-05 report source closure path set is incomplete or has extras.'
    }

    $headCommit = (Invoke-GitText -Arguments @('rev-parse', 'HEAD')).Text
    Assert-ContractEqual $Report.sourceClosure.headCommit $headCommit `
        'sourceClosure.headCommit'
    $repositoryStatus = (Invoke-GitText -Arguments @(
        'status', '--porcelain=v1', '--untracked-files=all')).Text
    $repositoryDirty = -not [string]::IsNullOrEmpty($repositoryStatus)
    Assert-ContractEqual ([bool]$Report.sourceClosure.repositoryDirty) `
        $repositoryDirty 'sourceClosure.repositoryDirty'

    $canonicalLines = [System.Collections.Generic.List[string]]::new()
    $closureDirty = $false
    foreach ($relativePath in $expectedClosurePaths) {
        $reported = @($reportFiles | Where-Object {
            $_.path -ceq $relativePath
        })
        if ($reported.Count -ne 1) {
            throw "Expected one source closure record for $relativePath."
        }
        $reported = $reported[0]
        $absolutePath = [System.IO.Path]::GetFullPath(
            (Join-Path $ProjectRoot ($relativePath -replace '/', '\')))
        $rootPrefix = $ProjectRoot.TrimEnd('\') + '\'
        if (-not $absolutePath.StartsWith(
                $rootPrefix,
                [System.StringComparison]::OrdinalIgnoreCase) -or
            -not (Test-Path -LiteralPath $absolutePath -PathType Leaf)) {
            throw "Closure file is missing/outside root: $relativePath"
        }

        $size = (Get-Item -LiteralPath $absolutePath).Length
        $worktreeSha256 = Get-Sha256Hex -LiteralPath $absolutePath
        $status = (Invoke-GitText -Arguments @(
            'status', '--porcelain=v1', '--untracked-files=all',
            '--', $relativePath)).Text
        $trackedProbe = Invoke-GitText -Arguments @(
            'ls-files', '--error-unmatch', '--', $relativePath) -AllowFailure
        $tracked = $trackedProbe.ExitCode -eq 0
        $indexOutput = (Invoke-GitText -Arguments @(
            'ls-files', '--stage', '--', $relativePath)).Text
        $indexBlob = Get-IndexBlob -StageOutput $indexOutput
        $headProbe = Invoke-GitText -Arguments @(
            'rev-parse', '--verify', "HEAD:$relativePath") -AllowFailure
        $headBlob = if ($headProbe.ExitCode -eq 0 -and
            -not [string]::IsNullOrEmpty($headProbe.Text)) {
            $headProbe.Text
        } else {
            $null
        }

        Assert-ContractEqual ([long]$reported.size) ([long]$size) `
            "$relativePath size"
        Assert-ContractEqual ([string]$reported.worktreeSha256) `
            ([string]$worktreeSha256) "$relativePath worktree SHA-256"
        Assert-ContractEqual ([bool]$reported.tracked) ([bool]$tracked) `
            "$relativePath tracked"
        Assert-ContractEqual $reported.headBlob $headBlob `
            "$relativePath HEAD blob"
        Assert-ContractEqual $reported.indexBlob $indexBlob `
            "$relativePath index blob"
        Assert-ContractEqual ([string]$reported.worktreeStatus) `
            ([string]$status) "$relativePath worktree status"

        if (-not [string]::IsNullOrEmpty($status)) {
            $closureDirty = $true
        }
        $statusBase64 = [System.Convert]::ToBase64String(
            [System.Text.Encoding]::UTF8.GetBytes($status))
        $canonicalLines.Add((
            "{0}`t{1}`t{2}`t{3}`t{4}`t{5}`t{6}" -f
                $relativePath,
                $size,
                $worktreeSha256,
                $(if ($tracked) { '1' } else { '0' }),
                $(if ($null -eq $headBlob) { '-' } else { $headBlob }),
                $(if ($null -eq $indexBlob) { '-' } else { $indexBlob }),
                $statusBase64))
    }

    Assert-ContractEqual ([bool]$Report.sourceClosure.closureDirty) `
        $closureDirty 'sourceClosure.closureDirty'
    $canonical = ($canonicalLines -join "`n") + "`n"
    $aggregate = Get-BytesSha256Hex -Bytes (
        [System.Text.Encoding]::UTF8.GetBytes($canonical))
    Assert-ContractEqual ([string]$Report.sourceClosure.aggregateSha256) `
        ([string]$aggregate) 'sourceClosure.aggregateSha256'

    $assemblyRelativePath = [string]$Report.testAssembly.relativePath
    $assemblyPath = [System.IO.Path]::GetFullPath(
        (Join-Path $ProjectRoot ($assemblyRelativePath -replace '/', '\')))
    $rootPrefix = $ProjectRoot.TrimEnd('\') + '\'
    if (-not $assemblyPath.StartsWith(
            $rootPrefix,
            [System.StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-Path -LiteralPath $assemblyPath -PathType Leaf)) {
        throw "Reported test assembly is missing/outside root: $assemblyRelativePath"
    }
    Assert-ContractEqual ([long]$Report.testAssembly.size) `
        ([long](Get-Item -LiteralPath $assemblyPath).Length) `
        'testAssembly.size'
    Assert-ContractEqual ([string]$Report.testAssembly.sha256) `
        ([string](Get-Sha256Hex -LiteralPath $assemblyPath)) `
        'testAssembly.sha256'
    Assert-ContractEqual $assemblyRelativePath `
        'launcher/tests/bin/Release/Launcher.Tests.dll' `
        'testAssembly.relativePath'
    $assemblySize = ConvertTo-ExactInt64 `
        -Value $Report.testAssembly.size `
        -Label 'testAssembly.size' -NonNegative
    if ($assemblySize -le 0) {
        throw 'testAssembly.size must be positive.'
    }
    if ([string]$Report.testAssembly.sha256 -cnotmatch '^[0-9A-F]{64}$') {
        throw 'testAssembly.sha256 is not canonical.'
    }

    $gates = @($Report.gates)
    $sourceGate = Get-ContractGate `
        -Gates $gates `
        -Id 'source_closure_bound' `
        -Phase 'evidence_identity' `
        -Comparison 'equals' `
        -Unit 'closure'
    Assert-ExactPropertySet `
        -Value $sourceGate.actual `
        -Expected @(
            'fileCount',
            'aggregateSha256',
            'repositoryDirty',
            'closureDirty') `
        -Label 'source_closure_bound.actual properties'
    Assert-ContractEqual `
        (ConvertTo-ExactInt64 `
            -Value $sourceGate.actual.fileCount `
            -Label 'source_closure_bound.actual.fileCount' -NonNegative) `
        ([long]$expectedClosurePaths.Count) `
        'source_closure_bound.actual.fileCount'
    Assert-ContractEqual ([string]$sourceGate.actual.aggregateSha256) `
        ([string]$Report.sourceClosure.aggregateSha256) `
        'source_closure_bound.actual.aggregateSha256'
    Assert-ContractEqual $sourceGate.actual.repositoryDirty `
        $Report.sourceClosure.repositoryDirty `
        'source_closure_bound.actual.repositoryDirty'
    Assert-ContractEqual $sourceGate.actual.closureDirty `
        $Report.sourceClosure.closureDirty `
        'source_closure_bound.actual.closureDirty'
    Assert-ExactPropertySet `
        -Value $sourceGate.expected `
        -Expected @('fileCount', 'aggregateSha256Length') `
        -Label 'source_closure_bound.expected properties'
    Assert-ContractEqual `
        (ConvertTo-ExactInt64 `
            -Value $sourceGate.expected.fileCount `
            -Label 'source_closure_bound.expected.fileCount' -NonNegative) `
        ([long]$expectedClosurePaths.Count) `
        'source_closure_bound.expected.fileCount'
    Assert-ContractEqual `
        (ConvertTo-ExactInt64 `
            -Value $sourceGate.expected.aggregateSha256Length `
            -Label (
                'source_closure_bound.expected.aggregateSha256Length') `
            -NonNegative) `
        64L 'source_closure_bound.expected.aggregateSha256Length'

    $assemblyGate = Get-ContractGate `
        -Gates $gates `
        -Id 'test_assembly_bound' `
        -Phase 'evidence_identity' `
        -Comparison 'equals' `
        -Unit 'assembly'
    Assert-ExactPropertySet `
        -Value $assemblyGate.actual `
        -Expected @('relativePath', 'size', 'sha256') `
        -Label 'test_assembly_bound.actual properties'
    Assert-ContractEqual ([string]$assemblyGate.actual.relativePath) `
        $assemblyRelativePath 'test_assembly_bound.actual.relativePath'
    Assert-ContractEqual `
        (ConvertTo-ExactInt64 `
            -Value $assemblyGate.actual.size `
            -Label 'test_assembly_bound.actual.size' -NonNegative) `
        $assemblySize 'test_assembly_bound.actual.size'
    Assert-ContractEqual ([string]$assemblyGate.actual.sha256) `
        ([string]$Report.testAssembly.sha256) `
        'test_assembly_bound.actual.sha256'
    Assert-ContractEqual ([string]$assemblyGate.expected) `
        'non-empty Launcher.Tests.dll with SHA-256' `
        'test_assembly_bound.expected'
}

function Test-AndVerifyExecutionBinaries {
    param([Parameter(Mandatory)]$Report)

    $expected = @(
        [pscustomobject]@{
            Name = 'core'
            Kind = 'managed'
            RelativePath =
                'launcher/tests/bin/Release/CRAZYFLASHER7MercenaryEmpire.Core.dll'
        }
        [pscustomobject]@{
            Name = 'excss'
            Kind = 'managed'
            RelativePath = 'launcher/tests/bin/Release/ExCSS.dll'
        }
        [pscustomobject]@{
            Name = 'harfbuzz_sharp'
            Kind = 'managed'
            RelativePath = 'launcher/tests/bin/Release/HarfBuzzSharp.dll'
        }
        [pscustomobject]@{
            Name = 'harfbuzz_sharp_native_win_x64'
            Kind = 'native'
            RelativePath =
                'launcher/tests/bin/Release/runtimes/win-x64/native/libHarfBuzzSharp.dll'
        }
        [pscustomobject]@{
            Name = 'shim_skia_sharp'
            Kind = 'managed'
            RelativePath = 'launcher/tests/bin/Release/ShimSkiaSharp.dll'
        }
        [pscustomobject]@{
            Name = 'skia_sharp'
            Kind = 'managed'
            RelativePath = 'launcher/tests/bin/Release/SkiaSharp.dll'
        }
        [pscustomobject]@{
            Name = 'skia_sharp_native_win_x64'
            Kind = 'native'
            RelativePath =
                'launcher/tests/bin/Release/runtimes/win-x64/native/libSkiaSharp.dll'
        }
        [pscustomobject]@{
            Name = 'svg_animation'
            Kind = 'managed'
            RelativePath = 'launcher/tests/bin/Release/Svg.Animation.dll'
        }
        [pscustomobject]@{
            Name = 'svg_custom'
            Kind = 'managed'
            RelativePath = 'launcher/tests/bin/Release/Svg.Custom.dll'
        }
        [pscustomobject]@{
            Name = 'svg_model'
            Kind = 'managed'
            RelativePath = 'launcher/tests/bin/Release/Svg.Model.dll'
        }
        [pscustomobject]@{
            Name = 'svg_scene_graph'
            Kind = 'managed'
            RelativePath = 'launcher/tests/bin/Release/Svg.SceneGraph.dll'
        }
        [pscustomobject]@{
            Name = 'svg_skia'
            Kind = 'managed'
            RelativePath = 'launcher/tests/bin/Release/Svg.Skia.dll'
        }
    )
    $reported = @($Report.executionBinaries)
    [string[]]$expectedNames = @(
        $expected | ForEach-Object { [string]$_.Name })
    [string[]]$reportedNames = @(
        $reported | ForEach-Object { [string]$_.name })
    Assert-ExactStringSequence `
        -Actual $reportedNames `
        -Expected $expectedNames `
        -Label 'executionBinaries.name order'

    $rootPrefix = $ProjectRoot.TrimEnd('\') + '\'
    foreach ($contract in $expected) {
        $binary = @($reported | Where-Object {
            [string]$_.name -ceq [string]$contract.Name
        })[0]
        Assert-ExactPropertySet `
            -Value $binary `
            -Expected @(
                'name', 'kind', 'relativePath', 'size', 'sha256', 'loaded') `
            -Label "executionBinaries.$($contract.Name) properties"
        Assert-ContractEqual ([string]$binary.kind) `
            ([string]$contract.Kind) "executionBinaries.$($contract.Name).kind"
        if (-not [string]::Equals(
                [string]$binary.relativePath,
                [string]$contract.RelativePath,
                [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "executionBinaries.$($contract.Name).relativePath mismatch."
        }
        $absolutePath = [System.IO.Path]::GetFullPath(
            (Join-Path $ProjectRoot (
                ([string]$contract.RelativePath) -replace '/', '\')))
        if (-not $absolutePath.StartsWith(
                $rootPrefix,
                [System.StringComparison]::OrdinalIgnoreCase) -or
            -not (Test-Path -LiteralPath $absolutePath -PathType Leaf)) {
            throw "Resolved target binary is missing/outside root: $($contract.Name)"
        }
        $reportedSize = ConvertTo-ExactInt64 `
            -Value $binary.size `
            -Label "executionBinaries.$($contract.Name).size" `
            -NonNegative
        if ($reportedSize -le 0) {
            throw "executionBinaries.$($contract.Name).size must be positive."
        }
        Assert-ContractEqual $reportedSize `
            ([long](Get-Item -LiteralPath $absolutePath).Length) `
            "executionBinaries.$($contract.Name).size"
        $reportedSha256 = [string]$binary.sha256
        if ($reportedSha256 -cnotmatch '^[0-9A-F]{64}$') {
            throw "executionBinaries.$($contract.Name).sha256 is not canonical."
        }
        Assert-ContractEqual $reportedSha256 `
            (Get-Sha256Hex -LiteralPath $absolutePath) `
            "executionBinaries.$($contract.Name).sha256"
        if ($binary.loaded -isnot [bool]) {
            throw "executionBinaries.$($contract.Name).loaded must be boolean."
        }
    }

    [string[]]$expectedRendererPaths = @(
        $expected |
            Where-Object { $_.Name -cne 'core' } |
            ForEach-Object { [string]$_.RelativePath })
    [System.Array]::Sort(
        $expectedRendererPaths,
        [System.StringComparer]::Ordinal)
    [string[]]$reportedRendererPaths = @(
        $Report.rendererTargetClosurePaths |
            ForEach-Object { [string]$_ })
    Assert-ExactStringSequence `
        -Actual $reportedRendererPaths `
        -Expected $expectedRendererPaths `
        -Label 'rendererTargetClosurePaths'

    [string[]]$expectedRendererOutputPaths = @(
        'launcher/tests/bin/Release/ExCSS.dll'
        'launcher/tests/bin/Release/HarfBuzzSharp.dll'
        'launcher/tests/bin/Release/ShimSkiaSharp.dll'
        'launcher/tests/bin/Release/SkiaSharp.dll'
        'launcher/tests/bin/Release/Svg.Animation.dll'
        'launcher/tests/bin/Release/Svg.Custom.dll'
        'launcher/tests/bin/Release/Svg.Model.dll'
        'launcher/tests/bin/Release/Svg.SceneGraph.dll'
        'launcher/tests/bin/Release/Svg.Skia.dll'
        'launcher/tests/bin/Release/runtimes/win-arm64/native/libHarfBuzzSharp.dll'
        'launcher/tests/bin/Release/runtimes/win-arm64/native/libSkiaSharp.dll'
        'launcher/tests/bin/Release/runtimes/win-x64/native/libHarfBuzzSharp.dll'
        'launcher/tests/bin/Release/runtimes/win-x64/native/libSkiaSharp.dll'
        'launcher/tests/bin/Release/runtimes/win-x86/native/libHarfBuzzSharp.dll'
        'launcher/tests/bin/Release/runtimes/win-x86/native/libSkiaSharp.dll'
    )
    [string[]]$independentRendererOutputPaths =
        @(Get-RendererOutputClosurePaths `
            -Root $ProjectRoot `
            -TargetRoot (Join-Path $ProjectRoot 'launcher\tests\bin\Release'))
    Assert-ExactStringSequence `
        -Actual $independentRendererOutputPaths `
        -Expected $expectedRendererOutputPaths `
        -Label 'independent renderer output closure'
    [string[]]$reportedRendererOutputPaths = @(
        $Report.rendererOutputClosurePaths |
            ForEach-Object { [string]$_ })
    Assert-ExactStringSequence `
        -Actual $reportedRendererOutputPaths `
        -Expected $expectedRendererOutputPaths `
        -Label 'rendererOutputClosurePaths'

    $unexpectedLoaded = @($Report.unexpectedLoadedRendererPaths)
    if ($unexpectedLoaded.Count -ne 0) {
        throw (
            'unexpectedLoadedRendererPaths must be empty: ' +
            (($unexpectedLoaded | ForEach-Object { [string]$_ }) -join ', '))
    }

    $loaded = @($Report.loadedExecutionBinaries)
    if ($loaded.Count -eq 0) {
        throw 'loadedExecutionBinaries must not be empty.'
    }
    $loadedPathSet = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)
    $loadedOrderKeys = [System.Collections.Generic.List[string]]::new()
    foreach ($binary in $loaded) {
        Assert-ExactPropertySet `
            -Value $binary `
            -Expected @(
                'fileName', 'kind', 'relativePath', 'insideProjectRoot',
                'size', 'sha256') `
            -Label "loadedExecutionBinaries.$($binary.relativePath) properties"
        if ($binary.insideProjectRoot -ne $true) {
            throw (
                "Loaded renderer-family binary is outside the project root: " +
                "$($binary.relativePath)")
        }
        $relativePath = [string]$binary.relativePath
        if (-not $loadedPathSet.Add($relativePath)) {
            throw "loadedExecutionBinaries contains duplicate '$relativePath'."
        }
        $contractMatches = @($expected | Where-Object {
            [string]::Equals(
                [string]$_.RelativePath,
                $relativePath,
                [System.StringComparison]::OrdinalIgnoreCase)
        })
        if ($contractMatches.Count -ne 1) {
            throw (
                "Loaded renderer-family binary is outside the exact target " +
                "contract: $relativePath")
        }
        $contract = $contractMatches[0]
        Assert-ContractEqual ([string]$binary.kind) `
            ([string]$contract.Kind) `
            "loadedExecutionBinaries.$relativePath.kind"
        Assert-ContractEqual ([string]$binary.fileName) `
            ([System.IO.Path]::GetFileName($relativePath)) `
            "loadedExecutionBinaries.$relativePath.fileName"

        $absolutePath = [System.IO.Path]::GetFullPath(
            (Join-Path $ProjectRoot ($relativePath -replace '/', '\')))
        if (-not $absolutePath.StartsWith(
                $rootPrefix,
                [System.StringComparison]::OrdinalIgnoreCase) -or
            -not (Test-Path -LiteralPath $absolutePath -PathType Leaf)) {
            throw "Loaded binary is missing/outside root: $relativePath"
        }
        $reportedSize = ConvertTo-ExactInt64 `
            -Value $binary.size `
            -Label "loadedExecutionBinaries.$relativePath.size" `
            -NonNegative
        if ($reportedSize -le 0) {
            throw "loadedExecutionBinaries.$relativePath.size must be positive."
        }
        Assert-ContractEqual $reportedSize `
            ([long](Get-Item -LiteralPath $absolutePath).Length) `
            "loadedExecutionBinaries.$relativePath.size"
        $reportedSha256 = [string]$binary.sha256
        if ($reportedSha256 -cnotmatch '^[0-9A-F]{64}$') {
            throw "loadedExecutionBinaries.$relativePath.sha256 is not canonical."
        }
        Assert-ContractEqual $reportedSha256 `
            (Get-Sha256Hex -LiteralPath $absolutePath) `
            "loadedExecutionBinaries.$relativePath.sha256"
        $loadedOrderKeys.Add(
            ([string]$binary.kind) + [char]0x1F + $relativePath)
    }
    [string[]]$loadedOrderActual = $loadedOrderKeys.ToArray()
    [string[]]$loadedOrderExpected = @($loadedOrderActual)
    [System.Array]::Sort(
        $loadedOrderExpected,
        [System.StringComparer]::Ordinal)
    Assert-ExactStringSequence `
        -Actual $loadedOrderActual `
        -Expected $loadedOrderExpected `
        -Label 'loadedExecutionBinaries order'

    foreach ($contract in $expected) {
        $resolved = @($reported | Where-Object {
            [string]$_.name -ceq [string]$contract.Name
        })[0]
        $isLoaded = $loadedPathSet.Contains([string]$contract.RelativePath)
        Assert-ContractEqual $resolved.loaded $isLoaded `
            "executionBinaries.$($contract.Name).loaded"
    }
    foreach ($requiredName in @(
            'core',
            'skia_sharp',
            'skia_sharp_native_win_x64',
            'svg_skia')) {
        $required = @($reported | Where-Object {
            [string]$_.name -ceq $requiredName
        })[0]
        Assert-ContractEqual $required.loaded $true `
            "executionBinaries.$requiredName.requiredLoaded"
    }

    $gate = Get-ContractGate `
        -Gates @($Report.gates) `
        -Id 'execution_binaries_bound' `
        -Phase 'evidence_identity' `
        -Comparison 'equals' `
        -Unit 'binary_closure'
    Assert-ExactPropertySet `
        -Value $gate.actual `
        -Expected @(
            'resolvedTargetBinaries',
            'loadedExecutionBinaries',
            'rendererTargetClosurePaths',
            'rendererOutputClosurePaths',
            'unexpectedLoadedRendererPaths') `
        -Label 'execution_binaries_bound.actual properties'
    Assert-JsonEquivalent `
        -Actual $gate.actual.resolvedTargetBinaries `
        -Expected $Report.executionBinaries `
        -Label 'execution_binaries_bound.actual.resolvedTargetBinaries'
    Assert-JsonEquivalent `
        -Actual $gate.actual.loadedExecutionBinaries `
        -Expected $Report.loadedExecutionBinaries `
        -Label 'execution_binaries_bound.actual.loadedExecutionBinaries'
    Assert-ExactStringSequence `
        -Actual @(
            $gate.actual.rendererTargetClosurePaths |
                ForEach-Object { [string]$_ }) `
        -Expected $expectedRendererPaths `
        -Label 'execution_binaries_bound.actual.rendererTargetClosurePaths'
    Assert-ExactStringSequence `
        -Actual @(
            $gate.actual.rendererOutputClosurePaths |
                ForEach-Object { [string]$_ }) `
        -Expected $expectedRendererOutputPaths `
        -Label 'execution_binaries_bound.actual.rendererOutputClosurePaths'
    Assert-ContractEqual `
        (@($gate.actual.unexpectedLoadedRendererPaths).Count) `
        0 'execution_binaries_bound.actual.unexpectedLoadedRendererPaths'

    Assert-ExactPropertySet `
        -Value $gate.expected `
        -Expected @(
            'binaries',
            'requiredLoaded',
            'rendererTargetFileCount',
            'rendererOutputFileCount',
            'unexpectedLoadedRendererPathCount',
            'each') `
        -Label 'execution_binaries_bound.expected properties'
    $expectedGateBinaries = @($gate.expected.binaries)
    if ($expectedGateBinaries.Count -ne $expected.Count) {
        throw 'execution_binaries_bound.expected.binaries count mismatch.'
    }
    for ($index = 0; $index -lt $expected.Count; $index++) {
        Assert-ExactPropertySet `
            -Value $expectedGateBinaries[$index] `
            -Expected @('name', 'kind', 'relativePath') `
            -Label "execution_binaries_bound.expected.binaries[$index] properties"
        Assert-ContractEqual ([string]$expectedGateBinaries[$index].name) `
            ([string]$expected[$index].Name) `
            "execution_binaries_bound.expected.binaries[$index].name"
        Assert-ContractEqual ([string]$expectedGateBinaries[$index].kind) `
            ([string]$expected[$index].Kind) `
            "execution_binaries_bound.expected.binaries[$index].kind"
        if (-not [string]::Equals(
                [string]$expectedGateBinaries[$index].relativePath,
                [string]$expected[$index].RelativePath,
                [System.StringComparison]::OrdinalIgnoreCase)) {
            throw (
                "execution_binaries_bound.expected.binaries[$index]." +
                'relativePath mismatch.')
        }
    }
    Assert-ExactStringSequence `
        -Actual @(
            $gate.expected.requiredLoaded |
                ForEach-Object { [string]$_ }) `
        -Expected @(
            'core',
            'skia_sharp',
            'skia_sharp_native_win_x64',
            'svg_skia') `
        -Label 'execution_binaries_bound.expected.requiredLoaded'
    $rendererTargetCount = ConvertTo-ExactInt64 `
        -Value $gate.expected.rendererTargetFileCount `
        -Label 'execution_binaries_bound.expected.rendererTargetFileCount' `
        -NonNegative
    Assert-ContractEqual $rendererTargetCount 11L `
        'execution_binaries_bound.expected.rendererTargetFileCount'
    $rendererOutputCount = ConvertTo-ExactInt64 `
        -Value $gate.expected.rendererOutputFileCount `
        -Label 'execution_binaries_bound.expected.rendererOutputFileCount' `
        -NonNegative
    Assert-ContractEqual $rendererOutputCount 15L `
        'execution_binaries_bound.expected.rendererOutputFileCount'
    $unexpectedCount = ConvertTo-ExactInt64 `
        -Value $gate.expected.unexpectedLoadedRendererPathCount `
        -Label (
            'execution_binaries_bound.expected.' +
            'unexpectedLoadedRendererPathCount') `
        -NonNegative
    Assert-ContractEqual $unexpectedCount 0L `
        'execution_binaries_bound.expected.unexpectedLoadedRendererPathCount'
    Assert-ContractEqual ([string]$gate.expected.each) `
        'non-empty exact target file with SHA-256' `
        'execution_binaries_bound.expected.each'
}

function Test-AndVerifyTimingContract {
    param(
        [Parameter(Mandatory)]$Report,
        [Parameter(Mandatory)]$Gates,
        [Parameter(Mandatory)][string[]]$ViewportIds
    )

    Assert-ContractEqual ([string]$Report.timings.quantileMethod) `
        'nearest_rank' 'timings.quantileMethod'

    $expectedCold = @(
        foreach ($viewportId in $ViewportIds) {
            [pscustomobject]@{
                Phase = 'cold_queue'
                Scenario = $viewportId
                Result = 'Queued'
            }
        })
    $expectedWarm = @(
        foreach ($viewportId in $ViewportIds) {
            [pscustomobject]@{
                Phase = 'warm_cache_lookup'
                Scenario = $viewportId
                Result = 'CacheHit'
            }
        })
    $expectedPending = @(
        for ($index = 1; $index -le 100; $index++) {
            [pscustomobject]@{
                Phase = 'pending_coalescing'
                Scenario = 'pending_{0:000}' -f $index
                Result = 'Queued'
            }
        })
    $expectedSteady = @(
        for ($index = 1; $index -le 3000; $index++) {
            [pscustomobject]@{
                Phase = 'steady_current_hit'
                Scenario = 'tick_{0:0000}' -f $index
                Result = 'CurrentHit'
            }
        })
    $expectedFresh = @(
        for ($sampleIndex = 1; $sampleIndex -le 20; $sampleIndex++) {
            foreach ($viewportId in $ViewportIds) {
                [pscustomobject]@{
                    Phase = 'warmed_fresh_{0:00}' -f $sampleIndex
                    Scenario = $viewportId
                    Result = $null
                }
            }
        })
    $expectedPipelineCold = @(
        foreach ($viewportId in $ViewportIds) {
            [pscustomobject]@{
                Phase = 'pipeline_cold_publish'
                Scenario = $viewportId
                Result = $null
            }
        })
    [string[]]$layerIds = @(
        'mp.backplate'
        'mp.fill'
        'mp.rim'
        'mp.rim-vf70'
        'mp.rim-vf91'
        'hp.backplate'
        'hp.fill'
        'hp.rim'
    )
    $expectedPArgb = @(
        foreach ($viewportId in $ViewportIds) {
            foreach ($layerId in $layerIds) {
                [pscustomobject]@{
                    Phase = $layerId
                    Scenario = $viewportId
                    Result = $null
                }
            }
        })

    $coldSamples = @($Report.timings.uiRequest.coldQueue.samples)
    $coldSummary = Test-AndRecomputeTimingBlock `
        -Samples $coldSamples `
        -ExpectedRows $expectedCold `
        -ReportedSummary $Report.timings.uiRequest.coldQueue.summary `
        -Label 'timings.uiRequest.coldQueue'
    $warmSamples = @(
        $Report.timings.uiRequest.warmInactiveCache.samples)
    $warmSummary = Test-AndRecomputeTimingBlock `
        -Samples $warmSamples `
        -ExpectedRows $expectedWarm `
        -ReportedSummary `
            $Report.timings.uiRequest.warmInactiveCache.summary `
        -Label 'timings.uiRequest.warmInactiveCache'
    $pendingSamples = @(
        $Report.timings.uiRequest.pendingCoalescing.samples)
    $pendingSummary = Test-AndRecomputeTimingBlock `
        -Samples $pendingSamples `
        -ExpectedRows $expectedPending `
        -ReportedSummary `
            $Report.timings.uiRequest.pendingCoalescing.summary `
        -Label 'timings.uiRequest.pendingCoalescing'

    Assert-ContractEqual `
        ([string]$Report.timings.uiRequest.steadyCurrentHit.
            canonicalSamplesPath) `
        'timings.steadyCurrentHit3000.samples' `
        'timings.uiRequest.steadyCurrentHit.canonicalSamplesPath'
    $steadySamples = @($Report.timings.steadyCurrentHit3000.samples)
    $steadySummary = Test-AndRecomputeTimingBlock `
        -Samples $steadySamples `
        -ExpectedRows $expectedSteady `
        -ReportedSummary $Report.timings.steadyCurrentHit3000.summary `
        -Label 'timings.steadyCurrentHit3000'
    Assert-TimingSummary `
        -Reported $Report.timings.uiRequest.steadyCurrentHit.summary `
        -Recomputed $steadySummary `
        -Label 'timings.uiRequest.steadyCurrentHit.summary'

    $steadyCanonicalCount = ConvertTo-ExactInt64 `
        -Value $Report.timings.steadyCurrentHit3000.sampleCount `
        -Label 'timings.steadyCurrentHit3000.sampleCount' `
        -NonNegative
    $steadyUiCount = ConvertTo-ExactInt64 `
        -Value $Report.timings.uiRequest.steadyCurrentHit.sampleCount `
        -Label 'timings.uiRequest.steadyCurrentHit.sampleCount' `
        -NonNegative
    Assert-ContractEqual $steadyCanonicalCount 3000L `
        'timings.steadyCurrentHit3000.sampleCount'
    Assert-ContractEqual $steadyUiCount 3000L `
        'timings.uiRequest.steadyCurrentHit.sampleCount'

    $combinedSamples = @(
        $coldSamples + $warmSamples + $pendingSamples + $steadySamples)
    $combinedExpected = @(
        $expectedCold + $expectedWarm + $expectedPending + $expectedSteady)
    $combinedSummary = Test-AndRecomputeTimingBlock `
        -Samples $combinedSamples `
        -ExpectedRows $combinedExpected `
        -ReportedSummary `
            $Report.timings.uiRequest.combinedSummaryDiagnosticOnly `
        -Label 'timings.uiRequest.combined'
    $uiSampleCount = ConvertTo-ExactInt64 `
        -Value $Report.timings.uiRequest.sampleCount `
        -Label 'timings.uiRequest.sampleCount' `
        -NonNegative
    Assert-ContractEqual $uiSampleCount ([long]$combinedSummary.Count) `
        'timings.uiRequest.sampleCount'
    Assert-ContractEqual $uiSampleCount 3108L `
        'timings.uiRequest.sampleCount frozen'

    $freshSamples = @($Report.timings.warmedFreshBake.samples)
    $freshOverall = Test-AndRecomputeTimingBlock `
        -Samples $freshSamples `
        -ExpectedRows $expectedFresh `
        -ReportedSummary `
            $Report.timings.warmedFreshBake.overallSummaryDiagnosticOnly `
        -Label 'timings.warmedFreshBake'
    Assert-ContractEqual `
        ([string]$Report.timings.warmedFreshBake.execution) `
        'one excluded native/JIT warmup per viewport, then round-robin samples each perform a fresh background SVG parse+raster+PArgb batch' `
        'timings.warmedFreshBake.execution'
    Assert-ContractEqual `
        ([string]$Report.timings.warmedFreshBake.sampleSemantics) `
        'warmed process; fresh asset work; not process-cold' `
        'timings.warmedFreshBake.sampleSemantics'
    $freshSamplesPerViewport = ConvertTo-ExactInt64 `
        -Value $Report.timings.warmedFreshBake.samplesPerViewport `
        -Label 'timings.warmedFreshBake.samplesPerViewport' `
        -NonNegative
    Assert-ContractEqual $freshSamplesPerViewport 20L `
        'timings.warmedFreshBake.samplesPerViewport'

    $viewportRows = @($Report.timings.warmedFreshBake.byViewport)
    Assert-ExactStringSequence `
        -Actual @($viewportRows | ForEach-Object {
            [string]$_.viewportId
        }) `
        -Expected $ViewportIds `
        -Label 'timings.warmedFreshBake.byViewport order'
    $freshByViewport = @{}
    foreach ($viewportId in $ViewportIds) {
        $row = @($viewportRows | Where-Object {
            [string]$_.viewportId -ceq $viewportId
        })[0]
        $viewportSamples = @($freshSamples | Where-Object {
            [string]$_.scenario -ceq $viewportId
        })
        $viewportExpected = @($expectedFresh | Where-Object {
            [string]$_.Scenario -ceq $viewportId
        })
        $freshByViewport[$viewportId] = Test-AndRecomputeTimingBlock `
            -Samples $viewportSamples `
            -ExpectedRows $viewportExpected `
            -ReportedSummary $row.summary `
            -Label "timings.warmedFreshBake.$viewportId"
    }

    $pipelineColdSummary = Test-AndRecomputeTimingBlock `
        -Samples @($Report.timings.pipelineColdPublish.samples) `
        -ExpectedRows $expectedPipelineCold `
        -ReportedSummary $Report.timings.pipelineColdPublish.summary `
        -Label 'timings.pipelineColdPublish'
    Assert-ContractEqual `
        ([string]$Report.timings.pipelineColdPublish.execution) `
        'Request through background pipeline to publish' `
        'timings.pipelineColdPublish.execution'

    $pArgbSummary = Test-AndRecomputeTimingBlock `
        -Samples @($Report.timings.pArgbCopy.samples) `
        -ExpectedRows $expectedPArgb `
        -ReportedSummary $Report.timings.pArgbCopy.summary `
        -Label 'timings.pArgbCopy'
    Assert-ContractEqual ([string]$Report.timings.pArgbCopy.execution) `
        'synthetic Bgra8888/Premul source at exact layer dimensions' `
        'timings.pArgbCopy.execution'

    $warmAliasSamples = @($Report.timings.warmCacheLookup.samples)
    $warmAliasSummary = Test-AndRecomputeTimingBlock `
        -Samples $warmAliasSamples `
        -ExpectedRows $expectedWarm `
        -ReportedSummary $Report.timings.warmCacheLookup.summary `
        -Label 'timings.warmCacheLookup'
    Assert-TimingSampleBlocksEqual `
        -Actual $warmAliasSamples `
        -Expected $warmSamples `
        -Label 'warm cache canonical/alias'
    Assert-ContractEqual ([string]$Report.timings.warmCacheLookup.execution) `
        'whole inactive-batch cache swap' `
        'timings.warmCacheLookup.execution'

    $pendingAliasSamples = @(
        $Report.timings.pendingCoalescing100.samples)
    $pendingAliasSummary = Test-AndRecomputeTimingBlock `
        -Samples $pendingAliasSamples `
        -ExpectedRows $expectedPending `
        -ReportedSummary $Report.timings.pendingCoalescing100.summary `
        -Label 'timings.pendingCoalescing100'
    Assert-TimingSampleBlocksEqual `
        -Actual $pendingAliasSamples `
        -Expected $pendingSamples `
        -Label 'pending coalescing canonical/alias'
    Assert-ContractEqual `
        ([string]$Report.timings.pendingCoalescing100.meaning) `
        '100 rapidly replaced viewport/DPI requests; latest pending work wins, not 100 completed bakes' `
        'timings.pendingCoalescing100.meaning'

    # Keep diagnostic-only summaries live in the verifier so accidental schema
    # removal or bogus non-finite fields cannot hide behind the gated p95s.
    $null = $freshOverall
    $null = $pipelineColdSummary
    $null = $pArgbSummary
    $null = $warmAliasSummary
    $null = $pendingAliasSummary

    $uiThreshold = ConvertTo-NonNegativeFiniteDouble `
        -Value $Report.timings.uiRequest.thresholdP95Ms `
        -Label 'timings.uiRequest.thresholdP95Ms'
    Assert-ContractEqual $uiThreshold 4.0 `
        'timings.uiRequest.thresholdP95Ms'
    $freshThreshold = ConvertTo-NonNegativeFiniteDouble `
        -Value $Report.timings.warmedFreshBake.thresholdP95Ms `
        -Label 'timings.warmedFreshBake.thresholdP95Ms'
    Assert-ContractEqual $freshThreshold 100.0 `
        'timings.warmedFreshBake.thresholdP95Ms'
    $warmThreshold = ConvertTo-NonNegativeFiniteDouble `
        -Value $Report.timings.warmCacheLookup.thresholdP95Ms `
        -Label 'timings.warmCacheLookup.thresholdP95Ms'
    Assert-ContractEqual $warmThreshold 1.0 `
        'timings.warmCacheLookup.thresholdP95Ms'

    $coldResultGate = Get-ContractGate `
        -Gates $Gates `
        -Id 'cold_queue_result' `
        -Phase 'pipeline_request' `
        -Comparison 'equals' `
        -Unit 'request'
    Assert-ContractEqual `
        (ConvertTo-ExactInt64 `
            -Value $coldResultGate.actual `
            -Label 'cold_queue_result.actual' -NonNegative) `
        4L 'cold_queue_result.actual'
    Assert-ContractEqual `
        (ConvertTo-ExactInt64 `
            -Value $coldResultGate.expected `
            -Label 'cold_queue_result.expected' -NonNegative) `
        4L 'cold_queue_result.expected'

    $warmResultGate = Get-ContractGate `
        -Gates $Gates `
        -Id 'warm_inactive_cache_result' `
        -Phase 'pipeline_request' `
        -Comparison 'equals' `
        -Unit 'request'
    Assert-ContractEqual `
        (ConvertTo-ExactInt64 `
            -Value $warmResultGate.actual `
            -Label 'warm_inactive_cache_result.actual' -NonNegative) `
        4L 'warm_inactive_cache_result.actual'
    Assert-ContractEqual `
        (ConvertTo-ExactInt64 `
            -Value $warmResultGate.expected `
            -Label 'warm_inactive_cache_result.expected' -NonNegative) `
        4L 'warm_inactive_cache_result.expected'

    $steadyResultGate = Get-ContractGate `
        -Gates $Gates `
        -Id 'steady_current_hit_result' `
        -Phase 'pipeline_request' `
        -Comparison 'equals' `
        -Unit 'request'
    Assert-ContractEqual `
        (ConvertTo-ExactInt64 `
            -Value $steadyResultGate.actual `
            -Label 'steady_current_hit_result.actual' -NonNegative) `
        3000L 'steady_current_hit_result.actual'
    Assert-ContractEqual `
        (ConvertTo-ExactInt64 `
            -Value $steadyResultGate.expected `
            -Label 'steady_current_hit_result.expected' -NonNegative) `
        3000L 'steady_current_hit_result.expected'

    Assert-UpperBoundGate `
        -Gates $Gates `
        -Id 'ui_request_cold_queue_p95' `
        -Phase 'ui_request_cold_queue' `
        -Unit 'ms' `
        -Actual ([double]$coldSummary.P95) `
        -Expected 4.0
    Assert-UpperBoundGate `
        -Gates $Gates `
        -Id 'ui_request_warm_cache_p95' `
        -Phase 'ui_request_warm_cache' `
        -Unit 'ms' `
        -Actual ([double]$warmSummary.P95) `
        -Expected 4.0
    Assert-UpperBoundGate `
        -Gates $Gates `
        -Id 'ui_request_pending_coalescing_p95' `
        -Phase 'ui_request_pending_coalescing' `
        -Unit 'ms' `
        -Actual ([double]$pendingSummary.P95) `
        -Expected 4.0
    Assert-UpperBoundGate `
        -Gates $Gates `
        -Id 'ui_request_steady_current_hit_p95' `
        -Phase 'ui_request_steady' `
        -Unit 'ms' `
        -Actual ([double]$steadySummary.P95) `
        -Expected 4.0
    foreach ($viewportId in $ViewportIds) {
        Assert-UpperBoundGate `
            -Gates $Gates `
            -Id "warmed_fresh_bake_p95_$viewportId" `
            -Phase 'warmed_fresh_bake' `
            -Unit 'ms' `
            -Actual ([double]$freshByViewport[$viewportId].P95) `
            -Expected 100.0
    }
    Assert-UpperBoundGate `
        -Gates $Gates `
        -Id 'warm_cache_lookup_p95' `
        -Phase 'warm_cache_lookup' `
        -Unit 'ms' `
        -Actual ([double]$warmSummary.P95) `
        -Expected 1.0
}

function Test-AndVerifyViewportContract {
    param(
        [Parameter(Mandatory)]$Report,
        [Parameter(Mandatory)]$Gates,
        [Parameter(Mandatory)][string[]]$ViewportIds
    )

    $expectedCases = @(
        [pscustomobject]@{
            Id = $ViewportIds[0]
            Host = @(0, 0, 1024, 576)
            Content = @(0, 0, 1024, 576)
            Dpi = 1.0
            Scale = 1.0
            Stage = @(0, 512, 1024, 64)
            Tight = @(0, 474, 282, 81)
            Letterbox = $false
            LetterboxTop = 0
            LetterboxBottom = 0
        }
        [pscustomobject]@{
            Id = $ViewportIds[1]
            Host = @(0, 0, 1600, 900)
            Content = @(0, 0, 1600, 900)
            Dpi = 1.25
            Scale = 1.5625
            Stage = @(0, 800, 1600, 100)
            Tight = @(0, 741, 440, 126)
            Letterbox = $false
            LetterboxTop = 0
            LetterboxBottom = 0
        }
        [pscustomobject]@{
            Id = $ViewportIds[2]
            Host = @(0, 0, 1920, 1080)
            Content = @(0, 0, 1920, 1080)
            Dpi = 1.50
            Scale = 1.875
            Stage = @(0, 960, 1920, 120)
            Tight = @(0, 890, 528, 150)
            Letterbox = $false
            LetterboxTop = 0
            LetterboxBottom = 0
        }
        [pscustomobject]@{
            Id = $ViewportIds[3]
            Host = @(0, 0, 1280, 960)
            Content = @(0, 120, 1280, 720)
            Dpi = 1.75
            Scale = 1.25
            Stage = @(0, 760, 1280, 80)
            Tight = @(0, 713, 352, 101)
            Letterbox = $true
            LetterboxTop = 120
            LetterboxBottom = 120
        }
    )
    [string[]]$layerIds = @(
        'mp.backplate',
        'mp.fill',
        'mp.rim',
        'mp.rim-vf70',
        'mp.rim-vf91',
        'hp.backplate',
        'hp.fill',
        'hp.rim')

    $rows = @($Report.visualMatrix)
    Assert-ExactStringSequence `
        -Actual @($rows | ForEach-Object { [string]$_.id }) `
        -Expected $ViewportIds `
        -Label 'visualMatrix viewport order'
    for ($index = 0; $index -lt $expectedCases.Count; $index++) {
        $expected = $expectedCases[$index]
        $row = $rows[$index]
        Assert-ExactPropertySet `
            -Value $row `
            -Expected @(
                'id',
                'hostViewport',
                'contentViewport',
                'monitorDpiScale',
                'physicalScale',
                'stagePhysicalBounds',
                'tightPhysicalBounds',
                'letterbox',
                'batchKey',
                'layers') `
            -Label "visualMatrix.$($expected.Id) properties"
        Assert-RectangleContract `
            -Rectangle $row.hostViewport `
            -X $expected.Host[0] `
            -Y $expected.Host[1] `
            -Width $expected.Host[2] `
            -Height $expected.Host[3] `
            -Label "visualMatrix.$($expected.Id).hostViewport"
        Assert-RectangleContract `
            -Rectangle $row.contentViewport `
            -X $expected.Content[0] `
            -Y $expected.Content[1] `
            -Width $expected.Content[2] `
            -Height $expected.Content[3] `
            -Label "visualMatrix.$($expected.Id).contentViewport"
        Assert-RectangleContract `
            -Rectangle $row.stagePhysicalBounds `
            -X $expected.Stage[0] `
            -Y $expected.Stage[1] `
            -Width $expected.Stage[2] `
            -Height $expected.Stage[3] `
            -Label "visualMatrix.$($expected.Id).stagePhysicalBounds"
        Assert-RectangleContract `
            -Rectangle $row.tightPhysicalBounds `
            -X $expected.Tight[0] `
            -Y $expected.Tight[1] `
            -Width $expected.Tight[2] `
            -Height $expected.Tight[3] `
            -Label "visualMatrix.$($expected.Id).tightPhysicalBounds"
        $dpi = ConvertTo-NonNegativeFiniteDouble `
            -Value $row.monitorDpiScale `
            -Label "visualMatrix.$($expected.Id).monitorDpiScale"
        $scale = ConvertTo-NonNegativeFiniteDouble `
            -Value $row.physicalScale `
            -Label "visualMatrix.$($expected.Id).physicalScale"
        Assert-ContractEqual $dpi ([double]$expected.Dpi) `
            "visualMatrix.$($expected.Id).monitorDpiScale"
        Assert-ContractEqual $scale ([double]$expected.Scale) `
            "visualMatrix.$($expected.Id).physicalScale"

        Assert-ExactPropertySet `
            -Value $row.letterbox `
            -Expected @('present', 'topPixels', 'bottomPixels') `
            -Label "visualMatrix.$($expected.Id).letterbox properties"
        Assert-ContractEqual $row.letterbox.present $expected.Letterbox `
            "visualMatrix.$($expected.Id).letterbox.present"
        Assert-ContractEqual `
            (ConvertTo-ExactInt64 `
                -Value $row.letterbox.topPixels `
                -Label "visualMatrix.$($expected.Id).letterbox.topPixels" `
                -NonNegative) `
            ([long]$expected.LetterboxTop) `
            "visualMatrix.$($expected.Id).letterbox.topPixels"
        Assert-ContractEqual `
            (ConvertTo-ExactInt64 `
                -Value $row.letterbox.bottomPixels `
                -Label "visualMatrix.$($expected.Id).letterbox.bottomPixels" `
                -NonNegative) `
            ([long]$expected.LetterboxBottom) `
            "visualMatrix.$($expected.Id).letterbox.bottomPixels"
        if ([string]::IsNullOrEmpty([string]$row.batchKey)) {
            throw "visualMatrix.$($expected.Id).batchKey is empty."
        }

        $layers = @($row.layers)
        Assert-ExactStringSequence `
            -Actual @($layers | ForEach-Object { [string]$_.layerId }) `
            -Expected $layerIds `
            -Label "visualMatrix.$($expected.Id).layers"
        foreach ($layer in $layers) {
            Assert-ExactPropertySet `
                -Value $layer `
                -Expected @(
                    'layerId',
                    'pixelWidth',
                    'pixelHeight',
                    'physicalBounds',
                    'key') `
                -Label (
                    "visualMatrix.$($expected.Id).$($layer.layerId) " +
                    'properties')
            $pixelWidth = ConvertTo-ExactInt64 `
                -Value $layer.pixelWidth `
                -Label (
                    "visualMatrix.$($expected.Id).$($layer.layerId)." +
                    'pixelWidth') `
                -NonNegative
            $pixelHeight = ConvertTo-ExactInt64 `
                -Value $layer.pixelHeight `
                -Label (
                    "visualMatrix.$($expected.Id).$($layer.layerId)." +
                    'pixelHeight') `
                -NonNegative
            if ($pixelWidth -le 0 -or $pixelHeight -le 0) {
                throw (
                    "visualMatrix.$($expected.Id).$($layer.layerId) " +
                    'has non-positive dimensions.')
            }
            Assert-ContractEqual `
                (ConvertTo-ExactInt64 `
                    -Value $layer.physicalBounds.width `
                    -Label (
                        "visualMatrix.$($expected.Id).$($layer.layerId)." +
                        'physicalBounds.width') `
                    -NonNegative) `
                $pixelWidth `
                "visualMatrix.$($expected.Id).$($layer.layerId).width"
            Assert-ContractEqual `
                (ConvertTo-ExactInt64 `
                    -Value $layer.physicalBounds.height `
                    -Label (
                        "visualMatrix.$($expected.Id).$($layer.layerId)." +
                        'physicalBounds.height') `
                    -NonNegative) `
                $pixelHeight `
                "visualMatrix.$($expected.Id).$($layer.layerId).height"
            Assert-ExactPropertySet `
                -Value $layer.key `
                -Expected @(
                    'assetSetRevision',
                    'exactManifestSha256',
                    'layerId',
                    'pixelWidth',
                    'pixelHeight',
                    'sourceToBitmapIdentity',
                    'rendererIdentity',
                    'rasterContractVersion') `
                -Label (
                    "visualMatrix.$($expected.Id).$($layer.layerId).key " +
                    'properties')
            Assert-ContractEqual ([string]$layer.key.assetSetRevision) `
                ([string]$Report.asset.assetSetRevision) `
                "visualMatrix.$($expected.Id).$($layer.layerId).revision"
            Assert-ContractEqual ([string]$layer.key.exactManifestSha256) `
                ([string]$Report.asset.exactManifestSha256) `
                "visualMatrix.$($expected.Id).$($layer.layerId).manifest"
            Assert-ContractEqual ([string]$layer.key.layerId) `
                ([string]$layer.layerId) `
                "visualMatrix.$($expected.Id).$($layer.layerId).key.layerId"
            Assert-ContractEqual `
                (ConvertTo-ExactInt64 `
                    -Value $layer.key.pixelWidth `
                    -Label (
                        "visualMatrix.$($expected.Id).$($layer.layerId)." +
                        'key.pixelWidth') `
                    -NonNegative) `
                $pixelWidth `
                "visualMatrix.$($expected.Id).$($layer.layerId).key.pixelWidth"
            Assert-ContractEqual `
                (ConvertTo-ExactInt64 `
                    -Value $layer.key.pixelHeight `
                    -Label (
                        "visualMatrix.$($expected.Id).$($layer.layerId)." +
                        'key.pixelHeight') `
                    -NonNegative) `
                $pixelHeight `
                "visualMatrix.$($expected.Id).$($layer.layerId).key.pixelHeight"
            $sourceToBitmapIdentity =
                [string]$layer.key.sourceToBitmapIdentity
            if (-not [regex]::IsMatch(
                    $sourceToBitmapIdentity,
                    '^[0-9A-F]{16}(?::[0-9A-F]{16}){3}$',
                    [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)) {
                throw (
                    "visualMatrix.$($expected.Id).$($layer.layerId)." +
                    'key.sourceToBitmapIdentity is not four exact double bit patterns.')
            }
            Assert-ContractEqual ([string]$layer.key.rendererIdentity) `
                ([string]$Report.renderer.cacheIdentity) `
                "visualMatrix.$($expected.Id).$($layer.layerId).renderer"
            Assert-ContractEqual `
                (ConvertTo-ExactInt64 `
                    -Value $layer.key.rasterContractVersion `
                    -Label (
                        "visualMatrix.$($expected.Id).$($layer.layerId)." +
                        'key.rasterContractVersion') `
                    -NonNegative) `
                ([long]$Report.asset.rasterContractVersion) `
                (
                    "visualMatrix.$($expected.Id).$($layer.layerId)." +
                    'key.rasterContractVersion')
        }

        $physicalGateId = "physical_scale_$($expected.Id)"
        $physicalGate = Get-ContractGate `
            -Gates $Gates `
            -Id $physicalGateId `
            -Phase 'viewport_contract' `
            -Comparison 'equals' `
            -Unit 'physical_scale'
        Assert-ContractEqual `
            (ConvertTo-NonNegativeFiniteDouble `
                -Value $physicalGate.actual `
                -Label "$physicalGateId.actual") `
            ([double]$expected.Scale) "$physicalGateId.actual"
        Assert-ContractEqual `
            (ConvertTo-NonNegativeFiniteDouble `
                -Value $physicalGate.expected `
                -Label "$physicalGateId.expected") `
            ([double]$expected.Scale) "$physicalGateId.expected"

        $dpiGateId = "dpi_telemetry_only_$($expected.Id)"
        $dpiGate = Get-ContractGate `
            -Gates $Gates `
            -Id $dpiGateId `
            -Phase 'viewport_contract' `
            -Comparison 'equals' `
            -Unit 'key_and_geometry'
        foreach ($gateValue in @($dpiGate.actual, $dpiGate.expected)) {
            Assert-ExactPropertySet `
                -Value $gateValue `
                -Expected @('batchKey', 'stage') `
                -Label "$dpiGateId key_and_geometry properties"
            Assert-ContractEqual ([string]$gateValue.batchKey) `
                ([string]$row.batchKey) "$dpiGateId.batchKey"
            Assert-JsonEquivalent `
                -Actual $gateValue.stage `
                -Expected $row.stagePhysicalBounds `
                -Label "$dpiGateId.stage"
        }
    }
}

function Test-AndVerifyPipelineContract {
    param(
        [Parameter(Mandatory)]$Report,
        [Parameter(Mandatory)]$Gates
    )

    [string[]]$counterProperties = @(
        'generation',
        'requestCount',
        'publishCount',
        'cacheHitCount',
        'currentLayerHitCount',
        'cacheLayerHitCount',
        'parseCount',
        'rasterCount',
        'activeWorkers',
        'maxConcurrentWorkers',
        'pendingReplacementCount',
        'staleDiscardCount',
        'faultCount',
        'cancelCount',
        'disposedBatchCount',
        'disposedLayerCount',
        'cacheBytes',
        'cacheCount',
        'desiredBatchKey',
        'currentBatchKey',
        'lastFault')
    [string[]]$numericCounterProperties = @(
        $counterProperties | Where-Object {
            $_ -notin @('desiredBatchKey', 'currentBatchKey', 'lastFault')
        })
    $snapshots = $Report.raster.pipelineCounters
    foreach ($snapshotName in @(
            'afterCold',
            'afterWarm',
            'afterPendingCoalescing',
            'beforeSteady',
            'afterSteady',
            'afterDispose')) {
        $snapshot = $snapshots.$snapshotName
        Assert-ExactPropertySet `
            -Value $snapshot `
            -Expected $counterProperties `
            -Label "raster.pipelineCounters.$snapshotName properties"
        foreach ($property in $numericCounterProperties) {
            $null = ConvertTo-ExactInt64 `
                -Value $snapshot.$property `
                -Label "raster.pipelineCounters.$snapshotName.$property" `
                -NonNegative
        }
        if ($null -ne $snapshot.lastFault -and
            $snapshot.lastFault -isnot [string]) {
            throw "raster.pipelineCounters.$snapshotName.lastFault is invalid."
        }
    }

    $afterCold = $snapshots.afterCold
    $afterWarm = $snapshots.afterWarm
    $afterPending = $snapshots.afterPendingCoalescing
    $beforeSteady = $snapshots.beforeSteady
    $afterSteady = $snapshots.afterSteady
    $afterDispose = $snapshots.afterDispose

    $coldExpected = [ordered]@{
        generation = 4
        requestCount = 4
        publishCount = 4
        cacheHitCount = 0
        currentLayerHitCount = 0
        cacheLayerHitCount = 0
        parseCount = 32
        rasterCount = 32
        activeWorkers = 0
        maxConcurrentWorkers = 1
        faultCount = 0
        disposedBatchCount = 0
        disposedLayerCount = 0
        cacheCount = 4
    }
    foreach ($entry in $coldExpected.GetEnumerator()) {
        Assert-ContractEqual `
            (ConvertTo-ExactInt64 `
                -Value $afterCold.($entry.Key) `
                -Label "pipeline.afterCold.$($entry.Key)" `
                -NonNegative) `
            ([long]$entry.Value) "pipeline.afterCold.$($entry.Key)"
    }
    if ([string]::IsNullOrEmpty([string]$afterCold.currentBatchKey)) {
        throw 'pipeline.afterCold.currentBatchKey is empty.'
    }
    Assert-ContractEqual ([string]$afterCold.desiredBatchKey) `
        ([string]$afterCold.currentBatchKey) `
        'pipeline.afterCold desired/current key'

    $warmExpected = [ordered]@{
        generation = 8
        requestCount = 8
        publishCount = 8
        cacheHitCount = 4
        currentLayerHitCount = 0
        cacheLayerHitCount = 32
        parseCount = 32
        rasterCount = 32
        activeWorkers = 0
        maxConcurrentWorkers = 1
        faultCount = 0
        disposedBatchCount = 0
        disposedLayerCount = 0
        cacheCount = 4
    }
    foreach ($entry in $warmExpected.GetEnumerator()) {
        Assert-ContractEqual `
            (ConvertTo-ExactInt64 `
                -Value $afterWarm.($entry.Key) `
                -Label "pipeline.afterWarm.$($entry.Key)" `
                -NonNegative) `
            ([long]$entry.Value) "pipeline.afterWarm.$($entry.Key)"
    }
    Assert-ContractEqual ([string]$afterWarm.desiredBatchKey) `
        ([string]$afterWarm.currentBatchKey) `
        'pipeline.afterWarm desired/current key'

    Assert-ContractEqual `
        (ConvertTo-ExactInt64 `
            -Value $afterPending.generation `
            -Label 'pipeline.afterPending.generation' -NonNegative) `
        108L 'pipeline.afterPending.generation'
    Assert-ContractEqual `
        (ConvertTo-ExactInt64 `
            -Value $afterPending.requestCount `
            -Label 'pipeline.afterPending.requestCount' -NonNegative) `
        108L 'pipeline.afterPending.requestCount'
    Assert-ContractEqual `
        (ConvertTo-ExactInt64 `
            -Value $afterPending.activeWorkers `
            -Label 'pipeline.afterPending.activeWorkers' -NonNegative) `
        0L 'pipeline.afterPending.activeWorkers'
    Assert-ContractEqual `
        (ConvertTo-ExactInt64 `
            -Value $afterPending.maxConcurrentWorkers `
            -Label 'pipeline.afterPending.maxConcurrentWorkers' -NonNegative) `
        1L 'pipeline.afterPending.maxConcurrentWorkers'
    Assert-ContractEqual `
        (ConvertTo-ExactInt64 `
            -Value $afterPending.faultCount `
            -Label 'pipeline.afterPending.faultCount' -NonNegative) `
        0L 'pipeline.afterPending.faultCount'
    Assert-ContractEqual ([string]$afterPending.desiredBatchKey) `
        ([string]$afterPending.currentBatchKey) `
        'pipeline.afterPending desired/current key'
    Assert-JsonEquivalent `
        -Actual $beforeSteady `
        -Expected $afterPending `
        -Label 'pipeline beforeSteady/afterPending'

    $steadyExpected = [ordered]@{
        generation = 3108
        requestCount = 3108
        activeWorkers = 0
        maxConcurrentWorkers = 1
        faultCount = 0
    }
    foreach ($entry in $steadyExpected.GetEnumerator()) {
        Assert-ContractEqual `
            (ConvertTo-ExactInt64 `
                -Value $afterSteady.($entry.Key) `
                -Label "pipeline.afterSteady.$($entry.Key)" `
                -NonNegative) `
            ([long]$entry.Value) "pipeline.afterSteady.$($entry.Key)"
    }
    foreach ($property in @(
            'publishCount',
            'cacheHitCount',
            'cacheLayerHitCount',
            'parseCount',
            'rasterCount',
            'pendingReplacementCount',
            'staleDiscardCount',
            'faultCount',
            'cancelCount',
            'disposedBatchCount',
            'disposedLayerCount',
            'cacheBytes',
            'cacheCount')) {
        Assert-ContractEqual `
            (ConvertTo-ExactInt64 `
                -Value $afterSteady.$property `
                -Label "pipeline.afterSteady.$property" `
                -NonNegative) `
            (ConvertTo-ExactInt64 `
                -Value $beforeSteady.$property `
                -Label "pipeline.beforeSteady.$property" `
                -NonNegative) `
            "pipeline steady invariant $property"
    }
    $currentLayerDelta =
        (ConvertTo-ExactInt64 `
            -Value $afterSteady.currentLayerHitCount `
            -Label 'pipeline.afterSteady.currentLayerHitCount' -NonNegative) -
        (ConvertTo-ExactInt64 `
            -Value $beforeSteady.currentLayerHitCount `
            -Label 'pipeline.beforeSteady.currentLayerHitCount' -NonNegative)
    Assert-ContractEqual $currentLayerDelta 24000L `
        'pipeline steady current-layer hit delta'
    Assert-ContractEqual ([string]$afterSteady.desiredBatchKey) `
        ([string]$beforeSteady.desiredBatchKey) `
        'pipeline steady desired key'
    Assert-ContractEqual ([string]$afterSteady.currentBatchKey) `
        ([string]$beforeSteady.currentBatchKey) `
        'pipeline steady current key'

    $steadyParseDelta =
        (ConvertTo-ExactInt64 `
            -Value $afterSteady.parseCount `
            -Label 'pipeline.afterSteady.parseCount' -NonNegative) -
        (ConvertTo-ExactInt64 `
            -Value $beforeSteady.parseCount `
            -Label 'pipeline.beforeSteady.parseCount' -NonNegative)
    $steadyRasterDelta =
        (ConvertTo-ExactInt64 `
            -Value $afterSteady.rasterCount `
            -Label 'pipeline.afterSteady.rasterCount' -NonNegative) -
        (ConvertTo-ExactInt64 `
            -Value $beforeSteady.rasterCount `
            -Label 'pipeline.beforeSteady.rasterCount' -NonNegative)
    $steadyPublishDelta =
        (ConvertTo-ExactInt64 `
            -Value $afterSteady.publishCount `
            -Label 'pipeline.afterSteady.publishCount' -NonNegative) -
        (ConvertTo-ExactInt64 `
            -Value $beforeSteady.publishCount `
            -Label 'pipeline.beforeSteady.publishCount' -NonNegative)
    Assert-ContractEqual `
        (ConvertTo-ExactInt64 `
            -Value $Report.raster.steady3000.requestCount `
            -Label 'raster.steady3000.requestCount' -NonNegative) `
        3000L 'raster.steady3000.requestCount'
    foreach ($entry in ([ordered]@{
            parseDelta = $steadyParseDelta
            rasterDelta = $steadyRasterDelta
            publishDelta = $steadyPublishDelta
        }).GetEnumerator()) {
        Assert-ContractEqual `
            (ConvertTo-ExactInt64 `
                -Value $Report.raster.steady3000.($entry.Key) `
                -Label "raster.steady3000.$($entry.Key)") `
            ([long]$entry.Value) "raster.steady3000.$($entry.Key)"
        Assert-ContractEqual ([long]$entry.Value) 0L `
            "raster.steady3000.$($entry.Key) frozen"
    }

    Assert-ContractEqual `
        (ConvertTo-ExactInt64 `
            -Value $afterDispose.generation `
            -Label 'pipeline.afterDispose.generation' -NonNegative) `
        ((ConvertTo-ExactInt64 `
            -Value $afterSteady.generation `
            -Label 'pipeline.afterSteady.generation' -NonNegative) + 1L) `
        'pipeline dispose generation'
    foreach ($property in @(
            'requestCount',
            'publishCount',
            'cacheHitCount',
            'currentLayerHitCount',
            'cacheLayerHitCount',
            'parseCount',
            'rasterCount',
            'maxConcurrentWorkers',
            'pendingReplacementCount',
            'staleDiscardCount',
            'faultCount',
            'cancelCount')) {
        Assert-ContractEqual `
            (ConvertTo-ExactInt64 `
                -Value $afterDispose.$property `
                -Label "pipeline.afterDispose.$property" -NonNegative) `
            (ConvertTo-ExactInt64 `
                -Value $afterSteady.$property `
                -Label "pipeline.afterSteady.$property" -NonNegative) `
            "pipeline dispose invariant $property"
    }
    $disposedBatchCount = ConvertTo-ExactInt64 `
        -Value $afterDispose.disposedBatchCount `
        -Label 'pipeline.afterDispose.disposedBatchCount' -NonNegative
    $disposedLayerCount = ConvertTo-ExactInt64 `
        -Value $afterDispose.disposedLayerCount `
        -Label 'pipeline.afterDispose.disposedLayerCount' -NonNegative
    if ($disposedBatchCount -le 0) {
        throw 'pipeline.afterDispose.disposedBatchCount must be positive.'
    }
    Assert-ContractEqual $disposedLayerCount `
        ($disposedBatchCount * 8L) `
        'pipeline.afterDispose disposed layer multiplier'
    foreach ($property in @('cacheBytes', 'cacheCount', 'activeWorkers')) {
        Assert-ContractEqual `
            (ConvertTo-ExactInt64 `
                -Value $afterDispose.$property `
                -Label "pipeline.afterDispose.$property" -NonNegative) `
            0L "pipeline.afterDispose.$property"
    }
    Assert-ContractEqual $afterDispose.desiredBatchKey $null `
        'pipeline.afterDispose.desiredBatchKey'
    Assert-ContractEqual $afterDispose.currentBatchKey $null `
        'pipeline.afterDispose.currentBatchKey'

    Assert-ExactPropertySet `
        -Value $Report.cache `
        -Expected @(
            'budgetBytes',
            'peakBytes',
            'finalLiveBytesBeforeDispose',
            'finalLiveBatchCountBeforeDispose',
            'bytesAfterDispose',
            'batchesAfterDispose',
            'inactiveBatchHitCount',
            'inactiveLayerHitCount',
            'currentLayerHitCount') `
        -Label 'cache properties'
    $cacheBudget = ConvertTo-ExactInt64 `
        -Value $Report.cache.budgetBytes `
        -Label 'cache.budgetBytes' -NonNegative
    $cachePeak = ConvertTo-ExactInt64 `
        -Value $Report.cache.peakBytes `
        -Label 'cache.peakBytes' -NonNegative
    Assert-ContractEqual $cacheBudget 16777216L 'cache.budgetBytes'
    [long[]]$observedSnapshotCacheBytes = @(
        (ConvertTo-ExactInt64 `
            -Value $afterCold.cacheBytes `
            -Label 'pipeline.afterCold.cacheBytes' -NonNegative)
        (ConvertTo-ExactInt64 `
            -Value $afterWarm.cacheBytes `
            -Label 'pipeline.afterWarm.cacheBytes' -NonNegative)
        (ConvertTo-ExactInt64 `
            -Value $afterPending.cacheBytes `
            -Label 'pipeline.afterPending.cacheBytes' -NonNegative)
        (ConvertTo-ExactInt64 `
            -Value $beforeSteady.cacheBytes `
            -Label 'pipeline.beforeSteady.cacheBytes' -NonNegative)
        (ConvertTo-ExactInt64 `
            -Value $afterSteady.cacheBytes `
            -Label 'pipeline.afterSteady.cacheBytes' -NonNegative)
    )
    [System.Array]::Sort($observedSnapshotCacheBytes)
    $recomputedCachePeak =
        $observedSnapshotCacheBytes[$observedSnapshotCacheBytes.Count - 1]
    Assert-ContractEqual $cachePeak $recomputedCachePeak `
        'cache.peakBytes from observed pipeline snapshots'
    Assert-ContractEqual `
        (ConvertTo-ExactInt64 `
            -Value $Report.cache.finalLiveBytesBeforeDispose `
            -Label 'cache.finalLiveBytesBeforeDispose' -NonNegative) `
        ([long]$afterSteady.cacheBytes) `
        'cache.finalLiveBytesBeforeDispose'
    Assert-ContractEqual `
        (ConvertTo-ExactInt64 `
            -Value $Report.cache.finalLiveBatchCountBeforeDispose `
            -Label 'cache.finalLiveBatchCountBeforeDispose' -NonNegative) `
        ([long]$afterSteady.cacheCount) `
        'cache.finalLiveBatchCountBeforeDispose'
    Assert-ContractEqual `
        (ConvertTo-ExactInt64 `
            -Value $Report.cache.bytesAfterDispose `
            -Label 'cache.bytesAfterDispose' -NonNegative) `
        ([long]$afterDispose.cacheBytes) 'cache.bytesAfterDispose'
    Assert-ContractEqual `
        (ConvertTo-ExactInt64 `
            -Value $Report.cache.batchesAfterDispose `
            -Label 'cache.batchesAfterDispose' -NonNegative) `
        ([long]$afterDispose.cacheCount) 'cache.batchesAfterDispose'
    foreach ($mapping in @(
            @('inactiveBatchHitCount', 'cacheHitCount'),
            @('inactiveLayerHitCount', 'cacheLayerHitCount'),
            @('currentLayerHitCount', 'currentLayerHitCount'))) {
        Assert-ContractEqual `
            (ConvertTo-ExactInt64 `
                -Value $Report.cache.($mapping[0]) `
                -Label "cache.$($mapping[0])" -NonNegative) `
            ([long]$afterSteady.($mapping[1])) "cache.$($mapping[0])"
    }
    Assert-ExactPropertySet `
        -Value $Report.lifecycle `
        -Expected @(
            'generation',
            'pendingReplacementCount',
            'cancelCount',
            'staleDiscardCount',
            'faultCount',
            'lastFault',
            'disposedBatchCount',
            'disposedLayerCount',
            'ownership') `
        -Label 'lifecycle properties'
    foreach ($property in @(
            'generation',
            'pendingReplacementCount',
            'cancelCount',
            'staleDiscardCount',
            'faultCount',
            'disposedBatchCount',
            'disposedLayerCount')) {
        Assert-ContractEqual `
            (ConvertTo-ExactInt64 `
                -Value $Report.lifecycle.$property `
                -Label "lifecycle.$property" -NonNegative) `
            ([long]$afterDispose.$property) "lifecycle.$property"
    }
    Assert-ContractEqual $Report.lifecycle.lastFault `
        $afterDispose.lastFault 'lifecycle.lastFault'
    Assert-ContractEqual ([string]$Report.lifecycle.ownership) `
        'atomic private eight-layer batch' 'lifecycle.ownership'

    $layerActivity = @($Report.raster.layerActivity)
    [string[]]$layerIds = @(
        'hp.backplate',
        'hp.fill',
        'hp.rim',
        'mp.backplate',
        'mp.fill',
        'mp.rim',
        'mp.rim-vf70',
        'mp.rim-vf91')
    Assert-ExactStringSequence `
        -Actual @($layerActivity | ForEach-Object {
            [string]$_.layerId
        }) `
        -Expected $layerIds `
        -Label 'raster.layerActivity order'
    $parseSum = 0L
    $rasterSum = 0L
    foreach ($layer in $layerActivity) {
        Assert-ExactPropertySet `
            -Value $layer `
            -Expected @(
                'layerId',
                'desiredGenerationCount',
                'parseCount',
                'rasterCount',
                'currentHitCount',
                'inactiveCacheHitCount',
                'inferredBatchDisposalCount') `
            -Label "raster.layerActivity.$($layer.layerId) properties"
        Assert-ContractEqual `
            (ConvertTo-ExactInt64 `
                -Value $layer.desiredGenerationCount `
                -Label "$($layer.layerId).desiredGenerationCount" `
                -NonNegative) `
            3108L "$($layer.layerId).desiredGenerationCount"
        Assert-ContractEqual `
            (ConvertTo-ExactInt64 `
                -Value $layer.currentHitCount `
                -Label "$($layer.layerId).currentHitCount" -NonNegative) `
            3000L "$($layer.layerId).currentHitCount"
        Assert-ContractEqual `
            (ConvertTo-ExactInt64 `
                -Value $layer.inactiveCacheHitCount `
                -Label "$($layer.layerId).inactiveCacheHitCount" -NonNegative) `
            4L "$($layer.layerId).inactiveCacheHitCount"
        Assert-ContractEqual `
            (ConvertTo-ExactInt64 `
                -Value $layer.inferredBatchDisposalCount `
                -Label "$($layer.layerId).inferredBatchDisposalCount" `
                -NonNegative) `
            $disposedBatchCount `
            "$($layer.layerId).inferredBatchDisposalCount"
        $parseSum += ConvertTo-ExactInt64 `
            -Value $layer.parseCount `
            -Label "$($layer.layerId).parseCount" -NonNegative
        $rasterSum += ConvertTo-ExactInt64 `
            -Value $layer.rasterCount `
            -Label "$($layer.layerId).rasterCount" -NonNegative
    }
    Assert-ContractEqual $parseSum ([long]$afterSteady.parseCount) `
        'raster.layerActivity parse sum'
    Assert-ContractEqual $rasterSum ([long]$afterSteady.rasterCount) `
        'raster.layerActivity raster sum'

    Assert-UpperBoundGate `
        -Gates $Gates `
        -Id 'cache_budget' `
        -Phase 'cache' `
        -Unit 'bytes' `
        -Actual ([double][math]::Max(
            $cachePeak,
            [long]$afterSteady.cacheBytes)) `
        -Expected ([double]$cacheBudget)

    $steadyGate = Get-ContractGate `
        -Gates $Gates `
        -Id 'steady_3000_zero_parse_raster_publish' `
        -Phase 'steady' `
        -Comparison 'equals' `
        -Unit 'layer_or_batch_count'
    foreach ($gateValue in @($steadyGate.actual, $steadyGate.expected)) {
        Assert-ExactPropertySet `
            -Value $gateValue `
            -Expected @('parseDelta', 'rasterDelta', 'publishDelta') `
            -Label 'steady_3000 gate value properties'
        foreach ($property in @(
                'parseDelta', 'rasterDelta', 'publishDelta')) {
            Assert-ContractEqual `
                (ConvertTo-ExactInt64 `
                    -Value $gateValue.$property `
                    -Label "steady_3000.$property") `
                0L "steady_3000.$property"
        }
    }

    $singleWorkerGate = Get-ContractGate `
        -Gates $Gates `
        -Id 'single_worker' `
        -Phase 'pipeline_lifecycle' `
        -Comparison 'equals' `
        -Unit 'worker'
    Assert-ContractEqual `
        (ConvertTo-ExactInt64 `
            -Value $singleWorkerGate.actual `
            -Label 'single_worker.actual' -NonNegative) `
        ([long]$afterSteady.maxConcurrentWorkers) 'single_worker.actual'
    Assert-ContractEqual `
        (ConvertTo-ExactInt64 `
            -Value $singleWorkerGate.expected `
            -Label 'single_worker.expected' -NonNegative) `
        1L 'single_worker.expected'

    $faultGate = Get-ContractGate `
        -Gates $Gates `
        -Id 'fault_free' `
        -Phase 'pipeline_lifecycle' `
        -Comparison 'equals' `
        -Unit 'fault'
    foreach ($gateValue in @($faultGate.actual, $faultGate.expected)) {
        Assert-ExactPropertySet `
            -Value $gateValue `
            -Expected @('faultCount', 'lastFault') `
            -Label 'fault_free gate value properties'
        Assert-ContractEqual `
            (ConvertTo-ExactInt64 `
                -Value $gateValue.faultCount `
                -Label 'fault_free.faultCount' -NonNegative) `
            0L 'fault_free.faultCount'
        Assert-ContractEqual $gateValue.lastFault $null 'fault_free.lastFault'
    }

    $pendingGate = Get-ContractGate `
        -Gates $Gates `
        -Id 'pending_coalescing_latest_wins' `
        -Phase 'pending_coalescing' `
        -Comparison 'equals' `
        -Unit 'batch_key'
    Assert-ContractEqual ([string]$pendingGate.actual) `
        ([string]$afterPending.currentBatchKey) `
        'pending_coalescing_latest_wins.actual'
    Assert-ContractEqual ([string]$pendingGate.expected) `
        ([string]$afterPending.desiredBatchKey) `
        'pending_coalescing_latest_wins.expected'

    $disposeGate = Get-ContractGate `
        -Gates $Gates `
        -Id 'pipeline_dispose_returns_to_zero' `
        -Phase 'pipeline_lifecycle' `
        -Comparison 'equals' `
        -Unit 'lifecycle_state'
    Assert-ExactPropertySet `
        -Value $disposeGate.actual `
        -Expected @(
            'disposedBatchCount',
            'disposedLayerCount',
            'cacheBytes',
            'cacheCount',
            'activeWorkers',
            'desiredBatchKey',
            'currentBatchKey') `
        -Label 'pipeline_dispose_returns_to_zero.actual properties'
    foreach ($property in @(
            'disposedBatchCount',
            'disposedLayerCount',
            'cacheBytes',
            'cacheCount',
            'activeWorkers')) {
        Assert-ContractEqual `
            (ConvertTo-ExactInt64 `
                -Value $disposeGate.actual.$property `
                -Label "pipeline_dispose.actual.$property" -NonNegative) `
            ([long]$afterDispose.$property) `
            "pipeline_dispose.actual.$property"
    }
    Assert-ContractEqual $disposeGate.actual.desiredBatchKey $null `
        'pipeline_dispose.actual.desiredBatchKey'
    Assert-ContractEqual $disposeGate.actual.currentBatchKey $null `
        'pipeline_dispose.actual.currentBatchKey'
    Assert-ExactPropertySet `
        -Value $disposeGate.expected `
        -Expected @(
            'disposedBatchCountGreaterThan',
            'disposedLayerMultiplier',
            'cacheBytes',
            'cacheCount',
            'activeWorkers',
            'desiredBatchKey',
            'currentBatchKey') `
        -Label 'pipeline_dispose_returns_to_zero.expected properties'
    foreach ($entry in ([ordered]@{
            disposedBatchCountGreaterThan = 0
            disposedLayerMultiplier = 8
            cacheBytes = 0
            cacheCount = 0
            activeWorkers = 0
        }).GetEnumerator()) {
        Assert-ContractEqual `
            (ConvertTo-ExactInt64 `
                -Value $disposeGate.expected.($entry.Key) `
                -Label "pipeline_dispose.expected.$($entry.Key)" `
                -NonNegative) `
            ([long]$entry.Value) "pipeline_dispose.expected.$($entry.Key)"
    }
    Assert-ContractEqual $disposeGate.expected.desiredBatchKey $null `
        'pipeline_dispose.expected.desiredBatchKey'
    Assert-ContractEqual $disposeGate.expected.currentBatchKey $null `
        'pipeline_dispose.expected.currentBatchKey'
}

function Assert-TopologyProbeContract {
    param(
        [Parameter(Mandatory)]$Probe,
        [Parameter(Mandatory)][object[]]$Bounds,
        [Parameter(Mandatory)][int[]]$RawOuterUnion,
        [Parameter(Mandatory)][int[]]$InflatedOuterUnion,
        [Parameter(Mandatory)][int[]]$ClippedSurface,
        [Parameter(Mandatory)][bool]$FullViewportBridge,
        [Parameter(Mandatory)][string]$Label
    )

    Assert-ExactPropertySet `
        -Value $Probe `
        -Expected @(
            'viewport',
            'bounds',
            'rawOuterUnion',
            'inflatePixels',
            'inflatedOuterUnion',
            'clippedSurface',
            'viewportPixels',
            'rawInflatedSurfacePixels',
            'submittedSurfacePixels',
            'offViewportPixels',
            'exactRectangleUnionPixels',
            'components',
            'bridgeWastePixels',
            'rawInflatedSurfaceBytes',
            'submittedSurfaceBytes',
            'amplification',
            'clippedViewportRatio',
            'exactVisibleFillRatio',
            'fullViewportBridge',
            'nearFullBridge',
            'requiresDecision',
            'recordedDecision',
            'elapsedTicks',
            'elapsedMilliseconds') `
        -Label "$Label properties"
    Assert-RectangleContract `
        -Rectangle $Probe.viewport `
        -X 0 -Y 0 -Width 1024 -Height 576 `
        -Label "$Label.viewport"
    $reportedBounds = @($Probe.bounds)
    if ($reportedBounds.Count -ne $Bounds.Count) {
        throw "$Label.bounds count mismatch."
    }
    for ($index = 0; $index -lt $Bounds.Count; $index++) {
        Assert-RectangleContract `
            -Rectangle $reportedBounds[$index] `
            -X $Bounds[$index][0] `
            -Y $Bounds[$index][1] `
            -Width $Bounds[$index][2] `
            -Height $Bounds[$index][3] `
            -Label "$Label.bounds[$index]"
    }
    Assert-RectangleContract `
        -Rectangle $Probe.rawOuterUnion `
        -X $RawOuterUnion[0] `
        -Y $RawOuterUnion[1] `
        -Width $RawOuterUnion[2] `
        -Height $RawOuterUnion[3] `
        -Label "$Label.rawOuterUnion"
    Assert-ContractEqual `
        (ConvertTo-ExactInt64 `
            -Value $Probe.inflatePixels `
            -Label "$Label.inflatePixels" -NonNegative) `
        6L "$Label.inflatePixels"
    Assert-RectangleContract `
        -Rectangle $Probe.inflatedOuterUnion `
        -X $InflatedOuterUnion[0] `
        -Y $InflatedOuterUnion[1] `
        -Width $InflatedOuterUnion[2] `
        -Height $InflatedOuterUnion[3] `
        -Label "$Label.inflatedOuterUnion"
    Assert-RectangleContract `
        -Rectangle $Probe.clippedSurface `
        -X $ClippedSurface[0] `
        -Y $ClippedSurface[1] `
        -Width $ClippedSurface[2] `
        -Height $ClippedSurface[3] `
        -Label "$Label.clippedSurface"

    $viewportPixels = 1024L * 576L
    $rawPixels =
        [long]$InflatedOuterUnion[2] * [long]$InflatedOuterUnion[3]
    $submittedPixels =
        [long]$ClippedSurface[2] * [long]$ClippedSurface[3]
    $exactPixels = 0L
    foreach ($bound in $Bounds) {
        $exactPixels += [long]$bound[2] * [long]$bound[3]
    }
    $expectedIntegers = [ordered]@{
        viewportPixels = $viewportPixels
        rawInflatedSurfacePixels = $rawPixels
        submittedSurfacePixels = $submittedPixels
        offViewportPixels = $rawPixels - $submittedPixels
        exactRectangleUnionPixels = $exactPixels
        components = $Bounds.Count
        bridgeWastePixels = $submittedPixels - $exactPixels
        rawInflatedSurfaceBytes = $rawPixels * 4L
        submittedSurfaceBytes = $submittedPixels * 4L
    }
    foreach ($entry in $expectedIntegers.GetEnumerator()) {
        Assert-ContractEqual `
            (ConvertTo-ExactInt64 `
                -Value $Probe.($entry.Key) `
                -Label "$Label.$($entry.Key)" -NonNegative) `
            ([long]$entry.Value) "$Label.$($entry.Key)"
    }

    $expectedRatios = [ordered]@{
        amplification = [double]$submittedPixels / [double]$exactPixels
        clippedViewportRatio =
            [double]$submittedPixels / [double]$viewportPixels
        exactVisibleFillRatio =
            [double]$exactPixels / [double]$submittedPixels
    }
    foreach ($entry in $expectedRatios.GetEnumerator()) {
        Assert-ContractEqual `
            (ConvertTo-NonNegativeFiniteDouble `
                -Value $Probe.($entry.Key) `
                -Label "$Label.$($entry.Key)") `
            ([double]$entry.Value) "$Label.$($entry.Key)"
    }
    Assert-ContractEqual $Probe.fullViewportBridge `
        $FullViewportBridge "$Label.fullViewportBridge"
    Assert-ContractEqual $Probe.nearFullBridge $true `
        "$Label.nearFullBridge"
    Assert-ContractEqual $Probe.requiresDecision $true `
        "$Label.requiresDecision"
    Assert-ContractEqual ([string]$Probe.recordedDecision) `
        'split_required' "$Label.recordedDecision"
    $null = ConvertTo-ExactInt64 `
        -Value $Probe.elapsedTicks `
        -Label "$Label.elapsedTicks" -NonNegative
    $null = ConvertTo-NonNegativeFiniteDouble `
        -Value $Probe.elapsedMilliseconds `
        -Label "$Label.elapsedMilliseconds"
}

function Test-AndVerifyTopologyContract {
    param(
        [Parameter(Mandatory)]$Report,
        [Parameter(Mandatory)]$Gates
    )

    $topology = $Report.topology
    Assert-ExactPropertySet `
        -Value $topology `
        -Expected @(
            'geometryConclusion',
            'recordedDecision',
            'measurementKind',
            'inflatePixels',
            'viewport',
            'productionRightTopFixedBounds',
            'rawCanonicalLayerEnvelope',
            'viewportClippedCanonicalEnvelope',
            'fullStage',
            'viewportClippedCanonicalEnvelopeProbe',
            'actualUpdateLayeredWindowMeasured') `
        -Label 'topology properties'
    Assert-ContractEqual ([string]$topology.geometryConclusion) `
        'geometry_requires_decision' 'topology.geometryConclusion'
    Assert-ContractEqual ([string]$topology.recordedDecision) `
        'split_required' 'topology.recordedDecision'
    Assert-ContractEqual ([string]$topology.measurementKind) `
        'synthetic_fixed_bounds' 'topology.measurementKind'
    Assert-ContractEqual `
        (ConvertTo-ExactInt64 `
            -Value $topology.inflatePixels `
            -Label 'topology.inflatePixels' -NonNegative) `
        6L 'topology.inflatePixels'
    Assert-RectangleContract `
        -Rectangle $topology.viewport `
        -X 0 -Y 0 -Width 1024 -Height 576 `
        -Label 'topology.viewport'
    Assert-RectangleContract `
        -Rectangle $topology.productionRightTopFixedBounds `
        -X 724 -Y 0 -Width 252 -Height 32 `
        -Label 'topology.productionRightTopFixedBounds'
    Assert-RectangleContract `
        -Rectangle $topology.rawCanonicalLayerEnvelope `
        -X -3 -Y 474 -Width 285 -Height 81 `
        -Label 'topology.rawCanonicalLayerEnvelope'
    Assert-RectangleContract `
        -Rectangle $topology.viewportClippedCanonicalEnvelope `
        -X 0 -Y 474 -Width 282 -Height 81 `
        -Label 'topology.viewportClippedCanonicalEnvelope'
    Assert-ContractEqual $topology.actualUpdateLayeredWindowMeasured `
        $false 'topology.actualUpdateLayeredWindowMeasured'
    Assert-ContractEqual $Report.scope.productionWidgetRegistered `
        $false 'scope.productionWidgetRegistered'
    Assert-ContractEqual $Report.scope.actualLayeredWindowCommitInvoked `
        $false 'scope.actualLayeredWindowCommitInvoked'

    $fullBounds = @(
        @(724, 0, 252, 32),
        @(0, 512, 1024, 64))
    Assert-TopologyProbeContract `
        -Probe $topology.fullStage `
        -Bounds $fullBounds `
        -RawOuterUnion @(0, 0, 1024, 576) `
        -InflatedOuterUnion @(-6, -6, 1036, 588) `
        -ClippedSurface @(0, 0, 1024, 576) `
        -FullViewportBridge $true `
        -Label 'topology.fullStage'
    $tightBounds = @(
        @(724, 0, 252, 32),
        @(0, 474, 282, 81))
    Assert-TopologyProbeContract `
        -Probe $topology.viewportClippedCanonicalEnvelopeProbe `
        -Bounds $tightBounds `
        -RawOuterUnion @(0, 0, 976, 555) `
        -InflatedOuterUnion @(-6, -6, 988, 567) `
        -ClippedSurface @(0, 0, 982, 561) `
        -FullViewportBridge $false `
        -Label 'topology.viewportClippedCanonicalEnvelopeProbe'

    $fullGate = Get-ContractGate `
        -Gates $Gates `
        -Id 'topology_full_stage_exact_geometry' `
        -Phase 'topology' `
        -Comparison 'equals' `
        -Unit 'geometry'
    Assert-ExactPropertySet `
        -Value $fullGate.actual `
        -Expected @('rightTop', 'playerInfo', 'probe') `
        -Label 'topology_full_stage_exact_geometry.actual properties'
    Assert-JsonEquivalent `
        -Actual $fullGate.actual.rightTop `
        -Expected $topology.productionRightTopFixedBounds `
        -Label 'topology_full_stage_exact_geometry.actual.rightTop'
    Assert-RectangleContract `
        -Rectangle $fullGate.actual.playerInfo `
        -X 0 -Y 512 -Width 1024 -Height 64 `
        -Label 'topology_full_stage_exact_geometry.actual.playerInfo'
    Assert-JsonEquivalent `
        -Actual $fullGate.actual.probe `
        -Expected $topology.fullStage `
        -Label 'topology_full_stage_exact_geometry.actual.probe'
    Assert-ContractEqual ([string]$fullGate.expected) `
        'frozen B0-01A full-stage geometry; near/full bridge; requires decision' `
        'topology_full_stage_exact_geometry.expected'

    $tightGate = Get-ContractGate `
        -Gates $Gates `
        -Id 'topology_viewport_clipped_canonical_exact_geometry' `
        -Phase 'topology' `
        -Comparison 'equals' `
        -Unit 'geometry'
    Assert-ExactPropertySet `
        -Value $tightGate.actual `
        -Expected @('rawLayerEnvelope', 'viewportClippedEnvelope', 'probe') `
        -Label (
            'topology_viewport_clipped_canonical_exact_geometry.actual ' +
            'properties')
    Assert-JsonEquivalent `
        -Actual $tightGate.actual.rawLayerEnvelope `
        -Expected $topology.rawCanonicalLayerEnvelope `
        -Label (
            'topology_viewport_clipped_canonical_exact_geometry.actual.' +
            'rawLayerEnvelope')
    Assert-JsonEquivalent `
        -Actual $tightGate.actual.viewportClippedEnvelope `
        -Expected $topology.viewportClippedCanonicalEnvelope `
        -Label (
            'topology_viewport_clipped_canonical_exact_geometry.actual.' +
            'viewportClippedEnvelope')
    Assert-JsonEquivalent `
        -Actual $tightGate.actual.probe `
        -Expected $topology.viewportClippedCanonicalEnvelopeProbe `
        -Label (
            'topology_viewport_clipped_canonical_exact_geometry.actual.probe')
    Assert-ContractEqual ([string]$tightGate.expected) `
        'B0-04 manifest layer envelope clipped to the main Flash viewport; near bridge; requires decision' `
        'topology_viewport_clipped_canonical_exact_geometry.expected'
}

function Test-AndVerifyProcessDiagnosticsContract {
    param([Parameter(Mandatory)]$Report)

    $diagnostics = $Report.processDiagnostics
    Assert-ExactPropertySet `
        -Value $diagnostics `
        -Expected @(
            'before',
            'after',
            'delta',
            'gdiEndpointInterpretation',
            'handleAndMemoryInterpretation') `
        -Label 'processDiagnostics properties'
    [string[]]$metricProperties = @(
        'processCpuMilliseconds',
        'totalAllocatedBytes',
        'gen0Collections',
        'gen1Collections',
        'gen2Collections',
        'managedMemoryBytes',
        'managedHeapSizeBytes',
        'workingSetBytes',
        'privateMemoryBytes',
        'processHandleCount',
        'gdiObjectCount',
        'userObjectCount')
    foreach ($phase in @('before', 'after', 'delta')) {
        Assert-ExactPropertySet `
            -Value $diagnostics.$phase `
            -Expected $metricProperties `
            -Label "processDiagnostics.$phase properties"
    }

    $beforeCpu = ConvertTo-NonNegativeFiniteDouble `
        -Value $diagnostics.before.processCpuMilliseconds `
        -Label 'processDiagnostics.before.processCpuMilliseconds'
    $afterCpu = ConvertTo-NonNegativeFiniteDouble `
        -Value $diagnostics.after.processCpuMilliseconds `
        -Label 'processDiagnostics.after.processCpuMilliseconds'
    $deltaCpu = ConvertTo-FiniteDouble `
        -Value $diagnostics.delta.processCpuMilliseconds `
        -Label 'processDiagnostics.delta.processCpuMilliseconds'
    Assert-ContractEqual $deltaCpu ($afterCpu - $beforeCpu) `
        'processDiagnostics.delta.processCpuMilliseconds'

    foreach ($property in @(
            'totalAllocatedBytes',
            'gen0Collections',
            'gen1Collections',
            'gen2Collections',
            'managedMemoryBytes',
            'managedHeapSizeBytes',
            'workingSetBytes',
            'privateMemoryBytes',
            'processHandleCount')) {
        $before = ConvertTo-ExactInt64 `
            -Value $diagnostics.before.$property `
            -Label "processDiagnostics.before.$property" -NonNegative
        $after = ConvertTo-ExactInt64 `
            -Value $diagnostics.after.$property `
            -Label "processDiagnostics.after.$property" -NonNegative
        $delta = ConvertTo-ExactInt64 `
            -Value $diagnostics.delta.$property `
            -Label "processDiagnostics.delta.$property"
        Assert-ContractEqual $delta ($after - $before) `
            "processDiagnostics.delta.$property"
    }
    foreach ($property in @('gdiObjectCount', 'userObjectCount')) {
        $before = ConvertTo-ExactInt64 `
            -Value $diagnostics.before.$property `
            -Label "processDiagnostics.before.$property"
        $after = ConvertTo-ExactInt64 `
            -Value $diagnostics.after.$property `
            -Label "processDiagnostics.after.$property"
        if ($before -lt -1 -or $after -lt -1) {
            throw "processDiagnostics.$property endpoint is below -1."
        }
        $expectedDelta = if ($before -lt 0 -or $after -lt 0) {
            -1L
        } else {
            $after - $before
        }
        $delta = ConvertTo-ExactInt64 `
            -Value $diagnostics.delta.$property `
            -Label "processDiagnostics.delta.$property"
        Assert-ContractEqual $delta $expectedDelta `
            "processDiagnostics.delta.$property"
    }
    Assert-ContractEqual `
        ([string]$diagnostics.gdiEndpointInterpretation) `
        'endpoint delta only; diagnostic, not a repeated-draw trend gate' `
        'processDiagnostics.gdiEndpointInterpretation'
    Assert-ContractEqual `
        ([string]$diagnostics.handleAndMemoryInterpretation) `
        'diagnostic only; lifecycle zero-state is the hard ownership gate' `
        'processDiagnostics.handleAndMemoryInterpretation'
}

function Test-AndVerifyScopeContract {
    param([Parameter(Mandatory)]$Report)

    Assert-ExactPropertySet `
        -Value $Report.scope `
        -Expected @(
            'productionWidgetRegistered',
            'actualLayeredWindowCommitInvoked',
            'fixtureBoundsSource',
            'conclusion') `
        -Label 'scope properties'
    Assert-ContractEqual $Report.scope.productionWidgetRegistered `
        $false 'scope.productionWidgetRegistered'
    Assert-ContractEqual $Report.scope.actualLayeredWindowCommitInvoked `
        $false 'scope.actualLayeredWindowCommitInvoked'
    Assert-ContractEqual ([string]$Report.scope.fixtureBoundsSource) `
        'B0-01A main-stage ty=512 and B0-04 typed manifest' `
        'scope.fixtureBoundsSource'
    Assert-ContractEqual ([string]$Report.scope.conclusion) `
        'B0-05 structural raster/cache/topology preflight only' `
        'scope.conclusion'

    Assert-ExactPropertySet `
        -Value $Report.dpiAwareness `
        -Expected @(
            'effective',
            'processBootstrapInvokedByQualification',
            'viewportCoordinates',
            'monitorDpiScaleRole',
            'appliedToRasterScale') `
        -Label 'dpiAwareness properties'
    $effective = [string]$Report.dpiAwareness.effective
    if ([string]::IsNullOrWhiteSpace($effective) -or
        $effective -cnotmatch (
            '^(Unaware|SystemAware|PerMonitorAware|PerMonitorAwareV2|' +
            'unavailable:[A-Za-z0-9_.+`]+)$')) {
        throw "dpiAwareness.effective is invalid: '$effective'"
    }
    Assert-ContractEqual `
        $Report.dpiAwareness.processBootstrapInvokedByQualification `
        $false 'dpiAwareness.processBootstrapInvokedByQualification'
    Assert-ContractEqual ([string]$Report.dpiAwareness.viewportCoordinates) `
        'physical_pixels' 'dpiAwareness.viewportCoordinates'
    Assert-ContractEqual ([string]$Report.dpiAwareness.monitorDpiScaleRole) `
        'diagnostic_only' 'dpiAwareness.monitorDpiScaleRole'
    Assert-ContractEqual $Report.dpiAwareness.appliedToRasterScale `
        $false 'dpiAwareness.appliedToRasterScale'

    [string[]]$expectedVerified = @(
        'production embedded asset and renderer identity loaded'
        'four physical content viewports planned without DPI double multiplication'
        'static layers parsed, rasterized and copied to PArgb'
        'single-worker latest-wins cache pipeline exercised'
        '3000 current-key requests caused zero parse/raster/publish'
        'fixed-bounds full/tight geometry requires an explicit topology decision'
        'recorded B0-05 topology decision is split_required'
    )
    Assert-ExactStringSequence `
        -Actual @($Report.verified | ForEach-Object { [string]$_ }) `
        -Expected $expectedVerified `
        -Label 'verified claims'
    [string[]]$expectedUnverified = @(
        'production full PlayerInfoWidget behavior'
        'actual NativeHud full-union paint, real draw, or UpdateLayeredWindow commit'
        'production 3000-tick hidden/enabled A/B'
        'GDI, USER, process-handle, and native-memory trend under repeated real draw/commit'
        'Flash oracle or cross-renderer visual parity'
        'game-scene composite aesthetics'
        'real-window mouse hit passthrough'
        'runtime PlayerInfo state integration'
        'candidate execution, e2e verification, promotion or standard entry'
        'human visual/UI acceptance'
    )
    Assert-ExactStringSequence `
        -Actual @($Report.unverified | ForEach-Object { [string]$_ }) `
        -Expected $expectedUnverified `
        -Label 'unverified claims'
}

function Test-AndVerifyAssetRendererContract {
    param([Parameter(Mandatory)]$Report)

    Assert-ExactPropertySet `
        -Value $Report.asset `
        -Expected @(
            'assetSetId',
            'assetSetRevision',
            'exactManifestSha256',
            'rasterContractVersion',
            'assetCount',
            'manifestBytes',
            'assets') `
        -Label 'asset properties'
    Assert-ContractEqual ([string]$Report.asset.assetSetId) `
        'player-info-hp-mp-b0' 'asset.assetSetId'
    Assert-ContractEqual ([string]$Report.asset.assetSetRevision) `
        'sha256:d67ab427748f5256bd18ea5669c9f1d045a6adaac30dce96f9660ea20c892ba1' `
        'asset.assetSetRevision'
    Assert-ContractEqual `
        (ConvertTo-ExactInt64 `
            -Value $Report.asset.rasterContractVersion `
            -Label 'asset.rasterContractVersion' -NonNegative) `
        1L 'asset.rasterContractVersion'
    Assert-ContractEqual `
        (ConvertTo-ExactInt64 `
            -Value $Report.asset.assetCount `
            -Label 'asset.assetCount' -NonNegative) `
        8L 'asset.assetCount'

    $assetRoot = Join-Path $ProjectRoot `
        'launcher\src\Guardian\Hud\PlayerInfo\Assets'
    $manifestPath = Join-Path $assetRoot 'player-info.manifest.json'
    $manifestSize = [long](Get-Item -LiteralPath $manifestPath).Length
    $manifestSha256 =
        (Get-Sha256Hex -LiteralPath $manifestPath).ToLowerInvariant()
    Assert-ContractEqual `
        (ConvertTo-ExactInt64 `
            -Value $Report.asset.manifestBytes `
            -Label 'asset.manifestBytes' -NonNegative) `
        $manifestSize 'asset.manifestBytes'
    Assert-ContractEqual ([string]$Report.asset.exactManifestSha256) `
        $manifestSha256 'asset.exactManifestSha256'

    $expectedAssets = @(
        [pscustomobject]@{
            Id = 'hp.backplate'
            RelativePath = 'hp/backplate.svg'
            ViewBox = @(-47, -47, 94, 94)
        }
        [pscustomobject]@{
            Id = 'hp.fill'
            RelativePath = 'hp/fill.svg'
            ViewBox = @(-47, -47, 94, 94)
        }
        [pscustomobject]@{
            Id = 'hp.rim'
            RelativePath = 'hp/rim.svg'
            ViewBox = @(-47, -47, 94, 94)
        }
        [pscustomobject]@{
            Id = 'mp.backplate'
            RelativePath = 'mp/backplate.svg'
            ViewBox = @(-41, -3, 218, 45)
        }
        [pscustomobject]@{
            Id = 'mp.fill'
            RelativePath = 'mp/fill.svg'
            ViewBox = @(-41, -3, 218, 45)
        }
        [pscustomobject]@{
            Id = 'mp.rim'
            RelativePath = 'mp/rim.svg'
            ViewBox = @(-41, -3, 218, 45)
        }
        [pscustomobject]@{
            Id = 'mp.rim-vf70'
            RelativePath = 'mp/rim-vf70.svg'
            ViewBox = @(-41, -3, 218, 45)
        }
        [pscustomobject]@{
            Id = 'mp.rim-vf91'
            RelativePath = 'mp/rim-vf91.svg'
            ViewBox = @(-41, -3, 218, 45)
        }
    )
    $reportedAssets = @($Report.asset.assets)
    Assert-ExactStringSequence `
        -Actual @($reportedAssets | ForEach-Object { [string]$_.id }) `
        -Expected @($expectedAssets | ForEach-Object { [string]$_.Id }) `
        -Label 'asset.assets order'
    for ($index = 0; $index -lt $expectedAssets.Count; $index++) {
        $expected = $expectedAssets[$index]
        $asset = $reportedAssets[$index]
        Assert-ExactPropertySet `
            -Value $asset `
            -Expected @(
                'id',
                'relativePath',
                'sha256',
                'byteCount',
                'viewBox',
                'registration',
                'cacheable') `
            -Label "asset.assets.$($expected.Id) properties"
        Assert-ContractEqual ([string]$asset.relativePath) `
            ([string]$expected.RelativePath) `
            "asset.assets.$($expected.Id).relativePath"
        $assetPath = [System.IO.Path]::GetFullPath(
            (Join-Path $assetRoot (
                ([string]$expected.RelativePath) -replace '/', '\')))
        $assetRootPrefix =
            [System.IO.Path]::GetFullPath($assetRoot).TrimEnd('\') + '\'
        if (-not $assetPath.StartsWith(
                $assetRootPrefix,
                [System.StringComparison]::OrdinalIgnoreCase) -or
            -not (Test-Path -LiteralPath $assetPath -PathType Leaf)) {
            throw "Production asset is missing/outside root: $($expected.Id)"
        }
        Assert-ContractEqual `
            (ConvertTo-ExactInt64 `
                -Value $asset.byteCount `
                -Label "asset.assets.$($expected.Id).byteCount" `
                -NonNegative) `
            ([long](Get-Item -LiteralPath $assetPath).Length) `
            "asset.assets.$($expected.Id).byteCount"
        $assetSha256 =
            (Get-Sha256Hex -LiteralPath $assetPath).ToLowerInvariant()
        Assert-ContractEqual ([string]$asset.sha256) $assetSha256 `
            "asset.assets.$($expected.Id).sha256"
        Assert-RectangleContract `
            -Rectangle $asset.viewBox `
            -X $expected.ViewBox[0] `
            -Y $expected.ViewBox[1] `
            -Width $expected.ViewBox[2] `
            -Height $expected.ViewBox[3] `
            -Label "asset.assets.$($expected.Id).viewBox"
        Assert-ExactPropertySet `
            -Value $asset.registration `
            -Expected @('x', 'y') `
            -Label "asset.assets.$($expected.Id).registration properties"
        Assert-ContractEqual `
            (ConvertTo-ExactInt64 `
                -Value $asset.registration.x `
                -Label "asset.assets.$($expected.Id).registration.x") `
            0L "asset.assets.$($expected.Id).registration.x"
        Assert-ContractEqual `
            (ConvertTo-ExactInt64 `
                -Value $asset.registration.y `
                -Label "asset.assets.$($expected.Id).registration.y") `
            0L "asset.assets.$($expected.Id).registration.y"
        Assert-ContractEqual $asset.cacheable $true `
            "asset.assets.$($expected.Id).cacheable"
    }

    Assert-ExactPropertySet `
        -Value $Report.renderer `
        -Expected @(
            'package',
            'version',
            'skiaSharpVersion',
            'featureSet',
            'colorType',
            'alphaType',
            'cacheIdentity') `
        -Label 'renderer properties'
    $expectedRenderer = [ordered]@{
        package = 'Svg.Skia'
        version = '5.1.1'
        skiaSharpVersion = '3.119.4'
        featureSet = 'cf7-player-info-static-svg-v1'
        colorType = 'Bgra8888'
        alphaType = 'premultiplied'
        cacheIdentity =
            'Svg.Skia/5.1.1;SkiaSharp/3.119.4;cf7-player-info-static-svg-v1;Bgra8888/premultiplied'
    }
    foreach ($entry in $expectedRenderer.GetEnumerator()) {
        Assert-ContractEqual ([string]$Report.renderer.($entry.Key)) `
            ([string]$entry.Value) "renderer.$($entry.Key)"
    }
}

function Test-AndVerifyQualificationContract {
    param([Parameter(Mandatory)]$Report)

    [string[]]$expectedGateIds = @(
        'physical_scale_viewport_1024x576_dpi100'
        'dpi_telemetry_only_viewport_1024x576_dpi100'
        'physical_scale_viewport_1600x900_dpi125'
        'dpi_telemetry_only_viewport_1600x900_dpi125'
        'physical_scale_viewport_1920x1080_dpi150'
        'dpi_telemetry_only_viewport_1920x1080_dpi150'
        'physical_scale_host_1280x960_letterbox_content_1280x720_dpi175'
        'dpi_telemetry_only_host_1280x960_letterbox_content_1280x720_dpi175'
        'cold_queue_result'
        'warm_inactive_cache_result'
        'steady_current_hit_result'
        'ui_request_cold_queue_p95'
        'ui_request_warm_cache_p95'
        'ui_request_pending_coalescing_p95'
        'ui_request_steady_current_hit_p95'
        'warmed_fresh_bake_p95_viewport_1024x576_dpi100'
        'warmed_fresh_bake_p95_viewport_1600x900_dpi125'
        'warmed_fresh_bake_p95_viewport_1920x1080_dpi150'
        'warmed_fresh_bake_p95_host_1280x960_letterbox_content_1280x720_dpi175'
        'warm_cache_lookup_p95'
        'cache_budget'
        'steady_3000_zero_parse_raster_publish'
        'single_worker'
        'fault_free'
        'pending_coalescing_latest_wins'
        'pipeline_dispose_returns_to_zero'
        'topology_full_stage_exact_geometry'
        'topology_viewport_clipped_canonical_exact_geometry'
        'source_closure_bound'
        'test_assembly_bound'
        'execution_binaries_bound'
    )
    $gates = @($Report.gates)
    Assert-ExactStringSet `
        -Actual @($gates | ForEach-Object { [string]$_.id }) `
        -Expected $expectedGateIds `
        -Label 'qualification gate IDs'

    [string[]]$contractViewportIds = @(
        'viewport_1024x576_dpi100'
        'viewport_1600x900_dpi125'
        'viewport_1920x1080_dpi150'
        'host_1280x960_letterbox_content_1280x720_dpi175'
    )
    Test-AndVerifyTimingContract `
        -Report $Report `
        -Gates $gates `
        -ViewportIds $contractViewportIds
    Test-AndVerifyViewportContract `
        -Report $Report `
        -Gates $gates `
        -ViewportIds $contractViewportIds
    Test-AndVerifyPipelineContract `
        -Report $Report `
        -Gates $gates
    Test-AndVerifyTopologyContract `
        -Report $Report `
        -Gates $gates
    Test-AndVerifyProcessDiagnosticsContract -Report $Report
    Test-AndVerifyScopeContract -Report $Report
    Test-AndVerifyAssetRendererContract -Report $Report

    $upperBounds = [ordered]@{
        'ui_request_cold_queue_p95' = 4.0
        'ui_request_warm_cache_p95' = 4.0
        'ui_request_pending_coalescing_p95' = 4.0
        'ui_request_steady_current_hit_p95' = 4.0
        'warmed_fresh_bake_p95_viewport_1024x576_dpi100' = 100.0
        'warmed_fresh_bake_p95_viewport_1600x900_dpi125' = 100.0
        'warmed_fresh_bake_p95_viewport_1920x1080_dpi150' = 100.0
        'warmed_fresh_bake_p95_host_1280x960_letterbox_content_1280x720_dpi175' = 100.0
        'warm_cache_lookup_p95' = 1.0
        'cache_budget' = 16777216.0
    }
    foreach ($entry in $upperBounds.GetEnumerator()) {
        $gate = Get-RequiredGate -Gates $gates -Id ([string]$entry.Key)
        Assert-ContractEqual ([string]$gate.comparison) `
            'less_than_or_equal' "$($entry.Key).comparison"
        Assert-ContractEqual ([double]$gate.expected) `
            ([double]$entry.Value) "$($entry.Key).expected"
        if ([double]$gate.actual -gt [double]$entry.Value) {
            throw "$($entry.Key) exceeds its frozen upper bound."
        }
    }

    Assert-ContractEqual ([string]$Report.timings.quantileMethod) `
        'nearest_rank' 'timings.quantileMethod'
    Assert-ContractEqual ([double]$Report.timings.uiRequest.thresholdP95Ms) `
        4.0 'timings.uiRequest.thresholdP95Ms'
    Assert-ContractEqual ([int]$Report.timings.uiRequest.sampleCount) `
        3108 'timings.uiRequest.sampleCount'
    Assert-ContractEqual `
        ([int]$Report.timings.uiRequest.coldQueue.summary.count) `
        4 'timings.uiRequest.coldQueue.count'
    Assert-ContractEqual `
        ([int]$Report.timings.uiRequest.warmInactiveCache.summary.count) `
        4 'timings.uiRequest.warmInactiveCache.count'
    Assert-ContractEqual `
        ([int]$Report.timings.uiRequest.pendingCoalescing.summary.count) `
        100 'timings.uiRequest.pendingCoalescing.count'
    Assert-ContractEqual `
        ([int]$Report.timings.uiRequest.steadyCurrentHit.summary.count) `
        3000 'timings.uiRequest.steadyCurrentHit.count'
    Assert-ContractEqual `
        ([double]$Report.timings.warmedFreshBake.thresholdP95Ms) `
        100.0 'timings.warmedFreshBake.thresholdP95Ms'
    Assert-ContractEqual `
        ([int]$Report.timings.warmedFreshBake.samplesPerViewport) `
        20 'timings.warmedFreshBake.samplesPerViewport'
    Assert-ContractEqual `
        (@($Report.timings.warmedFreshBake.samples).Count) `
        80 'timings.warmedFreshBake.samples.count'
    Assert-ContractEqual `
        ([double]$Report.timings.warmCacheLookup.thresholdP95Ms) `
        1.0 'timings.warmCacheLookup.thresholdP95Ms'

    [string[]]$expectedViewportIds = @(
        'viewport_1024x576_dpi100'
        'viewport_1600x900_dpi125'
        'viewport_1920x1080_dpi150'
        'host_1280x960_letterbox_content_1280x720_dpi175'
    )
    $viewportRows = @($Report.timings.warmedFreshBake.byViewport)
    Assert-ExactStringSet `
        -Actual @($viewportRows | ForEach-Object {
            [string]$_.viewportId
        }) `
        -Expected $expectedViewportIds `
        -Label 'warmedFreshBake viewport IDs'
    foreach ($viewportId in $expectedViewportIds) {
        $row = @($viewportRows | Where-Object {
            [string]$_.viewportId -ceq $viewportId
        })[0]
        Assert-ContractEqual ([int]$row.summary.count) `
            20 "warmedFreshBake.$viewportId.count"
    }

    Assert-ContractEqual ([int]$Report.raster.assetCount) `
        8 'raster.assetCount'
    Assert-ContractEqual ([long]$Report.cache.budgetBytes) `
        ([long]16777216) 'cache.budgetBytes'
    if ([long]$Report.cache.peakBytes -gt 16777216) {
        throw 'cache.peakBytes exceeds the frozen 16 MiB budget.'
    }
    Assert-ContractEqual ([int]$Report.raster.steady3000.requestCount) `
        3000 'raster.steady3000.requestCount'
    Assert-ContractEqual ([int]$Report.raster.steady3000.parseDelta) `
        0 'raster.steady3000.parseDelta'
    Assert-ContractEqual ([int]$Report.raster.steady3000.rasterDelta) `
        0 'raster.steady3000.rasterDelta'
    Assert-ContractEqual ([int]$Report.raster.steady3000.publishDelta) `
        0 'raster.steady3000.publishDelta'

    $afterPending = $Report.raster.pipelineCounters.afterPendingCoalescing
    Assert-ContractEqual ([int]$afterPending.maxConcurrentWorkers) `
        1 'pipeline.maxConcurrentWorkers'
    Assert-ContractEqual ([int]$afterPending.faultCount) `
        0 'pipeline.faultCount'
    Assert-ContractEqual ([string]$afterPending.currentBatchKey) `
        ([string]$afterPending.desiredBatchKey) `
        'pipeline pending latest-wins key'
    $afterDispose = $Report.raster.pipelineCounters.afterDispose
    if ([int]$afterDispose.disposedBatchCount -le 0 -or
        [int]$afterDispose.disposedLayerCount -ne
            ([int]$afterDispose.disposedBatchCount * 8) -or
        [long]$afterDispose.cacheBytes -ne 0 -or
        [int]$afterDispose.cacheCount -ne 0 -or
        [int]$afterDispose.activeWorkers -ne 0 -or
        $null -ne $afterDispose.desiredBatchKey -or
        $null -ne $afterDispose.currentBatchKey) {
        throw 'pipeline afterDispose does not satisfy the frozen zero-state contract.'
    }

    Assert-ContractEqual ([int]$Report.topology.inflatePixels) `
        6 'topology.inflatePixels'
    Assert-ContractEqual `
        ([int]$Report.topology.viewportClippedCanonicalEnvelope.width) `
        282 'topology.viewportClippedCanonicalEnvelope.width'
    Assert-ContractEqual `
        ([int]$Report.topology.viewportClippedCanonicalEnvelope.height) `
        81 'topology.viewportClippedCanonicalEnvelope.height'
    Assert-ContractEqual `
        ([int]$Report.topology.viewportClippedCanonicalEnvelopeProbe.clippedSurface.width) `
        982 'topology.tight.clippedSurface.width'
    Assert-ContractEqual `
        ([int]$Report.topology.viewportClippedCanonicalEnvelopeProbe.clippedSurface.height) `
        561 'topology.tight.clippedSurface.height'
    Assert-ContractEqual `
        ([bool]$Report.topology.viewportClippedCanonicalEnvelopeProbe.requiresDecision) `
        $true 'topology.tight.requiresDecision'
    Assert-ContractEqual `
        ([bool]$Report.topology.actualUpdateLayeredWindowMeasured) `
        $false 'topology.actualUpdateLayeredWindowMeasured'
    Assert-ContractEqual `
        ([bool]$Report.scope.actualLayeredWindowCommitInvoked) `
        $false 'scope.actualLayeredWindowCommitInvoked'
}

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = [System.IO.Path]::GetFullPath(
        (Join-Path $PSScriptRoot '..\..'))
} else {
    $ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
}

if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = Join-Path $ProjectRoot `
        'tmp\player-info-hud-b0-05-runtime-qualification.json'
} elseif (-not [System.IO.Path]::IsPathRooted($ReportPath)) {
    $ReportPath = Join-Path $ProjectRoot $ReportPath
}
$ReportPath = [System.IO.Path]::GetFullPath($ReportPath)

$testsProject = Join-Path $ProjectRoot 'launcher\tests\Launcher.Tests.csproj'
$resolver = Join-Path $ProjectRoot 'launcher\resolve-dotnet.ps1'
if (-not (Test-Path -LiteralPath $testsProject -PathType Leaf)) {
    throw "Launcher test project is missing: $testsProject"
}
if (-not (Test-Path -LiteralPath $resolver -PathType Leaf)) {
    throw "Exact-SDK resolver is missing: $resolver"
}

$reportDirectory = Split-Path -Parent $ReportPath
[System.IO.Directory]::CreateDirectory($reportDirectory) | Out-Null

. $resolver
$dotnet = Resolve-Cf7Dotnet -ProjectRoot $ProjectRoot
$sdkVersion = (& $dotnet --version 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $sdkVersion -ne '10.0.300') {
    throw "B0-05 qualification requires exact .NET SDK 10.0.300; got '$sdkVersion'."
}

$runId = [Guid]::NewGuid().ToString('N')
$previousReport = $env:CF7_PLAYER_INFO_B005_REPORT_PATH
$previousRunId = $env:CF7_PLAYER_INFO_B005_RUN_ID
$previousSdkVersion = $env:CF7_PLAYER_INFO_B005_SDK_VERSION
$previousProjectRoot = $env:CF7_PLAYER_INFO_B005_PROJECT_ROOT
$env:CF7_PLAYER_INFO_B005_REPORT_PATH = $ReportPath
$env:CF7_PLAYER_INFO_B005_RUN_ID = $runId
$env:CF7_PLAYER_INFO_B005_SDK_VERSION = $sdkVersion
$env:CF7_PLAYER_INFO_B005_PROJECT_ROOT = $ProjectRoot
$testExitCode = $null

try {
    $restore = Invoke-ProcessWithTimeout `
        -FilePath $dotnet `
        -Arguments @('restore', $testsProject, '--locked-mode') `
        -TimeoutSeconds $TestTimeoutSeconds `
        -Label 'B0-05 locked restore'
    if ($restore.ExitCode -ne 0) {
        throw "B0-05 locked restore failed with exit code $($restore.ExitCode)."
    }

    $test = Invoke-ProcessWithTimeout `
        -FilePath $dotnet `
        -Arguments @(
            'test'
            $testsProject
            '-c'
            'Release'
            '--no-restore'
            '--filter'
            'FullyQualifiedName=CF7Launcher.Tests.Guardian.Hud.PlayerInfo.PlayerInfoB005RuntimeQualificationTests.B0_05_SyntheticFixedBoundsRuntimeQualification'
            '--logger'
            'console;verbosity=normal'
        ) `
        -TimeoutSeconds $TestTimeoutSeconds `
        -Label 'B0-05 focused qualification test'
    $testExitCode = $test.ExitCode
} finally {
    $env:CF7_PLAYER_INFO_B005_REPORT_PATH = $previousReport
    $env:CF7_PLAYER_INFO_B005_RUN_ID = $previousRunId
    $env:CF7_PLAYER_INFO_B005_SDK_VERSION = $previousSdkVersion
    $env:CF7_PLAYER_INFO_B005_PROJECT_ROOT = $previousProjectRoot
}

if (-not (Test-Path -LiteralPath $ReportPath -PathType Leaf)) {
    throw "B0-05 test produced no report: $ReportPath"
}

$reportBytes = [System.IO.File]::ReadAllBytes($ReportPath)
if ($reportBytes.Length -ge 3 -and
    $reportBytes[0] -eq 0xEF -and
    $reportBytes[1] -eq 0xBB -and
    $reportBytes[2] -eq 0xBF) {
    throw "B0-05 report must be UTF-8 without BOM: $ReportPath"
}
if ($reportBytes.Length -eq 0 -or
    $reportBytes[$reportBytes.Length - 1] -ne 0x0A -or
    [System.Array]::IndexOf($reportBytes, [byte]0x0D) -ge 0) {
    throw "B0-05 report must use canonical LF line endings with one final LF: $ReportPath"
}

$report = Get-Content -LiteralPath $ReportPath -Raw -Encoding utf8 |
    ConvertFrom-Json
Assert-ContractEqual $report.schema `
    'cf7.player-info-hud.b0-05-runtime-qualification' 'report.schema'
Assert-ContractEqual $report.runId $runId 'report.runId'
Assert-ContractEqual $report.measurementKind `
    'synthetic_fixed_bounds' 'report.measurementKind'
Assert-ContractEqual $report.decision `
    'geometry_requires_decision' 'report.decision'
Assert-ContractEqual $report.recordedDecision `
    'split_required' 'report.recordedDecision'
Assert-ContractEqual $report.topology.geometryConclusion `
    'geometry_requires_decision' 'report.topology.geometryConclusion'
Assert-ContractEqual $report.topology.recordedDecision `
    'split_required' 'report.topology.recordedDecision'

$failures = @($report.failures)
$gates = @($report.gates)
if ($failures.Count -ne 0) {
    throw "B0-05 report contains gate failures: $($failures -join '; ')"
}
if ($gates.Count -eq 0) {
    throw 'B0-05 report contains no gates.'
}
$failedGates = @($gates | Where-Object { $_.passed -ne $true })
if ($failedGates.Count -ne 0) {
    throw (
        'B0-05 report contains failed gates: ' +
        (($failedGates | ForEach-Object { $_.id }) -join ', '))
}
Assert-ContractEqual $report.status 'passed' 'report.status'

Test-AndVerifyQualificationContract -Report $report
Test-AndVerifySourceClosure -Report $report
Test-AndVerifyExecutionBinaries -Report $report

if ($testExitCode -ne 0) {
    throw "B0-05 focused qualification test failed with exit code $testExitCode."
}

Write-Host (
    'PLAYER_INFO_B0_05_OK report={0} runId={1} assets={2} geometry={3} recordedDecision={4} cacheBytes={5} closure={6}' -f
        $ReportPath,
        $report.runId,
        $report.raster.assetCount,
        $report.topology.geometryConclusion,
        $report.topology.recordedDecision,
        $report.cache.peakBytes,
        $report.sourceClosure.aggregateSha256)
