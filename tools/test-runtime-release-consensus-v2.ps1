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
    param([switch]$Staged)
    $arguments = @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $fixtureRoot 'tools\verify-runtime-consensus.ps1'),'-ProjectRoot',$fixtureRoot)
    if ($Staged) { $arguments += '-Staged' }
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
    foreach ($directory in @('tools','config\build','runtime')) {
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
echo [{"attestation":{},"verificationResult":{"signature":{"certificate":{}},"verifiedTimestamps":[],"statement":{"predicateType":"https://slsa.dev/provenance/v1"}}}]
'@) -replace "`r?`n","`r`n")
    $env:PATH = $fakeBin + ';' + $originalPath

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
            policy=[ordered]@{fixedFiles=@('policy.txt','config/build/runtime-inputs.v2.json','config/build/runtime-builders.v2.json','config/build/runtime-github-builder.v2.json');trees=@()}
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

    Expect-Cf7FixtureFailure -Message 'promotion accepted a receipt bound to another candidate path' -Action {
        & $promotion -ProjectRoot $fixtureRoot -QueueRoot $queueRoot -RequestId $requestId `
            -PolicyReceiptPath $failedReceipt -CandidateRoot $passedCandidate.root `
            -ExternalAttestationPath @($passedProofs.localPath,$passedProofs.cloudPath)
    }
    $staleReceiptObject = Get-Content -LiteralPath $failedReceipt -Raw -Encoding UTF8 | ConvertFrom-Json
    $staleReceiptObject.candidateRoot = [IO.Path]::GetFullPath($passedCandidate.root)
    $staleReceiptPath = Join-Path $testRoot 'receipt-stale-same-path.json'
    Write-Cf7FixtureJson -Path $staleReceiptPath -Value $staleReceiptObject
    Expect-Cf7FixtureFailure -Message 'promotion accepted candidate bytes replaced after policy validation at the same path' -Action {
        & $promotion -ProjectRoot $fixtureRoot -QueueRoot $queueRoot -RequestId $requestId `
            -PolicyReceiptPath $staleReceiptPath -CandidateRoot $passedCandidate.root `
            -ExternalAttestationPath @($passedProofs.localPath,$passedProofs.cloudPath)
    }

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
    $verified = Invoke-Cf7ConsensusProcess
    Assert-Cf7Fixture -Condition ($verified.exitCode -eq 0) -Message "fresh mixed consensus record failed: $($verified.output)"

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

    & git -C $fixtureRoot add -- 'CRAZYFLASHER7MercenaryEmpire.exe' 'runtime' 'config/build/runtime-release-consensus.json'
    if ($LASTEXITCODE -ne 0) { throw 'Cannot stage promoted fixture deployment.' }
    Write-Cf7FixtureText -Path (Join-Path $fixtureRoot 'source.txt') -Text "worktree-only-source-drift`n"
    $stagedVerification = Invoke-Cf7ConsensusProcess -Staged
    Assert-Cf7Fixture -Condition ($stagedVerification.exitCode -eq 0) -Message "staged consensus did not use Index source mode: $($stagedVerification.output)"

    Write-Host "[RuntimeReleaseConsensusV2Test] PASS assertions=$script:assertions" -ForegroundColor Green
} finally {
    $env:PATH = $originalPath
    foreach ($thumbprint in $createdThumbprints) {
        $certificatePath = "Cert:\CurrentUser\My\$thumbprint"
        if (Test-Path -LiteralPath $certificatePath) { Remove-Item -LiteralPath $certificatePath -Force }
    }
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
