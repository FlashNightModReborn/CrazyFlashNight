param([string]$ProjectRoot)

$ErrorActionPreference = 'Stop'
if (-not $ProjectRoot) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('cf7-runtime-github-attestation-test-' + [Guid]::NewGuid().ToString('N'))
$fixtureRoot = Join-Path $testRoot 'fixture'
$candidateRoot = Join-Path $fixtureRoot 'candidate'
$toolsRoot = Join-Path $fixtureRoot 'tools'
$configRoot = Join-Path $fixtureRoot 'config\build'
$utf8NoBom = New-Object Text.UTF8Encoding($false)
$passed = 0

function Write-Cf7TestText([string]$Path, [string]$Text) {
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    [IO.File]::WriteAllText($Path, $Text, $utf8NoBom)
}

function Assert-Cf7Test([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "ASSERT: $Message" }
    $script:passed++
}

function Assert-Cf7Throws([scriptblock]$Action, [string]$Message) {
    $threw = $false
    try { & $Action | Out-Null } catch { $threw = $true }
    Assert-Cf7Test $threw $Message
}

try {
    New-Item -ItemType Directory -Path $toolsRoot,$configRoot,(Join-Path $candidateRoot 'runtime') -Force | Out-Null
    foreach ($name in @('runtime-build-v2-common.ps1','runtime-build-attestation-v2-common.ps1','new-runtime-github-build-envelope.ps1','verify-runtime-github-attestation.ps1')) {
        Copy-Item -LiteralPath (Join-Path (Join-Path $ProjectRoot 'tools') $name) -Destination (Join-Path $toolsRoot $name)
    }
    Write-Cf7TestText (Join-Path $fixtureRoot 'source.txt') "source-v1`n"
    Write-Cf7TestText (Join-Path $fixtureRoot 'producer.txt') "producer-v1`n"
    Write-Cf7TestText (Join-Path $fixtureRoot 'toolchain.txt') "toolchain-v1`n"
    Write-Cf7TestText (Join-Path $fixtureRoot 'policy.txt') "policy-v1`n"
    $inputs = [ordered]@{
        schema='cf7-runtime-inputs.v2'
        domains=[ordered]@{
            artifactSource=[ordered]@{ fixedFiles=@('source.txt'); trees=@() }
            producerRecipe=[ordered]@{ fixedFiles=@('producer.txt'); trees=@() }
            toolchainLock=[ordered]@{ fixedFiles=@('toolchain.txt'); trees=@() }
            policy=[ordered]@{ fixedFiles=@('policy.txt'); trees=@() }
        }
        payload=[ordered]@{
            fixedRoots=@('app.exe')
            trees=@('runtime')
            excludePaths=@('runtime/cf7-runtime-manifest.tsv')
            excludePrefixes=@()
        }
    }
    Write-Cf7TestText (Join-Path $configRoot 'runtime-inputs.v2.json') (($inputs | ConvertTo-Json -Depth 10) + "`n")
    $githubConfig = [ordered]@{
        schema='cf7-runtime-github-builder.v2'
        enabled=$true
        repository='FlashNightModReborn/CrazyFlashNight'
        signerWorkflow='FlashNightModReborn/CrazyFlashNight/.github/workflows/runtime-cloud-builder.yml'
        sourceRef='refs/heads/main'
        faultDomain='github-hosted-windows'
        runnerClass='github-hosted-windows'
        identityProvider='github-oidc-sigstore'
        longLivedPrivateKey=$false
    }
    $githubConfigPath = Join-Path $configRoot 'runtime-github-builder.v2.json'
    Write-Cf7TestText $githubConfigPath (($githubConfig | ConvertTo-Json -Depth 5) + "`n")

    & git -C $fixtureRoot init -q
    & git -C $fixtureRoot config user.name 'CF7 Test'
    & git -C $fixtureRoot config user.email 'cf7-test@example.invalid'
    & git -C $fixtureRoot add -- .
    & git -C $fixtureRoot commit -q -m fixture
    if ($LASTEXITCODE -ne 0) { throw 'Cannot create Git fixture.' }
    $sourceCommit = ([string](& git -C $fixtureRoot rev-parse HEAD)).Trim().ToLowerInvariant()

    [IO.File]::WriteAllBytes((Join-Path $candidateRoot 'app.exe'), [byte[]](1,2,3,4,5))
    [IO.File]::WriteAllBytes((Join-Path $candidateRoot 'runtime\core.dll'), [byte[]](9,8,7,6))
    . (Join-Path $toolsRoot 'runtime-build-v2-common.ps1')
    . (Join-Path $toolsRoot 'runtime-build-attestation-v2-common.ps1')
    $identity = Get-Cf7RuntimeV2Identity -ProjectRoot $fixtureRoot -Mode Worktree
    $closure = Get-Cf7RuntimePayloadClosureV2 -ProjectRoot $fixtureRoot -DeploymentRoot $candidateRoot -Mode Worktree
    $manifestLines = New-Object 'System.Collections.Generic.List[string]'
    $manifestLines.Add('cf7-runtime-manifest-v2')
    $manifestLines.Add('publishMode' + "`t" + 'framework-dependent')
    $manifestLines.Add('artifactSourceHash' + "`t" + $identity.artifactSourceHash)
    $manifestLines.Add('producerRecipeHash' + "`t" + $identity.producerRecipeHash)
    $manifestLines.Add('toolchainLockHash' + "`t" + $identity.toolchainLockHash)
    $manifestLines.Add('toolchainBaseline' + "`t" + 'fixture')
    $manifestLines.Add('buildIdentityHash' + "`t" + $identity.buildIdentityHash)
    $manifestLines.Add('payloadClosureHash' + "`t" + $closure.payloadClosureHash)
    foreach ($row in @($closure.files)) { $manifestLines.Add("file`t$($row.path)`t$($row.size)`t$($row.sha256)") }
    $manifestPath = Join-Path $candidateRoot 'runtime\cf7-runtime-manifest.tsv'
    Write-Cf7TestText $manifestPath ([string]::Join("`n", $manifestLines.ToArray()) + "`n")
    $originalManifest = [IO.File]::ReadAllText($manifestPath, [Text.Encoding]::UTF8)

    $envelopeA = Join-Path $testRoot 'envelope-a.json'
    $envelopeB = Join-Path $testRoot 'envelope-b.json'
    $generator = Join-Path $toolsRoot 'new-runtime-github-build-envelope.ps1'
    & $generator -ProjectRoot $fixtureRoot -CandidateRoot $candidateRoot -SourceCommitOid $sourceCommit -ConfigPath $githubConfigPath -OutputPath $envelopeA | Out-Null
    & $generator -ProjectRoot $fixtureRoot -CandidateRoot $candidateRoot -SourceCommitOid $sourceCommit -ConfigPath $githubConfigPath -OutputPath $envelopeB | Out-Null
    $envelopeBytesA = [IO.File]::ReadAllBytes($envelopeA)
    $envelopeBytesB = [IO.File]::ReadAllBytes($envelopeB)
    Assert-Cf7Test ([Convert]::ToBase64String($envelopeBytesA) -ceq [Convert]::ToBase64String($envelopeBytesB)) 'envelope generation must be deterministic'
    Assert-Cf7Test (-not ($envelopeBytesA.Length -ge 3 -and $envelopeBytesA[0] -eq 0xEF -and $envelopeBytesA[1] -eq 0xBB -and $envelopeBytesA[2] -eq 0xBF)) 'envelope must not contain a UTF-8 BOM'
    Assert-Cf7Test (-not ([Text.Encoding]::UTF8.GetString($envelopeBytesA).Contains("`r"))) 'envelope must use LF only'

    $bundlePath = Join-Path $testRoot 'bundle.json'
    Write-Cf7TestText $bundlePath ('{"mediaType":"application/vnd.dev.sigstore.bundle.v0.3+json"}' + "`r`n")
    $fakeGh = Join-Path $testRoot 'fake-gh.cmd'
    Write-Cf7TestText $fakeGh (@'
@echo off
> "%CF7_FAKE_GH_ARGS%" echo %*
if /I "%CF7_FAKE_GH_MODE%"=="fail" (
  >&2 echo forced gh attestation failure
  exit /b 17
)
if /I "%CF7_FAKE_GH_MODE%"=="empty" (
  echo []
  exit /b 0
)
if /I "%CF7_FAKE_GH_MODE%"=="badshape" (
  echo [{}]
  exit /b 0
)
if /I "%CF7_FAKE_GH_MODE%"=="wrongpredicate" (
  echo [{"attestation":{},"verificationResult":{"signature":{"certificate":{}},"verifiedTimestamps":[],"statement":{"predicateType":"https://example.invalid/wrong"}}}]
  exit /b 0
)
echo [{"attestation":{},"verificationResult":{"signature":{"certificate":{}},"verifiedTimestamps":[],"statement":{"predicateType":"https://slsa.dev/provenance/v1"}}}]
'@ -replace "`r?`n", "`r`n")
    $argsPath = Join-Path $testRoot 'gh-args.txt'
    $env:CF7_FAKE_GH_ARGS = $argsPath
    $env:CF7_FAKE_GH_MODE = 'ok'
    $wrapperPath = Join-Path $testRoot 'github-attestation-wrapper.json'
    $verifier = Join-Path $toolsRoot 'verify-runtime-github-attestation.ps1'
    $wrapper = & $verifier -ProjectRoot $fixtureRoot -CandidateRoot $candidateRoot -EnvelopePath $envelopeA -BundlePath $bundlePath `
        -ConfigPath $githubConfigPath -GitHubCliPath $fakeGh -ExpectedSourceCommitOid $sourceCommit -OutputPath $wrapperPath
    Assert-Cf7Test ([string]$wrapper.schema -ceq 'cf7-runtime-github-build-attestation.v2') 'wrapper schema'
    Assert-Cf7Test ([string]$wrapper.payload.faultDomain -ceq 'github-hosted-windows') 'normalized fault domain'
    Assert-Cf7Test ([string]$wrapper.payload.payloadClosureHash -ceq [string]$closure.payloadClosureHash) 'normalized payload closure'
    Assert-Cf7Test ([string]$wrapper.payload.sourceCommitOid -ceq $sourceCommit) 'normalized source commit'
    Assert-Cf7Test ([string]$wrapper.payload.builderIdentityHash -match '^[0-9A-F]{64}$') 'stable cloud builder identity hash'
    Assert-Cf7Test ([Convert]::FromBase64String([string]$wrapper.envelopeBase64).Length -eq $envelopeBytesA.Length) 'wrapper embeds envelope bytes'
    Assert-Cf7Test ([Convert]::FromBase64String([string]$wrapper.bundleBase64).Length -eq [IO.File]::ReadAllBytes($bundlePath).Length) 'wrapper embeds bundle bytes'
    $ghArgs = [IO.File]::ReadAllText($argsPath, [Text.Encoding]::Default)
    foreach ($required in @('attestation verify','--repo FlashNightModReborn/CrazyFlashNight','--signer-workflow FlashNightModReborn/CrazyFlashNight/.github/workflows/runtime-cloud-builder.yml','--source-ref refs/heads/main','--deny-self-hosted-runners','--bundle','--predicate-type https://slsa.dev/provenance/v1','--format json')) {
        Assert-Cf7Test ($ghArgs.Contains($required)) "gh argument missing: $required"
    }
    Assert-Cf7Test ($ghArgs.Contains($envelopeA)) 'gh must verify the exact envelope path'
    Assert-Cf7Test ($ghArgs.Contains($bundlePath)) 'gh must consume the downloaded offline bundle path'

    $localPayload = [pscustomobject][ordered]@{
        schema='cf7-runtime-build-attestation-payload.v2'
        builderKeyId=('1' * 64)
        builderEpoch=1
        faultDomain='local-fixture-machine'
        artifactSourceHash=$identity.artifactSourceHash
        producerRecipeHash=$identity.producerRecipeHash
        toolchainLockHash=$identity.toolchainLockHash
        buildIdentityHash=$identity.buildIdentityHash
        payloadClosureHash=$closure.payloadClosureHash
        createdAtUtc='2026-01-01T00:00:00.0000000Z'
        files=@($closure.files)
    }
    $mixedConsensus = Test-Cf7RuntimeVerifiedPayloadConsensusV2 -Payloads @($localPayload,$wrapper.payload) -MinimumConsensus 2
    Assert-Cf7Test ($mixedConsensus.signerIdentities.Count -eq 2) 'one local X509 payload plus one GitHub OIDC payload must form 2-of-N'
    Assert-Cf7Test ($mixedConsensus.faultDomains.Count -eq 2) 'mixed consensus must preserve two independent fault domains'
    Assert-Cf7Throws { Test-Cf7RuntimeVerifiedPayloadConsensusV2 -Payloads @($wrapper.payload,$wrapper.payload) -MinimumConsensus 2 } 'the same GitHub cloud identity cannot vote twice'
    $collidingDomainLocal = $localPayload.PSObject.Copy()
    $collidingDomainLocal.faultDomain = 'github-hosted-windows'
    Assert-Cf7Throws { Test-Cf7RuntimeVerifiedPayloadConsensusV2 -Payloads @($collidingDomainLocal,$wrapper.payload) -MinimumConsensus 2 } 'local and cloud votes sharing one fault domain cannot form consensus'
    Assert-Cf7Test (Assert-Cf7RuntimeGitHubProofEquivalentV2 -Expected $wrapper -Actual $wrapper) 'fresh GitHub proof equivalence gate must accept identical wrappers'
    $mutatedWrapper = (($wrapper | ConvertTo-Json -Depth 20) | ConvertFrom-Json)
    $mutatedWrapper.payload.faultDomain = 'mutated-cloud-domain'
    Assert-Cf7Throws { Assert-Cf7RuntimeGitHubProofEquivalentV2 -Expected $wrapper -Actual $mutatedWrapper } 'fresh GitHub proof equivalence gate must reject payload mutation'
    $extraFieldWrapper = (($wrapper | ConvertTo-Json -Depth 20) | ConvertFrom-Json)
    $extraFieldWrapper | Add-Member -NotePropertyName unverified -NotePropertyValue $true
    Assert-Cf7Throws { Assert-Cf7RuntimeGitHubProofEquivalentV2 -Expected $wrapper -Actual $extraFieldWrapper } 'fresh GitHub proof equivalence gate must reject unrecognized wrapper fields'

    $env:CF7_FAKE_GH_MODE = 'fail'
    Assert-Cf7Throws { & $verifier -ProjectRoot $fixtureRoot -CandidateRoot $candidateRoot -EnvelopePath $envelopeA -BundlePath $bundlePath -ConfigPath $githubConfigPath -GitHubCliPath $fakeGh -ExpectedSourceCommitOid $sourceCommit } 'gh verification failure must fail closed'
    foreach ($invalidGhMode in @('empty','badshape','wrongpredicate')) {
        $env:CF7_FAKE_GH_MODE = $invalidGhMode
        Assert-Cf7Throws { & $verifier -ProjectRoot $fixtureRoot -CandidateRoot $candidateRoot -EnvelopePath $envelopeA -BundlePath $bundlePath -ConfigPath $githubConfigPath -GitHubCliPath $fakeGh -ExpectedSourceCommitOid $sourceCommit } "gh output mode must fail closed: $invalidGhMode"
    }
    $env:CF7_FAKE_GH_MODE = 'ok'

    $canonicalEnvelopeText = [IO.File]::ReadAllText($envelopeA, [Text.Encoding]::UTF8)
    $identityTamperCases = @(
        @('repository','"repository":"FlashNightModReborn/CrazyFlashNight"','"repository":"WrongOwner/WrongRepo"'),
        @('signerWorkflow','"signerWorkflow":"FlashNightModReborn/CrazyFlashNight/.github/workflows/runtime-cloud-builder.yml"','"signerWorkflow":"FlashNightModReborn/CrazyFlashNight/.github/workflows/wrong.yml"'),
        @('sourceRef','"sourceRef":"refs/heads/main"','"sourceRef":"refs/heads/untrusted"'),
        @('faultDomain','"faultDomain":"github-hosted-windows"','"faultDomain":"untrusted-cloud"'),
        @('runnerClass','"runnerClass":"github-hosted-windows"','"runnerClass":"tampered-runner"')
    )
    foreach ($case in $identityTamperCases) {
        $tamperedEnvelope = Join-Path $testRoot ("envelope-tampered-$($case[0]).json")
        $tamperedText = $canonicalEnvelopeText.Replace([string]$case[1], [string]$case[2])
        Assert-Cf7Test ($tamperedText -cne $canonicalEnvelopeText) "tamper fixture replacement: $($case[0])"
        Write-Cf7TestText $tamperedEnvelope $tamperedText
        Assert-Cf7Throws { & $verifier -ProjectRoot $fixtureRoot -CandidateRoot $candidateRoot -EnvelopePath $tamperedEnvelope -BundlePath $bundlePath -ConfigPath $githubConfigPath -GitHubCliPath $fakeGh -ExpectedSourceCommitOid $sourceCommit } "tampered envelope identity must fail: $($case[0])"
    }

    $invalidBundlePath = Join-Path $testRoot 'bundle-invalid.json'
    Write-Cf7TestText $invalidBundlePath '{not-json}'
    Assert-Cf7Throws { & $verifier -ProjectRoot $fixtureRoot -CandidateRoot $candidateRoot -EnvelopePath $envelopeA -BundlePath $invalidBundlePath -ConfigPath $githubConfigPath -GitHubCliPath $fakeGh -ExpectedSourceCommitOid $sourceCommit } 'invalid offline bundle must fail before consensus'

    $keyedConfigPath = Join-Path $testRoot 'github-config-with-key.json'
    $keyedConfig = [ordered]@{}
    foreach ($property in $githubConfig.Keys) { $keyedConfig[$property] = $githubConfig[$property] }
    $keyedConfig.longLivedPrivateKey = $true
    Write-Cf7TestText $keyedConfigPath (($keyedConfig | ConvertTo-Json -Depth 5) + "`n")
    Assert-Cf7Throws { & $verifier -ProjectRoot $fixtureRoot -CandidateRoot $candidateRoot -EnvelopePath $envelopeA -BundlePath $bundlePath -ConfigPath $keyedConfigPath -GitHubCliPath $fakeGh -ExpectedSourceCommitOid $sourceCommit } 'GitHub builder config must reject long-lived private keys'

    $originalApp = [IO.File]::ReadAllBytes((Join-Path $candidateRoot 'app.exe'))
    [IO.File]::WriteAllBytes((Join-Path $candidateRoot 'app.exe'), [byte[]](1,2,3,4,0))
    Assert-Cf7Throws { & $verifier -ProjectRoot $fixtureRoot -CandidateRoot $candidateRoot -EnvelopePath $envelopeA -BundlePath $bundlePath -ConfigPath $githubConfigPath -GitHubCliPath $fakeGh -ExpectedSourceCommitOid $sourceCommit } 'tampered candidate bytes must fail'
    [IO.File]::WriteAllBytes((Join-Path $candidateRoot 'app.exe'), $originalApp)

    $wrongArtifactHash = 'F' * 64
    Write-Cf7TestText $manifestPath ($originalManifest.Replace([string]$identity.artifactSourceHash, $wrongArtifactHash))
    Assert-Cf7Throws { & $verifier -ProjectRoot $fixtureRoot -CandidateRoot $candidateRoot -EnvelopePath $envelopeA -BundlePath $bundlePath -ConfigPath $githubConfigPath -GitHubCliPath $fakeGh -ExpectedSourceCommitOid $sourceCommit } 'candidate identity mismatch must fail'
    Write-Cf7TestText $manifestPath $originalManifest

    Assert-Cf7Throws { & $verifier -ProjectRoot $fixtureRoot -CandidateRoot $candidateRoot -EnvelopePath $envelopeA -BundlePath $bundlePath -ConfigPath $githubConfigPath -GitHubCliPath $fakeGh -ExpectedSourceCommitOid ('0' * $sourceCommit.Length) } 'source commit mismatch must fail'

    $workflowText = [IO.File]::ReadAllText((Join-Path $ProjectRoot '.github\workflows\runtime-cloud-builder.yml'), [Text.Encoding]::UTF8)
    $buildJobText = [regex]::Match($workflowText, '(?ms)^  build:\s.*?(?=^  attest:)').Value
    $attestJobText = [regex]::Match($workflowText, '(?ms)^  attest:\s.*$').Value
    Assert-Cf7Test (-not $workflowText.Contains('>> $env:GITHUB_')) 'PowerShell 5.1 workflow files must not write UTF-16 through redirection to GitHub control files'
    Assert-Cf7Test ($workflowText.Contains('run-name: Runtime cloud builder ${{ inputs.source_commit || github.event.client_payload.source_commit }}')) 'cloud workflow run name must expose the immutable full source SHA'
    Assert-Cf7Test ($workflowText.Contains("-cnotmatch '^(?:[0-9a-f]{40}|[0-9a-f]{64})$'")) 'cloud dispatch must canonicalize source identity by requiring lowercase full SHA'
    Assert-Cf7Test ($workflowText.Contains('if ([string]$env:GITHUB_SHA -cne $normalizedRequested)')) `
        'cloud workflow must reject a workflow ref whose resolved SHA differs from the requested source commit'
    Assert-Cf7Test ($workflowText.Contains('if ([string]$cloudConfig.sourceRef -cne $env:GITHUB_REF)')) `
        'checked-out cloud config must bind its exact sourceRef to the workflow GITHUB_REF'
    Assert-Cf7Test (([regex]::Matches($workflowText, 'runs-on:\s*windows-2022')).Count -eq 2) 'both cloud jobs must use the explicit VS 2022 image family'
    Assert-Cf7Test (-not [regex]::IsMatch($workflowText, 'runs-on:\s*(?:windows-latest|windows-2025|self-hosted)')) 'cloud builder workflow must not use a mutable major-toolchain alias or self-hosted runners'
    Assert-Cf7Test ($buildJobText.Contains('CF7_EXPECTED_IMAGE_OS: win22') -and
        $buildJobText.Contains('$env:RUNNER_ENVIRONMENT -cne ''github-hosted''') -and
        $buildJobText.Contains('$env:ImageOS -cne $env:CF7_EXPECTED_IMAGE_OS')) `
        'cloud producer must fail closed when GitHub resolves an unexpected runner family'
    Assert-Cf7Test (-not [regex]::IsMatch($workflowText, '(?m)^\s*uses:\s*[^\s@]+@(?![0-9a-f]{40}(?:\s|$))')) 'every cloud workflow action must use one immutable full commit SHA'
    Assert-Cf7Test ($workflowText.Contains('name: Preserve failed bootstrap diagnostics') -and
        $workflowText.Contains('CF7_BOOTSTRAP_DIAGNOSTICS_DIR: ${{ github.workspace }}\tmp\runtime-bootstrap-diagnostics') -and
        $workflowText.Contains('path: tmp/runtime-bootstrap-diagnostics') -and
        $workflowText.Contains('if: failure()')) 'failed cloud producer must preserve bounded bootstrap diagnostics'
    Assert-Cf7Test ($workflowText.IndexOf('CF7_CANDIDATE_ROOT=$candidate', [StringComparison]::Ordinal) -lt
        $workflowText.IndexOf('-File .\launcher\build-runtime-candidate.ps1', [StringComparison]::Ordinal)) `
        'cloud candidate path must be exported before the producer can fail'
    Assert-Cf7Test ($buildJobText.Contains('fetch-depth: 1') -and -not $buildJobText.Contains('fetch-depth: 0')) 'cloud producer must fetch only the requested immutable tree, not full repository history'
    Assert-Cf7Test ($buildJobText.Contains('sparse-checkout-cone-mode: false') -and
        $buildJobText.Contains('tools/materialize-runtime-build-inputs.ps1') -and
        $buildJobText.Contains('name: Materialize exact runtime identity domains')) `
        'cloud producer must expand a partial checkout to the exact four identity domains'
    $integrityWorkflowText = [IO.File]::ReadAllText((Join-Path $ProjectRoot '.github\workflows\runtime-bundle-integrity.yml'), [Text.Encoding]::UTF8)
    Assert-Cf7Test (-not [regex]::IsMatch($integrityWorkflowText, '(?m)^\s*uses:\s*[^\s@]+@(?![0-9a-f]{40}(?:\s|$))')) 'runtime integrity workflow actions must use immutable full commit SHAs'
    Assert-Cf7Test ($integrityWorkflowText.Contains('actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0 # v7')) 'runtime integrity workflow must use the reviewed checkout v7 commit'
    foreach ($longPathSetting in @('GIT_CONFIG_COUNT: 1','GIT_CONFIG_KEY_0: core.longpaths','GIT_CONFIG_VALUE_0: true')) {
        Assert-Cf7Test ($buildJobText.Contains($longPathSetting)) "checkout must receive Windows long-path Git config: $longPathSetting"
    }
    foreach ($workflowNeedle in @(
        'actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0 # v7',
        'actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a # v7',
        'actions/download-artifact@3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c # v8',
        'actions/attest@f7c74d28b9d84cb8768d0b8ca14a4bac6ef463e6 # v4',
        'Validate staged cloud identity and archive layout',
        'Compress-Archive -Path'
    )) {
        Assert-Cf7Test ($workflowText.Contains($workflowNeedle)) "cloud workflow contract missing: $workflowNeedle"
    }
    foreach ($configValue in @($githubConfig.repository,$githubConfig.signerWorkflow,$githubConfig.sourceRef,$githubConfig.faultDomain,$githubConfig.runnerClass)) {
        Assert-Cf7Test ($workflowText.Contains([string]$configValue)) "cloud workflow/config identity drift: $configValue"
    }
    $bootstrapText = [IO.File]::ReadAllText((Join-Path $ProjectRoot 'tools\bootstrap-runtime-build-env.ps1'), [Text.Encoding]::UTF8)
    Assert-Cf7Test ($bootstrapText.Contains('modify --installPath') -and -not $bootstrapText.Contains('update --installPath')) `
        'Visual Studio component provisioning must use modify rather than update'
    Assert-Cf7Test ($bootstrapText.Contains("-all -prerelease -products '*'") -and $bootstrapText.Contains('Copy-Cf7VisualStudioSetupDiagnostics')) `
        'Visual Studio bootstrap must inventory all instances and preserve setup diagnostics'
    Assert-Cf7Test ($buildJobText -and -not $buildJobText.Contains('id-token: write') -and -not $buildJobText.Contains('attestations: write')) 'untrusted build job must not receive signing permissions'
    Assert-Cf7Test ($attestJobText.Contains('id-token: write') -and $attestJobText.Contains('attestations: write')) 'attestation job must have only-in-job signing permissions'
    Assert-Cf7Test ($attestJobText.IndexOf('Validate staged cloud identity and archive layout', [StringComparison]::Ordinal) -lt $attestJobText.IndexOf('actions/attest@', [StringComparison]::Ordinal)) 'trusted archive/envelope preflight must run before OIDC signing'
    Assert-Cf7Test ($attestJobText.Contains('subject-path: cloud-output/runtime-build-envelope.v2.json')) 'SLSA provenance subject must be the deterministic envelope'

    $preflightMatch = [regex]::Match($workflowText, '(?ms)^      - name: Validate staged cloud identity and archive layout\s+shell: powershell\s+env:.*?^        run: \|\r?\n(?<body>.*?)(?=^      - name: Generate SLSA provenance)')
    Assert-Cf7Test $preflightMatch.Success 'cannot extract trusted cloud artifact preflight from workflow'
    $preflightText = [regex]::Replace($preflightMatch.Groups['body'].Value, '(?m)^          ', '')
    $preflightScript = [scriptblock]::Create($preflightText)
    $preflightRoot = Join-Path $testRoot 'workflow-preflight'
    $preflightOut = Join-Path $preflightRoot 'cloud-output'
    $preflightCandidate = Join-Path $preflightRoot 'candidate'
    New-Item -ItemType Directory -Path $preflightOut,(Join-Path $preflightCandidate 'runtime') -Force | Out-Null
    $preflightExe = Join-Path $preflightCandidate 'CRAZYFLASHER7MercenaryEmpire.exe'
    $preflightCore = Join-Path $preflightCandidate 'runtime\core.dll'
    [IO.File]::WriteAllBytes($preflightExe, [byte[]](4,3,2,1))
    [IO.File]::WriteAllBytes($preflightCore, [byte[]](7,7,7))
    Write-Cf7TestText (Join-Path $preflightCandidate 'runtime\cf7-runtime-manifest.tsv') "cf7-runtime-manifest-v2`n"
    Write-Cf7TestText (Join-Path $preflightCandidate 'runtime-build-metadata.v2.json') "{}`n"
    $preflightRows = @(
        [pscustomobject][ordered]@{ path='CRAZYFLASHER7MercenaryEmpire.exe'; size=(Get-Item -LiteralPath $preflightExe).Length; sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $preflightExe).Hash.ToUpperInvariant() },
        [pscustomobject][ordered]@{ path='runtime/core.dll'; size=(Get-Item -LiteralPath $preflightCore).Length; sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $preflightCore).Hash.ToUpperInvariant() }
    )
    $preflightEnvelope = [ordered]@{
        schema='cf7-runtime-github-build-envelope.v2'
        repository=$githubConfig.repository
        signerWorkflow=$githubConfig.signerWorkflow
        sourceRef=$githubConfig.sourceRef
        faultDomain=$githubConfig.faultDomain
        runnerClass=$githubConfig.runnerClass
        sourceCommitOid=$sourceCommit
        files=$preflightRows
    }
    Write-Cf7TestText (Join-Path $preflightOut 'runtime-build-envelope.v2.json') (($preflightEnvelope | ConvertTo-Json -Depth 6 -Compress) + "`n")
    $preflightZip = Join-Path $preflightOut 'runtime-candidate.v2.zip'
    Compress-Archive -Path (Join-Path $preflightCandidate '*') -DestinationPath $preflightZip -CompressionLevel Optimal
    $env:CF7_SOURCE_COMMIT = $sourceCommit
    $env:CF7_EXPECTED_REPOSITORY = [string]$githubConfig.repository
    $env:CF7_EXPECTED_WORKFLOW = [string]$githubConfig.signerWorkflow
    $env:CF7_EXPECTED_REF = [string]$githubConfig.sourceRef
    $env:CF7_EXPECTED_FAULT_DOMAIN = [string]$githubConfig.faultDomain
    $env:CF7_EXPECTED_RUNNER_CLASS = [string]$githubConfig.runnerClass
    Push-Location $preflightRoot
    try { & $preflightScript }
    finally { Pop-Location }
    $script:passed++
    Remove-Item -LiteralPath $preflightZip -Force
    [IO.File]::WriteAllBytes($preflightExe, [byte[]](4,3,2,0))
    Compress-Archive -Path (Join-Path $preflightCandidate '*') -DestinationPath $preflightZip -CompressionLevel Optimal
    Assert-Cf7Throws {
        Push-Location $preflightRoot
        try { & $preflightScript } finally { Pop-Location }
    } 'trusted cloud artifact preflight must reject archive bytes that differ from the envelope'
    Remove-Item -LiteralPath $preflightZip -Force
    [IO.File]::WriteAllBytes($preflightExe, [byte[]](4,3,2,1))
    New-Item -ItemType Directory -Path (Join-Path $preflightCandidate 'logs') -Force | Out-Null
    Write-Cf7TestText (Join-Path $preflightCandidate 'logs\bootstrap.log') "host-specific diagnostics`n"
    Compress-Archive -Path (Join-Path $preflightCandidate '*') -DestinationPath $preflightZip -CompressionLevel Optimal
    Assert-Cf7Throws {
        Push-Location $preflightRoot
        try { & $preflightScript } finally { Pop-Location }
    } 'trusted cloud artifact preflight must reject undeclared bootstrap diagnostics'

    $layoutZip = Join-Path $testRoot 'candidate-layout.zip'
    Compress-Archive -Path (Join-Path $candidateRoot '*') -DestinationPath $layoutZip -CompressionLevel Optimal
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $layoutArchive = [IO.Compression.ZipFile]::OpenRead($layoutZip)
    try {
        $layoutEntries = @($layoutArchive.Entries | ForEach-Object { $_.FullName.Replace('\','/') })
        Assert-Cf7Test ($layoutEntries -contains 'app.exe') 'candidate archive must place the root executable directly at archive root'
        Assert-Cf7Test ($layoutEntries -contains 'runtime/cf7-runtime-manifest.tsv') 'candidate archive must place runtime directly at archive root'
    } finally { $layoutArchive.Dispose() }

    Copy-Item -LiteralPath (Join-Path $candidateRoot 'app.exe') -Destination (Join-Path $fixtureRoot 'app.exe') -Force
    New-Item -ItemType Directory -Path (Join-Path $fixtureRoot 'runtime') -Force | Out-Null
    Get-ChildItem -LiteralPath (Join-Path $candidateRoot 'runtime') -File | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $fixtureRoot 'runtime') -Force
    }
    & git -C $fixtureRoot add -- app.exe runtime
    if ($LASTEXITCODE -ne 0) { throw 'Cannot stage the index-mode deployment fixture.' }
    $indexWrapper = & $verifier -ProjectRoot $fixtureRoot -CandidateRoot $fixtureRoot -EnvelopePath $envelopeA -BundlePath $bundlePath `
        -ConfigPath $githubConfigPath -GitHubCliPath $fakeGh -ExpectedSourceCommitOid $sourceCommit -SourceMode Index -ReplayFromReleaseRecord
    Assert-Cf7Test ([string]$indexWrapper.canonicalPayloadSha256 -ceq [string]$wrapper.canonicalPayloadSha256) 'index replay must reproduce the same normalized cloud proof'
    Assert-Cf7Throws { & $verifier -ProjectRoot $fixtureRoot -CandidateRoot $candidateRoot -EnvelopePath $envelopeA -BundlePath $bundlePath -ConfigPath $githubConfigPath -GitHubCliPath $fakeGh -ExpectedSourceCommitOid $sourceCommit -SourceMode Index -ReplayFromReleaseRecord } 'index replay must reject a non-project CandidateRoot'

    Write-Cf7TestText (Join-Path $fixtureRoot 'successor-note.txt') "policy-only successor`n"
    & git -C $fixtureRoot add -- successor-note.txt
    & git -C $fixtureRoot commit -q -m successor
    if ($LASTEXITCODE -ne 0) { throw 'Cannot create successor fixture commit.' }
    Assert-Cf7Throws { & $verifier -ProjectRoot $fixtureRoot -CandidateRoot $candidateRoot -EnvelopePath $envelopeA -BundlePath $bundlePath -ConfigPath $githubConfigPath -GitHubCliPath $fakeGh -ExpectedSourceCommitOid $sourceCommit } 'default import must require exact source HEAD'
    $replayed = & $verifier -ProjectRoot $fixtureRoot -CandidateRoot $candidateRoot -EnvelopePath $envelopeA -BundlePath $bundlePath -ConfigPath $githubConfigPath -GitHubCliPath $fakeGh -ExpectedSourceCommitOid $sourceCommit -ReplayFromReleaseRecord
    Assert-Cf7Test ([string]$replayed.payload.sourceCommitOid -ceq $sourceCommit) 'release replay must accept a source commit ancestor when product identity is unchanged'

    $sameTree = ([string](& git -C $fixtureRoot rev-parse 'HEAD^{tree}')).Trim()
    $unrelatedCommit = ("unrelated replay fixture`n" | & git -C $fixtureRoot commit-tree $sameTree).Trim()
    if ($LASTEXITCODE -ne 0 -or $unrelatedCommit -notmatch '^[0-9a-fA-F]{40,64}$') { throw 'Cannot create unrelated fixture commit.' }
    & git -C $fixtureRoot checkout -q --detach $unrelatedCommit
    if ($LASTEXITCODE -ne 0) { throw 'Cannot check out unrelated fixture commit.' }
    Assert-Cf7Throws { & $verifier -ProjectRoot $fixtureRoot -CandidateRoot $candidateRoot -EnvelopePath $envelopeA -BundlePath $bundlePath -ConfigPath $githubConfigPath -GitHubCliPath $fakeGh -ExpectedSourceCommitOid $sourceCommit -ReplayFromReleaseRecord } 'release replay must reject a non-descendant checkout'

    Write-Host "[RuntimeGitHubAttestationTest] PASS assertions=$passed" -ForegroundColor Green
} finally {
    Remove-Item Env:CF7_FAKE_GH_ARGS -ErrorAction SilentlyContinue
    Remove-Item Env:CF7_FAKE_GH_MODE -ErrorAction SilentlyContinue
    foreach ($name in @('CF7_SOURCE_COMMIT','CF7_EXPECTED_REPOSITORY','CF7_EXPECTED_WORKFLOW','CF7_EXPECTED_REF','CF7_EXPECTED_FAULT_DOMAIN','CF7_EXPECTED_RUNNER_CLASS')) {
        Remove-Item ("Env:" + $name) -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $testRoot -PathType Container) {
        $resolved = [IO.Path]::GetFullPath($testRoot)
        $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\cf7-runtime-github-attestation-test-'
        if ($resolved.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $resolved -Recurse -Force }
    }
}
