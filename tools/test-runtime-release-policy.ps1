# Lightweight contract tests for validate-launcher-release-policy.ps1.  Uses a
# temporary Git fixture and injected test check manifest; no real product generators,
# browsers, compilers, or high-cost audits are executed.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$validator = Join-Path $projectRoot 'tools\validate-launcher-release-policy.ps1'
$powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
$testBase = [IO.Path]::GetFullPath((Join-Path $projectRoot 'tmp\runtime-release-policy-tests')).TrimEnd('\')
$fixtureRoot = Join-Path $testBase ([Guid]::NewGuid().ToString('N'))
$checks = 0

function Assert-Cf7Test {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
    $script:checks++
}

function Write-Cf7Utf8NoBom {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($false)))
}

function Write-Cf7TestManifest {
    param([string]$Path, [object[]]$Entries)
    $manifest = [ordered]@{ schema = 'cf7-runtime-policy-test-manifest.v1'; checks = @($Entries) }
    Write-Cf7Utf8NoBom -Path $Path -Text (($manifest | ConvertTo-Json -Depth 8) + "`n")
}

function Invoke-Cf7Validator {
    param([string]$ManifestPath, [string]$ReceiptPath, [string]$CandidateRoot, [string]$IdentityMode = 'Worktree')
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $arguments = @(
            '-NoProfile','-ExecutionPolicy','Bypass','-File',$validator,
            '-ProjectRoot',$fixtureRoot,'-TestCheckManifestPath',$ManifestPath,
            '-AllowTestManifest','-ReceiptPath',$ReceiptPath,'-IdentityMode',$IdentityMode
        )
        if (-not [string]::IsNullOrWhiteSpace($CandidateRoot)) { $arguments += @('-CandidateRoot',$CandidateRoot) }
        $output = @(& $powershell @arguments 2>&1)
        $exitCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousPreference }
    return [pscustomobject]@{ ExitCode = $exitCode; Output = ($output -join "`n") }
}

if (-not (Test-Path -LiteralPath $validator -PathType Leaf)) {
    throw "Validator missing: $validator"
}
$validatorSource = [IO.File]::ReadAllText($validator, [Text.Encoding]::UTF8)
Assert-Cf7Test (-not $validatorSource.Contains('Candidate policy validation requires IdentityMode=Worktree')) `
    'production candidate checks must support an exactly materialized staged/index release tree'
Assert-Cf7Test ($validatorSource.Contains("[Environment]::SetEnvironmentVariable('CF7_DOTNET_EXE', `$null, 'Process')")) `
    'production candidate checks must discard a caller-injected dotnet host'
Assert-Cf7Test ($validatorSource.Contains(". `$buildEnvGate -ProjectRoot `$ProjectRoot -Mode Validate")) `
    'production candidate checks must initialize the project-pinned runtime toolchain'
Assert-Cf7Test ($validatorSource.Contains('candidate policy validation is forbidden')) `
    'production candidate checks must fail closed when the pinned dotnet host is unavailable'
$lootRequiredWebPaths = @(
    'modules\loot\loot-runtime.js',
    'modules\loot\loot-state.js',
    'modules\loot\loot-view.js',
    'modules\loot\loot-organizer.js',
    'modules\loot\loot-panel.js'
)
$requiredWebPathsMatch = [regex]::Match(
    $validatorSource,
    '(?s)\$requiredWebPaths\s*=\s*@\((?<body>.*?)\)\s*\r?\n\s*\$checks\s*\+=\s*New-Cf7RequiredPathsCheck\s+-Name\s+''required-web-runtime-assets''')
Assert-Cf7Test $requiredWebPathsMatch.Success `
    'production required-Web-assets declaration must remain statically discoverable'
foreach ($relativePath in $lootRequiredWebPaths) {
    Assert-Cf7Test $requiredWebPathsMatch.Groups['body'].Value.Contains("'$relativePath'") `
        "production required-Web-assets must include the loot panel asset: $relativePath"
}

New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
try {
    New-Item -ItemType Directory -Path (Join-Path $fixtureRoot 'tools') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $fixtureRoot 'assets') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $fixtureRoot 'tmp') -Force | Out-Null
    Write-Cf7Utf8NoBom -Path (Join-Path $fixtureRoot 'product.txt') -Text "stable`n"
    Write-Cf7Utf8NoBom -Path (Join-Path $fixtureRoot 'assets\present.txt') -Text "present`n"

    $commonStub = @'
function Get-Cf7RuntimeV2ReleaseTreeOid {
    param([string]$ProjectRoot, [string]$Mode)
    $oid = & git -C $ProjectRoot rev-parse 'HEAD^{tree}'
    if ($LASTEXITCODE -ne 0) { throw 'fixture tree unavailable' }
    return ([string]$oid).Trim().ToLowerInvariant()
}
function Get-Cf7RuntimeV2Identity {
    param([string]$ProjectRoot, [string]$Mode)
    return [pscustomobject]@{
        artifactSourceHash = ('A' * 64)
        producerRecipeHash = ('B' * 64)
        toolchainLockHash = ('C' * 64)
        policyHash = ('D' * 64)
        buildIdentityHash = ('E' * 64)
    }
}
function Get-Cf7RuntimePayloadClosureV2 {
    param([string]$ProjectRoot, [string]$DeploymentRoot, [string]$Mode)
    return [pscustomobject]@{ payloadClosureHash = ('F' * 64); files = @() }
}
'@
    $commonPath = Join-Path $fixtureRoot 'tools\runtime-build-v2-common.ps1'
    Write-Cf7Utf8NoBom -Path $commonPath -Text $commonStub
    Write-Cf7Utf8NoBom -Path (Join-Path $fixtureRoot 'tools\test-pass.ps1') -Text @'
param([string]$Path)
if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { exit 9 }
Write-Output 'fixture diagnostic output must not become a receipt check'
exit 0
'@
    Write-Cf7Utf8NoBom -Path (Join-Path $fixtureRoot 'tools\test-fail.ps1') -Text "exit 23`n"
    Write-Cf7Utf8NoBom -Path (Join-Path $fixtureRoot 'tools\test-mutate.ps1') -Text @'
param([string]$Path)
[IO.File]::WriteAllText($Path, "mutated`n", (New-Object Text.UTF8Encoding($false)))
exit 0
'@

    & git -C $fixtureRoot init -q
    if ($LASTEXITCODE -ne 0) { throw 'git init failed' }
    & git -C $fixtureRoot config user.email 'runtime-policy-test@example.invalid'
    & git -C $fixtureRoot config user.name 'Runtime Policy Test'
    & git -C $fixtureRoot config core.autocrlf false
    $fixtureExcludes = Join-Path $fixtureRoot 'tmp\empty-global-ignore'
    Write-Cf7Utf8NoBom -Path $fixtureExcludes -Text ''
    & git -C $fixtureRoot config core.excludesFile $fixtureExcludes
    & git -C $fixtureRoot add -- product.txt assets tools
    & git -C $fixtureRoot commit -q -m fixture
    if ($LASTEXITCODE -ne 0) { throw 'fixture commit failed' }

    # 1. Passing checks produce a fully bound v2 receipt and do not touch tracked bytes.
    $passManifest = Join-Path $fixtureRoot 'tmp\pass-manifest.json'
    $passReceipt = Join-Path $fixtureRoot 'tmp\pass-receipt.json'
    Write-Cf7TestManifest -Path $passManifest -Entries @(
        [ordered]@{ name = 'fixture-resource'; kind = 'requiredPaths'; root = '${PROJECT_ROOT}\assets'; paths = @('present.txt') },
        [ordered]@{
            name = 'fixture-command'; kind = 'command'; filePath = $powershell
            arguments = @('-NoProfile', '-File', '${PROJECT_ROOT}\tools\test-pass.ps1', '${PROJECT_ROOT}\product.txt')
            workingDirectory = '${PROJECT_ROOT}'
        }
    )
    $productBefore = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $fixtureRoot 'product.txt')).Hash
    $passRun = Invoke-Cf7Validator -ManifestPath $passManifest -ReceiptPath $passReceipt
    $productAfter = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $fixtureRoot 'product.txt')).Hash
    Assert-Cf7Test ($passRun.ExitCode -eq 0) "passing validation must exit zero; output=$($passRun.Output)"
    Assert-Cf7Test ($productBefore -eq $productAfter) 'validation must preserve tracked product bytes'
    Assert-Cf7Test (Test-Path -LiteralPath $passReceipt -PathType Leaf) 'passing validation must write a receipt'
    $passJson = Get-Content -Raw -Encoding UTF8 -LiteralPath $passReceipt | ConvertFrom-Json
    Assert-Cf7Test ($passJson.schema -eq 'cf7-runtime-policy-validation.v2') 'receipt schema must be v2'
    Assert-Cf7Test ($passJson.profile -eq 'test' -and $passJson.passed -eq $true) 'test receipt must be labeled and passed'
    Assert-Cf7Test ([string]$passJson.releaseTreeOid -match '^[0-9a-f]{40,64}$') 'receipt must bind the release tree'
    Assert-Cf7Test ($passJson.artifactSourceHash -eq ('A' * 64)) 'receipt must bind artifact source hash'
    Assert-Cf7Test ($passJson.producerRecipeHash -eq ('B' * 64)) 'receipt must bind producer recipe hash'
    Assert-Cf7Test ($passJson.toolchainLockHash -eq ('C' * 64) -and $passJson.toolchainHash -eq ('C' * 64)) 'receipt must bind toolchain hash'
    Assert-Cf7Test ($passJson.policyHash -eq ('D' * 64)) 'receipt must bind policy hash'
    Assert-Cf7Test ($null -eq $passJson.candidateRoot -and $null -eq $passJson.candidatePayloadClosureHash) 'receipt without a candidate must carry explicit null candidate bindings'
    Assert-Cf7Test (@($passJson.checks).Count -eq 4) 'child diagnostic output must not contaminate the structured checks array'
    Assert-Cf7Test (@($passJson.checks | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.name) }).Count -eq 0) 'every receipt check must be a named structured record'
    Assert-Cf7Test (@($passJson.checks | Where-Object { $_.name -eq 'tracked-tree-readonly' -and $_.passed }).Count -eq 1) 'receipt must prove tracked-tree readonly invariant'

    # 1b. Candidate-bound receipts include the exact payload closure and prove that
    # the candidate stayed byte-stable throughout all policy checks.
    $candidateRoot = Join-Path $fixtureRoot 'tmp\candidate'
    New-Item -ItemType Directory -Path $candidateRoot -Force | Out-Null
    $candidateReceipt = Join-Path $fixtureRoot 'tmp\candidate-receipt.json'
    $candidateRun = Invoke-Cf7Validator -ManifestPath $passManifest -ReceiptPath $candidateReceipt -CandidateRoot $candidateRoot
    $candidateJson = Get-Content -Raw -Encoding UTF8 -LiteralPath $candidateReceipt | ConvertFrom-Json
    Assert-Cf7Test ($candidateRun.ExitCode -eq 0) "candidate-bound test validation must pass; output=$($candidateRun.Output)"
    Assert-Cf7Test ([IO.Path]::GetFullPath([string]$candidateJson.candidateRoot) -eq [IO.Path]::GetFullPath($candidateRoot)) 'receipt must bind the normalized candidate path'
    Assert-Cf7Test ($candidateJson.candidatePayloadClosureHash -eq ('F' * 64)) 'receipt must bind the exact candidate payload closure'
    Assert-Cf7Test (@($candidateJson.checks | Where-Object { $_.name -eq 'candidate-payload-readonly' -and $_.passed }).Count -eq 1) 'receipt must prove candidate payload readonly invariant'

    $indexCandidateReceipt = Join-Path $fixtureRoot 'tmp\candidate-index-receipt.json'
    $indexCandidateRun = Invoke-Cf7Validator -ManifestPath $passManifest -ReceiptPath $indexCandidateReceipt `
        -CandidateRoot $candidateRoot -IdentityMode Index
    $indexCandidateJson = Get-Content -Raw -Encoding UTF8 -LiteralPath $indexCandidateReceipt | ConvertFrom-Json
    Assert-Cf7Test ($indexCandidateRun.ExitCode -eq 0 -and $indexCandidateJson.passed -eq $true) `
        'candidate-bound receipt must support an exactly materialized staged/index release tree'

    # 2. A missing required product resource fails and is preserved in the receipt.
    $missingManifest = Join-Path $fixtureRoot 'tmp\missing-manifest.json'
    $missingReceipt = Join-Path $fixtureRoot 'tmp\missing-receipt.json'
    Write-Cf7TestManifest -Path $missingManifest -Entries @(
        [ordered]@{ name = 'required-missing'; kind = 'requiredPaths'; root = '${PROJECT_ROOT}\assets'; paths = @('absent.txt') }
    )
    $missingRun = Invoke-Cf7Validator -ManifestPath $missingManifest -ReceiptPath $missingReceipt
    $missingJson = Get-Content -Raw -Encoding UTF8 -LiteralPath $missingReceipt | ConvertFrom-Json
    Assert-Cf7Test ($missingRun.ExitCode -eq 1 -and $missingJson.passed -eq $false) 'missing resource must fail validation'
    Assert-Cf7Test (@($missingJson.checks | Where-Object { $_.name -eq 'required-missing' -and -not $_.passed }).Count -eq 1) 'missing resource failure must be recorded'

    # 2b. The production loot panel is a five-module closure: the complete set passes,
    # while removing any single module fails closed and names that path in the receipt.
    $lootWebRoot = Join-Path $fixtureRoot 'web'
    foreach ($relativePath in $lootRequiredWebPaths) {
        Write-Cf7Utf8NoBom -Path (Join-Path $lootWebRoot $relativePath) -Text "fixture`n"
    }
    $lootManifest = Join-Path $fixtureRoot 'tmp\loot-web-assets-manifest.json'
    Write-Cf7TestManifest -Path $lootManifest -Entries @(
        [ordered]@{
            name = 'required-loot-panel-chain'
            kind = 'requiredPaths'
            root = '${PROJECT_ROOT}\web'
            paths = $lootRequiredWebPaths
        }
    )
    $lootPassReceipt = Join-Path $fixtureRoot 'tmp\loot-web-assets-pass-receipt.json'
    $lootPassRun = Invoke-Cf7Validator -ManifestPath $lootManifest -ReceiptPath $lootPassReceipt
    $lootPassJson = Get-Content -Raw -Encoding UTF8 -LiteralPath $lootPassReceipt | ConvertFrom-Json
    Assert-Cf7Test ($lootPassRun.ExitCode -eq 0 -and $lootPassJson.passed -eq $true) `
        "complete loot panel asset closure must pass; output=$($lootPassRun.Output)"
    Assert-Cf7Test (@($lootPassJson.checks | Where-Object {
        $_.name -eq 'required-loot-panel-chain' -and $_.passed
    }).Count -eq 1) 'complete loot panel asset closure must be recorded as passed'
    foreach ($missingPath in $lootRequiredWebPaths) {
        $missingFullPath = Join-Path $lootWebRoot $missingPath
        Remove-Item -LiteralPath $missingFullPath -Force
        try {
            $leaf = [IO.Path]::GetFileNameWithoutExtension($missingPath)
            $receiptPath = Join-Path $fixtureRoot "tmp\loot-web-assets-missing-$leaf-receipt.json"
            $lootMissingRun = Invoke-Cf7Validator -ManifestPath $lootManifest -ReceiptPath $receiptPath
            $lootMissingJson = Get-Content -Raw -Encoding UTF8 -LiteralPath $receiptPath | ConvertFrom-Json
            $failedCheck = @($lootMissingJson.checks | Where-Object {
                $_.name -eq 'required-loot-panel-chain' -and -not $_.passed
            })
            Assert-Cf7Test ($lootMissingRun.ExitCode -eq 1 -and $lootMissingJson.passed -eq $false) `
                "missing loot panel asset must fail validation: $missingPath"
            Assert-Cf7Test ($failedCheck.Count -eq 1 -and [string]$failedCheck[0].detail -match [regex]::Escape($missingPath)) `
                "missing loot panel asset must be named in the failed policy check: $missingPath"
        } finally {
            Write-Cf7Utf8NoBom -Path $missingFullPath -Text "fixture`n"
        }
    }

    # 3. A child gate's nonzero code reaches its check record and the top-level result;
    # remaining checks still run so a single receipt contains the full diagnosis.
    $failureManifest = Join-Path $fixtureRoot 'tmp\failure-manifest.json'
    $failureReceipt = Join-Path $fixtureRoot 'tmp\failure-receipt.json'
    Write-Cf7TestManifest -Path $failureManifest -Entries @(
        [ordered]@{
            name = 'intentional-failure'; kind = 'command'; filePath = $powershell
            arguments = @('-NoProfile', '-File', '${PROJECT_ROOT}\tools\test-fail.ps1')
            workingDirectory = '${PROJECT_ROOT}'
        },
        [ordered]@{ name = 'after-failure'; kind = 'requiredPaths'; root = '${PROJECT_ROOT}\assets'; paths = @('present.txt') }
    )
    $failureRun = Invoke-Cf7Validator -ManifestPath $failureManifest -ReceiptPath $failureReceipt
    $failureJson = Get-Content -Raw -Encoding UTF8 -LiteralPath $failureReceipt | ConvertFrom-Json
    $failedGate = @($failureJson.checks | Where-Object { $_.name -eq 'intentional-failure' })[0]
    Assert-Cf7Test ($failureRun.ExitCode -eq 1 -and $failedGate.exitCode -eq 23) 'child failure code must propagate into a failed top-level validation'
    Assert-Cf7Test (@($failureJson.checks | Where-Object { $_.name -eq 'after-failure' -and $_.passed }).Count -eq 1) 'diagnostic validation must continue after a failed child gate'

    # 4. Even a gate that exits zero cannot silently mutate tracked release content.
    $mutationManifest = Join-Path $fixtureRoot 'tmp\mutation-manifest.json'
    $mutationReceipt = Join-Path $fixtureRoot 'tmp\mutation-receipt.json'
    Write-Cf7TestManifest -Path $mutationManifest -Entries @(
        [ordered]@{
            name = 'mutating-gate'; kind = 'command'; filePath = $powershell
            arguments = @('-NoProfile', '-File', '${PROJECT_ROOT}\tools\test-mutate.ps1', '${PROJECT_ROOT}\product.txt')
            workingDirectory = '${PROJECT_ROOT}'
        }
    )
    $mutationRun = Invoke-Cf7Validator -ManifestPath $mutationManifest -ReceiptPath $mutationReceipt
    $mutationJson = Get-Content -Raw -Encoding UTF8 -LiteralPath $mutationReceipt | ConvertFrom-Json
    Assert-Cf7Test ($mutationRun.ExitCode -eq 1) 'tracked mutation must fail validation'
    Assert-Cf7Test (@($mutationJson.checks | Where-Object { $_.name -eq 'tracked-tree-readonly' -and -not $_.passed }).Count -eq 1) 'tracked mutation must fail readonly invariant'
    & git -C $fixtureRoot checkout -q -- product.txt
    if ($LASTEXITCODE -ne 0) { throw 'fixture cleanup checkout failed' }

    # 5. Missing v2 common fails early with an actionable message, not a null-command crash.
    $commonBackup = $commonPath + '.off'
    Move-Item -LiteralPath $commonPath -Destination $commonBackup
    try {
        $missingCommonRun = Invoke-Cf7Validator -ManifestPath $passManifest -ReceiptPath (Join-Path $fixtureRoot 'tmp\missing-common-receipt.json')
        Assert-Cf7Test ($missingCommonRun.ExitCode -eq 2) 'missing v2 common must use setup-error exit code 2'
        Assert-Cf7Test ($missingCommonRun.Output -match 'v2 identity common is missing') 'missing v2 common must explain the missing dependency'
    } finally {
        Move-Item -LiteralPath $commonBackup -Destination $commonPath
    }

    Write-Host "[RuntimePolicyTest] OK checks=$checks" -ForegroundColor Green
} finally {
    $resolvedFixture = [IO.Path]::GetFullPath($fixtureRoot)
    if ($resolvedFixture.StartsWith($testBase + '\', [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolvedFixture)) {
        Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
    }
}
