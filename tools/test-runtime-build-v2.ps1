param([string]$ProjectRoot)

$ErrorActionPreference = 'Stop'
if (-not $ProjectRoot) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
. (Join-Path $ProjectRoot 'tools\runtime-build-v2-common.ps1')
. (Join-Path $ProjectRoot 'tools\runtime-build-attestation-v2-common.ps1')

$script:checks = 0
$createdThumbprints = New-Object 'System.Collections.Generic.List[string]'
$testRoot = Join-Path $ProjectRoot ("tmp\runtime-build-v2-test-" + [Guid]::NewGuid().ToString('N'))
$tmpRoot = [IO.Path]::GetFullPath((Join-Path $ProjectRoot 'tmp')).TrimEnd('\') + '\'
$resolvedTestRoot = [IO.Path]::GetFullPath($testRoot).TrimEnd('\')
if (-not $resolvedTestRoot.StartsWith($tmpRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe runtime v2 test path.' }
$utf8NoBom = New-Object Text.UTF8Encoding($false)

function Write-TestText([string]$Path, [string]$Value) {
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    [IO.File]::WriteAllText($Path, $Value, $utf8NoBom)
}

function Assert-Equal([string]$Label, $Expected, $Actual) {
    if ([string]$Expected -ne [string]$Actual) { throw "$Label expected=$Expected actual=$Actual" }
    $script:checks++
}

function Assert-NotEqual([string]$Label, $Left, $Right) {
    if ([string]$Left -eq [string]$Right) { throw "$Label unexpectedly remained $Left" }
    $script:checks++
}

function Expect-Failure([string]$Label, [scriptblock]$Action) {
    try { & $Action; throw "Expected failure did not occur: $Label" }
    catch {
        if ($_.Exception.Message -eq "Expected failure did not occur: $Label") { throw }
        $script:checks++
    }
}

function New-TestCertificate([string]$Name) {
    $certificate = New-SelfSignedCertificate `
        -Type Custom `
        -Subject "CN=CF7 Runtime V2 Test $Name $([Guid]::NewGuid().ToString('N'))" `
        -CertStoreLocation 'Cert:\CurrentUser\My' `
        -KeyAlgorithm RSA `
        -KeyLength 2048 `
        -HashAlgorithm SHA256 `
        -KeyExportPolicy NonExportable `
        -KeyUsage DigitalSignature `
        -NotAfter ([DateTime]::UtcNow.AddDays(2)) `
        -TextExtension @('2.5.29.19={critical}{text}ca=false', '2.5.29.37={text}1.3.6.1.5.5.7.3.3')
    $script:createdThumbprints.Add($certificate.Thumbprint.Replace(' ', '').ToUpperInvariant())
    return $certificate
}

function New-RegistryEntry([System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate, [string]$BuilderId, [string]$FaultDomain) {
    return [pscustomobject][ordered]@{
        builderId = $BuilderId
        keyId = Get-Cf7RuntimeV2BuilderKeyId -Certificate $Certificate
        certificateThumbprint = $Certificate.Thumbprint.Replace(' ', '').ToUpperInvariant()
        certificateBase64 = [Convert]::ToBase64String($Certificate.RawData)
        enabled = $true
        epoch = 1
        faultDomain = $FaultDomain
    }
}

try {
    if (-not (Get-Command New-SelfSignedCertificate -ErrorAction SilentlyContinue)) { throw 'New-SelfSignedCertificate is required by runtime v2 tests.' }
    $repositoryConfig = Read-Cf7RuntimeV2Config -ProjectRoot $ProjectRoot -Mode Worktree
    $repositoryArtifactFiles = @($repositoryConfig.domains.artifactSource.fixedFiles)
    $repositoryArtifactTrees = @($repositoryConfig.domains.artifactSource.trees)
    $repositoryProducerFiles = @($repositoryConfig.domains.producerRecipe.fixedFiles)
    $repositoryPolicyFiles = @($repositoryConfig.domains.policy.fixedFiles)
    $repositoryPolicyTrees = @($repositoryConfig.domains.policy.trees)
    $unicodePolicyFile = [string](@($repositoryPolicyFiles | Where-Object {
        [string]$_ -notmatch '^[\x00-\x7F]+$'
    }) | Select-Object -First 1)
    Assert-Equal 'repository policy retains one non-ASCII fixed-file fixture' $true `
        (-not [string]::IsNullOrWhiteSpace($unicodePolicyFile))
    Assert-Equal 'line-ending rules belong only to producer recipe' $true `
        (('.gitattributes' -in $repositoryProducerFiles) -and ('.gitattributes' -notin $repositoryPolicyFiles))
    Assert-Equal 'identity common belongs only to producer recipe' $true `
        (('tools/runtime-build-v2-common.ps1' -in $repositoryProducerFiles) -and ('tools/runtime-build-v2-common.ps1' -notin $repositoryPolicyFiles))
    Assert-Equal 'attestation common belongs only to policy' $true `
        (('tools/runtime-build-attestation-v2-common.ps1' -in $repositoryPolicyFiles) -and ('tools/runtime-build-attestation-v2-common.ps1' -notin $repositoryProducerFiles))
    Assert-Equal 'third-party notice is an artifact source fixed file' $true `
        ('launcher/THIRD-PARTY-NOTICES.txt' -cin $repositoryArtifactFiles)
    $repositoryAttributes = [IO.File]::ReadAllText(
        (Join-Path $ProjectRoot '.gitattributes'),
        [Text.Encoding]::UTF8)
    Assert-Equal 'third-party notice checkout bytes are pinned to LF and preserve bundled notice whitespace' 1 `
        @([regex]::Matches(
            $repositoryAttributes,
            '(?m)^launcher/THIRD-PARTY-NOTICES\.txt text eol=lf whitespace=-blank-at-eol$')).Count
    $repositoryNoticeBytes = [IO.File]::ReadAllBytes(
        (Join-Path $ProjectRoot 'launcher\THIRD-PARTY-NOTICES.txt'))
    Assert-Equal 'third-party notice worktree contains no CR bytes' 0 `
        @($repositoryNoticeBytes | Where-Object { $_ -eq 13 }).Count
    $playerInfoAssetTrees = @($repositoryArtifactTrees | Where-Object {
        [string]$_.path -ceq 'launcher/src/Guardian/Hud/PlayerInfo/Assets'
    })
    Assert-Equal 'player-info assets have one narrow artifact-source tree' 1 $playerInfoAssetTrees.Count
    Assert-Equal 'player-info artifact-source extensions are exactly JSON and SVG' '.json,.svg' `
        ((@($playerInfoAssetTrees[0].includeExtensions | ForEach-Object { [string]$_ }) | Sort-Object) -join ',')
    Assert-Equal 'player-info artifact-source tree has no path exclusions' 0 @($playerInfoAssetTrees[0].excludePaths).Count
    Assert-Equal 'player-info artifact-source tree has no prefix exclusions' 0 @($playerInfoAssetTrees[0].excludePrefixes).Count
    Assert-Equal 'player-info production validator is policy-bound' $true `
        ('tools/validate-player-info-svg-production-contract.ps1' -cin $repositoryPolicyFiles)
    $rendererQualificationTrees = @($repositoryPolicyTrees | Where-Object {
        [string]$_.path -ceq 'tools/player-info-hud/renderer-qualification'
    })
    Assert-Equal 'renderer qualification has one narrow policy tree' 1 $rendererQualificationTrees.Count
    Assert-Equal 'renderer qualification policy extensions are exact' '.cs,.csproj,.json,.svg' `
        ((@($rendererQualificationTrees[0].includeExtensions | ForEach-Object { [string]$_ }) | Sort-Object) -join ',')
    Assert-Equal 'renderer qualification policy tree has no individual path exclusions' 0 `
        @($rendererQualificationTrees[0].excludePaths).Count
    Assert-Equal 'renderer qualification policy tree excludes only machine build caches' `
        'tools/player-info-hud/renderer-qualification/bin/,tools/player-info-hud/renderer-qualification/obj/' `
        ((@($rendererQualificationTrees[0].excludePrefixes | ForEach-Object { [string]$_ }) | Sort-Object) -join ',')
    $buildScript = [IO.File]::ReadAllText((Join-Path $ProjectRoot 'launcher\build.ps1'))
    $producerScript = [IO.File]::ReadAllText((Join-Path $ProjectRoot 'launcher\build-runtime-candidate.ps1'))
    $startScript = [IO.File]::ReadAllText((Join-Path $ProjectRoot 'automation\start.ps1'))
    $promotionScript = [IO.File]::ReadAllText((Join-Path $ProjectRoot 'tools\promote-runtime-bundle.ps1'))
    $identityCommonScript = [IO.File]::ReadAllText((Join-Path $ProjectRoot 'tools\runtime-build-v2-common.ps1'))
    $materializerScript = [IO.File]::ReadAllText((Join-Path $ProjectRoot 'tools\materialize-runtime-build-inputs.ps1'))
    $bootstrapSource = [IO.File]::ReadAllText((Join-Path $ProjectRoot 'launcher\native\bootstrap\bootstrap.cpp'))
    $programSource = [IO.File]::ReadAllText((Join-Path $ProjectRoot 'launcher\src\Program.cs'))
    $producerTokens = $null
    $producerParseErrors = $null
    $producerAst = [Management.Automation.Language.Parser]::ParseInput(
        $producerScript, [ref]$producerTokens, [ref]$producerParseErrors)
    Assert-Equal 'producer script parses for isolated work-root contract tests' 0 @($producerParseErrors).Count
    $producerFunctions = @($producerAst.FindAll({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst]
    }, $true))
    foreach ($functionName in @(
        'Resolve-Cf7RuntimeWorkBase',
        'New-Cf7RuntimeWorkJobLayout',
        'Assert-Cf7RuntimeWorkCleanupTarget'
    )) {
        $functionAst = @($producerFunctions | Where-Object { $_.Name -eq $functionName })
        Assert-Equal "producer exports one $functionName helper" 1 $functionAst.Count
        Invoke-Expression $functionAst[0].Extent.Text
    }
    $machineTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    $defaultWorkBase = Resolve-Cf7RuntimeWorkBase `
        -SystemTempRoot $machineTemp -SourceProjectRoot $ProjectRoot
    $expectedWorkBase = [IO.Path]::GetFullPath((Join-Path $machineTemp 'cf7-runtime-build-work')).TrimEnd('\')
    Assert-Equal 'producer defaults work root to machine-local system temp' $expectedWorkBase $defaultWorkBase
    Assert-Equal 'producer default work root is independent of parenthesized repository path' $false `
        ($defaultWorkBase.Equals($ProjectRoot, [StringComparison]::OrdinalIgnoreCase) -or
            $defaultWorkBase.StartsWith($ProjectRoot + '\', [StringComparison]::OrdinalIgnoreCase))
    $overrideWorkBase = Join-Path $machineTemp 'cf7-runtime-work-override'
    Assert-Equal 'producer preserves safe CF7_RUNTIME_WORK_ROOT override' `
        ([IO.Path]::GetFullPath($overrideWorkBase).TrimEnd('\')) `
        (Resolve-Cf7RuntimeWorkBase -OverrideRoot $overrideWorkBase -SystemTempRoot $machineTemp -SourceProjectRoot $ProjectRoot)
    Expect-Failure 'producer rejects filesystem-root work path' {
        Resolve-Cf7RuntimeWorkBase -OverrideRoot ([IO.Path]::GetPathRoot($machineTemp)) `
            -SystemTempRoot $machineTemp -SourceProjectRoot $ProjectRoot | Out-Null
    }
    Expect-Failure 'producer rejects relative work path before normalization' {
        Resolve-Cf7RuntimeWorkBase -OverrideRoot 'relative\cf7-work' `
            -SystemTempRoot $machineTemp -SourceProjectRoot $ProjectRoot | Out-Null
    }
    Expect-Failure 'producer rejects UNC work path' {
        Resolve-Cf7RuntimeWorkBase -OverrideRoot '\\server\share\cf7-work' `
            -SystemTempRoot $machineTemp -SourceProjectRoot $ProjectRoot | Out-Null
    }
    Expect-Failure 'producer rejects CMD metacharacters in work path' {
        Resolve-Cf7RuntimeWorkBase -OverrideRoot (Join-Path $machineTemp 'cf7-(unsafe)-work') `
            -SystemTempRoot $machineTemp -SourceProjectRoot $ProjectRoot | Out-Null
    }
    Expect-Failure 'producer rejects repository-contained work path' {
        Resolve-Cf7RuntimeWorkBase -OverrideRoot (Join-Path $ProjectRoot 'tmp\runtime-build-work') `
            -SystemTempRoot $machineTemp -SourceProjectRoot $ProjectRoot | Out-Null
    }
    $workLayout = New-Cf7RuntimeWorkJobLayout -WorkBase $defaultWorkBase -RunToken ('a' * 32)
    Assert-Equal 'producer job is an exact direct child of the work root' $defaultWorkBase `
        ([IO.Path]::GetFullPath((Split-Path -Parent $workLayout.jobRoot)).TrimEnd('\'))
    Assert-Equal 'producer projected work path remains inside MAX_PATH' $true ($workLayout.longestProbe.Length -lt 260)
    Assert-Equal 'producer cleanup accepts only its exact job leaf' $workLayout.jobRoot `
        (Assert-Cf7RuntimeWorkCleanupTarget -WorkBase $defaultWorkBase -JobRoot $workLayout.jobRoot)
    Expect-Failure 'producer cleanup rejects work root itself' {
        Assert-Cf7RuntimeWorkCleanupTarget -WorkBase $defaultWorkBase -JobRoot $defaultWorkBase | Out-Null
    }
    Expect-Failure 'producer cleanup rejects nested descendants' {
        Assert-Cf7RuntimeWorkCleanupTarget -WorkBase $defaultWorkBase `
            -JobRoot (Join-Path $workLayout.jobRoot 'nested') | Out-Null
    }
    Expect-Failure 'producer cleanup rejects malformed sibling leaf' {
        Assert-Cf7RuntimeWorkCleanupTarget -WorkBase $defaultWorkBase `
            -JobRoot (Join-Path $defaultWorkBase ('other-' + ('b' * 32))) | Out-Null
    }
    $tooLongWorkBase = Join-Path ([IO.Path]::GetPathRoot($machineTemp)) ('w' * 210)
    Expect-Failure 'producer rejects projected work path outside MAX_PATH' {
        New-Cf7RuntimeWorkJobLayout -WorkBase $tooLongWorkBase -RunToken ('c' * 32) | Out-Null
    }
    Assert-Equal 'candidate uses isolated runtime verification mode' $true `
        ($producerScript.Contains("Arguments = '--verify-runtime-only'") -and $bootstrapSource.Contains('L"--verify-runtime-only"'))
    Assert-Equal 'candidate waits for GUI bootstrap exit code' $true `
        ($producerScript.Contains('$verifyProcess.WaitForExit(120000)') -and $producerScript.Contains('$verifyProcess.ExitCode') -and
            $producerScript.Contains('$verifyProcess.Kill()'))
    Assert-Equal 'candidate does not invoke asynchronous verify-only call operator' $false `
        ($producerScript -match '(?m)^\s*&\s+\$userFacingExe\s+--verify-only\s*$')
    Assert-Equal 'build result is explicit that a candidate is not deployed' $true `
        ($buildScript.Contains("deploymentStatus = 'NOT_DEPLOYED'") -and
            $buildScript.Contains('formalDeploymentModified = $false') -and
            $buildScript.Contains("runtimeMode = 'isolated_candidate'"))
    Assert-Equal 'candidate producer snapshots the complete formal deployment closure' $true `
        ($producerScript.Contains('Get-Cf7FormalDeploymentSnapshot') -and
            $producerScript.Contains("'CRAZYFLASHER7MercenaryEmpire.exe'") -and
            $producerScript.Contains("'runtime'") -and
            $producerScript.Contains("'config\build\runtime-release-consensus.json'") -and
            $producerScript.Contains('changed the formal deployment closure'))
    Assert-Equal 'candidate build output cannot be mistaken for deployment' $true `
        ($buildScript.Contains('CANDIDATE BUILD ONLY - NOT DEPLOYED') -and
            $producerScript.Contains('CANDIDATE ONLY - NOT DEPLOYED') -and
            $producerScript.Contains('FORMAL RUNTIME UNCHANGED'))
    Assert-Equal 'start defaults formal and requires an explicit repository-bound candidate root' $true `
        ($startScript.Contains('[string]$CandidateRoot') -and
            $startScript.Contains("`$runtimeMode = 'formal_runtime'") -and
            $startScript.Contains("`$runtimeMode = 'isolated_candidate'") -and
            $startScript.Contains('[IO.Path]::IsPathRooted($CandidateRoot)') -and
            $startScript.Contains('tmp\runtime-candidates\v2') -and
            $startScript.Contains('runtime-build-metadata.v2.json') -and
            $startScript.Contains('verify-runtime-bundle-v2.ps1'))
    Assert-Equal 'promotion waits for deployed GUI bootstrap exit code' $true `
        ($promotionScript.Contains('$verifyProcess.WaitForExit(120000)') -and $promotionScript.Contains('$verifyProcess.ExitCode') -and
            $promotionScript.Contains('$verifyProcess.Kill()'))
    Assert-Equal 'bootstrap keeps runtime-only and full-install preflights separate' $true `
        ($bootstrapSource.Contains('static bool PreflightRuntimeFiles') -and $bootstrapSource.Contains('static bool PreflightCriticalFiles'))
    Assert-Equal 'bootstrap rejects ambiguous verification modes' $true `
        ($bootstrapSource.Contains('verifyRuntimeOnly && verifyCompleteInstall') -and $bootstrapSource.Contains('return 64;'))
    Assert-Equal 'Core candidate mode requires explicit project root and identity-bound v2 marker' $true `
        ($programSource.Contains('explicitProjectRoot = TryGetProjectRootFromArgs(args)') -and
            $programSource.Contains('cf7-runtime-candidate-metadata.v2') -and
            $programSource.Contains('tmp", "runtime-candidates", "v2') -and
            $programSource.Contains('metadataBuildIdentity, manifestBuildIdentity') -and
            $programSource.Contains('metadataPayloadClosure, manifestPayloadClosure'))
    Assert-Equal 'Core preserves full and runtime-only self-check modes' $true `
        ($programSource.Contains('"--verify-only"') -and $programSource.Contains('"--verify-runtime-only"'))
    Assert-Equal 'promotion does not deploy candidate metadata marker' $false `
        $promotionScript.Contains('runtime-build-metadata.v2.json')
    Assert-Equal 'index fixed-file lookup is independent of core.quotepath display escaping' $true `
        ($identityCommonScript.Contains("cat-file -e (':' + `$fixed)"))
    Assert-Equal 'sparse materializer sends non-ASCII paths to Git as UTF-8' $true `
        ($materializerScript.Contains('$OutputEncoding = New-Object Text.UTF8Encoding($false)'))
    $shortCandidateLeaf = New-Cf7RuntimeV2CandidateLeafName `
        -BuildIdentityHash ('A' * 64) -BuilderId ('builder-' + ('x' * 100)) -RunToken 'test-run-1'
    Assert-Equal 'candidate directory does not expose unbounded builder label' $false $shortCandidateLeaf.Contains('builder-')
    Assert-Equal 'candidate directory has a bounded legacy-path-safe leaf' $true ($shortCandidateLeaf.Length -le 64)
    $projectedCandidateProbe = Join-Path (Join-Path $ProjectRoot ('tmp\runtime-candidates\v2\' + $shortCandidateLeaf)) `
        'runtime\CRAZYFLASHER7MercenaryEmpire.Core.runtimeconfig.json'
    Assert-Equal 'default candidate layout remains inside bootstrap MAX_PATH' $true ($projectedCandidateProbe.Length -lt 260)
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    $configPath = Join-Path $testRoot 'config\runtime-inputs.v2.json'
    $fixtureConfig = [pscustomobject][ordered]@{
        schema = 'cf7-runtime-inputs.v2'
        domains = [pscustomobject][ordered]@{
            artifactSource = [pscustomobject][ordered]@{
                fixedFiles = @('src/app.cs','native/lib.rs','launcher/THIRD-PARTY-NOTICES.txt')
                trees = @(
                    [pscustomobject][ordered]@{
                        path = 'src'
                        includeExtensions = @('.cs')
                        excludePaths = @('src/HotkeyGuard.cs','src/app.cs')
                        excludePrefixes = @()
                    },
                    [pscustomobject][ordered]@{
                        path = 'launcher/src/Guardian/Hud/PlayerInfo/Assets'
                        includeExtensions = @('.svg','.json')
                        excludePaths = @()
                        excludePrefixes = @()
                    }
                )
            }
            producerRecipe = [pscustomobject][ordered]@{ fixedFiles = @('recipe.ps1'); trees = @() }
            toolchainLock = [pscustomobject][ordered]@{ fixedFiles = @('toolchain.json'); trees = @() }
            policy = [pscustomobject][ordered]@{ fixedFiles = @('policy.ps1',$unicodePolicyFile); trees = @() }
        }
        payload = [pscustomobject][ordered]@{
            fixedRoots = @('CRAZYFLASHER7MercenaryEmpire.exe')
            trees = @('runtime')
            excludePaths = @('runtime/cf7-runtime-manifest.tsv','runtime/runtime-build-attestation.json')
            excludePrefixes = @('runtime/attestations/')
        }
    }
    Write-TestText $configPath (($fixtureConfig | ConvertTo-Json -Depth 10) + "`n")
    Write-TestText (Join-Path $testRoot 'src\app.cs') "class App {}`n"
    Write-TestText (Join-Path $testRoot 'src\HotkeyGuard.cs') "class Ignored {}`n"
    Write-TestText (Join-Path $testRoot 'native\lib.rs') "pub fn value() -> i32 { 1 }`n"
    Write-TestText (Join-Path $testRoot 'launcher\THIRD-PARTY-NOTICES.txt') "fixture notice`n"
    Write-TestText (Join-Path $testRoot 'launcher\src\Guardian\Hud\PlayerInfo\Assets\hp\fill.svg') `
        "<svg xmlns=`"http://www.w3.org/2000/svg`"><path d=`"M0 0h1v1z`"/></svg>`n"
    Write-TestText (Join-Path $testRoot 'launcher\src\Guardian\Hud\PlayerInfo\Assets\player-info.manifest.json') `
        "{`"format`":`"fixture`"}`n"
    Write-TestText (Join-Path $testRoot 'recipe.ps1') "Write-Output build`n"
    Write-TestText (Join-Path $testRoot 'toolchain.json') "{`"sdk`":`"1`"}`n"
    Write-TestText (Join-Path $testRoot 'policy.ps1') "Write-Output verify`n"
    Write-TestText (Join-Path $testRoot $unicodePolicyFile) "@echo off`r`n"
    Write-TestText (Join-Path $testRoot 'CRAZYFLASHER7MercenaryEmpire.exe') 'bootstrap'
    Write-TestText (Join-Path $testRoot 'runtime\payload.dll') 'payload-v1'
    Write-TestText (Join-Path $testRoot 'runtime\cf7-runtime-manifest.tsv') 'manifest-v1'
    Write-TestText (Join-Path $testRoot 'runtime\runtime-build-attestation.json') 'attestation-v1'
    Write-TestText (Join-Path $testRoot 'runtime\attestations\old.json') 'old-attestation'

    & git -C $testRoot init --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Cannot initialize runtime v2 Git fixture.' }
    & git -C $testRoot config core.quotepath true
    if ($LASTEXITCODE -ne 0) { throw 'Cannot enable quoted-path output in runtime v2 Git fixture.' }
    & git -C $testRoot add --all
    if ($LASTEXITCODE -ne 0) { throw 'Cannot stage runtime v2 Git fixture.' }

    $baseWorktree = Get-Cf7RuntimeBuildIdentityV2 -ProjectRoot $testRoot -Mode Worktree -ConfigPath $configPath
    $baseIndex = Get-Cf7RuntimeBuildIdentityV2 -ProjectRoot $testRoot -Mode Index -ConfigPath $configPath
    foreach ($field in @('artifactSourceHash','producerRecipeHash','toolchainLockHash','policyHash','buildIdentityHash')) {
        Assert-Equal "Worktree/Index baseline $field" $baseWorktree.$field $baseIndex.$field
    }

    Write-TestText (Join-Path $testRoot 'policy.ps1') "Write-Output verify-v2`n"
    $policyChanged = Get-Cf7RuntimeBuildIdentityV2 -ProjectRoot $testRoot -Mode Worktree -ConfigPath $configPath
    Assert-Equal 'policy isolation artifact' $baseWorktree.artifactSourceHash $policyChanged.artifactSourceHash
    Assert-Equal 'policy isolation producer' $baseWorktree.producerRecipeHash $policyChanged.producerRecipeHash
    Assert-Equal 'policy isolation toolchain' $baseWorktree.toolchainLockHash $policyChanged.toolchainLockHash
    Assert-NotEqual 'policy hash changes' $baseWorktree.policyHash $policyChanged.policyHash
    Assert-Equal 'policy does not change build identity' $baseWorktree.buildIdentityHash $policyChanged.buildIdentityHash
    $stillStaged = Get-Cf7RuntimeBuildIdentityV2 -ProjectRoot $testRoot -Mode Index -ConfigPath $configPath
    Assert-Equal 'Index ignores unstaged policy edit' $baseIndex.policyHash $stillStaged.policyHash
    Write-TestText (Join-Path $testRoot 'policy.ps1') "Write-Output verify`n"

    Write-TestText (Join-Path $testRoot 'src\app.cs') "class App { static int V = 2; }`n"
    $sourceChanged = Get-Cf7RuntimeBuildIdentityV2 -ProjectRoot $testRoot -Mode Worktree -ConfigPath $configPath
    Assert-NotEqual 'artifact source changes' $baseWorktree.artifactSourceHash $sourceChanged.artifactSourceHash
    Assert-Equal 'artifact change leaves recipe' $baseWorktree.producerRecipeHash $sourceChanged.producerRecipeHash
    Assert-Equal 'artifact change leaves toolchain' $baseWorktree.toolchainLockHash $sourceChanged.toolchainLockHash
    Assert-Equal 'artifact change leaves policy' $baseWorktree.policyHash $sourceChanged.policyHash
    Assert-NotEqual 'artifact change changes build identity' $baseWorktree.buildIdentityHash $sourceChanged.buildIdentityHash
    Assert-Equal 'Index ignores unstaged source edit' $baseIndex.artifactSourceHash (Get-Cf7RuntimeBuildIdentityV2 -ProjectRoot $testRoot -Mode Index -ConfigPath $configPath).artifactSourceHash
    Write-TestText (Join-Path $testRoot 'src\app.cs') "class App {}`n"

    Write-TestText (Join-Path $testRoot 'launcher\src\Guardian\Hud\PlayerInfo\Assets\hp\fill.svg') `
        "<svg xmlns=`"http://www.w3.org/2000/svg`"><path d=`"M0 0h2v1z`"/></svg>`n"
    $svgChanged = Get-Cf7RuntimeBuildIdentityV2 -ProjectRoot $testRoot -Mode Worktree -ConfigPath $configPath
    Assert-NotEqual 'single SVG byte change changes artifact source' $baseWorktree.artifactSourceHash $svgChanged.artifactSourceHash
    Assert-Equal 'single SVG byte change leaves producer recipe' $baseWorktree.producerRecipeHash $svgChanged.producerRecipeHash
    Assert-Equal 'single SVG byte change leaves toolchain lock' $baseWorktree.toolchainLockHash $svgChanged.toolchainLockHash
    Assert-Equal 'single SVG byte change leaves policy' $baseWorktree.policyHash $svgChanged.policyHash
    Assert-NotEqual 'single SVG byte change changes build identity' $baseWorktree.buildIdentityHash $svgChanged.buildIdentityHash
    $svgStillStaged = Get-Cf7RuntimeBuildIdentityV2 -ProjectRoot $testRoot -Mode Index -ConfigPath $configPath
    foreach ($field in @('artifactSourceHash','producerRecipeHash','toolchainLockHash','policyHash','buildIdentityHash')) {
        Assert-Equal "Index ignores unstaged SVG edit for $field" $baseIndex.$field $svgStillStaged.$field
    }
    Write-TestText (Join-Path $testRoot 'launcher\src\Guardian\Hud\PlayerInfo\Assets\hp\fill.svg') `
        "<svg xmlns=`"http://www.w3.org/2000/svg`"><path d=`"M0 0h1v1z`"/></svg>`n"

    Write-TestText (Join-Path $testRoot 'recipe.ps1') "Write-Output build-v2`n"
    $recipeChanged = Get-Cf7RuntimeBuildIdentityV2 -ProjectRoot $testRoot -Mode Worktree -ConfigPath $configPath
    Assert-NotEqual 'producer recipe changes' $baseWorktree.producerRecipeHash $recipeChanged.producerRecipeHash
    Assert-Equal 'recipe change leaves artifact' $baseWorktree.artifactSourceHash $recipeChanged.artifactSourceHash
    Assert-Equal 'recipe change leaves toolchain' $baseWorktree.toolchainLockHash $recipeChanged.toolchainLockHash
    Assert-Equal 'recipe change leaves policy' $baseWorktree.policyHash $recipeChanged.policyHash
    Write-TestText (Join-Path $testRoot 'recipe.ps1') "Write-Output build`n"

    Write-TestText (Join-Path $testRoot 'toolchain.json') "{`"sdk`":`"2`"}`n"
    $toolchainChanged = Get-Cf7RuntimeBuildIdentityV2 -ProjectRoot $testRoot -Mode Worktree -ConfigPath $configPath
    Assert-NotEqual 'toolchain changes' $baseWorktree.toolchainLockHash $toolchainChanged.toolchainLockHash
    Assert-Equal 'toolchain change leaves artifact' $baseWorktree.artifactSourceHash $toolchainChanged.artifactSourceHash
    Assert-Equal 'toolchain change leaves recipe' $baseWorktree.producerRecipeHash $toolchainChanged.producerRecipeHash
    Assert-Equal 'toolchain change leaves policy' $baseWorktree.policyHash $toolchainChanged.policyHash
    Write-TestText (Join-Path $testRoot 'toolchain.json') "{`"sdk`":`"1`"}`n"

    Write-TestText (Join-Path $testRoot 'src\HotkeyGuard.cs') "class Ignored { static int V = 99; }`n"
    $ignoredChanged = Get-Cf7RuntimeBuildIdentityV2 -ProjectRoot $testRoot -Mode Worktree -ConfigPath $configPath
    Assert-Equal 'excluded HotkeyGuard leaves artifact identity' $baseWorktree.artifactSourceHash $ignoredChanged.artifactSourceHash
    Write-TestText (Join-Path $testRoot 'src\HotkeyGuard.cs') "class Ignored {}`n"

    $closureBase = Get-Cf7RuntimePayloadClosureV2 -ProjectRoot $testRoot -DeploymentRoot $testRoot -Mode Worktree -ConfigPath $configPath
    Assert-Equal 'payload closure file count excludes envelope files' 2 @($closureBase.files).Count
    $closureIndex = Get-Cf7RuntimePayloadClosureV2 -ProjectRoot $testRoot -DeploymentRoot $testRoot -Mode Index -ConfigPath $configPath
    Assert-Equal 'payload Worktree/Index closure' $closureBase.payloadClosureHash $closureIndex.payloadClosureHash
    Write-TestText (Join-Path $testRoot 'runtime\cf7-runtime-manifest.tsv') 'manifest-v2'
    Write-TestText (Join-Path $testRoot 'runtime\runtime-build-attestation.json') 'attestation-v2'
    Write-TestText (Join-Path $testRoot 'runtime\attestations\old.json') 'old-attestation-v2'
    $closureEnvelopeChanged = Get-Cf7RuntimePayloadClosureV2 -ProjectRoot $testRoot -DeploymentRoot $testRoot -Mode Worktree -ConfigPath $configPath
    Assert-Equal 'manifest and attestations excluded from payload closure' $closureBase.payloadClosureHash $closureEnvelopeChanged.payloadClosureHash
    Write-TestText (Join-Path $testRoot 'runtime\payload.dll') 'payload-v2'
    $closurePayloadChanged = Get-Cf7RuntimePayloadClosureV2 -ProjectRoot $testRoot -DeploymentRoot $testRoot -Mode Worktree -ConfigPath $configPath
    Assert-NotEqual 'payload bytes change closure' $closureBase.payloadClosureHash $closurePayloadChanged.payloadClosureHash
    Write-TestText (Join-Path $testRoot 'runtime\payload.dll') 'payload-v1'

    # Reproduce the pristine hosted-runner case: quoted Git paths are enabled, the
    # checkout initially contains only ASCII seed files, and the materializer must
    # transmit a non-ASCII root path through Windows PowerShell's native stdin.
    $sparseFixture = Join-Path $testRoot 'sparse-fixture'
    $sparseConfigPath = Join-Path $sparseFixture 'config\build\runtime-inputs.v2.json'
    $sparseConfig = [pscustomobject][ordered]@{
        schema = 'cf7-runtime-inputs.v2'
        domains = [pscustomobject][ordered]@{
            artifactSource = [pscustomobject][ordered]@{ fixedFiles = @('src/app.cs'); trees = @() }
            producerRecipe = [pscustomobject][ordered]@{
                fixedFiles = @('tools/runtime-build-v2-common.ps1','tools/materialize-runtime-build-inputs.ps1')
                trees = @()
            }
            toolchainLock = [pscustomobject][ordered]@{ fixedFiles = @('toolchain.json'); trees = @() }
            policy = [pscustomobject][ordered]@{ fixedFiles = @($unicodePolicyFile); trees = @() }
        }
        payload = [pscustomobject][ordered]@{
            fixedRoots = @()
            trees = @()
            excludePaths = @()
            excludePrefixes = @()
        }
    }
    Write-TestText $sparseConfigPath (($sparseConfig | ConvertTo-Json -Depth 10) + "`n")
    Write-TestText (Join-Path $sparseFixture 'src\app.cs') "class SparseApp {}`n"
    Write-TestText (Join-Path $sparseFixture 'toolchain.json') "{}`n"
    Write-TestText (Join-Path $sparseFixture $unicodePolicyFile) "@echo off`r`n"
    New-Item -ItemType Directory -Path (Join-Path $sparseFixture 'tools') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $ProjectRoot 'tools\runtime-build-v2-common.ps1') `
        -Destination (Join-Path $sparseFixture 'tools\runtime-build-v2-common.ps1')
    Copy-Item -LiteralPath (Join-Path $ProjectRoot 'tools\materialize-runtime-build-inputs.ps1') `
        -Destination (Join-Path $sparseFixture 'tools\materialize-runtime-build-inputs.ps1')
    & git -C $sparseFixture init --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Cannot initialize sparse materializer fixture.' }
    & git -C $sparseFixture config user.name 'CF7 Runtime Test'
    & git -C $sparseFixture config user.email 'runtime-test@example.invalid'
    & git -C $sparseFixture config core.quotepath true
    & git -C $sparseFixture add --all
    & git -C $sparseFixture commit --quiet -m fixture
    if ($LASTEXITCODE -ne 0) { throw 'Cannot commit sparse materializer fixture.' }
    & git -C $sparseFixture sparse-checkout init --no-cone
    if ($LASTEXITCODE -ne 0) { throw 'Cannot initialize sparse materializer fixture checkout.' }
    $seedPatterns = @(
        '/config/build/runtime-inputs.v2.json',
        '/tools/materialize-runtime-build-inputs.ps1',
        '/tools/runtime-build-v2-common.ps1'
    )
    $previousFixtureOutputEncoding = $OutputEncoding
    try {
        $OutputEncoding = New-Object Text.UTF8Encoding($false)
        $seedPatterns | & git -C $sparseFixture sparse-checkout set --no-cone --stdin
    } finally {
        $OutputEncoding = $previousFixtureOutputEncoding
    }
    if ($LASTEXITCODE -ne 0) { throw 'Cannot seed sparse materializer fixture checkout.' }
    Assert-Equal 'sparse fixture starts without the non-ASCII policy file' $false `
        (Test-Path -LiteralPath (Join-Path $sparseFixture $unicodePolicyFile) -PathType Leaf)
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
        (Join-Path $sparseFixture 'tools\materialize-runtime-build-inputs.ps1') -ProjectRoot $sparseFixture | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Sparse materializer rejected the non-ASCII fixed file.' }
    Assert-Equal 'sparse materializer restores the non-ASCII policy file' $true `
        (Test-Path -LiteralPath (Join-Path $sparseFixture $unicodePolicyFile) -PathType Leaf)

    $certificateA = New-TestCertificate 'A'
    $certificateB = New-TestCertificate 'B'
    $certificateC = New-TestCertificate 'C'
    try {
        $entryA = New-RegistryEntry $certificateA 'builder-a' 'machine-a'
        $entryB = New-RegistryEntry $certificateB 'builder-b' 'machine-b'
        $entryC = New-RegistryEntry $certificateC 'builder-c' 'machine-a'
        $registryPath = Join-Path $testRoot 'runtime-builders.v2.json'
        $registry = [pscustomobject][ordered]@{ schema = 'cf7-runtime-builders.v2'; minimumConsensus = 2; builders = @($entryA,$entryB,$entryC) }
        Write-TestText $registryPath (($registry | ConvertTo-Json -Depth 8) + "`n")
        $thumbA = $certificateA.Thumbprint
        $thumbB = $certificateB.Thumbprint
        $thumbC = $certificateC.Thumbprint
    } finally {
        $certificateA.Dispose()
        $certificateB.Dispose()
        $certificateC.Dispose()
    }

    $attestationA = New-Cf7RuntimeBuildAttestationV2 -ProjectRoot $testRoot -DeploymentRoot $testRoot -CertificateThumbprint $thumbA -RegistryPath $registryPath -ConfigPath $configPath
    $attestationB = New-Cf7RuntimeBuildAttestationV2 -ProjectRoot $testRoot -DeploymentRoot $testRoot -CertificateThumbprint $thumbB -RegistryPath $registryPath -ConfigPath $configPath
    $attestationC = New-Cf7RuntimeBuildAttestationV2 -ProjectRoot $testRoot -DeploymentRoot $testRoot -CertificateThumbprint $thumbC -RegistryPath $registryPath -ConfigPath $configPath
    Test-Cf7RuntimeBuildAttestationV2 -Attestation $attestationA -RegistryPath $registryPath | Out-Null
    $script:checks++
    $consensus = Test-Cf7RuntimeBuildConsensusV2 -Attestations @($attestationA,$attestationB) -RegistryPath $registryPath
    Assert-Equal 'valid consensus closure' $attestationA.payload.payloadClosureHash $consensus.payloadClosureHash

    $cloudPayload = [pscustomobject][ordered]@{
        schema = 'cf7-runtime-github-build-attestation-payload.v2'
        builderKind = 'github-oidc'
        builderIdentityHash = ('D' * 64)
        faultDomain = 'github-hosted-windows'
        artifactSourceHash = $attestationA.payload.artifactSourceHash
        producerRecipeHash = $attestationA.payload.producerRecipeHash
        toolchainLockHash = $attestationA.payload.toolchainLockHash
        buildIdentityHash = $attestationA.payload.buildIdentityHash
        payloadClosureHash = $attestationA.payload.payloadClosureHash
        files = $attestationA.payload.files
    }
    $mixedConsensus = Test-Cf7RuntimeVerifiedPayloadConsensusV2 `
        -Payloads @($attestationA.payload,$cloudPayload) -MinimumConsensus 2
    Assert-Equal 'local + GitHub mixed consensus closure' $attestationA.payload.payloadClosureHash $mixedConsensus.payloadClosureHash
    Assert-Equal 'local + GitHub mixed consensus fault domains' 2 @($mixedConsensus.faultDomains).Count
    $sameDomainCloud = $cloudPayload | ConvertTo-Json -Depth 12 | ConvertFrom-Json
    $sameDomainCloud.faultDomain = $attestationA.payload.faultDomain
    Expect-Failure 'mixed consensus duplicate fault domain' {
        Test-Cf7RuntimeVerifiedPayloadConsensusV2 -Payloads @($attestationA.payload,$sameDomainCloud) | Out-Null
    }

    $tampered = $attestationA | ConvertTo-Json -Depth 12 | ConvertFrom-Json
    $tampered.payload.createdAtUtc = [DateTime]::UtcNow.AddMinutes(-10).ToString('o')
    Expect-Failure 'signed payload tamper' { Test-Cf7RuntimeBuildAttestationV2 -Attestation $tampered -RegistryPath $registryPath | Out-Null }
    $signatureTampered = $attestationA | ConvertTo-Json -Depth 12 | ConvertFrom-Json
    $signatureBytes = [Convert]::FromBase64String([string]$signatureTampered.signature.valueBase64)
    $signatureBytes[0] = $signatureBytes[0] -bxor 1
    $signatureTampered.signature.valueBase64 = [Convert]::ToBase64String($signatureBytes)
    Expect-Failure 'signature byte tamper' { Test-Cf7RuntimeBuildAttestationV2 -Attestation $signatureTampered -RegistryPath $registryPath | Out-Null }
    Expect-Failure 'duplicate key consensus' { Test-Cf7RuntimeBuildConsensusV2 -Attestations @($attestationA,$attestationA) -RegistryPath $registryPath | Out-Null }
    Expect-Failure 'duplicate fault domain consensus' { Test-Cf7RuntimeBuildConsensusV2 -Attestations @($attestationA,$attestationC) -RegistryPath $registryPath | Out-Null }

    Write-TestText (Join-Path $testRoot 'runtime\payload.dll') 'payload-mismatch'
    $mismatchAttestation = New-Cf7RuntimeBuildAttestationV2 -ProjectRoot $testRoot -DeploymentRoot $testRoot -CertificateThumbprint $thumbB -RegistryPath $registryPath -ConfigPath $configPath
    Expect-Failure 'different payload closure consensus' { Test-Cf7RuntimeBuildConsensusV2 -Attestations @($attestationA,$mismatchAttestation) -RegistryPath $registryPath | Out-Null }
    Write-TestText (Join-Path $testRoot 'runtime\payload.dll') 'payload-v1'

    $registry.builders[0].epoch = 2
    Write-TestText $registryPath (($registry | ConvertTo-Json -Depth 8) + "`n")
    Expect-Failure 'registry epoch mismatch' { Test-Cf7RuntimeBuildAttestationV2 -Attestation $attestationA -RegistryPath $registryPath | Out-Null }
    $registry.builders[0].epoch = 1
    $registry.builders[0].enabled = $false
    Write-TestText $registryPath (($registry | ConvertTo-Json -Depth 8) + "`n")
    Expect-Failure 'disabled registry key' { Test-Cf7RuntimeBuildAttestationV2 -Attestation $attestationA -RegistryPath $registryPath | Out-Null }

    Write-Host "[RuntimeBuildV2Test] OK checks=$script:checks" -ForegroundColor Green
} finally {
    foreach ($thumbprint in $createdThumbprints) {
        $certificatePath = "Cert:\CurrentUser\My\$thumbprint"
        if (Test-Path -LiteralPath $certificatePath) { Remove-Item -LiteralPath $certificatePath -Force }
    }
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
