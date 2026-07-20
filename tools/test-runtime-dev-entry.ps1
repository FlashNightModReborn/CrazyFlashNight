[CmdletBinding()]
param(
    [string]$ProjectRoot
)

$ErrorActionPreference = 'Stop'
if (-not $ProjectRoot) {
    $testDirectory = if ($PSScriptRoot) {
        $PSScriptRoot
    } else {
        Split-Path -Parent -Path $MyInvocation.MyCommand.Path
    }
    $ProjectRoot = Split-Path -Parent $testDirectory
}
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
$devPath = Join-Path $ProjectRoot 'automation\dev.ps1'
$cmdMatches = @(Get-ChildItem -LiteralPath $ProjectRoot -File -Filter '*.cmd' | Where-Object {
    (Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8).IndexOf(
        '%~dp0automation\dev.ps1', [StringComparison]::Ordinal) -ge 0
})
$cmdPath = if ($cmdMatches.Count -eq 1) { $cmdMatches[0].FullName } else { $null }

$script:checkCount = 0
function Assert-Cf7DevEntry {
    param(
        [Parameter(Mandatory=$true)][bool]$Condition,
        [Parameter(Mandatory=$true)][string]$Message
    )
    $script:checkCount++
    if (-not $Condition) { throw "Runtime dev entry regression: $Message" }
}

function Assert-Cf7DevContains {
    param(
        [Parameter(Mandatory=$true)][string]$Text,
        [Parameter(Mandatory=$true)][string]$Needle,
        [Parameter(Mandatory=$true)][string]$Message
    )
    Assert-Cf7DevEntry -Condition ($Text.IndexOf($Needle, [StringComparison]::Ordinal) -ge 0) -Message $Message
}

Assert-Cf7DevEntry -Condition (Test-Path -LiteralPath $devPath -PathType Leaf) -Message "entry missing: $devPath"
Assert-Cf7DevEntry -Condition ($cmdMatches.Count -eq 1) `
    -Message "expected exactly one root CMD wrapper for automation/dev.ps1, found $($cmdMatches.Count)"

$tokens = $null
$parseErrors = $null
[void][Management.Automation.Language.Parser]::ParseFile($devPath, [ref]$tokens, [ref]$parseErrors)
Assert-Cf7DevEntry -Condition ($parseErrors.Count -eq 0) `
    -Message "PowerShell parse failed: $($parseErrors | ForEach-Object Message -join '; ')"

$devSource = Get-Content -LiteralPath $devPath -Raw -Encoding UTF8
Assert-Cf7DevContains $devSource '[switch]$ForceBuild' 'dev entry must support -ForceBuild'
Assert-Cf7DevContains $devSource '[switch]$BuildOnly' 'dev entry must support -BuildOnly'
Assert-Cf7DevContains $devSource '[switch]$ReuseOnly' 'dev entry must support -ReuseOnly'
Assert-Cf7DevContains $devSource '[switch]$Status' 'dev entry must support -Status'
Assert-Cf7DevContains $devSource 'Get-Cf7RuntimeBuildIdentityV2' 'reuse must bind to current Worktree identity'
Assert-Cf7DevContains $devSource 'cf7-local-dev-runtime-selection.v1' 'active pointer must have a versioned schema'
Assert-Cf7DevContains $devSource 'candidateRelativePath' 'active pointer must store a repository-relative candidate path'
Assert-Cf7DevContains $devSource 'INDEX_ONLY_REVERIFY_BEFORE_EXECUTION' 'active pointer must explicitly deny trust authority'
Assert-Cf7DevContains $devSource '[IO.File]::Replace' 'active pointer updates must atomically replace an existing pointer'
Assert-Cf7DevContains $devSource 'active.v1.backup-' `
    'Windows PowerShell pointer replacement must use a real same-directory backup path'
Assert-Cf7DevContains $devSource '[IO.File]::Replace($temporaryPointer, $activePointerPath, $backupPointer, $true)' `
    'pointer replacement must use the Windows PowerShell-compatible atomic overload'
Assert-Cf7DevContains $devSource '-SkipPrepare' 'cache miss build must skip release prepare'
Assert-Cf7DevContains $devSource '-SkipPolicy' 'cache miss build must skip production policy'
Assert-Cf7DevContains $devSource "-BuilderId 'local-dev'" 'cache miss build must use the local development label'
Assert-Cf7DevContains $devSource "[string]`$buildRecord.deploymentStatus -cne 'NOT_DEPLOYED'" `
    'dev entry must validate candidate-only build status'
Assert-Cf7DevContains $devSource "[string]`$buildRecord.runtimeMode -cne 'isolated_candidate'" `
    'dev entry must validate isolated candidate mode'
Assert-Cf7DevContains $devSource '-CandidateRoot' 'dev entry must hand the exact candidate to start.ps1'
Assert-Cf7DevContains $devSource "lifecycleState = 'candidate_executed'" `
    'successful default execution must report candidate_executed'
Assert-Cf7DevContains $devSource "'equivocation'" `
    'status must expose same-identity payload closure divergence'
Assert-Cf7DevContains $devSource '[AllowEmptyCollection()][object[]]$Matches = @()' `
    'status and reuse selection must accept a fresh worktree with zero cached candidates'
Assert-Cf7DevContains $devSource 'Fresh local candidate diverged from an existing payload closure' `
    '-ForceBuild must reject a fresh candidate that diverges from an existing closure'
Assert-Cf7DevEntry -Condition ($devSource.IndexOf('Copy-Item', [StringComparison]::OrdinalIgnoreCase) -lt 0) `
    -Message 'dev entry must never copy a candidate into formal runtime'
Assert-Cf7DevEntry -Condition ($devSource.IndexOf('ForceReplace', [StringComparison]::OrdinalIgnoreCase) -lt 0) `
    -Message 'dev entry must preserve immutable candidates'

$cmdSource = Get-Content -LiteralPath $cmdPath -Raw -Encoding UTF8
Assert-Cf7DevContains $cmdSource '%~dp0automation\dev.ps1' 'root CMD must resolve dev.ps1 relative to itself'
Assert-Cf7DevContains $cmdSource '%*' 'root CMD must forward all caller arguments'
Assert-Cf7DevContains $cmdSource 'CF7_NO_PAUSE' 'root CMD must support non-interactive failure handling'
Assert-Cf7DevContains $cmdSource 'pause' 'root CMD must preserve a double-click failure window by default'
Assert-Cf7DevEntry -Condition ($cmdSource.IndexOf('CRAZYFLASHER7MercenaryEmpire.exe', [StringComparison]::OrdinalIgnoreCase) -lt 0) `
    -Message 'root CMD must not bypass the controlled development entry'

# Exercise the exact File.Replace contract under Windows PowerShell/.NET Framework.
# A null backup path is accepted by some modern runtimes but throws there, which would
# turn an otherwise successful real launch into a false failure on the second pointer write.
$replaceFixtureRoot = Join-Path $ProjectRoot ('tmp\runtime-dev-replace-test-' + [Guid]::NewGuid().ToString('N'))
$replaceSource = Join-Path $replaceFixtureRoot 'next.json'
$replaceTarget = Join-Path $replaceFixtureRoot 'active.json'
$replaceBackup = Join-Path $replaceFixtureRoot 'backup.json'
try {
    New-Item -ItemType Directory -Path $replaceFixtureRoot -Force | Out-Null
    [IO.File]::WriteAllText($replaceSource, 'new')
    [IO.File]::WriteAllText($replaceTarget, 'old')
    [IO.File]::Replace($replaceSource, $replaceTarget, $replaceBackup, $true)
    Assert-Cf7DevEntry -Condition ((Get-Content -LiteralPath $replaceTarget -Raw) -ceq 'new') `
        -Message 'Windows PowerShell-compatible atomic replacement must activate the new pointer bytes'
    Assert-Cf7DevEntry -Condition ((Get-Content -LiteralPath $replaceBackup -Raw) -ceq 'old') `
        -Message 'atomic replacement must preserve the prior pointer in its temporary backup'
} finally {
    if (Test-Path -LiteralPath $replaceFixtureRoot -PathType Container) {
        Remove-Item -LiteralPath $replaceFixtureRoot -Recurse -Force
    }
}

$pointerPath = Join-Path $ProjectRoot 'tmp\runtime-dev\active.v1.json'
$pointerExistedBefore = Test-Path -LiteralPath $pointerPath -PathType Leaf
$pointerHashBefore = if ($pointerExistedBefore) {
    (Get-FileHash -LiteralPath $pointerPath -Algorithm SHA256).Hash
} else {
    $null
}
$statusOutput = @(& $devPath -Status)
$statusRecords = @($statusOutput | Where-Object {
    $null -ne $_ -and [string]$_.schema -ceq 'cf7-local-dev-runtime-status.v1'
})
Assert-Cf7DevEntry -Condition ($statusRecords.Count -eq 1) -Message 'status must return exactly one structured record'
Assert-Cf7DevEntry -Condition ([string]$statusRecords[0].deploymentStatus -ceq 'NOT_DEPLOYED') `
    -Message 'status must never describe the local candidate as deployed'
$pointerExistsAfter = Test-Path -LiteralPath $pointerPath -PathType Leaf
Assert-Cf7DevEntry -Condition ($pointerExistsAfter -eq $pointerExistedBefore) `
    -Message '-Status must not create or remove the active pointer'
if ($pointerExistedBefore) {
    $pointerHashAfter = (Get-FileHash -LiteralPath $pointerPath -Algorithm SHA256).Hash
    Assert-Cf7DevEntry -Condition ($pointerHashAfter -ceq $pointerHashBefore) `
        -Message '-Status must not mutate the active pointer'
}

# Materialize two tiny, same-identity metadata fixtures with different closures. They are
# deliberately incomplete runtime bundles: status selection is metadata-only, while every
# executable path remains protected by start.ps1's authoritative full verifier.
. (Join-Path $ProjectRoot 'tools\runtime-build-v2-common.ps1')
$fixtureIdentity = Get-Cf7RuntimeBuildIdentityV2 -ProjectRoot $ProjectRoot -Mode Worktree
$candidateBase = Join-Path $ProjectRoot 'tmp\runtime-candidates\v2'
$fixturePrefix = 'dev-entry-equivocation-' + [Guid]::NewGuid().ToString('N')
$fixtureRoots = @(
    (Join-Path $candidateBase ($fixturePrefix + '-a')),
    (Join-Path $candidateBase ($fixturePrefix + '-b'))
)
$utf8NoBom = New-Object Text.UTF8Encoding($false)
try {
    for ($index = 0; $index -lt $fixtureRoots.Count; $index++) {
        $fixtureRuntime = Join-Path $fixtureRoots[$index] 'runtime'
        New-Item -ItemType Directory -Path $fixtureRuntime -Force | Out-Null
        $closure = if ($index -eq 0) { 'A' * 64 } else { 'B' * 64 }
        $metadata = [ordered]@{
            schema = 'cf7-runtime-candidate-metadata.v2'
            builderLabel = 'dev-entry-test'
            artifactSourceHash = [string]$fixtureIdentity.artifactSourceHash
            producerRecipeHash = [string]$fixtureIdentity.producerRecipeHash
            toolchainLockHash = [string]$fixtureIdentity.toolchainLockHash
            buildIdentityHash = [string]$fixtureIdentity.buildIdentityHash
            payloadClosureHash = $closure
            createdAtUtc = [DateTime]::UtcNow.ToString('o')
        }
        [IO.File]::WriteAllText(
            (Join-Path $fixtureRoots[$index] 'runtime-build-metadata.v2.json'),
            (($metadata | ConvertTo-Json -Depth 5) + "`n"),
            $utf8NoBom)
        [IO.File]::WriteAllText(
            (Join-Path $fixtureRuntime 'cf7-runtime-manifest.tsv'),
            "fixture`n",
            $utf8NoBom)
        [IO.File]::WriteAllBytes(
            (Join-Path $fixtureRuntime 'CRAZYFLASHER7MercenaryEmpire.Core.dll'),
            [byte[]]@($index + 1))
    }
    $equivocationOutput = @(& $devPath -Status)
    $equivocationRecords = @($equivocationOutput | Where-Object {
        $null -ne $_ -and [string]$_.schema -ceq 'cf7-local-dev-runtime-status.v1'
    })
    Assert-Cf7DevEntry -Condition ($equivocationRecords.Count -eq 1) `
        -Message 'equivocation status must return exactly one structured record'
    Assert-Cf7DevEntry -Condition ([string]$equivocationRecords[0].selectionState -ceq 'equivocation') `
        -Message 'same-identity divergent closures must produce equivocation status'
    Assert-Cf7DevEntry -Condition ($null -eq $equivocationRecords[0].candidateRoot) `
        -Message 'equivocation status must not return a reusable candidate'
    Assert-Cf7DevEntry -Condition ([int]$equivocationRecords[0].matchingPayloadClosureCount -gt 1) `
        -Message 'equivocation status must expose the conflicting closure count'
} finally {
    foreach ($fixtureRoot in $fixtureRoots) {
        $resolvedFixture = [IO.Path]::GetFullPath($fixtureRoot).TrimEnd('\')
        $resolvedBase = [IO.Path]::GetFullPath($candidateBase).TrimEnd('\')
        if ([IO.Path]::GetDirectoryName($resolvedFixture).TrimEnd('\').Equals(
                $resolvedBase, [StringComparison]::OrdinalIgnoreCase) -and
                [IO.Path]::GetFileName($resolvedFixture).StartsWith(
                    $fixturePrefix, [StringComparison]::Ordinal)) {
            Remove-Item -LiteralPath $resolvedFixture -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

$invalidCombinationRejected = $false
try {
    & $devPath -Status -ForceBuild
} catch {
    $invalidCombinationRejected = $_.Exception.Message -like '*-Status cannot be combined*'
}
Assert-Cf7DevEntry -Condition $invalidCombinationRejected -Message 'invalid status/build option combination must fail'

Write-Host "[RuntimeDevEntry] PASS checks=$script:checkCount" -ForegroundColor Green
