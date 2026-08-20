param([string]$ProjectRoot)

$ErrorActionPreference = 'Stop'
if (-not $ProjectRoot) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('cf7-runtime-release-v2-test-' + [Guid]::NewGuid().ToString('N'))
$fixtureRoot = Join-Path $testRoot 'project'
$queueRoot = Join-Path $testRoot 'queue'
$fakeBin = Join-Path $testRoot 'fake-bin'
$utf8NoBom = New-Object Text.UTF8Encoding($false)
$script:assertions = 0
$createdThumbprints = New-Object 'System.Collections.Generic.List[string]'
$originalPath = $env:PATH
$originalReplayMutationPath = $env:CF7_RUNTIME_TEST_REPLAY_MUTATION_PATH

function Write-Cf7FixtureText {
    param([string]$Path,[string]$Text)
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    [IO.File]::WriteAllText($Path,$Text,$utf8NoBom)
}

function Write-Cf7FixtureJson {
    param([string]$Path,[object]$Value,[int]$Depth = 30)
    Write-Cf7FixtureText -Path $Path -Text (($Value | ConvertTo-Json -Depth $Depth) + "`n")
}

function Assert-Cf7Fixture {
    param([bool]$Condition,[string]$Message)
    if (-not $Condition) { throw "Runtime release v2 fixture failed: $Message" }
    $script:assertions++
}

function Expect-Cf7FixtureFailure {
    param([scriptblock]$Action,[string]$Message)
    $failed = $false
    try { & $Action | Out-Null } catch { $failed = $true }
    Assert-Cf7Fixture -Condition $failed -Message $Message
}

function New-Cf7ExitProgram {
    param([string]$Path,[int]$ExitCode)
    $className = 'Cf7RuntimeExit' + [Guid]::NewGuid().ToString('N')
    $source = "using System; public static class $className { public static int Main(string[] args) { return $ExitCode; } }"
    Add-Type -TypeDefinition $source -Language CSharp -OutputAssembly $Path -OutputType ConsoleApplication
}

function Get-Cf7DeploymentSnapshot {
    param([string]$Root)
    $paths = New-Object 'System.Collections.Generic.List[string]'
    foreach ($relative in @('CRAZYFLASHER7MercenaryEmpire.exe','config/build/runtime-release-consensus.json')) {
        $full = Join-Path $Root ($relative -replace '/','\')
        if (Test-Path -LiteralPath $full -PathType Leaf) { $paths.Add($relative) }
    }
    $runtimeRoot = Join-Path $Root 'runtime'
    if (Test-Path -LiteralPath $runtimeRoot -PathType Container) {
        foreach ($file in Get-ChildItem -LiteralPath $runtimeRoot -File -Recurse) {
            $paths.Add($file.FullName.Substring($Root.Length + 1).Replace('\','/'))
        }
    }
    $rows = @()
    foreach ($relative in @($paths | Sort-Object)) {
        $full = Join-Path $Root ($relative -replace '/','\')
        $rows += "$relative`t$((Get-FileHash -Algorithm SHA256 -LiteralPath $full).Hash)"
    }
    return [string]::Join("`n",$rows)
}

function Get-Cf7TreeSnapshot {
    param([string]$Root,[switch]$ExcludeGit,[string[]]$ExcludePath = @())
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return '<missing>' }
    $rootPath = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\')
    $excluded = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($path in $ExcludePath) {
        $fullPath = if ([IO.Path]::IsPathRooted($path)) {
            [IO.Path]::GetFullPath($path)
        } else {
            [IO.Path]::GetFullPath((Join-Path $rootPath ($path -replace '/','\')))
        }
        [void]$excluded.Add($fullPath)
    }
    $rows = New-Object 'System.Collections.Generic.List[string]'
    foreach ($item in @(Get-ChildItem -LiteralPath $rootPath -Force -Recurse | Sort-Object FullName)) {
        if ($excluded.Contains([IO.Path]::GetFullPath($item.FullName))) { continue }
        $relative = $item.FullName.Substring($rootPath.Length + 1).Replace('\','/')
        if ($ExcludeGit -and ($relative -eq '.git' -or $relative.StartsWith('.git/'))) { continue }
        if ($item.PSIsContainer) {
            $rows.Add("D`t$relative")
        } else {
            $rows.Add("F`t$relative`t$($item.Length)`t$((Get-FileHash -Algorithm SHA256 -LiteralPath $item.FullName).Hash)")
        }
    }
    return [string]::Join("`n",$rows.ToArray())
}

function Assert-Cf7PreflightReportCanonical {
    param([string]$Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    Assert-Cf7Fixture -Condition ($bytes.Length -gt 1) -Message 'preflight report is empty'
    Assert-Cf7Fixture -Condition (-not ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB)) -Message 'preflight report has a UTF-8 BOM'
    Assert-Cf7Fixture -Condition ($bytes[$bytes.Length - 1] -eq 0x0A) -Message 'preflight report lacks a final LF'
    Assert-Cf7Fixture -Condition (-not ($bytes -contains [byte]0x0D)) -Message 'preflight report contains CR bytes'
}

function Assert-Cf7TextExcludes {
    param([string]$Text,[string[]]$Values,[string]$Message)
    foreach ($value in $Values) {
        if ([string]::IsNullOrWhiteSpace($value)) { continue }
        Assert-Cf7Fixture -Condition (
            $Text.IndexOf($value,[StringComparison]::OrdinalIgnoreCase) -lt 0) `
            -Message "$Message`: $value"
    }
}

function Write-Cf7CandidateManifest {
    param([string]$CandidateRoot,[object]$Identity)
    $closure = Get-Cf7RuntimePayloadClosureV2 -ProjectRoot $fixtureRoot -DeploymentRoot $CandidateRoot -Mode Worktree
    $lines = New-Object 'System.Collections.Generic.List[string]'
    foreach ($line in @(
        'cf7-runtime-manifest-v2',
        "publishMode`tframework-dependent",
        "artifactSourceHash`t$($Identity.artifactSourceHash)",
        "producerRecipeHash`t$($Identity.producerRecipeHash)",
        "toolchainLockHash`t$($Identity.toolchainLockHash)",
        "toolchainBaseline`tfixture",
        "buildIdentityHash`t$($Identity.buildIdentityHash)",
        "payloadClosureHash`t$($closure.payloadClosureHash)"
    )) { $lines.Add($line) }
    foreach ($row in @($closure.files)) { $lines.Add("file`t$($row.path)`t$($row.size)`t$($row.sha256)") }
    Write-Cf7FixtureText -Path (Join-Path $CandidateRoot 'runtime\cf7-runtime-manifest.tsv') `
        -Text ([string]::Join("`n",$lines.ToArray()) + "`n")
    return $closure
}

function New-Cf7Candidate {
    param([string]$Name,[int]$ExitCode,[object]$Identity)
    $root = Join-Path $testRoot $Name
    New-Item -ItemType Directory -Path (Join-Path $root 'runtime') -Force | Out-Null
    New-Cf7ExitProgram -Path (Join-Path $root 'CRAZYFLASHER7MercenaryEmpire.exe') -ExitCode $ExitCode
    Write-Cf7FixtureText -Path (Join-Path $root 'runtime\core.dll') -Text "payload-$Name`n"
    $closure = Write-Cf7CandidateManifest -CandidateRoot $root -Identity $Identity
    return [pscustomobject]@{ root=$root; closure=$closure }
}

function New-Cf7PolicyReceipt {
    param([string]$Path,[string]$CandidateRoot,[object]$Identity,[string]$ReleaseTreeOid)
    $candidateClosure = Get-Cf7RuntimePayloadClosureV2 -ProjectRoot $fixtureRoot -DeploymentRoot $CandidateRoot -Mode Worktree
    $receipt = [ordered]@{
        schema='cf7-runtime-policy-validation.v2'; profile='production'; passed=$true
        releaseTreeOid=$ReleaseTreeOid.ToLowerInvariant()
        policyHash=([string]$Identity.policyHash).ToUpperInvariant()
        artifactSourceHash=([string]$Identity.artifactSourceHash).ToUpperInvariant()
        producerRecipeHash=([string]$Identity.producerRecipeHash).ToUpperInvariant()
        toolchainLockHash=([string]$Identity.toolchainLockHash).ToUpperInvariant()
        toolchainHash=([string]$Identity.toolchainLockHash).ToUpperInvariant()
        buildIdentityHash=([string]$Identity.buildIdentityHash).ToUpperInvariant()
        candidateRoot=[IO.Path]::GetFullPath($CandidateRoot)
        candidatePayloadClosureHash=([string]$candidateClosure.payloadClosureHash).ToUpperInvariant()
        startedAtUtc=[DateTime]::UtcNow.AddSeconds(-1).ToString('o')
        completedAtUtc=[DateTime]::UtcNow.ToString('o')
        trackedStateBefore=('0' * 64); trackedStateAfter=('0' * 64)
        checks=@(
            [ordered]@{name='release-tree-materialized';kind='invariant';passed=$true;exitCode=0;durationMs=0;command=$null;detail='fixture'},
            [ordered]@{name='tracked-tree-readonly';kind='invariant';passed=$true;exitCode=0;durationMs=0;command=$null;detail='fixture'},
            [ordered]@{name='candidate-payload-readonly';kind='invariant';passed=$true;exitCode=0;durationMs=0;command=$null;detail='fixture'}
        )
    }
    Write-Cf7FixtureJson -Path $Path -Value $receipt
    return $Path
}

function New-Cf7ProofSet {
    param([string]$Name,[object]$Candidate,[object]$Identity,[string]$SourceCommitOid,[string]$RegistryPath,[string]$Thumbprint)
    $localPath = Join-Path $testRoot "$Name-x509.json"
    $local = New-Cf7RuntimeBuildAttestationV2 -ProjectRoot $fixtureRoot -DeploymentRoot $Candidate.root `
        -CertificateThumbprint $Thumbprint -RegistryPath $RegistryPath -Mode Worktree
    Write-Cf7FixtureJson -Path $localPath -Value $local

    $envelopePath = Join-Path $testRoot "$Name-envelope.json"
    & (Join-Path $fixtureRoot 'tools\new-runtime-github-build-envelope.ps1') `
        -ProjectRoot $fixtureRoot -CandidateRoot $Candidate.root -SourceCommitOid $SourceCommitOid -OutputPath $envelopePath | Out-Null
    $bundlePath = Join-Path $testRoot "$Name-bundle.json"
    Write-Cf7FixtureText -Path $bundlePath -Text "{`"mediaType`":`"application/vnd.dev.sigstore.bundle.v0.3+json`"}`n"
    $cloud = & (Join-Path $fixtureRoot 'tools\verify-runtime-github-attestation.ps1') `
        -ProjectRoot $fixtureRoot -CandidateRoot $Candidate.root -EnvelopePath $envelopePath -BundlePath $bundlePath `
        -GitHubCliPath (Join-Path $fakeBin 'gh.cmd') -ExpectedSourceCommitOid $SourceCommitOid
    $cloudPath = Join-Path $testRoot "$Name-github.json"
    Write-Cf7FixtureJson -Path $cloudPath -Value $cloud
    return [pscustomobject]@{ localPath=$localPath; cloudPath=$cloudPath }
}

function Invoke-Cf7ConsensusProcess {
    param([switch]$Staged, [string]$PreVerifiedGitHubProofPath)
    $arguments = @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $fixtureRoot 'tools\verify-runtime-consensus.ps1'),'-ProjectRoot',$fixtureRoot)
    if ($Staged) { $arguments += '-Staged' }
    if ($PreVerifiedGitHubProofPath) { $arguments += @('-PreVerifiedGitHubProofPath', $PreVerifiedGitHubProofPath) }
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& powershell.exe @arguments 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    return [pscustomobject]@{ exitCode=$exitCode; output=($output -join "`n") }
}

try {
    New-Item -ItemType Directory -Path $fixtureRoot,$queueRoot,$fakeBin -Force | Out-Null
    foreach ($directory in @(
        'tools',
        'config\build',
        'runtime',
        'launcher\tests\runtime-preflight-protected-long-tree',
        'docs\evidence',
        'tools\player-info-hud\evidence\b0-06'
    )) {
        New-Item -ItemType Directory -Path (Join-Path $fixtureRoot $directory) -Force | Out-Null
    }
    foreach ($name in @(
        'runtime-build-common.ps1','runtime-build-v2-common.ps1','runtime-build-attestation-v2-common.ps1',
        'runtime-build-queue-common.ps1','verify-runtime-bundle-v2.ps1','verify-runtime-consensus.ps1',
        'verify-runtime-github-attestation.ps1','new-runtime-github-build-envelope.ps1','promote-runtime-bundle.ps1'
    )) {
        Copy-Item -LiteralPath (Join-Path (Join-Path $ProjectRoot 'tools') $name) -Destination (Join-Path (Join-Path $fixtureRoot 'tools') $name)
    }
    . (Join-Path $fixtureRoot 'tools\runtime-build-common.ps1')
    . (Join-Path $fixtureRoot 'tools\runtime-build-v2-common.ps1')
    . (Join-Path $fixtureRoot 'tools\runtime-build-attestation-v2-common.ps1')
    . (Join-Path $fixtureRoot 'tools\runtime-build-queue-common.ps1')

    Write-Cf7FixtureText -Path (Join-Path $fakeBin 'gh.cmd') -Text ((@'
@echo off
if defined CF7_RUNTIME_TEST_REPLAY_MUTATION_PATH (
  >"%CF7_RUNTIME_TEST_REPLAY_MUTATION_PATH%" echo replay-window-drift
)
echo [{"attestation":{},"verificationResult":{"signature":{"certificate":{}},"verifiedTimestamps":[],"statement":{"predicateType":"https://slsa.dev/provenance/v1"}}}]
'@) -replace "`r?`n","`r`n")
    $env:PATH = $fakeBin + ';' + $originalPath
    $env:CF7_RUNTIME_TEST_REPLAY_MUTATION_PATH = $null

    Write-Cf7FixtureText -Path (Join-Path $fixtureRoot 'source.txt') -Text "source-v1`n"
    Write-Cf7FixtureText -Path (Join-Path $fixtureRoot 'producer.txt') -Text "producer-v1`n"
    Write-Cf7FixtureText -Path (Join-Path $fixtureRoot 'toolchain.txt') -Text "toolchain-v1`n"
    Write-Cf7FixtureText -Path (Join-Path $fixtureRoot 'policy.txt') -Text "policy-v1`n"
    $inputs = [ordered]@{
        schema='cf7-runtime-inputs.v2'
        domains=[ordered]@{
            artifactSource=[ordered]@{fixedFiles=@('source.txt');trees=@()}
            producerRecipe=[ordered]@{fixedFiles=@('producer.txt');trees=@()}
            toolchainLock=[ordered]@{fixedFiles=@('toolchain.txt');trees=@()}
            policy=[ordered]@{
                fixedFiles=@('policy.txt','config/build/runtime-inputs.v2.json','config/build/runtime-builders.v2.json','config/build/runtime-github-builder.v2.json')
                trees=@([ordered]@{
                    path='launcher/tests/runtime-preflight-protected-long-tree';includeExtensions=@('.cs');excludePaths=@();excludePrefixes=@()
                })
            }
        }
        payload=[ordered]@{fixedRoots=@('CRAZYFLASHER7MercenaryEmpire.exe');trees=@('runtime');excludePaths=@('runtime/cf7-runtime-manifest.tsv');excludePrefixes=@()}
    }
    Write-Cf7FixtureJson -Path (Join-Path $fixtureRoot 'config\build\runtime-inputs.v2.json') -Value $inputs -Depth 12
    $githubConfig = [ordered]@{
        schema='cf7-runtime-github-builder.v2';enabled=$true;repository='FlashNightModReborn/CrazyFlashNight'
        signerWorkflow='FlashNightModReborn/CrazyFlashNight/.github/workflows/runtime-cloud-builder.yml'
        sourceRef='refs/tags/runtime-build-v2/test-consensus';faultDomain='github-hosted-windows';runnerClass='github-hosted-windows'
        identityProvider='github-oidc-sigstore';longLivedPrivateKey=$false
    }
    Write-Cf7FixtureJson -Path (Join-Path $fixtureRoot 'config\build\runtime-github-builder.v2.json') -Value $githubConfig

    $certificate = New-SelfSignedCertificate -Type Custom `
        -Subject ('CN=CF7 Release Fixture ' + [Guid]::NewGuid().ToString('N')) `
        -CertStoreLocation 'Cert:\CurrentUser\My' -KeyAlgorithm RSA -KeyLength 2048 -HashAlgorithm SHA256 `
        -KeyExportPolicy NonExportable -KeyUsage DigitalSignature -NotAfter ([DateTime]::UtcNow.AddDays(2))
    $thumbprint = $certificate.Thumbprint.Replace(' ','').ToUpperInvariant()
    $createdThumbprints.Add($thumbprint)
    $builderEntry = [ordered]@{
        builderId='fixture-local';keyId=Get-Cf7RuntimeV2BuilderKeyId -Certificate $certificate
        certificateThumbprint=$thumbprint;certificateBase64=[Convert]::ToBase64String($certificate.RawData)
        enabled=$true;epoch=1;faultDomain='fixture-local-machine'
    }
    $certificate.Dispose()
    $registryPath = Join-Path $fixtureRoot 'config\build\runtime-builders.v2.json'
    Write-Cf7FixtureJson -Path $registryPath -Value ([ordered]@{schema='cf7-runtime-builders.v2';minimumConsensus=2;builders=@($builderEntry)})

    & git -C $fixtureRoot init -q
    & git -C $fixtureRoot config user.name 'CF7 Runtime Release Fixture'
    & git -C $fixtureRoot config user.email 'runtime-release-fixture@example.invalid'
    & git -C $fixtureRoot config core.autocrlf false

    New-Cf7ExitProgram -Path (Join-Path $fixtureRoot 'CRAZYFLASHER7MercenaryEmpire.exe') -ExitCode 0
    Write-Cf7FixtureText -Path (Join-Path $fixtureRoot 'runtime\old.dll') -Text "old-runtime`n"
    $identity = Get-Cf7RuntimeBuildIdentityV2 -ProjectRoot $fixtureRoot -Mode Worktree
    Write-Cf7CandidateManifest -CandidateRoot $fixtureRoot -Identity $identity | Out-Null
    Write-Cf7FixtureText -Path (Join-Path $fixtureRoot 'config\build\runtime-release-consensus.json') -Text "{}`n"
    & git -C $fixtureRoot add -- .
    & git -C $fixtureRoot commit -q -m 'fixture baseline'
    if ($LASTEXITCODE -ne 0) { throw 'Cannot commit runtime release fixture baseline.' }
    $sourceCommit = ([string](& git -C $fixtureRoot rev-parse 'HEAD^{commit}')).Trim().ToLowerInvariant()
    $releaseTree = ([string](& git -C $fixtureRoot rev-parse 'HEAD^{tree}')).Trim().ToLowerInvariant()
    $identity = Get-Cf7RuntimeBuildIdentityV2 -ProjectRoot $fixtureRoot -Mode Worktree

    Initialize-Cf7RuntimeQueue -QueueRoot $queueRoot
    $requestId = Get-Cf7RuntimeRequestId -ReleaseTreeOid $releaseTree -PolicyHash $identity.policyHash
    $requestDirectory = Join-Path (Join-Path $queueRoot 'requests') $requestId
    New-Item -ItemType Directory -Path $requestDirectory -Force | Out-Null
    $bundleFile = Join-Path $requestDirectory 'source.bundle'
    Write-Cf7FixtureText -Path $bundleFile -Text "fixture source bundle`n"
    $request = [ordered]@{
        schema='cf7-runtime-build-request.v2';requestId=$requestId;sourceKind='Treeish'
        releaseTreeOid=$releaseTree;sourceCommitOid=$sourceCommit;requestCommitOid=$sourceCommit;bundleTreeOid=$releaseTree
        artifactSourceHash=$identity.artifactSourceHash;producerRecipeHash=$identity.producerRecipeHash
        toolchainLockHash=$identity.toolchainLockHash;policyHash=$identity.policyHash;buildIdentityHash=$identity.buildIdentityHash
        bundleFile='source.bundle';bundleSha256=Get-Cf7QueueFileSha256 -Path $bundleFile
        requiredQuorum=2;createdAtUtc=[DateTime]::UtcNow.ToString('o')
    }
    Write-Cf7FixtureJson -Path (Join-Path $requestDirectory 'request.json') -Value $request

    $failedCandidate = New-Cf7Candidate -Name 'candidate-fail' -ExitCode 19 -Identity $identity
    $passedCandidate = New-Cf7Candidate -Name 'candidate-pass' -ExitCode 0 -Identity $identity
    $failedReceipt = New-Cf7PolicyReceipt -Path (Join-Path $testRoot 'receipt-fail.json') -CandidateRoot $failedCandidate.root -Identity $identity -ReleaseTreeOid $releaseTree
    $passedReceipt = New-Cf7PolicyReceipt -Path (Join-Path $testRoot 'receipt-pass.json') -CandidateRoot $passedCandidate.root -Identity $identity -ReleaseTreeOid $releaseTree
    $failedProofs = New-Cf7ProofSet -Name 'fail' -Candidate $failedCandidate -Identity $identity -SourceCommitOid $sourceCommit -RegistryPath $registryPath -Thumbprint $thumbprint
    $passedProofs = New-Cf7ProofSet -Name 'pass' -Candidate $passedCandidate -Identity $identity -SourceCommitOid $sourceCommit -RegistryPath $registryPath -Thumbprint $thumbprint
    $promotion = Join-Path $fixtureRoot 'tools\promote-runtime-bundle.ps1'

    $preflightPath = Join-Path $fixtureRoot 'docs\evidence\preflight-pass.json'
    $preflightRepeatPath = Join-Path $fixtureRoot 'docs\evidence\preflight-pass-repeat.json'
    $projectBeforePreflight = Get-Cf7TreeSnapshot -Root $fixtureRoot -ExcludeGit
    $queueBeforePreflight = Get-Cf7TreeSnapshot -Root $queueRoot
    $candidateBeforePreflight = Get-Cf7TreeSnapshot -Root $passedCandidate.root
    $deploymentBeforePreflight = Get-Cf7DeploymentSnapshot -Root $fixtureRoot
    $scratchBeforePreflight = [string]::Join("`n",@(
        Get-ChildItem -LiteralPath ([IO.Path]::GetTempPath()) -Directory -Filter 'cf7-runtime-github-replay-*' -ErrorAction SilentlyContinue |
            ForEach-Object { $_.Name } | Sort-Object
    ))
    & $promotion -ProjectRoot $fixtureRoot -QueueRoot $queueRoot -RequestId $requestId `
        -PolicyReceiptPath $passedReceipt -CandidateRoot $passedCandidate.root `
        -ExternalAttestationPath @($passedProofs.localPath,$passedProofs.localPath,$passedProofs.cloudPath) `
        -VerifyOnly -ReportPath $preflightPath
    Assert-Cf7Fixture -Condition (Test-Path -LiteralPath $preflightPath -PathType Leaf) -Message 'successful VerifyOnly did not create its report'
    Assert-Cf7Fixture -Condition (
        (Get-Cf7TreeSnapshot -Root $fixtureRoot -ExcludeGit -ExcludePath $preflightPath) -ceq
        $projectBeforePreflight) `
        -Message 'VerifyOnly mutated the fixture project outside its report'
    Assert-Cf7Fixture -Condition ((Get-Cf7TreeSnapshot -Root $queueRoot) -ceq $queueBeforePreflight) -Message 'VerifyOnly mutated the request queue'
    Assert-Cf7Fixture -Condition ((Get-Cf7TreeSnapshot -Root $passedCandidate.root) -ceq $candidateBeforePreflight) -Message 'VerifyOnly mutated the selected candidate'
    Assert-Cf7Fixture -Condition ((Get-Cf7DeploymentSnapshot -Root $fixtureRoot) -ceq $deploymentBeforePreflight) -Message 'VerifyOnly mutated the live deployment'
    $scratchAfterPreflight = [string]::Join("`n",@(
        Get-ChildItem -LiteralPath ([IO.Path]::GetTempPath()) -Directory -Filter 'cf7-runtime-github-replay-*' -ErrorAction SilentlyContinue |
            ForEach-Object { $_.Name } | Sort-Object
    ))
    Assert-Cf7Fixture -Condition ($scratchAfterPreflight -ceq $scratchBeforePreflight) -Message 'VerifyOnly left GitHub replay scratch behind'
    Assert-Cf7Fixture -Condition (-not (Test-Path -LiteralPath (Join-Path $fixtureRoot 'tmp\runtime-promotions'))) -Message 'VerifyOnly created a promotion transaction root'

    Assert-Cf7PreflightReportCanonical -Path $preflightPath
    $preflightBytes = [IO.File]::ReadAllBytes($preflightPath)
    $preflightText = [Text.Encoding]::UTF8.GetString($preflightBytes)
    $preflight = $preflightText | ConvertFrom-Json
    Assert-Cf7Fixture -Condition ([string]$preflight.schema -ceq 'cf7-runtime-promotion-preflight.v2') -Message 'preflight report schema is not v2'
    Assert-Cf7Fixture -Condition ([string]$preflight.status -ceq 'preflight-passed') -Message 'preflight report status is not preflight-passed'
    Assert-Cf7Fixture -Condition ([string]$preflight.scope -ceq 'promotion-preflight') -Message 'preflight report scope is not promotion-preflight'
    Assert-Cf7Fixture -Condition ($preflight.runtimeMutationPerformed -eq $false) -Message 'preflight report claims a runtime mutation'
    Assert-Cf7Fixture -Condition ($preflight.releaseStateMutationPerformed -eq $false) -Message 'preflight report claims a release-state mutation'
    Assert-Cf7Fixture -Condition ($preflight.reportCreated -eq $true) -Message 'preflight report does not disclose its own CreateNew write'
    Assert-Cf7Fixture -Condition ($preflight.promotionPerformed -eq $false) -Message 'preflight report claims promotion'
    Assert-Cf7Fixture -Condition ($preflight.deploymentPerformed -eq $false) -Message 'preflight report claims deployment'
    Assert-Cf7Fixture -Condition ($preflight.reusableAsPromotionInput -eq $false) -Message 'preflight report claims it is reusable as promotion input'
    Assert-Cf7Fixture -Condition (@($preflight.limitations) -contains 'This report is not a promotion input.') -Message 'preflight report lacks the promotion-input disclaimer'
    Assert-Cf7Fixture -Condition (@($preflight.limitations) -contains 'No promotion or deployment was performed.') -Message 'preflight report lacks the no-deployment disclaimer'
    Assert-Cf7Fixture -Condition ([string]$preflight.request.requestId -ceq $requestId) -Message 'preflight report requestId mismatch'
    Assert-Cf7Fixture -Condition ([string]$preflight.request.releaseTreeOid -ceq $releaseTree) -Message 'preflight report releaseTreeOid mismatch'
    foreach ($field in @('artifactSourceHash','producerRecipeHash','toolchainLockHash','policyHash','buildIdentityHash')) {
        Assert-Cf7Fixture -Condition (
            ([string]$preflight.request.$field).ToUpperInvariant() -ceq ([string]$identity.$field).ToUpperInvariant()) `
            -Message "preflight report identity mismatch: $field"
    }
    Assert-Cf7Fixture -Condition (
        ([string]$preflight.candidate.payloadClosureHash).ToUpperInvariant() -ceq
        ([string]$passedCandidate.closure.payloadClosureHash).ToUpperInvariant()) `
        -Message 'preflight report payload closure mismatch'
    $passedManifestHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (
        Join-Path $passedCandidate.root 'runtime\cf7-runtime-manifest.tsv')).Hash.ToUpperInvariant()
    Assert-Cf7Fixture -Condition (
        ([string]$preflight.candidate.manifestSha256).ToUpperInvariant() -ceq $passedManifestHash) `
        -Message 'preflight report manifest hash mismatch'
    Assert-Cf7Fixture -Condition (
        ([string]$preflight.policy.receiptSha256).ToUpperInvariant() -ceq
        (Get-Cf7BytesSha256 -Bytes ([IO.File]::ReadAllBytes($passedReceipt)))) `
        -Message 'preflight report policy receipt hash mismatch'
    Assert-Cf7Fixture -Condition ([int]$preflight.candidate.fileCount -eq @($preflight.candidate.files).Count) -Message 'preflight report fileCount mismatch'
    Assert-Cf7Fixture -Condition ([string]$preflight.consensus.schema -ceq 'cf7-runtime-build-consensus-result.v2') -Message 'preflight report consensus schema mismatch'
    Assert-Cf7Fixture -Condition ([int]$preflight.consensus.minimumConsensus -eq 2) -Message 'preflight report minimum consensus mismatch'
    Assert-Cf7Fixture -Condition ([int]$preflight.consensus.proofCount -eq 2) -Message 'preflight report did not deterministically deduplicate proofs'
    Assert-Cf7Fixture -Condition (@($preflight.consensus.proofs).Count -eq 2) -Message 'preflight report proof summary count mismatch'
    $proofSignerIdentities = [string[]]@($preflight.consensus.proofs | ForEach-Object { [string]$_.signerIdentity })
    $proofFaultDomains = [string[]]@($preflight.consensus.proofs | ForEach-Object { [string]$_.faultDomain })
    $sortedProofSignerIdentities = [string[]]$proofSignerIdentities.Clone()
    $sortedProofFaultDomains = [string[]]$proofFaultDomains.Clone()
    [Array]::Sort($sortedProofSignerIdentities,[StringComparer]::Ordinal)
    [Array]::Sort($sortedProofFaultDomains,[StringComparer]::Ordinal)
    Assert-Cf7Fixture -Condition (
        [string]::Join("`n",@($preflight.consensus.signerIdentities)) -ceq
        [string]::Join("`n",$sortedProofSignerIdentities)) `
        -Message 'preflight report signerIdentities do not match the sorted proof set'
    Assert-Cf7Fixture -Condition (
        [string]::Join("`n",@($preflight.consensus.faultDomains)) -ceq
        [string]::Join("`n",$sortedProofFaultDomains)) `
        -Message 'preflight report faultDomains do not match the sorted proof set'
    Assert-Cf7Fixture -Condition ($sortedProofSignerIdentities.Count -eq 2 -and $sortedProofSignerIdentities[0] -cne $sortedProofSignerIdentities[1]) -Message 'preflight report lacks two signer identities'
    Assert-Cf7Fixture -Condition ($sortedProofFaultDomains.Count -eq 2 -and $sortedProofFaultDomains[0] -cne $sortedProofFaultDomains[1]) -Message 'preflight report lacks two fault domains'
    Assert-Cf7TextExcludes -Text $preflightText -Values @(
        $testRoot,$fixtureRoot,$queueRoot,$failedCandidate.root,$passedCandidate.root,$fakeBin,
        $ProjectRoot,[Environment]::UserName,[Environment]::MachineName
    ) -Message 'preflight report leaked local path or machine identity'
    Assert-Cf7Fixture -Condition ($preflightText -notmatch '(?i)"[^"]*(AtUtc|timestamp)[^"]*"\s*:') -Message 'preflight report contains a timestamp field'
    Assert-Cf7Fixture -Condition ($preflightText -notmatch '\d{4}-\d{2}-\d{2}T\d{2}:') -Message 'preflight report contains an ISO timestamp value'

    & $promotion -ProjectRoot $fixtureRoot -QueueRoot $queueRoot -RequestId $requestId `
        -PolicyReceiptPath $passedReceipt -CandidateRoot $passedCandidate.root `
        -ExternalAttestationPath @($passedProofs.localPath,$passedProofs.localPath,$passedProofs.cloudPath) `
        -VerifyOnly -ReportPath $preflightRepeatPath
    Assert-Cf7PreflightReportCanonical -Path $preflightRepeatPath
    Assert-Cf7Fixture -Condition (
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($preflightRepeatPath)) -ceq
        [Convert]::ToBase64String($preflightBytes)) `
        -Message 'identical VerifyOnly inputs did not produce byte-stable reports'

    $preflightEvidencePath = Join-Path $fixtureRoot 'tools\player-info-hud\evidence\b0-06\runtime-promotion-preflight.json'
    & $promotion -ProjectRoot $fixtureRoot -QueueRoot $queueRoot -RequestId $requestId `
        -PolicyReceiptPath $passedReceipt -CandidateRoot $passedCandidate.root `
        -ExternalAttestationPath @($passedProofs.localPath,$passedProofs.localPath,$passedProofs.cloudPath) `
        -VerifyOnly -ReportPath $preflightEvidencePath
    Assert-Cf7Fixture -Condition (
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($preflightEvidencePath)) -ceq
        [Convert]::ToBase64String($preflightBytes)) `
        -Message 'tracked-evidence ReportPath changed byte-stable report content'
    $docsEvidencePath = Join-Path $fixtureRoot 'docs\evidence\runtime-promotion-preflight.json'
    & $promotion -ProjectRoot $fixtureRoot -QueueRoot $queueRoot -RequestId $requestId `
        -PolicyReceiptPath $passedReceipt -CandidateRoot $passedCandidate.root `
        -ExternalAttestationPath @($passedProofs.localPath,$passedProofs.localPath,$passedProofs.cloudPath) `
        -VerifyOnly -ReportPath $docsEvidencePath
    Assert-Cf7Fixture -Condition (
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($docsEvidencePath)) -ceq
        [Convert]::ToBase64String($preflightBytes)) `
        -Message 'docs evidence ReportPath changed byte-stable report content'

    $outsideReportPath = Join-Path $testRoot 'preflight-outside-project.json'
    Expect-Cf7FixtureFailure -Message 'VerifyOnly accepted a ReportPath outside ProjectRoot' -Action {
        & $promotion -ProjectRoot $fixtureRoot -QueueRoot $queueRoot -RequestId $requestId `
            -PolicyReceiptPath $passedReceipt -CandidateRoot $passedCandidate.root `
            -ExternalAttestationPath @($passedProofs.localPath,$passedProofs.cloudPath) `
            -VerifyOnly -ReportPath $outsideReportPath
    }
    Assert-Cf7Fixture -Condition (-not (Test-Path -LiteralPath $outsideReportPath)) -Message 'outside-project report path was created'

    $preexistingReportBytes = [IO.File]::ReadAllBytes($preflightPath)
    Expect-Cf7FixtureFailure -Message 'VerifyOnly overwrote a pre-existing report' -Action {
        & $promotion -ProjectRoot $fixtureRoot -QueueRoot $queueRoot -RequestId $requestId `
            -PolicyReceiptPath $passedReceipt -CandidateRoot $passedCandidate.root `
            -ExternalAttestationPath @($passedProofs.localPath,$passedProofs.cloudPath) `
            -VerifyOnly -ReportPath $preflightPath
    }
    Assert-Cf7Fixture -Condition (
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($preflightPath)) -ceq
        [Convert]::ToBase64String($preexistingReportBytes)) `
        -Message 'pre-existing report bytes changed after CreateNew rejection'

    foreach ($protectedReportPath in @(
        (Join-Path $fixtureRoot 'config\build\preflight-protected.json'),
        (Join-Path $fixtureRoot 'launcher\tests\runtime-preflight-protected-long-tree\preflight-protected.txt'),
        (Join-Path $fixtureRoot 'runtime\preflight-protected.json'),
        (Join-Path $queueRoot 'preflight-protected.json'),
        (Join-Path $passedCandidate.root 'preflight-protected.json')
    )) {
        Expect-Cf7FixtureFailure -Message "VerifyOnly wrote a protected report path: $protectedReportPath" -Action {
            & $promotion -ProjectRoot $fixtureRoot -QueueRoot $queueRoot -RequestId $requestId `
                -PolicyReceiptPath $passedReceipt -CandidateRoot $passedCandidate.root `
                -ExternalAttestationPath @($passedProofs.localPath,$passedProofs.cloudPath) `
                -VerifyOnly -ReportPath $protectedReportPath
        }
        Assert-Cf7Fixture -Condition (-not (Test-Path -LiteralPath $protectedReportPath)) -Message "protected report path was created: $protectedReportPath"
    }
    $longProtectedTree = Join-Path $fixtureRoot 'launcher\tests\runtime-preflight-protected-long-tree'
    $shortTreeOutput = @(& cmd.exe /d /c ('for %I in ("{0}") do @echo %~sI' -f $longProtectedTree) 2>$null)
    $shortTreePath = [string]@($shortTreeOutput | Select-Object -Last 1)
    $shortTreeLeaf = [IO.Path]::GetFileName($shortTreePath.Trim())
    if (-not [string]::IsNullOrWhiteSpace($shortTreeLeaf) -and
            -not $shortTreeLeaf.Equals([IO.Path]::GetFileName($longProtectedTree),[StringComparison]::OrdinalIgnoreCase)) {
        $shortAliasReport = Join-Path (Join-Path (Split-Path -Parent $longProtectedTree) $shortTreeLeaf) 'preflight-short-alias.txt'
        $longAliasTarget = Join-Path $longProtectedTree 'preflight-short-alias.txt'
        Expect-Cf7FixtureFailure -Message 'VerifyOnly accepted a ReportPath through an 8.3 short-path ancestor' -Action {
            & $promotion -ProjectRoot $fixtureRoot -QueueRoot $queueRoot -RequestId $requestId `
                -PolicyReceiptPath $passedReceipt -CandidateRoot $passedCandidate.root `
                -ExternalAttestationPath @($passedProofs.localPath,$passedProofs.cloudPath) `
                -VerifyOnly -ReportPath $shortAliasReport
        }
        Assert-Cf7Fixture -Condition (-not (Test-Path -LiteralPath $longAliasTarget)) -Message '8.3 alias created a report inside a protected input tree'
    }
    $junctionPath = Join-Path $fixtureRoot 'docs\evidence\runtime-junction'
    $junctionTargetReport = Join-Path $fixtureRoot 'runtime\preflight-through-junction.json'
    try {
        New-Item -ItemType Junction -Path $junctionPath -Target (Join-Path $fixtureRoot 'runtime') | Out-Null
        $junctionReportPath = Join-Path $junctionPath 'preflight-through-junction.json'
        Expect-Cf7FixtureFailure -Message 'VerifyOnly accepted a ReportPath through a junction ancestor' -Action {
            & $promotion -ProjectRoot $fixtureRoot -QueueRoot $queueRoot -RequestId $requestId `
                -PolicyReceiptPath $passedReceipt -CandidateRoot $passedCandidate.root `
                -ExternalAttestationPath @($passedProofs.localPath,$passedProofs.cloudPath) `
                -VerifyOnly -ReportPath $junctionReportPath
        }
        Assert-Cf7Fixture -Condition (-not (Test-Path -LiteralPath $junctionTargetReport)) -Message 'junction alias created a report inside runtime'
    } finally {
        if (Test-Path -LiteralPath $junctionPath) { [IO.Directory]::Delete($junctionPath) }
    }

    $deploymentBeforeReplayDrift = Get-Cf7DeploymentSnapshot -Root $fixtureRoot
    $replayDriftCases = @(
        [pscustomobject]@{
            name='worktree identity'
            path=(Join-Path $fixtureRoot 'source.txt')
            report=(Join-Path $fixtureRoot 'docs\evidence\preflight-replay-source-drift.json')
        },
        [pscustomobject]@{
            name='candidate closure'
            path=(Join-Path $passedCandidate.root 'runtime\core.dll')
            report=(Join-Path $fixtureRoot 'docs\evidence\preflight-replay-candidate-drift.json')
        },
        [pscustomobject]@{
            name='request record'
            path=(Join-Path $requestDirectory 'request.json')
            report=(Join-Path $fixtureRoot 'docs\evidence\preflight-replay-request-drift.json')
        },
        [pscustomobject]@{
            name='policy receipt'
            path=$passedReceipt
            report=(Join-Path $fixtureRoot 'docs\evidence\preflight-replay-receipt-drift.json')
        },
        [pscustomobject]@{
            name='builder registry'
            path=$registryPath
            report=(Join-Path $fixtureRoot 'docs\evidence\preflight-replay-registry-drift.json')
        },
        [pscustomobject]@{
            name='external proof'
            path=$passedProofs.localPath
            report=(Join-Path $fixtureRoot 'docs\evidence\preflight-replay-proof-drift.json')
        }
    )
    foreach ($driftCase in $replayDriftCases) {
        $originalDriftBytes = [IO.File]::ReadAllBytes([string]$driftCase.path)
        try {
            $env:CF7_RUNTIME_TEST_REPLAY_MUTATION_PATH = [string]$driftCase.path
            Expect-Cf7FixtureFailure -Message "VerifyOnly accepted replay-window drift: $($driftCase.name)" -Action {
                & $promotion -ProjectRoot $fixtureRoot -QueueRoot $queueRoot -RequestId $requestId `
                    -PolicyReceiptPath $passedReceipt -CandidateRoot $passedCandidate.root `
                    -ExternalAttestationPath @($passedProofs.localPath,$passedProofs.cloudPath) `
                    -VerifyOnly -ReportPath ([string]$driftCase.report)
            }
        } finally {
            $env:CF7_RUNTIME_TEST_REPLAY_MUTATION_PATH = $null
            [IO.File]::WriteAllBytes([string]$driftCase.path,$originalDriftBytes)
        }
        Assert-Cf7Fixture -Condition (-not (Test-Path -LiteralPath ([string]$driftCase.report))) `
            -Message "replay-window drift left a report: $($driftCase.name)"
        Assert-Cf7Fixture -Condition (
            [Convert]::ToBase64String([IO.File]::ReadAllBytes([string]$driftCase.path)) -ceq
            [Convert]::ToBase64String($originalDriftBytes)) `
            -Message "replay-window drift fixture was not restored: $($driftCase.name)"
    }
    Assert-Cf7Fixture -Condition (
        (Get-Cf7DeploymentSnapshot -Root $fixtureRoot) -ceq $deploymentBeforeReplayDrift) `
        -Message 'replay-window drift tests mutated deployment'
    $liveReplayDriftPath = Join-Path $fixtureRoot 'runtime\preflight-replay-live-drift.tmp'
    $liveReplayDriftReport = Join-Path $fixtureRoot 'docs\evidence\preflight-replay-live-drift.json'
    try {
        $env:CF7_RUNTIME_TEST_REPLAY_MUTATION_PATH = $liveReplayDriftPath
        Expect-Cf7FixtureFailure -Message 'VerifyOnly accepted replay-window live deployment drift' -Action {
            & $promotion -ProjectRoot $fixtureRoot -QueueRoot $queueRoot -RequestId $requestId `
                -PolicyReceiptPath $passedReceipt -CandidateRoot $passedCandidate.root `
                -ExternalAttestationPath @($passedProofs.localPath,$passedProofs.cloudPath) `
                -VerifyOnly -ReportPath $liveReplayDriftReport
        }
    } finally {
        $env:CF7_RUNTIME_TEST_REPLAY_MUTATION_PATH = $null
        if (Test-Path -LiteralPath $liveReplayDriftPath) { Remove-Item -LiteralPath $liveReplayDriftPath -Force }
    }
    Assert-Cf7Fixture -Condition (-not (Test-Path -LiteralPath $liveReplayDriftReport)) -Message 'live replay-window drift left a report'
    Assert-Cf7Fixture -Condition (
        (Get-Cf7DeploymentSnapshot -Root $fixtureRoot) -ceq $deploymentBeforeReplayDrift) `
        -Message 'live replay-window drift fixture was not restored'

    $crossCandidateReport = Join-Path $fixtureRoot 'docs\evidence\preflight-cross-candidate.json'
    $deploymentBeforeCrossCandidate = Get-Cf7DeploymentSnapshot -Root $fixtureRoot
    Expect-Cf7FixtureFailure -Message 'VerifyOnly accepted a receipt bound to another candidate path' -Action {
        & $promotion -ProjectRoot $fixtureRoot -QueueRoot $queueRoot -RequestId $requestId `
            -PolicyReceiptPath $failedReceipt -CandidateRoot $passedCandidate.root `
            -ExternalAttestationPath @($passedProofs.localPath,$passedProofs.cloudPath) `
            -VerifyOnly -ReportPath $crossCandidateReport
    }
    Assert-Cf7Fixture -Condition (-not (Test-Path -LiteralPath $crossCandidateReport)) -Message 'cross-candidate VerifyOnly failure left a report'
    Assert-Cf7Fixture -Condition (
        (Get-Cf7DeploymentSnapshot -Root $fixtureRoot) -ceq $deploymentBeforeCrossCandidate) `
        -Message 'cross-candidate VerifyOnly failure mutated deployment'
    Expect-Cf7FixtureFailure -Message 'promotion accepted a receipt bound to another candidate path' -Action {
        & $promotion -ProjectRoot $fixtureRoot -QueueRoot $queueRoot -RequestId $requestId `
            -PolicyReceiptPath $failedReceipt -CandidateRoot $passedCandidate.root `
            -ExternalAttestationPath @($passedProofs.localPath,$passedProofs.cloudPath)
    }
    $staleReceiptObject = Get-Content -LiteralPath $failedReceipt -Raw -Encoding UTF8 | ConvertFrom-Json
    $staleReceiptObject.candidateRoot = [IO.Path]::GetFullPath($passedCandidate.root)
    $staleReceiptPath = Join-Path $testRoot 'receipt-stale-same-path.json'
    Write-Cf7FixtureJson -Path $staleReceiptPath -Value $staleReceiptObject
    $staleReceiptReport = Join-Path $fixtureRoot 'docs\evidence\preflight-stale-receipt.json'
    Expect-Cf7FixtureFailure -Message 'VerifyOnly accepted candidate bytes replaced after policy validation at the same path' -Action {
        & $promotion -ProjectRoot $fixtureRoot -QueueRoot $queueRoot -RequestId $requestId `
            -PolicyReceiptPath $staleReceiptPath -CandidateRoot $passedCandidate.root `
            -ExternalAttestationPath @($passedProofs.localPath,$passedProofs.cloudPath) `
            -VerifyOnly -ReportPath $staleReceiptReport
    }
    Assert-Cf7Fixture -Condition (-not (Test-Path -LiteralPath $staleReceiptReport)) -Message 'stale-receipt VerifyOnly failure left a report'
    Expect-Cf7FixtureFailure -Message 'promotion accepted candidate bytes replaced after policy validation at the same path' -Action {
        & $promotion -ProjectRoot $fixtureRoot -QueueRoot $queueRoot -RequestId $requestId `
            -PolicyReceiptPath $staleReceiptPath -CandidateRoot $passedCandidate.root `
            -ExternalAttestationPath @($passedProofs.localPath,$passedProofs.cloudPath)
    }

    $proofMismatchReport = Join-Path $fixtureRoot 'docs\evidence\preflight-proof-mismatch.json'
    Expect-Cf7FixtureFailure -Message 'VerifyOnly accepted producer proofs for another payload closure' -Action {
        & $promotion -ProjectRoot $fixtureRoot -QueueRoot $queueRoot -RequestId $requestId `
            -PolicyReceiptPath $passedReceipt -CandidateRoot $passedCandidate.root `
            -ExternalAttestationPath @($failedProofs.localPath,$failedProofs.cloudPath) `
            -VerifyOnly -ReportPath $proofMismatchReport
    }
    Assert-Cf7Fixture -Condition (-not (Test-Path -LiteralPath $proofMismatchReport)) -Message 'proof-mismatch VerifyOnly failure left a report'

    $sourcePath = Join-Path $fixtureRoot 'source.txt'
    $sourceOriginalBytes = [IO.File]::ReadAllBytes($sourcePath)
    $requestDriftReport = Join-Path $fixtureRoot 'docs\evidence\preflight-request-drift.json'
    try {
        Write-Cf7FixtureText -Path $sourcePath -Text "worktree-request-drift`n"
        Expect-Cf7FixtureFailure -Message 'VerifyOnly accepted worktree/request identity drift' -Action {
            & $promotion -ProjectRoot $fixtureRoot -QueueRoot $queueRoot -RequestId $requestId `
                -PolicyReceiptPath $passedReceipt -CandidateRoot $passedCandidate.root `
                -ExternalAttestationPath @($passedProofs.localPath,$passedProofs.cloudPath) `
                -VerifyOnly -ReportPath $requestDriftReport
        }
    } finally {
        [IO.File]::WriteAllBytes($sourcePath,$sourceOriginalBytes)
    }
    Assert-Cf7Fixture -Condition (-not (Test-Path -LiteralPath $requestDriftReport)) -Message 'request-drift VerifyOnly failure left a report'

    $failedBootstrapPreflightPath = Join-Path $fixtureRoot 'docs\evidence\preflight-failed-bootstrap.json'
    $beforeFailedBootstrapPreflight = Get-Cf7DeploymentSnapshot -Root $fixtureRoot
    & $promotion -ProjectRoot $fixtureRoot -QueueRoot $queueRoot -RequestId $requestId `
        -PolicyReceiptPath $failedReceipt -CandidateRoot $failedCandidate.root `
        -ExternalAttestationPath @($failedProofs.localPath,$failedProofs.cloudPath) `
        -VerifyOnly -ReportPath $failedBootstrapPreflightPath
    Assert-Cf7Fixture -Condition (Test-Path -LiteralPath $failedBootstrapPreflightPath -PathType Leaf) -Message 'VerifyOnly executed or rejected the formal bootstrap verification phase'
    Assert-Cf7Fixture -Condition (
        (Get-Cf7DeploymentSnapshot -Root $fixtureRoot) -ceq $beforeFailedBootstrapPreflight) `
        -Message 'failed-bootstrap VerifyOnly mutated deployment'

    $beforeRollback = Get-Cf7DeploymentSnapshot -Root $fixtureRoot
    Expect-Cf7FixtureFailure -Message 'failing promoted bootstrap did not trigger rollback' -Action {
        & $promotion -ProjectRoot $fixtureRoot -QueueRoot $queueRoot -RequestId $requestId `
            -PolicyReceiptPath $failedReceipt -CandidateRoot $failedCandidate.root `
            -ExternalAttestationPath @($failedProofs.localPath,$failedProofs.cloudPath)
    }
    Assert-Cf7Fixture -Condition ((Get-Cf7DeploymentSnapshot -Root $fixtureRoot) -ceq $beforeRollback) -Message 'rollback did not restore every previous deployment byte'
    $deploymentStatus = @(& git -C $fixtureRoot status --porcelain -- 'CRAZYFLASHER7MercenaryEmpire.exe' 'runtime' 'config/build/runtime-release-consensus.json')
    Assert-Cf7Fixture -Condition ($deploymentStatus.Count -eq 0) -Message 'rollback left the tracked deployment dirty'

    & $promotion -ProjectRoot $fixtureRoot -QueueRoot $queueRoot -RequestId $requestId `
        -PolicyReceiptPath $passedReceipt -CandidateRoot $passedCandidate.root `
        -ExternalAttestationPath @($passedProofs.localPath,$passedProofs.localPath,$passedProofs.cloudPath)
    $recordPath = Join-Path $fixtureRoot 'config\build\runtime-release-consensus.json'
    $recordOriginalBytes = [IO.File]::ReadAllBytes($recordPath)
    $record = [Text.Encoding]::UTF8.GetString($recordOriginalBytes) | ConvertFrom-Json
    Assert-Cf7Fixture -Condition (@($record.attestations).Count -eq 2) -Message 'duplicate local proof was not deterministically deduplicated'
    Assert-Cf7Fixture -Condition (@($record.attestations | Where-Object { $_.schema -eq 'cf7-runtime-build-attestation.v2' }).Count -eq 1) -Message 'release record lacks exactly one X509 proof'
    Assert-Cf7Fixture -Condition (@($record.attestations | Where-Object { $_.schema -eq 'cf7-runtime-github-build-attestation.v2' }).Count -eq 1) -Message 'release record lacks exactly one GitHub proof'
    Assert-Cf7Fixture -Condition ([string]$record.requestId -ceq [string]$preflight.request.requestId) -Message 'preflight/real-promotion requestId parity failed'
    Assert-Cf7Fixture -Condition ([string]$record.releaseTreeOid -ceq [string]$preflight.request.releaseTreeOid) -Message 'preflight/real-promotion releaseTreeOid parity failed'
    foreach ($field in @('artifactSourceHash','producerRecipeHash','toolchainLockHash','policyHash','buildIdentityHash')) {
        Assert-Cf7Fixture -Condition (
            ([string]$record.$field).ToUpperInvariant() -ceq
            ([string]$preflight.request.$field).ToUpperInvariant()) `
            -Message "preflight/real-promotion identity parity failed: $field"
    }
    Assert-Cf7Fixture -Condition (
        ([string]$record.payloadClosureHash).ToUpperInvariant() -ceq
        ([string]$preflight.candidate.payloadClosureHash).ToUpperInvariant()) `
        -Message 'preflight/real-promotion payload closure parity failed'
    Assert-Cf7Fixture -Condition (
        ([string]$record.manifestSha256).ToUpperInvariant() -ceq
        ([string]$preflight.candidate.manifestSha256).ToUpperInvariant()) `
        -Message 'preflight/real-promotion manifest parity failed'
    Assert-Cf7Fixture -Condition (
        ([string]$record.policyReceiptSha256).ToUpperInvariant() -ceq
        ([string]$preflight.policy.receiptSha256).ToUpperInvariant()) `
        -Message 'preflight/real-promotion policy receipt parity failed'
    $recordProofSummaries = @(
        foreach ($proof in @($record.attestations)) {
            $isX509 = [string]$proof.schema -eq 'cf7-runtime-build-attestation.v2'
            [pscustomobject][ordered]@{
                schema = [string]$proof.schema
                kind = if ($isX509) { 'x509' } else { 'github-oidc' }
                signerIdentity = if ($isX509) {
                    'x509:' + ([string]$proof.payload.builderKeyId).ToUpperInvariant()
                } else {
                    'github-oidc:' + ([string]$proof.payload.builderIdentityHash).ToUpperInvariant()
                }
                faultDomain = [string]$proof.payload.faultDomain
                canonicalPayloadSha256 = if ($isX509) {
                    ([string]$proof.signature.canonicalPayloadSha256).ToUpperInvariant()
                } else {
                    ([string]$proof.canonicalPayloadSha256).ToUpperInvariant()
                }
            }
        }
    )
    Assert-Cf7Fixture -Condition ($recordProofSummaries.Count -eq @($preflight.consensus.proofs).Count) -Message 'preflight/real-promotion proof count parity failed'
    for ($proofIndex = 0; $proofIndex -lt $recordProofSummaries.Count; $proofIndex++) {
        foreach ($field in @('schema','kind','signerIdentity','faultDomain','canonicalPayloadSha256')) {
            Assert-Cf7Fixture -Condition (
                [string]$recordProofSummaries[$proofIndex].$field -ceq
                [string]$preflight.consensus.proofs[$proofIndex].$field) `
                -Message "preflight/real-promotion proof parity failed: index=$proofIndex field=$field"
        }
    }
    $verified = Invoke-Cf7ConsensusProcess
    Assert-Cf7Fixture -Condition ($verified.exitCode -eq 0) -Message "fresh mixed consensus record failed: $($verified.output)"

    # P3 fast path: a pre-verified GitHub proof file lets consensus skip the second Sigstore
    # replay, but only for byte-identical wrappers bound to this request.
    $recordGitHubProof = @($record.attestations | Where-Object { $_.schema -eq 'cf7-runtime-github-build-attestation.v2' })
    Assert-Cf7Fixture -Condition ($recordGitHubProof.Count -eq 1) -Message 'release record must contain exactly one GitHub proof for the fast-path fixture'
    $goodPreVerifiedPath = Join-Path $testRoot 'preverified-good.json'
    Write-Cf7FixtureJson -Path $goodPreVerifiedPath -Value ([ordered]@{
        schema='cf7-runtime-github-preverified-proofs.v1'; requestId=$requestId; proofs=@($recordGitHubProof[0])
    })
    $fastPath = Invoke-Cf7ConsensusProcess -PreVerifiedGitHubProofPath $goodPreVerifiedPath
    Assert-Cf7Fixture -Condition ($fastPath.exitCode -eq 0) -Message "pre-verified fast path rejected the promotion-verified wrapper: $($fastPath.output)"
    $emptyPreVerifiedPath = Join-Path $testRoot 'preverified-empty.json'
    Write-Cf7FixtureJson -Path $emptyPreVerifiedPath -Value ([ordered]@{
        schema='cf7-runtime-github-preverified-proofs.v1'; requestId=$requestId; proofs=@()
    })
    Assert-Cf7Fixture -Condition ((Invoke-Cf7ConsensusProcess -PreVerifiedGitHubProofPath $emptyPreVerifiedPath).exitCode -ne 0) `
        -Message 'an empty pre-verified proof set passed the consensus fast path'
    $tamperedPreVerified = $recordGitHubProof[0] | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $tamperedPreVerified.payload.faultDomain = 'tampered-cloud-domain'
    $tamperedPreVerifiedPath = Join-Path $testRoot 'preverified-tampered.json'
    Write-Cf7FixtureJson -Path $tamperedPreVerifiedPath -Value ([ordered]@{
        schema='cf7-runtime-github-preverified-proofs.v1'; requestId=$requestId; proofs=@($tamperedPreVerified)
    })
    Assert-Cf7Fixture -Condition ((Invoke-Cf7ConsensusProcess -PreVerifiedGitHubProofPath $tamperedPreVerifiedPath).exitCode -ne 0) `
        -Message 'a tampered pre-verified wrapper passed the consensus fast path'
    $wrongRequestPreVerifiedPath = Join-Path $testRoot 'preverified-wrong-request.json'
    Write-Cf7FixtureJson -Path $wrongRequestPreVerifiedPath -Value ([ordered]@{
        schema='cf7-runtime-github-preverified-proofs.v1'; requestId=('0' * 64); proofs=@($recordGitHubProof[0])
    })
    Assert-Cf7Fixture -Condition ((Invoke-Cf7ConsensusProcess -PreVerifiedGitHubProofPath $wrongRequestPreVerifiedPath).exitCode -ne 0) `
        -Message 'a pre-verified proof set for another request passed the consensus fast path'
    Assert-Cf7Fixture -Condition ((Invoke-Cf7ConsensusProcess -PreVerifiedGitHubProofPath (Join-Path $testRoot 'preverified-missing.json')).exitCode -ne 0) `
        -Message 'a missing pre-verified proof file passed the consensus fast path'
    Assert-Cf7Fixture -Condition ((Invoke-Cf7ConsensusProcess -Staged -PreVerifiedGitHubProofPath $goodPreVerifiedPath).exitCode -ne 0) `
        -Message 'the pre-verified fast path was accepted in staged-index mode'

    $tampered = [Text.Encoding]::UTF8.GetString($recordOriginalBytes) | ConvertFrom-Json
    ($tampered.attestations | Where-Object { $_.schema -eq 'cf7-runtime-github-build-attestation.v2' }).payload.faultDomain = 'tampered-cloud-domain'
    Write-Cf7FixtureJson -Path $recordPath -Value $tampered
    Assert-Cf7Fixture -Condition ((Invoke-Cf7ConsensusProcess).exitCode -ne 0) -Message 'tampered stored GitHub payload passed fresh proof replay'
    [IO.File]::WriteAllBytes($recordPath,$recordOriginalBytes)

    $reordered = [Text.Encoding]::UTF8.GetString($recordOriginalBytes) | ConvertFrom-Json
    $reversedAttestations = @($reordered.attestations)
    [Array]::Reverse($reversedAttestations)
    $reordered.attestations = $reversedAttestations
    Write-Cf7FixtureJson -Path $recordPath -Value $reordered
    Assert-Cf7Fixture -Condition ((Invoke-Cf7ConsensusProcess).exitCode -ne 0) -Message 'non-canonical producer proof order passed verification'
    [IO.File]::WriteAllBytes($recordPath,$recordOriginalBytes)

    $receiptTamperedRecord = [Text.Encoding]::UTF8.GetString($recordOriginalBytes) | ConvertFrom-Json
    $receiptObject = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String([string]$receiptTamperedRecord.policyReceiptBase64)) | ConvertFrom-Json
    $receiptObject.toolchainHash = ('0' * 64)
    $receiptTamperedBytes = [Text.Encoding]::UTF8.GetBytes(($receiptObject | ConvertTo-Json -Depth 30) + "`n")
    $receiptTamperedRecord.policyReceiptBase64 = [Convert]::ToBase64String($receiptTamperedBytes)
    $receiptTamperedRecord.policyReceiptSha256 = Get-Cf7BytesSha256 -Bytes $receiptTamperedBytes
    Write-Cf7FixtureJson -Path $recordPath -Value $receiptTamperedRecord
    Assert-Cf7Fixture -Condition ((Invoke-Cf7ConsensusProcess).exitCode -ne 0) -Message 'inconsistent receipt toolchain alias passed verification'
    [IO.File]::WriteAllBytes($recordPath,$recordOriginalBytes)

    $manifestPath = Join-Path $fixtureRoot 'runtime\cf7-runtime-manifest.tsv'
    $manifestOriginalBytes = [IO.File]::ReadAllBytes($manifestPath)
    $manifestText = [Text.Encoding]::UTF8.GetString($manifestOriginalBytes)
    $manifestText = $manifestText.Replace("payloadClosureHash`t$($passedCandidate.closure.payloadClosureHash)","payloadClosureHash`t$('0' * 64)")
    Write-Cf7FixtureText -Path $manifestPath -Text $manifestText
    $manifestTamperedRecord = [Text.Encoding]::UTF8.GetString($recordOriginalBytes) | ConvertFrom-Json
    $manifestTamperedRecord.manifestSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $manifestPath).Hash
    Write-Cf7FixtureJson -Path $recordPath -Value $manifestTamperedRecord
    Assert-Cf7Fixture -Condition ((Invoke-Cf7ConsensusProcess).exitCode -ne 0) -Message 'record-adjusted but internally invalid runtime manifest passed consensus verification'
    [IO.File]::WriteAllBytes($manifestPath,$manifestOriginalBytes)
    [IO.File]::WriteAllBytes($recordPath,$recordOriginalBytes)

    # The baseline/pass fixture executables intentionally have the same size. A rapid
    # Move-Item replacement can therefore look clean to Git for one stat-cache tick on
    # Windows. Remove the fixture deployment from the index first so this test always
    # stages bytes instead of accidentally exercising the previous baseline blob.
    & git -C $fixtureRoot rm --cached -q -r --ignore-unmatch -- `
        'CRAZYFLASHER7MercenaryEmpire.exe' 'runtime' 'config/build/runtime-release-consensus.json'
    if ($LASTEXITCODE -ne 0) { throw 'Cannot invalidate promoted fixture deployment index entries.' }
    & git -C $fixtureRoot add -- 'CRAZYFLASHER7MercenaryEmpire.exe' 'runtime' 'config/build/runtime-release-consensus.json'
    if ($LASTEXITCODE -ne 0) { throw 'Cannot stage promoted fixture deployment.' }
    $indexedBootstrapHash = Get-Cf7BytesSha256 -Bytes (
        Get-Cf7GitBlobBytes -ProjectRoot $fixtureRoot -RelativePath 'CRAZYFLASHER7MercenaryEmpire.exe')
    $promotedBootstrapHash = (Get-FileHash -Algorithm SHA256 `
        -LiteralPath (Join-Path $fixtureRoot 'CRAZYFLASHER7MercenaryEmpire.exe')).Hash
    Assert-Cf7Fixture -Condition ($indexedBootstrapHash -ceq $promotedBootstrapHash) `
        -Message 'staged bootstrap bytes do not match the promoted fixture deployment'
    Write-Cf7FixtureText -Path (Join-Path $fixtureRoot 'source.txt') -Text "worktree-only-source-drift`n"
    $stagedVerification = Invoke-Cf7ConsensusProcess -Staged
    Assert-Cf7Fixture -Condition ($stagedVerification.exitCode -eq 0) `
        -Message "staged deployment consensus verification failed: $($stagedVerification.output)"

    Write-Host "[RuntimeReleaseConsensusV2Test] PASS assertions=$script:assertions" -ForegroundColor Green
} finally {
    $env:PATH = $originalPath
    $env:CF7_RUNTIME_TEST_REPLAY_MUTATION_PATH = $originalReplayMutationPath
    foreach ($thumbprint in $createdThumbprints) {
        $certificatePath = "Cert:\CurrentUser\My\$thumbprint"
        if (Test-Path -LiteralPath $certificatePath) { Remove-Item -LiteralPath $certificatePath -Force }
    }
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
