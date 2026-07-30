[CmdletBinding()]
param(
    [string]$ProjectRoot,
    [string]$ReportPath,
    [ValidateRange(120, 1200)]
    [int]$TestTimeoutSeconds = 900
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

[string[]]$performanceOverrideEnvironmentNames = @(
    'DOTNET_TieredPGO'
    'COMPlus_TieredPGO'
    'DOTNET_TieredCompilation'
    'COMPlus_TieredCompilation'
    'DOTNET_ReadyToRun'
    'COMPlus_ReadyToRun'
    'DOTNET_TC_QuickJit'
    'COMPlus_TC_QuickJit'
    'DOTNET_TC_QuickJitForLoops'
    'COMPlus_TC_QuickJitForLoops'
    'DOTNET_gcServer'
    'COMPlus_gcServer'
)

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
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][int]$TimeoutSeconds,
        [Parameter(Mandatory)][string]$Label
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
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try {
                & taskkill.exe /PID $process.Id /T /F 2>&1 | Out-Null
            } catch {
                # Preserve the timeout as the primary failure.
            }
            [void]$process.WaitForExit(10000)
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

function Assert-Equal {
    param(
        $Actual,
        $Expected,
        [Parameter(Mandatory)][string]$Label
    )

    if ($null -eq $Actual -and $null -eq $Expected) {
        return
    }
    if ($null -eq $Actual -or $null -eq $Expected) {
        throw "$Label mismatch: expected='$Expected' actual='$Actual'."
    }
    if ($Actual -is [string] -or $Expected -is [string]) {
        if ([string]::Equals(
                [string]$Actual,
                [string]$Expected,
                [System.StringComparison]::Ordinal)) {
            return
        }
        throw "$Label mismatch: expected='$Expected' actual='$Actual'."
    }
    if ($Actual -is [System.IConvertible] -and
        $Expected -is [System.IConvertible]) {
        try {
            $actualDecimal = [System.Convert]::ToDecimal(
                $Actual,
                [System.Globalization.CultureInfo]::InvariantCulture)
            $expectedDecimal = [System.Convert]::ToDecimal(
                $Expected,
                [System.Globalization.CultureInfo]::InvariantCulture)
            if ($actualDecimal -eq $expectedDecimal) {
                return
            }
        } catch {
            # Fall through to exact object equality for non-numeric values.
        }
    }
    if (-not [object]::Equals($Actual, $Expected)) {
        throw "$Label mismatch: expected='$Expected' actual='$Actual'."
    }
}

function Get-ExactBoolean {
    param(
        [AllowNull()]$Value,
        [Parameter(Mandatory)][string]$Label
    )

    if ($null -eq $Value -or $Value -isnot [System.Boolean]) {
        $actualType = if ($null -eq $Value) {
            '<null>'
        } else {
            $Value.GetType().FullName
        }
        throw "$Label must be a JSON boolean; actualType='$actualType'."
    }
    return [bool]$Value
}

function Assert-ExactStringSet {
    param(
        [Parameter(Mandatory)][string[]]$Actual,
        [Parameter(Mandatory)][string[]]$Expected,
        [Parameter(Mandatory)][string]$Label
    )

    [string[]]$actualSorted = @($Actual)
    [string[]]$expectedSorted = @($Expected)
    [array]::Sort($actualSorted, [System.StringComparer]::Ordinal)
    [array]::Sort($expectedSorted, [System.StringComparer]::Ordinal)
    Assert-Equal $actualSorted.Count $expectedSorted.Count "$Label.count"
    for ($index = 0; $index -lt $expectedSorted.Count; $index++) {
        Assert-Equal $actualSorted[$index] $expectedSorted[$index] `
            "$Label[$index]"
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

function Assert-Near {
    param(
        [double]$Actual,
        [double]$Expected,
        [Parameter(Mandatory)][string]$Label,
        [double]$Tolerance = 0.0000005
    )

    if ([double]::IsNaN($Actual) -or
        [double]::IsInfinity($Actual) -or
        [math]::Abs($Actual - $Expected) -gt $Tolerance) {
        throw "$Label mismatch: expected='$Expected' actual='$Actual'."
    }
}

function ConvertTo-FiniteSamples {
    param(
        [Parameter(Mandatory)]$Values,
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][int]$ExpectedCount
    )

    [double[]]$samples = @($Values | ForEach-Object { [double]$_ })
    if ($samples.Count -ne $ExpectedCount) {
        throw "$Label count mismatch: expected=$ExpectedCount actual=$($samples.Count)."
    }
    for ($index = 0; $index -lt $samples.Count; $index++) {
        if ([double]::IsNaN($samples[$index]) -or
            [double]::IsInfinity($samples[$index]) -or
            $samples[$index] -lt 0) {
            throw "$Label[$index] must be finite and non-negative."
        }
    }
    return ,$samples
}

function Get-NearestRankSummary {
    param([Parameter(Mandatory)][double[]]$Samples)

    if ($Samples.Count -eq 0) {
        return [pscustomobject]@{
            count = 0
            p50 = 0.0
            p95 = 0.0
            p99 = 0.0
            max = 0.0
        }
    }
    [double[]]$sorted = @($Samples)
    [array]::Sort($sorted)
    function Get-Rank([double]$Percentile) {
        $index = [math]::Max(
            0,
            [int][math]::Ceiling($Percentile * $sorted.Count) - 1)
        return [double]$sorted[$index]
    }
    return [pscustomobject]@{
        count = $sorted.Count
        p50 = Get-Rank 0.50
        p95 = Get-Rank 0.95
        p99 = Get-Rank 0.99
        max = [double]$sorted[$sorted.Count - 1]
    }
}

function Assert-Summary {
    param(
        [Parameter(Mandatory)]$Reported,
        [Parameter(Mandatory)]$Computed,
        [Parameter(Mandatory)][string]$Label
    )

    Assert-Equal ([int]$Reported.count) ([int]$Computed.count) "$Label.count"
    foreach ($property in @('p50', 'p95', 'p99', 'max')) {
        Assert-Near ([double]$Reported.$property) `
            ([double]$Computed.$property) "$Label.$property"
    }
}

function Assert-RectangleEqual {
    param(
        [Parameter(Mandatory)]$Actual,
        [Parameter(Mandatory)]$Expected,
        [Parameter(Mandatory)][string]$Label
    )

    foreach ($property in @('x', 'y', 'width', 'height', 'pixels', 'bytes')) {
        Assert-Equal ([long]$Actual.$property) `
            ([long]$Expected.$property) "$Label.$property"
    }
}

function Get-PositiveMonotonicGrowth {
    param([Parameter(Mandatory)][int[]]$Values)

    if ($Values.Count -lt 2 -or
        $Values[$Values.Count - 1] -le $Values[0]) {
        return $false
    }
    for ($index = 1; $index -lt $Values.Count; $index++) {
        if ($Values[$index] -lt $Values[$index - 1]) {
            return $false
        }
    }
    return $true
}

function Get-Sha256Hex {
    param([Parameter(Mandatory)][string]$LiteralPath)

    return (Get-FileHash -LiteralPath $LiteralPath -Algorithm SHA256).Hash
}

function Assert-FileIdentity {
    param(
        [Parameter(Mandatory)]$Identity,
        [Parameter(Mandatory)][string]$Label
    )

    $path = Join-Path $ProjectRoot ([string]$Identity.path)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "$Label path is missing: $path"
    }
    $file = Get-Item -LiteralPath $path
    Assert-Equal ([long]$Identity.bytes) ([long]$file.Length) "$Label.bytes"
    Assert-Equal ([string]$Identity.sha256) `
        (Get-Sha256Hex -LiteralPath $path) "$Label.sha256"
}

function Get-FilteredGitBlobOid {
    param(
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][string]$LiteralPath,
        [Parameter(Mandatory)][string]$Label
    )

    $output = & git.exe -C $ProjectRoot hash-object `
        "--path=$RelativePath" $LiteralPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "$Label git hash-object failed: $($output | Out-String)"
    }
    $oid = ($output | Out-String).Trim().ToLowerInvariant()
    if ($oid -notmatch '^(?:[0-9a-f]{40}|[0-9a-f]{64})$') {
        throw "$Label git hash-object returned an invalid OID: $oid"
    }
    return $oid
}

function Assert-FileIdentityClosure {
    param(
        [Parameter(Mandatory)]$Items,
        [Parameter(Mandatory)][string[]]$ExpectedPaths,
        [Parameter(Mandatory)][string]$Label,
        [switch]$RequireGitBlobOid
    )

    [string[]]$expected = @($ExpectedPaths | ForEach-Object {
        ([string]$_).Replace('\', '/')
    })
    [array]::Sort($expected, [System.StringComparer]::Ordinal)
    if (@($expected | Sort-Object -CaseSensitive -Unique).Count -ne
        $expected.Count) {
        throw "$Label expected path closure contains duplicates."
    }
    $actual = @($Items)
    Assert-Equal $actual.Count $expected.Count "$Label.count"
    for ($index = 0; $index -lt $expected.Count; $index++) {
        $item = $actual[$index]
        Assert-Equal ([string]$item.path) $expected[$index] `
            "$Label[$index].path"
        Assert-FileIdentity $item "$Label[$index]"
        if ($RequireGitBlobOid) {
            $fullPath = Join-Path $ProjectRoot ([string]$item.path)
            $computedOid = Get-FilteredGitBlobOid `
                -RelativePath ([string]$item.path) `
                -LiteralPath $fullPath `
                -Label "$Label[$index]"
            Assert-Equal ([string]$item.gitBlobOid) $computedOid `
                "$Label[$index].gitBlobOid"
        } elseif (
            $null -ne $item.PSObject.Properties['gitBlobOid']) {
            throw "$Label[$index] must not contain gitBlobOid."
        }
    }
}

function Get-PlayerInfoAssetRevision {
    param(
        [Parameter(Mandatory)]$AssetSources
    )

    $hash = [System.Security.Cryptography.IncrementalHash]::CreateHash(
        [System.Security.Cryptography.HashAlgorithmName]::SHA256)
    try {
        foreach ($asset in @($AssetSources)) {
            [byte[]]$pathBytes =
                [System.Text.UTF8Encoding]::new($false, $true).GetBytes(
                    [string]$asset.relativePath)
            [byte[]]$fileBytes = [System.IO.File]::ReadAllBytes(
                (Join-Path $ProjectRoot ([string]$asset.sourceFile.path)))
            $hash.AppendData($pathBytes)
            $hash.AppendData([byte[]]@(0))
            $hash.AppendData($fileBytes)
            $hash.AppendData([byte[]]@(0))
        }
        return [System.BitConverter]::ToString(
            $hash.GetHashAndReset()).Replace('-', '').ToLowerInvariant()
    } finally {
        $hash.Dispose()
    }
}

function Test-ReportContract {
    param(
        [Parameter(Mandatory)]$Report,
        [Parameter(Mandatory)][string]$ExpectedRunId,
        [Parameter(Mandatory)][string]$ExpectedAffinityMask
    )

    Assert-Equal ([string]$Report.schema) `
        'cf7.player-info-hud.b0-06-runtime-qualification' 'schema'
    Assert-Equal ([int]$Report.schemaVersion) 2 'schemaVersion'
    Assert-Equal ([string]$Report.runId) $ExpectedRunId 'runId'
    Assert-Equal ([string]$Report.measurementKind) `
        'actual_sta_hwnd_update_layered_window' 'measurementKind'
    Assert-Equal ([string]$Report.status) 'passed' 'status'
    Assert-Equal ([int]$Report.qualification.visualSteps) 3000 `
        'qualification.visualSteps'
    Assert-Equal ([int]$Report.qualification.idleTicks) 3000 `
        'qualification.idleTicks'
    Assert-Equal `
        ([int]$Report.qualification.lifecycleWarmupCycleCountPerGroup) 100 `
        'qualification.lifecycleWarmupCycleCountPerGroup'
    Assert-Equal ([int]$Report.qualification.lifecycleWarmupMaxGroups) 5 `
        'qualification.lifecycleWarmupMaxGroups'
    Assert-Equal `
        ([int]$Report.qualification.lifecycleWarmupRequiredConsecutiveConvergedGroups) `
        2 `
        'qualification.lifecycleWarmupRequiredConsecutiveConvergedGroups'
    [int]$lifecycleWarmupCycles =
        [int]$Report.qualification.lifecycleWarmupCycles
    if ($lifecycleWarmupCycles -lt 200 -or
        $lifecycleWarmupCycles -gt 500 -or
        ($lifecycleWarmupCycles % 100) -ne 0) {
        throw "qualification.lifecycleWarmupCycles is invalid: $lifecycleWarmupCycles"
    }
    Assert-Equal ([int]$Report.qualification.lifecycleCycles) 100 `
        'qualification.lifecycleCycles'
    Assert-Equal `
        ([int]$Report.qualification.lifecycleCheckpointInterval) 10 `
        'qualification.lifecycleCheckpointInterval'
    Assert-Equal ([string]$Report.qualification.quantileMethod) `
        'nearest_rank' 'qualification.quantileMethod'
    Assert-Equal ([bool]$Report.qualification.fixtureOnly) $true `
        'qualification.fixtureOnly'
    Assert-Equal ([bool]$Report.qualification.realUiDataConnected) $false `
        'qualification.realUiDataConnected'
    Assert-Equal `
        ([bool]$Report.qualification.oldFlashHudMutationAttempted) $false `
        'qualification.oldFlashHudMutationAttempted'
    Assert-Equal `
        ([bool]$Report.qualification.oldFlashHudVisibilityObserved) $false `
        'qualification.oldFlashHudVisibilityObserved'
    Assert-Equal ([bool]$Report.qualification.nativeHudRegistration) $false `
        'qualification.nativeHudRegistration'
    Assert-Equal `
        ([string]$Report.qualification.resourceEndpointPreparation) `
        'symmetric Application.DoEvents + full GC/finalizer drain before active_start and idle_end' `
        'qualification.resourceEndpointPreparation'
    Assert-Equal `
        ([string]$Report.qualification.lifecycleResourceEndpointPreparation) `
        'up to five full 100-cycle isomorphic lifecycle groups until two consecutive groups independently satisfy strict checkpoint-envelope convergence, then symmetric Application.DoEvents + full GC/finalizer drain before a new measured lifecycle_start and lifecycle_end' `
        'qualification.lifecycleResourceEndpointPreparation'
    Assert-Equal ([string]$Report.machine.staThread) 'STA' 'machine.staThread'
    Assert-Equal ([bool]$Report.splitSurface.hwnd.created) $true `
        'splitSurface.hwnd.created'
    Assert-Equal `
        ([bool]$Report.splitSurface.hwnd.actualUpdateLayeredWindowMeasured) `
        $true 'splitSurface.hwnd.actualUpdateLayeredWindowMeasured'

    $gitHead = (& git.exe -C $ProjectRoot rev-parse HEAD 2>&1 |
        Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to resolve the execution-time base commit: $gitHead"
    }
    Assert-Equal `
        ([string]$Report.sourceIdentity.baseCommitAtExecution) `
        $gitHead 'sourceIdentity.baseCommitAtExecution'
    Assert-Equal `
        ([string]$Report.sourceIdentity.commitBindingSemantics) `
        'pre-evidence-commit base only; containing commit is verified externally from the report blob and sourceTraceClosure gitBlobOid values' `
        'sourceIdentity.commitBindingSemantics'
    Assert-Equal ([string]$Report.sourceIdentity.sdkVersion) '10.0.300' `
        'sourceIdentity.sdkVersion'
    Assert-Equal ([string]$Report.runtime.qualificationSdkVersion) `
        '10.0.300' 'runtime.qualificationSdkVersion'

    if ($ExpectedAffinityMask -notmatch '^[0-9A-F]{16}$') {
        throw "Expected runner affinity mask is invalid: '$ExpectedAffinityMask'."
    }
    [uint64]$expectedAffinityValue = [uint64]::Parse(
        $ExpectedAffinityMask,
        [System.Globalization.NumberStyles]::AllowHexSpecifier,
        [System.Globalization.CultureInfo]::InvariantCulture)
    if ($expectedAffinityValue -eq 0) {
        throw 'Expected runner affinity mask must be nonzero.'
    }

    $runtimeEnvironment = $Report.runtime.performanceEnvironment
    Assert-ExactPropertySet `
        -Value $runtimeEnvironment `
        -Expected @(
            'inheritedOverrides',
            'processPriorityClass',
            'processorAffinityMask',
            'expectedProcessPriorityClass',
            'expectedProcessorAffinityMask') `
        -Label 'runtime.performanceEnvironment'
    Assert-ExactPropertySet `
        -Value $runtimeEnvironment.inheritedOverrides `
        -Expected $performanceOverrideEnvironmentNames `
        -Label 'runtime.performanceEnvironment.inheritedOverrides'
    $allOverridesAbsent = $true
    foreach ($name in $performanceOverrideEnvironmentNames) {
        if ($null -ne $runtimeEnvironment.inheritedOverrides.$name) {
            $allOverridesAbsent = $false
        }
        Assert-Equal $runtimeEnvironment.inheritedOverrides.$name `
            $null "runtime.performanceEnvironment.inheritedOverrides.$name"
    }
    Assert-Equal ([string]$runtimeEnvironment.processPriorityClass) `
        'Normal' 'runtime.performanceEnvironment.processPriorityClass'
    Assert-Equal ([string]$runtimeEnvironment.expectedProcessPriorityClass) `
        'Normal' 'runtime.performanceEnvironment.expectedProcessPriorityClass'
    Assert-Equal ([string]$runtimeEnvironment.processorAffinityMask) `
        $ExpectedAffinityMask `
        'runtime.performanceEnvironment.processorAffinityMask'
    Assert-Equal ([string]$runtimeEnvironment.expectedProcessorAffinityMask) `
        $ExpectedAffinityMask `
        'runtime.performanceEnvironment.expectedProcessorAffinityMask'
    $serverGc = Get-ExactBoolean `
        -Value $Report.runtime.serverGc `
        -Label 'runtime.serverGc'
    $performanceEnvironmentQualified = Get-ExactBoolean `
        -Value $Report.runtime.performanceEnvironmentQualified `
        -Label 'runtime.performanceEnvironmentQualified'
    Assert-Equal $serverGc $false 'runtime.serverGc'
    $independentlyQualifiedPerformanceEnvironment =
        $allOverridesAbsent -and
        ([string]$runtimeEnvironment.processPriorityClass -ceq 'Normal') -and
        ([string]$runtimeEnvironment.expectedProcessPriorityClass -ceq
            'Normal') -and
        ([string]$runtimeEnvironment.processorAffinityMask -ceq
            $ExpectedAffinityMask) -and
        ([string]$runtimeEnvironment.expectedProcessorAffinityMask -ceq
            $ExpectedAffinityMask) -and
        $expectedAffinityValue -ne 0 -and
        -not $serverGc
    Assert-Equal $performanceEnvironmentQualified `
        $independentlyQualifiedPerformanceEnvironment `
        'runtime.performanceEnvironmentQualified.reconstructed'
    Assert-Equal $independentlyQualifiedPerformanceEnvironment $true `
        'runtime.performanceEnvironmentQualified'

    Assert-FileIdentityClosure `
        -Items $Report.sourceIdentity.projectAssemblies `
        -ExpectedPaths @(
            'launcher/tests/bin/Release/CRAZYFLASHER7MercenaryEmpire.Core.dll'
            'launcher/tests/bin/Release/Launcher.Tests.dll'
        ) `
        -Label 'sourceIdentity.projectAssemblies'
    Assert-FileIdentityClosure `
        -Items $Report.sourceIdentity.rendererResolutionClosure.resolutionMetadata `
        -ExpectedPaths @(
            'launcher/tests/bin/Release/Launcher.Tests.deps.json'
            'launcher/tests/bin/Release/Launcher.Tests.runtimeconfig.json'
        ) `
        -Label 'sourceIdentity.rendererResolutionClosure.resolutionMetadata'
    Assert-FileIdentityClosure `
        -Items $Report.sourceIdentity.rendererResolutionClosure.rendererBinaries `
        -ExpectedPaths @(
            'launcher/tests/bin/Release/ExCSS.dll'
            'launcher/tests/bin/Release/HarfBuzzSharp.dll'
            'launcher/tests/bin/Release/ShimSkiaSharp.dll'
            'launcher/tests/bin/Release/SkiaSharp.dll'
            'launcher/tests/bin/Release/Svg.Animation.dll'
            'launcher/tests/bin/Release/Svg.Custom.dll'
            'launcher/tests/bin/Release/Svg.Model.dll'
            'launcher/tests/bin/Release/Svg.SceneGraph.dll'
            'launcher/tests/bin/Release/Svg.Skia.dll'
            'launcher/tests/bin/Release/runtimes/win-x64/native/libHarfBuzzSharp.dll'
            'launcher/tests/bin/Release/runtimes/win-x64/native/libSkiaSharp.dll'
        ) `
        -Label 'sourceIdentity.rendererResolutionClosure.rendererBinaries'
    Assert-FileIdentityClosure `
        -Items $Report.sourceIdentity.sourceTraceClosure `
        -ExpectedPaths @(
            'launcher/src/Program.cs'
            'launcher/src/Guardian/FlashCoordinateMapper.cs'
            'launcher/src/Guardian/LauncherCommandRouter.cs'
            'launcher/src/Guardian/NativeHudOverlay.cs'
            'launcher/src/Guardian/OverlayBase.cs'
            'launcher/src/Guardian/PanelHostController.cs'
            'launcher/src/Guardian/Hud/AudioHudState.cs'
            'launcher/src/Guardian/Hud/ComboWidget.cs'
            'launcher/src/Guardian/Hud/LayeredWindowCommit.cs'
            'launcher/src/Guardian/Hud/MapHudDataCatalog.cs'
            'launcher/src/Guardian/Hud/NotchWidget.cs'
            'launcher/src/Guardian/Hud/RightContextWidget.cs'
            'launcher/src/Guardian/Hud/RightHudLayout.cs'
            'launcher/src/Guardian/Hud/SafeExitPanelWidget.cs'
            'launcher/src/Guardian/Hud/ToastWidget.cs'
            'launcher/src/Guardian/Hud/PlayerInfo/PlayerInfoAnimationModel.cs'
            'launcher/src/Guardian/Hud/PlayerInfo/PlayerInfoFrameCompositor.cs'
            'launcher/src/Guardian/Hud/PlayerInfo/PlayerInfoLayeredDibSurface.cs'
            'launcher/src/Guardian/Hud/PlayerInfo/PlayerInfoPathGlyphAtlas.cs'
            'launcher/src/Guardian/Hud/PlayerInfo/PlayerInfoPathGlyphAtlas.Generated.cs'
            'launcher/src/Guardian/Hud/PlayerInfo/PlayerInfoRasterPipeline.cs'
            'launcher/src/Guardian/Hud/PlayerInfo/PlayerInfoRasterPlan.cs'
            'launcher/src/Guardian/Hud/PlayerInfo/PlayerInfoSplitSurface.cs'
            'launcher/src/Guardian/Hud/PlayerInfo/PlayerInfoStrictSvg.cs'
            'launcher/src/Guardian/Hud/PlayerInfo/PlayerInfoSvgAssetCatalog.cs'
            'launcher/src/Guardian/Hud/PlayerInfo/PlayerInfoSvgRasterizer.cs'
            'launcher/src/Guardian/Hud/PlayerInfo/PlayerInfoVisualState.cs'
            'launcher/src/Guardian/Hud/PlayerInfo/PlayerInfoWidget.cs'
            'launcher/tests/Guardian/Hud/PlayerInfo/PlayerInfoB006RuntimeQualificationTests.cs'
            'tools/player-info-hud/evidence/b0-06/glyph-atlas-provenance.json'
            'tools/player-info-hud/generate-player-info-glyph-atlas.py'
            'tools/player-info-hud/run-b0-06-runtime-qualification.ps1'
            'flashswf/UI/玩家信息界面.swf'
        ) `
        -Label 'sourceIdentity.sourceTraceClosure' `
        -RequireGitBlobOid
    Assert-Equal ([string]$Report.sourceIdentity.exactClosureScope) `
        'project Core/Test assemblies, declared renderer resolution files, embedded PlayerInfo assets, and exact B0 source trace' `
        'sourceIdentity.exactClosureScope'
    Assert-Equal `
        ([bool]$Report.sourceIdentity.environmentBoundary.includedInExactBinaryClosure) `
        $false `
        'sourceIdentity.environmentBoundary.includedInExactBinaryClosure'
    [string[]]$environmentComponents = @(
        $Report.sourceIdentity.environmentBoundary.components |
            ForEach-Object { [string]$_ }
    )
    [string[]]$expectedEnvironmentComponents = @(
        'Windows OS, user32, gdi32, and DWM implementation'
        'Microsoft.NETCore.App shared framework'
    )
    Assert-Equal $environmentComponents.Count `
        $expectedEnvironmentComponents.Count `
        'sourceIdentity.environmentBoundary.components.count'
    for ($index = 0;
        $index -lt $expectedEnvironmentComponents.Count;
        $index++) {
        Assert-Equal $environmentComponents[$index] `
            $expectedEnvironmentComponents[$index] `
            "sourceIdentity.environmentBoundary.components[$index]"
    }
    Assert-Equal `
        ([string]$Report.sourceIdentity.environmentBoundary.meaning) `
        'observed execution environment; not byte-bound by this report' `
        'sourceIdentity.environmentBoundary.meaning'

    Assert-Equal ([string]$Report.assets.assetSetId) `
        'player-info-hp-mp-b0' 'assets.assetSetId'
    Assert-Equal ([int]$Report.assets.assetCount) 8 'assets.assetCount'
    Assert-Equal ([string]$Report.assets.rendererPackage) `
        'Svg.Skia' 'assets.rendererPackage'
    Assert-Equal ([string]$Report.assets.rendererVersion) `
        '5.1.1' 'assets.rendererVersion'
    Assert-Equal ([string]$Report.assets.skiaSharpVersion) `
        '3.119.4' 'assets.skiaSharpVersion'
    Assert-Equal ([string]$Report.assets.revisionAlgorithm) `
        'sha256(sorted UTF-8 relative path + NUL + exact file bytes + NUL)' `
        'assets.revisionAlgorithm'
    Assert-Equal ([string]$Report.assets.manifestSource.path) `
        'launcher/src/Guardian/Hud/PlayerInfo/Assets/player-info.manifest.json' `
        'assets.manifestSource.path'
    Assert-FileIdentity $Report.assets.manifestSource `
        'assets.manifestSource'
    $manifestPath = Join-Path $ProjectRoot `
        ([string]$Report.assets.manifestSource.path)
    $manifestSha = (
        Get-Sha256Hex -LiteralPath $manifestPath).ToLowerInvariant()
    Assert-Equal ([string]$Report.assets.exactManifestSha256) `
        $manifestSha 'assets.exactManifestSha256'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 |
        ConvertFrom-Json
    Assert-Equal ([string]$manifest.format) `
        'cf7.player-info-hud.asset-manifest' 'assets.manifest.format'
    Assert-Equal ([int]$manifest.schemaVersion) 1 `
        'assets.manifest.schemaVersion'

    $expectedAssets = @(
        [pscustomobject]@{ id = 'hp.backplate'; path = 'hp/backplate.svg' }
        [pscustomobject]@{ id = 'hp.fill'; path = 'hp/fill.svg' }
        [pscustomobject]@{ id = 'hp.rim'; path = 'hp/rim.svg' }
        [pscustomobject]@{ id = 'mp.backplate'; path = 'mp/backplate.svg' }
        [pscustomobject]@{ id = 'mp.fill'; path = 'mp/fill.svg' }
        [pscustomobject]@{ id = 'mp.rim-vf70'; path = 'mp/rim-vf70.svg' }
        [pscustomobject]@{ id = 'mp.rim-vf91'; path = 'mp/rim-vf91.svg' }
        [pscustomobject]@{ id = 'mp.rim'; path = 'mp/rim.svg' }
    )
    $assetSources = @($Report.assets.assetSources)
    $manifestAssets = @($manifest.assets)
    Assert-Equal $assetSources.Count $expectedAssets.Count `
        'assets.assetSources.count'
    Assert-Equal $manifestAssets.Count $expectedAssets.Count `
        'assets.manifest.assets.count'
    $manifestAssetsByPath =
        [System.Collections.Generic.Dictionary[string, object]]::new(
            [System.StringComparer]::Ordinal)
    foreach ($manifestAsset in $manifestAssets) {
        $manifestAssetPath = [string]$manifestAsset.path
        if ($manifestAssetsByPath.ContainsKey($manifestAssetPath)) {
            throw "assets.manifest contains duplicate path '$($manifestAsset.path)'."
        }
        $manifestAssetsByPath.Add($manifestAssetPath, $manifestAsset)
    }
    for ($assetIndex = 0;
        $assetIndex -lt $expectedAssets.Count;
        $assetIndex++) {
        $expectedAsset = $expectedAssets[$assetIndex]
        $asset = $assetSources[$assetIndex]
        $manifestAsset = $null
        if (-not $manifestAssetsByPath.TryGetValue(
                [string]$expectedAsset.path,
                [ref]$manifestAsset)) {
            throw "assets.manifest lacks '$($expectedAsset.path)'."
        }
        Assert-Equal ([string]$asset.id) `
            ([string]$expectedAsset.id) `
            "assets.assetSources[$assetIndex].id"
        Assert-Equal ([string]$asset.relativePath) `
            ([string]$expectedAsset.path) `
            "assets.assetSources[$assetIndex].relativePath"
        Assert-Equal ([string]$manifestAsset.id) `
            ([string]$expectedAsset.id) `
            "assets.manifest.assets[$assetIndex].id"
        Assert-Equal ([string]$manifestAsset.path) `
            ([string]$expectedAsset.path) `
            "assets.manifest.assets[$assetIndex].path"
        [string]$expectedSourcePath =
            'launcher/src/Guardian/Hud/PlayerInfo/Assets/' +
            [string]$expectedAsset.path
        Assert-Equal ([string]$asset.sourceFile.path) `
            $expectedSourcePath `
            "assets.assetSources[$assetIndex].sourceFile.path"
        Assert-FileIdentity $asset.sourceFile `
            "assets.assetSources[$assetIndex].sourceFile"
        $sourceAssetPath = Join-Path $ProjectRoot `
            ([string]$asset.sourceFile.path)
        $sourceAsset = Get-Item -LiteralPath $sourceAssetPath
        Assert-Equal ([int]$asset.loadedBytes) `
            ([long]$sourceAsset.Length) `
            "assets.assetSources[$assetIndex].loadedBytes"
        $sourceSha = (
            Get-Sha256Hex -LiteralPath $sourceAssetPath).ToLowerInvariant()
        Assert-Equal ([string]$asset.loadedSha256) $sourceSha `
            "assets.assetSources[$assetIndex].loadedSha256"
        Assert-Equal ([string]$manifestAsset.sha256) $sourceSha `
            "assets.manifest.assets[$assetIndex].sha256"
    }
    $computedAssetRevision =
        Get-PlayerInfoAssetRevision -AssetSources $assetSources
    Assert-Equal ([string]$Report.assets.assetSetRevision) `
        ('sha256:' + $computedAssetRevision) `
        'assets.assetSetRevision'
    Assert-Equal ([string]$manifest.assetSet.revision) `
        ([string]$Report.assets.assetSetRevision) `
        'assets.manifest.assetSet.revision'

    $ownership = $Report.rasterOwnership
    Assert-Equal ([int]$ownership.canonicalLayerCount) 8 `
        'rasterOwnership.canonicalLayerCount'
    Assert-Equal ([int]$ownership.ownedFragmentCount) 2 `
        'rasterOwnership.ownedFragmentCount'
    Assert-Equal ([int]$ownership.parseCount) 10 `
        'rasterOwnership.parseCount'
    Assert-Equal ([int]$ownership.rasterCount) 10 `
        'rasterOwnership.rasterCount'
    Assert-Equal ([long]$ownership.byteBudget) 16777216 `
        'rasterOwnership.byteBudget'
    if ([long]$ownership.batchByteSize -gt
        [long]$ownership.byteBudget) {
        throw 'The independently baked raster batch exceeds 16 MiB.'
    }

    $ownershipLayers = @($ownership.layers)
    Assert-Equal $ownershipLayers.Count 8 `
        'rasterOwnership.layers.count'
    [string[]]$ownershipLayerIds = @(
        $ownershipLayers | ForEach-Object { [string]$_.layerId }
    )
    [string[]]$distinctOwnershipLayerIds = @(
        $ownershipLayerIds |
            Sort-Object -CaseSensitive -Unique
    )
    Assert-Equal $distinctOwnershipLayerIds.Count 8 `
        'rasterOwnership.layers.uniqueIds'

    [long]$independentBatchBytes = 0
    [int]$independentFragmentCount = 0
    $fragmentOwners = @()
    foreach ($layer in $ownershipLayers) {
        [string[]]$fragmentIds = @(
            $layer.fragmentIds | ForEach-Object { [string]$_ }
        )
        [long]$layerBytes =
            ([long]$layer.pixelWidth) *
            ([long]$layer.pixelHeight) *
            4L *
            (1L + [long]$fragmentIds.Count)
        $independentBatchBytes += $layerBytes
        $independentFragmentCount += $fragmentIds.Count
        Assert-Equal ([long]$layer.declaredByteSize) $layerBytes `
            "rasterOwnership.$($layer.layerId).declaredByteSize"
        Assert-Equal ([long]$layer.independentlyComputedByteSize) `
            $layerBytes `
            "rasterOwnership.$($layer.layerId).independentByteSize"
        Assert-Equal ([int]$layer.mainBitmapWidth) `
            ([int]$layer.pixelWidth) `
            "rasterOwnership.$($layer.layerId).mainBitmapWidth"
        Assert-Equal ([int]$layer.mainBitmapHeight) `
            ([int]$layer.pixelHeight) `
            "rasterOwnership.$($layer.layerId).mainBitmapHeight"
        Assert-Equal ([string]$layer.mainPixelFormat) `
            'Format32bppPArgb' `
            "rasterOwnership.$($layer.layerId).mainPixelFormat"
        Assert-Equal ([bool]$layer.mainBitmapMatchesKeyAndPArgb) `
            $true `
            "rasterOwnership.$($layer.layerId).mainBitmapContract"

        $fragments = @($layer.fragments)
        Assert-Equal $fragments.Count $fragmentIds.Count `
            "rasterOwnership.$($layer.layerId).fragments.count"
        for ($fragmentIndex = 0;
            $fragmentIndex -lt $fragments.Count;
            $fragmentIndex++) {
            $fragment = $fragments[$fragmentIndex]
            Assert-Equal ([string]$fragment.fragmentId) `
                $fragmentIds[$fragmentIndex] `
                "rasterOwnership.$($layer.layerId).fragment.id"
            Assert-Equal ([int]$fragment.width) `
                ([int]$layer.pixelWidth) `
                "rasterOwnership.$($layer.layerId).fragment.width"
            Assert-Equal ([int]$fragment.height) `
                ([int]$layer.pixelHeight) `
                "rasterOwnership.$($layer.layerId).fragment.height"
            Assert-Equal ([string]$fragment.pixelFormat) `
                'Format32bppPArgb' `
                "rasterOwnership.$($layer.layerId).fragment.pixelFormat"
            Assert-Equal ([bool]$fragment.matchesKeyAndPArgb) `
                $true `
                "rasterOwnership.$($layer.layerId).fragment.contract"
        }
        if ($fragmentIds.Count -gt 0) {
            $fragmentOwners += $layer
        }
    }
    Assert-Equal $independentFragmentCount 2 `
        'rasterOwnership.independentFragmentCount'
    Assert-Equal $fragmentOwners.Count 1 `
        'rasterOwnership.fragmentOwners.count'
    Assert-Equal ([string]$fragmentOwners[0].layerId) 'mp.fill' `
        'rasterOwnership.fragmentOwners.layerId'
    [string[]]$expectedFragmentIds = @(
        'mp-left-mask'
        'mp-right-mask'
    )
    [string[]]$actualFragmentIds = @(
        $fragmentOwners[0].fragmentIds |
            ForEach-Object { [string]$_ }
    )
    Assert-Equal $actualFragmentIds.Count $expectedFragmentIds.Count `
        'rasterOwnership.fragmentIds.count'
    for ($index = 0; $index -lt $expectedFragmentIds.Count; $index++) {
        Assert-Equal $actualFragmentIds[$index] `
            $expectedFragmentIds[$index] `
            "rasterOwnership.fragmentIds[$index]"
    }
    Assert-Equal ([long]$ownership.independentlyComputedByteSize) `
        $independentBatchBytes `
        'rasterOwnership.independentlyComputedByteSize'
    Assert-Equal ([long]$ownership.batchByteSize) `
        $independentBatchBytes `
        'rasterOwnership.batchByteSize'
    foreach ($property in @(
            'allPayloadsMatchKeyAndPArgb',
            'allBitmapReferencesDistinct',
            'batchDisposed',
            'batchLayerAccessThrowsObjectDisposed',
            'layerBitmapAccessThrowsObjectDisposed',
            'fragmentAccessThrowsObjectDisposed')) {
        Assert-Equal ([bool]$ownership.$property) $true `
            "rasterOwnership.$property"
    }
    Assert-Equal ([int]$ownership.disposedLayerCount) 8 `
        'rasterOwnership.disposedLayerCount'

    $lifecycle = $Report.surfaceLifecycle
    $lifecycleWarmup = $lifecycle.warmup
    Assert-Equal ([int]$lifecycleWarmup.groupCycleCount) 100 `
        'surfaceLifecycle.warmup.groupCycleCount'
    Assert-Equal ([int]$lifecycleWarmup.maxGroups) 5 `
        'surfaceLifecycle.warmup.maxGroups'
    Assert-Equal `
        ([int]$lifecycleWarmup.requiredConsecutiveConvergedGroups) 2 `
        'surfaceLifecycle.warmup.requiredConsecutiveConvergedGroups'
    Assert-Equal ([int]$lifecycleWarmup.checkpointInterval) 10 `
        'surfaceLifecycle.warmup.checkpointInterval'
    Assert-Equal ([bool]$lifecycleWarmup.converged) $true `
        'surfaceLifecycle.warmup.converged'
    Assert-Equal `
        ([bool]$lifecycleWarmup.acceptanceMeasurementImmediatelyFollowsConvergedPair) `
        $true `
        'surfaceLifecycle.warmup.acceptanceMeasurementImmediatelyFollowsConvergedPair'
    Assert-Equal ([string]$lifecycleWarmup.convergenceRule) `
        "first pair of consecutive complete groups where each group's GDI, USER, and process handle checkpoints never exceed that group's start, endpoint deltas are <= 0, and positive-monotonic trends are all false" `
        'surfaceLifecycle.warmup.convergenceRule'
    Assert-Equal ([string]$lifecycleWarmup.exclusionReason) `
        'process-level first-use stabilization exercised only by complete isomorphic PlayerInfo lifecycle groups; the independent 100 cycles immediately following the first consecutive converged pair retain the unchanged zero-growth gates' `
        'surfaceLifecycle.warmup.exclusionReason'

    $lifecycleWarmupGroups = @($lifecycleWarmup.groups)
    if ($lifecycleWarmupGroups.Count -lt 2 -or
        $lifecycleWarmupGroups.Count -gt 5) {
        throw "surfaceLifecycle.warmup.groups count is invalid: $($lifecycleWarmupGroups.Count)"
    }
    Assert-Equal ([int]$lifecycleWarmup.groupsRun) `
        $lifecycleWarmupGroups.Count `
        'surfaceLifecycle.warmup.groupsRun'
    Assert-Equal ([int]$lifecycleWarmup.convergedPairEndGroupIndex) `
        $lifecycleWarmupGroups.Count `
        'surfaceLifecycle.warmup.convergedPairEndGroupIndex'
    Assert-Equal ([int]$lifecycleWarmup.totalCycles) `
        ($lifecycleWarmupGroups.Count * 100) `
        'surfaceLifecycle.warmup.totalCycles'
    Assert-Equal $lifecycleWarmupCycles `
        ($lifecycleWarmupGroups.Count * 100) `
        'qualification.lifecycleWarmupCyclesVsGroups'

    [int[]]$expectedLifecycleSteps = @(
        0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100
    )
    $previousWarmupResources = $null
    [System.Collections.Generic.List[bool]]$warmupConvergenceSequence =
        [System.Collections.Generic.List[bool]]::new()
    for ($groupIndex = 0;
        $groupIndex -lt $lifecycleWarmupGroups.Count;
        $groupIndex++) {
        $group = $lifecycleWarmupGroups[$groupIndex]
        $groupLabel = "surfaceLifecycle.warmup.groups[$groupIndex]"
        Assert-Equal ([int]$group.index) ($groupIndex + 1) `
            "$groupLabel.index"
        Assert-Equal ([int]$group.cycles) 100 "$groupLabel.cycles"
        Assert-Equal ([int]$group.roundsCompleted) 100 `
            "$groupLabel.roundsCompleted"
        Assert-Equal ([bool]$group.measurementExcluded) $true `
            "$groupLabel.measurementExcluded"
        Assert-Equal ([int]$group.ownerOwnedFormsBaseline) 0 `
            "$groupLabel.ownerOwnedFormsBaseline"
        Assert-Equal @($group.ownerOwnedFormHandlesBaseline).Count 0 `
            "$groupLabel.ownerOwnedFormHandlesBaseline.count"

        $groupResources = $group.resources
        foreach ($property in @(
                'cpuMilliseconds',
                'allocatedBytes',
                'gc0',
                'gc1',
                'gc2',
                'workingSetBytes',
                'privateBytes',
                'processHandles',
                'gdiObjects',
                'userObjects')) {
            $computed = [double]$groupResources.after.$property -
                [double]$groupResources.before.$property
            Assert-Near ([double]$groupResources.delta.$property) `
                $computed "$groupLabel.resources.delta.$property"
        }

        $groupCheckpoints = @($groupResources.checkpoints)
        Assert-Equal $groupCheckpoints.Count 11 `
            "$groupLabel.resources.checkpoints.count"
        for ($checkpointIndex = 0;
            $checkpointIndex -lt $groupCheckpoints.Count;
            $checkpointIndex++) {
            $checkpoint = $groupCheckpoints[$checkpointIndex]
            Assert-Equal ([int]$checkpoint.step) `
                $expectedLifecycleSteps[$checkpointIndex] `
                "$groupLabel.resources.checkpoints[$checkpointIndex].step"
            [string]$expectedPhase = if ($checkpointIndex -eq 0) {
                'lifecycle_start'
            } elseif (
                $checkpointIndex -eq $groupCheckpoints.Count - 1) {
                'lifecycle_end'
            } else {
                'lifecycle'
            }
            Assert-Equal ([string]$checkpoint.phase) $expectedPhase `
                "$groupLabel.resources.checkpoints[$checkpointIndex].phase"
        }
        foreach ($property in @(
                'cpuMilliseconds',
                'allocatedBytes',
                'gc0',
                'gc1',
                'gc2',
                'workingSetBytes',
                'privateBytes',
                'processHandles',
                'gdiObjects',
                'userObjects')) {
            Assert-Equal $groupResources.before.$property `
                $groupCheckpoints[0].metrics.$property `
                "$groupLabel.resources.beforeCheckpointIdentity.$property"
            Assert-Equal $groupResources.after.$property `
                $groupCheckpoints[10].metrics.$property `
                "$groupLabel.resources.afterCheckpointIdentity.$property"
        }

        [int[]]$groupGdiSeries = @(
            $groupCheckpoints | ForEach-Object {
                [int]$_.metrics.gdiObjects
            }
        )
        [int[]]$groupUserSeries = @(
            $groupCheckpoints | ForEach-Object {
                [int]$_.metrics.userObjects
            }
        )
        [int[]]$groupProcessSeries = @(
            $groupCheckpoints | ForEach-Object {
                [int]$_.metrics.processHandles
            }
        )
        $groupGdiGrowth =
            Get-PositiveMonotonicGrowth $groupGdiSeries
        $groupUserGrowth =
            Get-PositiveMonotonicGrowth $groupUserSeries
        $groupProcessGrowth =
            Get-PositiveMonotonicGrowth $groupProcessSeries
        Assert-Equal `
            ([bool]$groupResources.handleTrend.gdiPositiveMonotonicGrowth) `
            $groupGdiGrowth "$groupLabel.resources.handleTrend.gdi"
        Assert-Equal `
            ([bool]$groupResources.handleTrend.userPositiveMonotonicGrowth) `
            $groupUserGrowth "$groupLabel.resources.handleTrend.user"
        Assert-Equal `
            ([bool]$groupResources.handleTrend.processPositiveMonotonicGrowth) `
            $groupProcessGrowth "$groupLabel.resources.handleTrend.process"
        $groupAnyGrowth = (
            $groupGdiGrowth -or
            $groupUserGrowth -or
            $groupProcessGrowth
        )
        Assert-Equal `
            ([bool]$groupResources.handleTrend.anyPositiveMonotonicGrowth) `
            $groupAnyGrowth "$groupLabel.resources.handleTrend.any"

        $noCheckpointAboveStart = (
            @($groupGdiSeries | Where-Object {
                $_ -gt $groupGdiSeries[0]
            }).Count -eq 0 -and
            @($groupUserSeries | Where-Object {
                $_ -gt $groupUserSeries[0]
            }).Count -eq 0 -and
            @($groupProcessSeries | Where-Object {
                $_ -gt $groupProcessSeries[0]
            }).Count -eq 0
        )
        Assert-Equal ([bool]$group.noCheckpointAboveStart) `
            $noCheckpointAboveStart `
            "$groupLabel.noCheckpointAboveStart"
        $groupConverged = (
            $noCheckpointAboveStart -and
            [int]$groupResources.delta.gdiObjects -le 0 -and
            [int]$groupResources.delta.userObjects -le 0 -and
            [int]$groupResources.delta.processHandles -le 0 -and
            -not $groupAnyGrowth
        )
        Assert-Equal ([bool]$group.converged) $groupConverged `
            "$groupLabel.converged"
        $warmupConvergenceSequence.Add($groupConverged)

        if ($null -ne $previousWarmupResources) {
            foreach ($property in @(
                    'cpuMilliseconds',
                    'allocatedBytes',
                    'gc0',
                    'gc1',
                    'gc2')) {
                if ([double]$groupResources.before.$property -lt
                    [double]$previousWarmupResources.after.$property) {
                    throw "$groupLabel '$property' precedes the previous group endpoint."
                }
            }
        }
        $previousWarmupResources = $groupResources
    }
    $firstConvergedPairEndGroupIndex = $null
    for ($groupIndex = 1;
        $groupIndex -lt $warmupConvergenceSequence.Count;
        $groupIndex++) {
        if ($warmupConvergenceSequence[$groupIndex - 1] -and
            $warmupConvergenceSequence[$groupIndex]) {
            $firstConvergedPairEndGroupIndex = $groupIndex + 1
            break
        }
    }
    if ($null -eq $firstConvergedPairEndGroupIndex) {
        throw 'No consecutive pair of independently converged lifecycle warmup groups was reconstructed.'
    }
    Assert-Equal ([int]$firstConvergedPairEndGroupIndex) `
        $lifecycleWarmupGroups.Count `
        'surfaceLifecycle.warmup.firstConvergedPairEndsAtGroupsRun'
    Assert-Equal ([int]$lifecycleWarmup.convergedPairEndGroupIndex) `
        ([int]$firstConvergedPairEndGroupIndex) `
        'surfaceLifecycle.warmup.convergedPairEndGroupIndexReconstructed'
    foreach ($property in @(
            'cpuMilliseconds',
            'allocatedBytes',
            'gc0',
            'gc1',
            'gc2')) {
        if ([double]$lifecycle.resources.before.$property -lt
            [double]$previousWarmupResources.after.$property) {
            throw "Measured lifecycle '$property' precedes its converged warmup-pair endpoint."
        }
    }
    Assert-Equal ([bool]$lifecycle.acceptanceMeasurementEligible) $true `
        'surfaceLifecycle.acceptanceMeasurementEligible'
    Assert-Equal ([string]$lifecycle.measurementRole) `
        'acceptance_measurement' `
        'surfaceLifecycle.measurementRole'

    Assert-Equal ([int]$lifecycle.cycles) 100 `
        'surfaceLifecycle.cycles'
    Assert-Equal ([int]$lifecycle.checkpointInterval) 10 `
        'surfaceLifecycle.checkpointInterval'
    [int]$ownedFormsBaseline =
        [int]$lifecycle.ownerOwnedFormsBaseline
    Assert-Equal $ownedFormsBaseline 0 `
        'surfaceLifecycle.ownerOwnedFormsBaseline'
    Assert-Equal @($lifecycle.ownerOwnedFormHandlesBaseline).Count 0 `
        'surfaceLifecycle.ownerOwnedFormHandlesBaseline.count'
    $lifecycleRounds = @($lifecycle.rounds)
    Assert-Equal $lifecycleRounds.Count 100 `
        'surfaceLifecycle.rounds.count'
    for ($roundIndex = 0;
        $roundIndex -lt $lifecycleRounds.Count;
        $roundIndex++) {
        $round = $lifecycleRounds[$roundIndex]
        [int]$expectedCycle = $roundIndex + 1
        [string]$expectedFixture = if (
            ($expectedCycle % 2) -eq 0) {
            'full'
        } else {
            'empty'
        }
        Assert-Equal ([int]$round.cycle) $expectedCycle `
            "surfaceLifecycle.rounds[$roundIndex].cycle"
        Assert-Equal ([string]$round.fixtureCase) $expectedFixture `
            "surfaceLifecycle.rounds[$roundIndex].fixtureCase"
        Assert-Equal ([bool]$round.hwndCreated) $true `
            "surfaceLifecycle.rounds[$roundIndex].hwndCreated"
        if ([string]$round.hwnd -notmatch '^0x[0-9A-F]+$' -or
            [string]$round.hwnd -eq '0x0') {
            throw "surfaceLifecycle.rounds[$roundIndex].hwnd is invalid."
        }
        Assert-Equal ([long]$round.publishCount) 1 `
            "surfaceLifecycle.rounds[$roundIndex].publishCount"
        Assert-Equal ([long]$round.parseCount) 10 `
            "surfaceLifecycle.rounds[$roundIndex].parseCount"
        Assert-Equal ([long]$round.rasterCount) 10 `
            "surfaceLifecycle.rounds[$roundIndex].rasterCount"
        Assert-Equal ([long]$round.repaintRequestCount) 1 `
            "surfaceLifecycle.rounds[$roundIndex].repaintRequestCount"
        Assert-Equal ([long]$round.paintCount) 1 `
            "surfaceLifecycle.rounds[$roundIndex].paintCount"
        Assert-Equal ([long]$round.commitCount) 1 `
            "surfaceLifecycle.rounds[$roundIndex].commitCount"
        Assert-Equal ([int]$round.observerCommitCount) 1 `
            "surfaceLifecycle.rounds[$roundIndex].observerCommitCount"
        Assert-Equal ([int]$round.observerSuccessCount) 1 `
            "surfaceLifecycle.rounds[$roundIndex].observerSuccessCount"
        Assert-Equal ([long]$round.commitSuccessCount) 1 `
            "surfaceLifecycle.rounds[$roundIndex].commitSuccessCount"
        Assert-Equal ([long]$round.commitFailureCount) 0 `
            "surfaceLifecycle.rounds[$roundIndex].commitFailureCount"
        Assert-Equal ([bool]$round.queuedCaseChanged) $true `
            "surfaceLifecycle.rounds[$roundIndex].queuedCaseChanged"
        Assert-Equal ([long]$round.queuedRepaintDelta) 1 `
            "surfaceLifecycle.rounds[$roundIndex].queuedRepaintDelta"
        Assert-Equal ([long]$round.queuedPaintDelta) 0 `
            "surfaceLifecycle.rounds[$roundIndex].queuedPaintDelta"
        Assert-Equal ([long]$round.queuedCommitDelta) 0 `
            "surfaceLifecycle.rounds[$roundIndex].queuedCommitDelta"
        Assert-Equal ([bool]$round.shutdown) $true `
            "surfaceLifecycle.rounds[$roundIndex].shutdown"
        Assert-Equal ([int]$round.activeWorkersAfterShutdown) 0 `
            "surfaceLifecycle.rounds[$roundIndex].activeWorkersAfterShutdown"
        Assert-Equal ([long]$round.cacheBytesAfterShutdown) 0 `
            "surfaceLifecycle.rounds[$roundIndex].cacheBytesAfterShutdown"
        Assert-Equal ([int]$round.cacheCountAfterShutdown) 0 `
            "surfaceLifecycle.rounds[$roundIndex].cacheCountAfterShutdown"
        Assert-Equal $round.desiredBatchKeyAfterShutdown $null `
            "surfaceLifecycle.rounds[$roundIndex].desiredBatchKeyAfterShutdown"
        Assert-Equal $round.currentBatchKeyAfterShutdown $null `
            "surfaceLifecycle.rounds[$roundIndex].currentBatchKeyAfterShutdown"
        Assert-Equal $round.lastFaultAfterShutdown $null `
            "surfaceLifecycle.rounds[$roundIndex].lastFaultAfterShutdown"
        Assert-Equal ([long]$round.disposedBatchCount) 1 `
            "surfaceLifecycle.rounds[$roundIndex].disposedBatchCount"
        Assert-Equal ([long]$round.disposedLayerCount) 8 `
            "surfaceLifecycle.rounds[$roundIndex].disposedLayerCount"
        Assert-Equal ([long]$round.paintDeltaAfterShutdownPump) 0 `
            "surfaceLifecycle.rounds[$roundIndex].paintDeltaAfterShutdownPump"
        Assert-Equal ([long]$round.commitDeltaAfterShutdownPump) 0 `
            "surfaceLifecycle.rounds[$roundIndex].commitDeltaAfterShutdownPump"
        Assert-Equal `
            ([int]$round.observerLateCommitDeltaBeforeDispose) 0 `
            "surfaceLifecycle.rounds[$roundIndex].observerLateCommitDeltaBeforeDispose"
        Assert-Equal ([int]$round.ownerOwnedFormsAfterCreate) 1 `
            "surfaceLifecycle.rounds[$roundIndex].ownerOwnedFormsAfterCreate"
        Assert-Equal `
            ([bool]$round.ownerContainsCandidateAfterCreate) $true `
            "surfaceLifecycle.rounds[$roundIndex].ownerContainsCandidateAfterCreate"
        Assert-Equal `
            ([bool]$round.ownerBaselineSetPreservedAfterCreate) $true `
            "surfaceLifecycle.rounds[$roundIndex].ownerBaselineSetPreservedAfterCreate"
        Assert-Equal ([int]$round.ownerOwnedFormsAfterDrain) 1 `
            "surfaceLifecycle.rounds[$roundIndex].ownerOwnedFormsAfterDrain"
        Assert-Equal `
            ([bool]$round.ownerContainsCandidateAfterDrain) $true `
            "surfaceLifecycle.rounds[$roundIndex].ownerContainsCandidateAfterDrain"
        Assert-Equal `
            ([bool]$round.ownerBaselineSetPreservedAfterDrain) $true `
            "surfaceLifecycle.rounds[$roundIndex].ownerBaselineSetPreservedAfterDrain"
        Assert-Equal ([bool]$round.isWindowAfterDrain) $true `
            "surfaceLifecycle.rounds[$roundIndex].isWindowAfterDrain"
        Assert-Equal ([bool]$round.isWindowAfterDispose) $false `
            "surfaceLifecycle.rounds[$roundIndex].isWindowAfterDispose"
        Assert-Equal ([bool]$round.isDisposedAfterDispose) $true `
            "surfaceLifecycle.rounds[$roundIndex].isDisposedAfterDispose"
        Assert-Equal ([bool]$round.isHandleCreatedAfterDispose) $false `
            "surfaceLifecycle.rounds[$roundIndex].isHandleCreatedAfterDispose"
        Assert-Equal ([int]$round.ownerOwnedFormsAfterDispose) `
            $ownedFormsBaseline `
            "surfaceLifecycle.rounds[$roundIndex].ownerOwnedFormsAfterDispose"
        Assert-Equal `
            ([bool]$round.ownerBaselineSetRestoredAfterDispose) $true `
            "surfaceLifecycle.rounds[$roundIndex].ownerBaselineSetRestoredAfterDispose"
        Assert-Equal `
            ([int]$round.observerLateCommitDeltaAfterDispose) 0 `
            "surfaceLifecycle.rounds[$roundIndex].observerLateCommitDeltaAfterDispose"
    }

    $lifecycleResources = $lifecycle.resources
    foreach ($property in @(
            'cpuMilliseconds',
            'allocatedBytes',
            'gc0',
            'gc1',
            'gc2',
            'workingSetBytes',
            'privateBytes',
            'processHandles',
            'gdiObjects',
            'userObjects')) {
        $computed = [double]$lifecycleResources.after.$property -
            [double]$lifecycleResources.before.$property
        Assert-Near ([double]$lifecycleResources.delta.$property) `
            $computed "surfaceLifecycle.resources.delta.$property"
    }
    foreach ($property in @('gdiObjects', 'userObjects', 'processHandles')) {
        if ([int]$lifecycleResources.delta.$property -gt 0) {
            throw "Surface lifecycle handle endpoint grew: $property=$($lifecycleResources.delta.$property)."
        }
    }

    $lifecycleCheckpoints = @($lifecycleResources.checkpoints)
    Assert-Equal $lifecycleCheckpoints.Count 11 `
        'surfaceLifecycle.resources.checkpoints.count'
    for ($checkpointIndex = 0;
        $checkpointIndex -lt $lifecycleCheckpoints.Count;
        $checkpointIndex++) {
        $checkpoint = $lifecycleCheckpoints[$checkpointIndex]
        Assert-Equal ([int]$checkpoint.step) `
            $expectedLifecycleSteps[$checkpointIndex] `
            "surfaceLifecycle.resources.checkpoints[$checkpointIndex].step"
        [string]$expectedPhase = if ($checkpointIndex -eq 0) {
            'lifecycle_start'
        } elseif (
            $checkpointIndex -eq $lifecycleCheckpoints.Count - 1) {
            'lifecycle_end'
        } else {
            'lifecycle'
        }
        Assert-Equal ([string]$checkpoint.phase) $expectedPhase `
            "surfaceLifecycle.resources.checkpoints[$checkpointIndex].phase"
    }
    foreach ($property in @(
            'cpuMilliseconds',
            'allocatedBytes',
            'gc0',
            'gc1',
            'gc2',
            'workingSetBytes',
            'privateBytes',
            'processHandles',
            'gdiObjects',
            'userObjects')) {
        Assert-Equal $lifecycleResources.before.$property `
            $lifecycleCheckpoints[0].metrics.$property `
            "surfaceLifecycle.resources.beforeCheckpointIdentity.$property"
        Assert-Equal $lifecycleResources.after.$property `
            $lifecycleCheckpoints[10].metrics.$property `
            "surfaceLifecycle.resources.afterCheckpointIdentity.$property"
    }
    [int[]]$lifecycleGdiSeries = @(
        $lifecycleCheckpoints | ForEach-Object {
            [int]$_.metrics.gdiObjects
        }
    )
    [int[]]$lifecycleUserSeries = @(
        $lifecycleCheckpoints | ForEach-Object {
            [int]$_.metrics.userObjects
        }
    )
    [int[]]$lifecycleProcessSeries = @(
        $lifecycleCheckpoints | ForEach-Object {
            [int]$_.metrics.processHandles
        }
    )
    $lifecycleGdiGrowth =
        Get-PositiveMonotonicGrowth $lifecycleGdiSeries
    $lifecycleUserGrowth =
        Get-PositiveMonotonicGrowth $lifecycleUserSeries
    $lifecycleProcessGrowth =
        Get-PositiveMonotonicGrowth $lifecycleProcessSeries
    Assert-Equal `
        ([bool]$lifecycleResources.handleTrend.gdiPositiveMonotonicGrowth) `
        $lifecycleGdiGrowth 'surfaceLifecycle.resources.handleTrend.gdi'
    Assert-Equal `
        ([bool]$lifecycleResources.handleTrend.userPositiveMonotonicGrowth) `
        $lifecycleUserGrowth 'surfaceLifecycle.resources.handleTrend.user'
    Assert-Equal `
        ([bool]$lifecycleResources.handleTrend.processPositiveMonotonicGrowth) `
        $lifecycleProcessGrowth `
        'surfaceLifecycle.resources.handleTrend.process'
    Assert-Equal `
        ([bool]$lifecycleResources.handleTrend.anyPositiveMonotonicGrowth) `
        ($lifecycleGdiGrowth -or
            $lifecycleUserGrowth -or
            $lifecycleProcessGrowth) `
        'surfaceLifecycle.resources.handleTrend.any'
    if ($lifecycleGdiGrowth -or
        $lifecycleUserGrowth -or
        $lifecycleProcessGrowth) {
        throw 'A surface lifecycle handle checkpoint series has positive monotonic growth.'
    }

    [string[]]$expectedWidgetTypes = @(
        'CF7Launcher.Guardian.Hud.ComboWidget'
        'CF7Launcher.Guardian.Hud.NotchWidget'
        'CF7Launcher.Guardian.Hud.RightContextWidget'
        'CF7Launcher.Guardian.Hud.SafeExitPanelWidget'
        'CF7Launcher.Guardian.Hud.ToastWidget'
    )
    [string[]]$actualWidgetTypes =
        @($Report.nativeHud.productionWidgetTypes | ForEach-Object {
            [string]$_
        })
    Assert-Equal $actualWidgetTypes.Count $expectedWidgetTypes.Count `
        'nativeHud.productionWidgetTypes.count'
    for ($index = 0; $index -lt $expectedWidgetTypes.Count; $index++) {
        Assert-Equal $actualWidgetTypes[$index] $expectedWidgetTypes[$index] `
            "nativeHud.productionWidgetTypes[$index]"
    }
    Assert-RectangleEqual $Report.nativeHud.unionAfter `
        $Report.nativeHud.unionBefore 'nativeHud.union'

    $hiddenSamples = ConvertTo-FiniteSamples `
        $Report.nativeHud.playerInfoHidden.commitSamples `
        'nativeHud.hidden.commitSamples' 3000
    $enabledSamples = ConvertTo-FiniteSamples `
        $Report.nativeHud.playerInfoEnabled.commitSamples `
        'nativeHud.enabled.commitSamples' 3000
    $hiddenSummary = Get-NearestRankSummary $hiddenSamples
    $enabledSummary = Get-NearestRankSummary $enabledSamples
    Assert-Summary $Report.nativeHud.playerInfoHidden.commitSummary `
        $hiddenSummary 'nativeHud.hidden.commitSummary'
    Assert-Summary $Report.nativeHud.playerInfoEnabled.commitSummary `
        $enabledSummary 'nativeHud.enabled.commitSummary'
    Assert-Equal ([int]$Report.nativeHud.playerInfoHidden.successCount) `
        3000 'nativeHud.hidden.successCount'
    Assert-Equal ([int]$Report.nativeHud.playerInfoEnabled.successCount) `
        3000 'nativeHud.enabled.successCount'
    $hiddenDimensions = @($Report.nativeHud.playerInfoHidden.dimensions)
    $enabledDimensions = @($Report.nativeHud.playerInfoEnabled.dimensions)
    Assert-Equal $hiddenDimensions.Count 1 'nativeHud.hidden.dimensions.count'
    Assert-Equal $enabledDimensions.Count 1 'nativeHud.enabled.dimensions.count'
    foreach ($dimension in @($hiddenDimensions[0], $enabledDimensions[0])) {
        Assert-Equal ([int]$dimension.width) `
            ([int]$Report.nativeHud.unionBefore.width) `
            'nativeHud.commit.width'
        Assert-Equal ([int]$dimension.height) `
            ([int]$Report.nativeHud.unionBefore.height) `
            'nativeHud.commit.height'
    }
    if ([double]$hiddenSummary.p95 -gt 0) {
        $regression =
            (([double]$enabledSummary.p95 / [double]$hiddenSummary.p95) - 1) *
            100
        Assert-Near `
            ([double]$Report.nativeHud.commitP95RegressionPercent) `
            $regression 'nativeHud.commitP95RegressionPercent'
        if ($regression -gt 10.0) {
            throw "NativeHud commit p95 regression $regression exceeds 10%."
        }
    } elseif ($null -ne $Report.nativeHud.commitP95RegressionPercent) {
        throw 'Zero hidden-side p95 requires a null relative regression.'
    }

    $active = $Report.splitSurface.active
    Assert-Equal ([int]$active.visualSteps) 3000 'split.active.visualSteps'
    Assert-Equal `
        ([int]$active.targetTransitions + [int]$active.easingSteps) `
        3000 'split.active.transition+easing'
    foreach ($property in @(
            'repaintRequestCount',
            'paintCount',
            'commitCount',
            'commitSuccessCount')) {
        Assert-Equal ([long]$active.counters.$property) 3000 `
            "split.active.counters.$property"
    }
    Assert-Equal ([long]$active.counters.commitFailureCount) 0 `
        'split.active.counters.commitFailureCount'
    Assert-Equal ([string]$active.observerCommitMeasurementScope) `
        'actual prepared-memory-DC UpdateLayeredWindow transaction; reusable top-down PArgb DIB/memory-DC setup and cleanup are amortized across frames and guarded by lifecycle GDI/USER/process zero-growth checks' `
        'split.active.observerCommitMeasurementScope'

    $requestSamples = ConvertTo-FiniteSamples $active.requestSamples `
        'split.active.requestSamples' 3000
    $surfaceSamples = ConvertTo-FiniteSamples $active.surfaceSamples `
        'split.active.surfaceSamples' 3000
    $paintSamples = ConvertTo-FiniteSamples $active.paintSamples `
        'split.active.paintSamples' 3000
    $commitSamples = ConvertTo-FiniteSamples $active.commitSamples `
        'split.active.commitSamples' 3000
    $observerSamples = ConvertTo-FiniteSamples $active.observerCommitSamples `
        'split.active.observerCommitSamples' 3000
    $ulwSamples = ConvertTo-FiniteSamples `
        $active.updateLayeredWindowOnlySamples `
        'split.active.updateLayeredWindowOnlySamples' 3000
    $computedSummaries = [ordered]@{
        requestSummary = Get-NearestRankSummary $requestSamples
        surfaceSummary = Get-NearestRankSummary $surfaceSamples
        paintSummary = Get-NearestRankSummary $paintSamples
        commitSummary = Get-NearestRankSummary $commitSamples
        observerCommitSummary = Get-NearestRankSummary $observerSamples
        updateLayeredWindowOnlySummary = Get-NearestRankSummary $ulwSamples
    }
    foreach ($entry in $computedSummaries.GetEnumerator()) {
        Assert-Summary $active.($entry.Key) $entry.Value `
            "split.active.$($entry.Key)"
    }
    if ([double]$computedSummaries.surfaceSummary.p95 -gt 4.0) {
        throw "Split surface p95 exceeds 4 ms."
    }
    if ([double]$computedSummaries.observerCommitSummary.p95 -ge 33.0) {
        throw "Split actual commit p95 must be below 33 ms."
    }
    $observerGeometry = @($active.observerCommitGeometry)
    Assert-Equal $observerGeometry.Count 1 `
        'split.active.observerCommitGeometry.count'
    Assert-Equal ([int]$observerGeometry[0].screenX) `
        ([int]$Report.viewport.tightPhysicalBounds.x) `
        'split.active.observerCommitGeometry.screenX'
    Assert-Equal ([int]$observerGeometry[0].screenY) `
        ([int]$Report.viewport.tightPhysicalBounds.y) `
        'split.active.observerCommitGeometry.screenY'
    Assert-Equal ([int]$observerGeometry[0].width) 528 `
        'split.active.observerCommitGeometry.width'
    Assert-Equal ([int]$observerGeometry[0].height) 150 `
        'split.active.observerCommitGeometry.height'
    Assert-Equal ([int]$Report.viewport.tightPhysicalBounds.width) 528 `
        'viewport.tightPhysicalBounds.width'
    Assert-Equal ([int]$Report.viewport.tightPhysicalBounds.height) 150 `
        'viewport.tightPhysicalBounds.height'
    Assert-Equal ([long]$Report.viewport.tightPixels) 79200 `
        'viewport.tightPixels'
    Assert-Equal ([long]$Report.viewport.tightBytes) 316800 `
        'viewport.tightBytes'

    $idle = $Report.splitSurface.idle
    Assert-Equal ([int]$idle.ticks) 3000 'split.idle.ticks'
    foreach ($property in @(
            'repaintRequestCount',
            'paintCount',
            'commitCount',
            'commitSuccessCount',
            'commitFailureCount')) {
        Assert-Equal ([long]$idle.counters.$property) 0 `
            "split.idle.counters.$property"
    }

    $activePipeline = $Report.splitSurface.pipeline.active
    Assert-Equal ([long]$activePipeline.parseCount) 10 `
        'split.pipeline.active.parseCount'
    Assert-Equal ([long]$activePipeline.rasterCount) 10 `
        'split.pipeline.active.rasterCount'
    Assert-Equal ([long]$activePipeline.publishCount) 1 `
        'split.pipeline.active.publishCount'
    Assert-Equal ([long]$activePipeline.faultCount) 0 `
        'split.pipeline.active.faultCount'
    Assert-Equal ([int]$activePipeline.activeWorkers) 0 `
        'split.pipeline.active.activeWorkers'
    Assert-Equal ([int]$activePipeline.maxConcurrentWorkers) 1 `
        'split.pipeline.active.maxConcurrentWorkers'
    Assert-Equal ([long]$activePipeline.cacheBytes) `
        $independentBatchBytes `
        'split.pipeline.active.cacheBytes'
    if ([long]$activePipeline.cacheBytes -gt 16777216) {
        throw 'The active surface pipeline cache exceeds 16 MiB.'
    }
    Assert-Equal ([int]$activePipeline.cacheCount) 1 `
        'split.pipeline.active.cacheCount'
    if ([string]::IsNullOrWhiteSpace(
            [string]$activePipeline.currentBatchKey)) {
        throw 'The active surface pipeline currentBatchKey is empty.'
    }
    Assert-Equal ([string]$activePipeline.currentBatchKey) `
        ([string]$activePipeline.desiredBatchKey) `
        'split.pipeline.active.currentEqualsDesired'

    $shutdown = $Report.splitSurface.pipeline.shutdown
    Assert-Equal ([bool]$shutdown.surfaceShutdown) $true `
        'split.pipeline.shutdown.surfaceShutdown'
    $shutdownPipeline = $shutdown.counters
    Assert-Equal ([long]$shutdownPipeline.parseCount) 10 `
        'split.pipeline.shutdown.parseCount'
    Assert-Equal ([long]$shutdownPipeline.rasterCount) 10 `
        'split.pipeline.shutdown.rasterCount'
    Assert-Equal ([long]$shutdownPipeline.faultCount) 0 `
        'split.pipeline.shutdown.faultCount'
    Assert-Equal ([int]$shutdownPipeline.activeWorkers) 0 `
        'split.pipeline.shutdown.activeWorkers'
    Assert-Equal ([long]$shutdownPipeline.cacheBytes) 0 `
        'split.pipeline.shutdown.cacheBytes'
    Assert-Equal ([int]$shutdownPipeline.cacheCount) 0 `
        'split.pipeline.shutdown.cacheCount'
    Assert-Equal $shutdownPipeline.desiredBatchKey $null `
        'split.pipeline.shutdown.desiredBatchKey'
    Assert-Equal $shutdownPipeline.currentBatchKey $null `
        'split.pipeline.shutdown.currentBatchKey'
    Assert-Equal $shutdownPipeline.lastFault $null `
        'split.pipeline.shutdown.lastFault'
    Assert-Equal ([long]$shutdownPipeline.disposedBatchCount) 1 `
        'split.pipeline.shutdown.disposedBatchCount'
    Assert-Equal ([long]$shutdownPipeline.disposedLayerCount) 8 `
        'split.pipeline.shutdown.disposedLayerCount'

    $resources = $Report.resources
    foreach ($property in @(
            'cpuMilliseconds',
            'allocatedBytes',
            'gc0',
            'gc1',
            'gc2',
            'workingSetBytes',
            'privateBytes',
            'processHandles',
            'gdiObjects',
            'userObjects')) {
        $computed = [double]$resources.after.$property -
            [double]$resources.before.$property
        Assert-Near ([double]$resources.delta.$property) $computed `
            "resources.delta.$property"
    }
    foreach ($property in @('gdiObjects', 'userObjects', 'processHandles')) {
        if ([int]$resources.delta.$property -gt 0) {
            throw "Resource handle endpoint grew: $property=$($resources.delta.$property)."
        }
    }

    $checkpoints = @($resources.checkpoints)
    if ($checkpoints.Count -ne 14) {
        throw "Expected 14 resource checkpoints; got $($checkpoints.Count)."
    }
    foreach ($property in @(
            'cpuMilliseconds',
            'allocatedBytes',
            'gc0',
            'gc1',
            'gc2',
            'workingSetBytes',
            'privateBytes',
            'processHandles',
            'gdiObjects',
            'userObjects')) {
        Assert-Equal $resources.before.$property `
            $checkpoints[0].metrics.$property `
            "resources.beforeCheckpointIdentity.$property"
        Assert-Equal $resources.after.$property `
            $checkpoints[13].metrics.$property `
            "resources.afterCheckpointIdentity.$property"
    }
    [int[]]$gdiSeries = @($checkpoints | ForEach-Object {
        [int]$_.metrics.gdiObjects
    })
    [int[]]$userSeries = @($checkpoints | ForEach-Object {
        [int]$_.metrics.userObjects
    })
    [int[]]$processSeries = @($checkpoints | ForEach-Object {
        [int]$_.metrics.processHandles
    })
    $gdiGrowth = Get-PositiveMonotonicGrowth $gdiSeries
    $userGrowth = Get-PositiveMonotonicGrowth $userSeries
    $processGrowth = Get-PositiveMonotonicGrowth $processSeries
    Assert-Equal `
        ([bool]$resources.handleTrend.gdiPositiveMonotonicGrowth) `
        $gdiGrowth 'resources.handleTrend.gdi'
    Assert-Equal `
        ([bool]$resources.handleTrend.userPositiveMonotonicGrowth) `
        $userGrowth 'resources.handleTrend.user'
    Assert-Equal `
        ([bool]$resources.handleTrend.processPositiveMonotonicGrowth) `
        $processGrowth 'resources.handleTrend.process'
    Assert-Equal `
        ([bool]$resources.handleTrend.anyPositiveMonotonicGrowth) `
        ($gdiGrowth -or $userGrowth -or $processGrowth) `
        'resources.handleTrend.any'
    if ($gdiGrowth -or $userGrowth -or $processGrowth) {
        throw 'A handle checkpoint series has positive monotonic growth.'
    }

    [string[]]$expectedGateIds = @(
        'native_hud_all_commits_succeeded'
        'native_hud_all_production_widgets_visible'
        'native_hud_commit_dimensions_match_union'
        'native_hud_commit_p95_regression'
        'native_hud_enabled_commit_count'
        'native_hud_hidden_commit_count'
        'native_hud_union_unchanged'
        'raster_batch_byte_budget'
        'raster_batch_byte_size'
        'raster_batch_canonical_layer_count'
        'raster_batch_exact_fragment_ids'
        'raster_batch_owned_dispose'
        'raster_batch_owned_fragment_count'
        'raster_batch_owned_payload_contract'
        'raster_batch_parse_count'
        'raster_batch_raster_count'
        'split_actual_commit_p95'
        'split_commit_count'
        'split_commit_geometry_matches_tight'
        'split_commit_success_count'
        'split_idle_commit_zero'
        'split_idle_paint_zero'
        'split_idle_repaint_zero'
        'split_paint_count'
        'split_repaint_count'
        'split_sample_counts'
        'split_surface_p95'
        'split_visual_step_count'
        'split_pipeline_active_bake_contract'
        'split_pipeline_active_cache_contract'
        'split_pipeline_shutdown_drained'
        'split_pipeline_shutdown_owned_dispose'
        'surface_lifecycle_cycle_count'
        'surface_lifecycle_gdi_handles_no_net_growth'
        'surface_lifecycle_handle_series_not_positive_linear'
        'surface_lifecycle_no_late_commit'
        'surface_lifecycle_owner_forms_restored'
        'surface_lifecycle_process_handles_no_net_growth'
        'surface_lifecycle_queued_render_suppressed'
        'surface_lifecycle_real_publish_and_ulw'
        'surface_lifecycle_shutdown_drained'
        'surface_lifecycle_user_handles_no_net_growth'
        'surface_lifecycle_warmup_converged'
        'surface_lifecycle_window_destroyed'
        'gdi_handles_no_net_growth'
        'handle_series_not_positive_linear'
        'process_handles_no_net_growth'
        'user_handles_no_net_growth'
    )
    [array]::Sort($expectedGateIds, [System.StringComparer]::Ordinal)
    [string[]]$actualGateIds = @($Report.gates | ForEach-Object {
        if ($_.passed -ne $true) {
            throw "Report gate failed: $($_.id)."
        }
        [string]$_.id
    })
    [array]::Sort($actualGateIds, [System.StringComparer]::Ordinal)
    Assert-Equal $actualGateIds.Count $expectedGateIds.Count 'gates.count'
    for ($index = 0; $index -lt $expectedGateIds.Count; $index++) {
        Assert-Equal $actualGateIds[$index] $expectedGateIds[$index] `
            "gates[$index]"
    }
    if (@($Report.failures).Count -ne 0) {
        throw "Report failures are non-empty: $($Report.failures -join '; ')"
    }
}

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = [System.IO.Path]::GetFullPath(
        (Join-Path $PSScriptRoot '..\..'))
} else {
    $ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
}
if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = Join-Path $ProjectRoot `
        'tmp\player-info-hud-b0-06-runtime-qualification.json'
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
[System.IO.Directory]::CreateDirectory(
    (Split-Path -Parent $ReportPath)) | Out-Null

$definedPerformanceOverrides = @(
    $performanceOverrideEnvironmentNames | Where-Object {
        $null -ne [System.Environment]::GetEnvironmentVariable(
            $_,
            [System.EnvironmentVariableTarget]::Process)
    })
if ($definedPerformanceOverrides.Count -ne 0) {
    throw (
        'B0-06 qualification requires these JIT/GC overrides to be absent: ' +
        ($definedPerformanceOverrides -join ', '))
}

$runnerProcess = [System.Diagnostics.Process]::GetCurrentProcess()
try {
    $expectedPriorityClass = $runnerProcess.PriorityClass.ToString()
    if ($expectedPriorityClass -cne 'Normal') {
        throw (
            'B0-06 qualification requires Normal runner priority; got ' +
            "'$expectedPriorityClass'.")
    }
    [long]$signedAffinityMask =
        $runnerProcess.ProcessorAffinity.ToInt64()
    [byte[]]$affinityBytes =
        [System.BitConverter]::GetBytes($signedAffinityMask)
    [uint64]$unsignedAffinityMask =
        [System.BitConverter]::ToUInt64($affinityBytes, 0)
    if ($unsignedAffinityMask -eq 0) {
        throw 'B0-06 qualification requires a nonzero runner affinity mask.'
    }
    $expectedAffinityMask = $unsignedAffinityMask.ToString(
        'X16',
        [System.Globalization.CultureInfo]::InvariantCulture)
} finally {
    $runnerProcess.Dispose()
}

. $resolver
$dotnet = Resolve-Cf7Dotnet -ProjectRoot $ProjectRoot
$sdkVersion = (& $dotnet --version 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $sdkVersion -ne '10.0.300') {
    throw "B0-06 qualification requires exact .NET SDK 10.0.300; got '$sdkVersion'."
}

$runId = [Guid]::NewGuid().ToString('N')
$previousReport = $env:CF7_PLAYER_INFO_B006_REPORT_PATH
$previousRunId = $env:CF7_PLAYER_INFO_B006_RUN_ID
$previousSdk = $env:CF7_PLAYER_INFO_B006_SDK_VERSION
$previousRoot = $env:CF7_PLAYER_INFO_B006_PROJECT_ROOT
$previousExpectedPriorityClass =
    $env:CF7_PLAYER_INFO_B006_EXPECTED_PRIORITY_CLASS
$previousExpectedAffinityMask =
    $env:CF7_PLAYER_INFO_B006_EXPECTED_AFFINITY_MASK
$env:CF7_PLAYER_INFO_B006_REPORT_PATH = $ReportPath
$env:CF7_PLAYER_INFO_B006_RUN_ID = $runId
$env:CF7_PLAYER_INFO_B006_SDK_VERSION = $sdkVersion
$env:CF7_PLAYER_INFO_B006_PROJECT_ROOT = $ProjectRoot
$env:CF7_PLAYER_INFO_B006_EXPECTED_PRIORITY_CLASS =
    $expectedPriorityClass
$env:CF7_PLAYER_INFO_B006_EXPECTED_AFFINITY_MASK =
    $expectedAffinityMask
$testExitCode = $null
try {
    $restore = Invoke-ProcessWithTimeout `
        -FilePath $dotnet `
        -Arguments @('restore', $testsProject, '--locked-mode') `
        -TimeoutSeconds $TestTimeoutSeconds `
        -Label 'B0-06 locked restore'
    if ($restore.ExitCode -ne 0) {
        throw "B0-06 locked restore failed with exit code $($restore.ExitCode)."
    }
    $build = Invoke-ProcessWithTimeout `
        -FilePath $dotnet `
        -Arguments @(
            'build'
            $testsProject
            '-c'
            'Release'
            '--no-restore'
            '--no-incremental'
        ) `
        -TimeoutSeconds $TestTimeoutSeconds `
        -Label 'B0-06 non-incremental Release build'
    if ($build.ExitCode -ne 0) {
        throw "B0-06 non-incremental build failed with exit code $($build.ExitCode)."
    }
    $test = Invoke-ProcessWithTimeout `
        -FilePath $dotnet `
        -Arguments @(
            'test'
            $testsProject
            '-c'
            'Release'
            '--no-restore'
            '--no-build'
            '--filter'
            'FullyQualifiedName=CF7Launcher.Tests.Guardian.Hud.PlayerInfo.PlayerInfoB006RuntimeQualificationTests.B0_06_ActualStaHwndAndLayeredWindowQualification'
            '--logger'
            'console;verbosity=normal'
        ) `
        -TimeoutSeconds $TestTimeoutSeconds `
        -Label 'B0-06 focused HWND/ULW qualification'
    $testExitCode = $test.ExitCode
} finally {
    $env:CF7_PLAYER_INFO_B006_REPORT_PATH = $previousReport
    $env:CF7_PLAYER_INFO_B006_RUN_ID = $previousRunId
    $env:CF7_PLAYER_INFO_B006_SDK_VERSION = $previousSdk
    $env:CF7_PLAYER_INFO_B006_PROJECT_ROOT = $previousRoot
    $env:CF7_PLAYER_INFO_B006_EXPECTED_PRIORITY_CLASS =
        $previousExpectedPriorityClass
    $env:CF7_PLAYER_INFO_B006_EXPECTED_AFFINITY_MASK =
        $previousExpectedAffinityMask
}

if (-not (Test-Path -LiteralPath $ReportPath -PathType Leaf)) {
    throw "B0-06 test produced no report: $ReportPath"
}
$reportBytes = [System.IO.File]::ReadAllBytes($ReportPath)
if ($reportBytes.Length -ge 3 -and
    $reportBytes[0] -eq 0xEF -and
    $reportBytes[1] -eq 0xBB -and
    $reportBytes[2] -eq 0xBF) {
    throw 'B0-06 report must be UTF-8 without BOM.'
}
if ($reportBytes.Length -eq 0 -or
    $reportBytes[$reportBytes.Length - 1] -ne 0x0A -or
    [array]::IndexOf($reportBytes, [byte]0x0D) -ge 0) {
    throw 'B0-06 report must use canonical LF with one final LF.'
}
$report = Get-Content -LiteralPath $ReportPath -Raw -Encoding utf8 |
    ConvertFrom-Json
if ($testExitCode -ne 0) {
    Assert-Equal ([string]$report.schema) `
        'cf7.player-info-hud.b0-06-runtime-qualification' 'failure.schema'
    Assert-Equal ([int]$report.schemaVersion) 2 'failure.schemaVersion'
    Assert-Equal ([string]$report.runId) $runId 'failure.runId'
    Assert-Equal ([string]$report.status) 'failed' 'failure.status'
    Assert-Equal ([string]$report.measurementKind) `
        'actual_sta_hwnd_update_layered_window' 'failure.measurementKind'
    $failureProperty = $report.PSObject.Properties['failure']
    if ($null -ne $failureProperty) {
        $failureType = [string]$report.failure.type
        $failureMessage = [string]$report.failure.message
        if ([string]::IsNullOrWhiteSpace($failureType) -or
            [string]::IsNullOrWhiteSpace($failureMessage)) {
            throw 'B0-06 exception report must identify failure.type and failure.message.'
        }
        $failureDetail = '{0}: {1}' -f $failureType, $failureMessage
    } else {
        $failureMessages = @(
            $report.failures |
                ForEach-Object { [string]$_ } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($failureMessages.Count -eq 0) {
            throw 'B0-06 failed report must contain exception or gate diagnostics.'
        }
        $failureDetail = $failureMessages -join '; '
    }
    throw (
        'B0-06 focused qualification failed with exit code {0}: {1}' -f
            $testExitCode,
            $failureDetail)
}

Test-ReportContract `
    -Report $report `
    -ExpectedRunId $runId `
    -ExpectedAffinityMask $expectedAffinityMask

$reportSha256 = Get-Sha256Hex -LiteralPath $ReportPath
Write-Host (
    'PLAYER_INFO_B0_06_OK report={0} runId={1} bytes={2} sha256={3} nativeHiddenP95={4} nativeEnabledP95={5} splitSurfaceP95={6} splitCommitP95={7}' -f
        $ReportPath,
        $runId,
        $reportBytes.Length,
        $reportSha256,
        $report.nativeHud.playerInfoHidden.commitSummary.p95,
        $report.nativeHud.playerInfoEnabled.commitSummary.p95,
        $report.splitSurface.active.surfaceSummary.p95,
        $report.splitSurface.active.observerCommitSummary.p95)
