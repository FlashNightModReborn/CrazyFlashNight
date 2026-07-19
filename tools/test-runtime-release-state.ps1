param([string]$TestNamePattern)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$classifierSource = Join-Path $repoRoot 'tools\classify-runtime-release-state.ps1'
$workflowSource = Join-Path $repoRoot '.github\workflows\runtime-bundle-integrity.yml'
$nativeGateSource = Join-Path $repoRoot 'config\build\native-change-gate.v1.json'
$nativeGateBytes = [IO.File]::ReadAllBytes($nativeGateSource)
$admissionConfigSource = Join-Path $repoRoot 'config\build\main-branch-admission.v2.json'
$admissionConfigBytes = [IO.File]::ReadAllBytes($admissionConfigSource)
$runtimeV2CommonSource = Join-Path $repoRoot 'tools\runtime-build-v2-common.ps1'
$runtimeAttestationCommonSource = Join-Path $repoRoot 'tools\runtime-build-attestation-v2-common.ps1'
$targetRegistrySource = Join-Path $repoRoot 'config\build\runtime-builders.v2.json'
$targetRegistryBytes = [IO.File]::ReadAllBytes($targetRegistrySource)
$powerShellExecutable = (Get-Process -Id $PID).Path
$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$testRoot = Join-Path $tempBase ("cf7-runtime-release-state-tests-" + [Guid]::NewGuid().ToString('N'))
$utf8NoBom = New-Object Text.UTF8Encoding($false)
$passed = 0
$failed = 0

function Set-TestFile([string]$Path, [string]$Content) {
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { [void](New-Item -ItemType Directory -Path $parent -Force) }
    [IO.File]::WriteAllText($Path, $Content, $script:utf8NoBom)
}

function Set-TestBytes([string]$Path, [byte[]]$Bytes) {
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { [void](New-Item -ItemType Directory -Path $parent -Force) }
    [IO.File]::WriteAllBytes($Path, $Bytes)
}

function Get-TestSha256([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '') }
    finally { $sha.Dispose() }
}

function Get-TestOutputField([string]$Output, [string]$Name) {
    $match = [regex]::Match($Output, '(?:^|\s)' + [regex]::Escape($Name) + '=([^\s]+)')
    if (-not $match.Success) { throw "Classifier output lacks $Name`: $Output" }
    return [string]$match.Groups[1].Value
}

function Get-TestBaseSentinelsSha256($Fixture) {
    $lines = New-Object 'Collections.Generic.List[string]'
    foreach ($relativePath in @(
        'config/build/runtime-inputs.v2.json',
        'config/build/main-branch-admission.v2.json',
        'config/build/native-change-gate.v1.json',
        'runtime/cf7-runtime-manifest.tsv',
        'config/build/runtime-release-consensus.json',
        'config/build/runtime-builders.v2.json',
        'config/build/runtime-v2-migration-bootstrap.json',
        'CRAZYFLASHER7MercenaryEmpire.exe'
    )) {
        $oidLines = @(Invoke-TestGit $Fixture.Root @('rev-parse',"$($Fixture.Base):$relativePath"))
        $lines.Add("$relativePath`t$(([string]$oidLines[0]).Trim().ToLowerInvariant())")
    }
    $array = [string[]]$lines.ToArray()
    [Array]::Sort($array, [StringComparer]::Ordinal)
    return Get-TestSha256 ([Text.Encoding]::UTF8.GetBytes(([string]::Join("`n", $array) + "`n")))
}

function Remove-TestLooseBlob($Fixture, [string]$Revision, [string]$RelativePath) {
    $oidLines = @(Invoke-TestGit $Fixture.Root @('rev-parse',"${Revision}:$RelativePath"))
    $oid = ([string]$oidLines[0]).Trim().ToLowerInvariant()
    if ($oid -notmatch '^[0-9a-f]{40}$') { throw "Unexpected test object ID: $oid" }
    $objectsRoot = [IO.Path]::GetFullPath((Join-Path $Fixture.Root '.git\objects')).TrimEnd('\')
    $objectPath = [IO.Path]::GetFullPath((Join-Path $objectsRoot ($oid.Substring(0,2) + '\' + $oid.Substring(2))))
    if (-not $objectPath.StartsWith($objectsRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove an object outside the disposable fixture: $objectPath"
    }
    if (-not (Test-Path -LiteralPath $objectPath -PathType Leaf)) { throw "Expected loose test blob is missing: $oid" }
    Remove-Item -LiteralPath $objectPath -Force
}

function Invoke-TestGit([string]$Root, [string[]]$Arguments) {
    $output = @(& git -C $Root @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "git $($Arguments -join ' ') failed: $($output -join ' ')" }
    return @($output)
}

function Set-TestControl($Fixture, [int]$Integrity = 0, [int]$Strict = 0, [int]$Consensus = 0, [int]$ConsensusIntegrity = 0) {
    $control = [ordered]@{
        integrityExit=$Integrity
        strictExit=$Strict
        consensusExit=$Consensus
        consensusIntegrityExit=$ConsensusIntegrity
    }
    Set-TestFile (Join-Path $Fixture.Root '.cf7-test-control.json') ($control | ConvertTo-Json -Compress)
    $calls = Join-Path $Fixture.Root '.cf7-calls.log'
    if (Test-Path -LiteralPath $calls) { Remove-Item -LiteralPath $calls -Force }
}

function New-TestFixture([ValidateSet('v1','v2')][string]$ManifestVersion = 'v1', [switch]$BaseRegistry) {
    $root = Join-Path $script:testRoot ([Guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $root -Force)
    [void](New-Item -ItemType Directory -Path (Join-Path $root 'tools') -Force)
    Copy-Item -LiteralPath $script:classifierSource -Destination (Join-Path $root 'tools\classify-runtime-release-state.ps1')
    Copy-Item -LiteralPath $script:runtimeV2CommonSource -Destination (Join-Path $root 'tools\runtime-build-v2-common.ps1')
    Copy-Item -LiteralPath $script:runtimeAttestationCommonSource -Destination (Join-Path $root 'tools\runtime-build-attestation-v2-common.ps1')

    $bundleStub = @'
param([string]$ProjectRoot, [switch]$Staged, [switch]$IntegrityOnly)
$control = Get-Content -LiteralPath (Join-Path $ProjectRoot '.cf7-test-control.json') -Raw | ConvertFrom-Json
$phase = if ($IntegrityOnly) { 'integrity' } else { 'strict' }
[IO.File]::AppendAllText((Join-Path $ProjectRoot '.cf7-calls.log'), "__KIND__:$phase`n")
$code = if ($IntegrityOnly) { [int]$control.integrityExit } else { [int]$control.strictExit }
Write-Host "[StubBundle] kind=__KIND__ phase=$phase exit=$code"
exit $code
'@
    Set-TestFile (Join-Path $root 'tools\verify-runtime-bundle.ps1') ($bundleStub.Replace('__KIND__','v1'))
    Set-TestFile (Join-Path $root 'tools\verify-runtime-bundle-v2.ps1') ($bundleStub.Replace('__KIND__','v2'))
    Set-TestFile (Join-Path $root 'tools\verify-runtime-consensus.ps1') @'
param([string]$ProjectRoot, [switch]$Staged, [switch]$IntegrityOnly)
$control = Get-Content -LiteralPath (Join-Path $ProjectRoot '.cf7-test-control.json') -Raw | ConvertFrom-Json
$phase = if ($IntegrityOnly) { 'integrity' } else { 'strict' }
[IO.File]::AppendAllText((Join-Path $ProjectRoot '.cf7-calls.log'), "consensus:$phase`n")
$code = if ($IntegrityOnly) { [int]$control.consensusIntegrityExit } else { [int]$control.consensusExit }
Write-Host "[StubConsensus] phase=$phase exit=$code"
exit $code
'@

    $header = "cf7-runtime-manifest-$ManifestVersion"
    Set-TestFile (Join-Path $root 'runtime\cf7-runtime-manifest.tsv') "$header`npayload`n"
    Set-TestFile (Join-Path $root 'runtime\core.bin') 'runtime-v1'
    Set-TestFile (Join-Path $root 'CRAZYFLASHER7MercenaryEmpire.exe') 'bootstrap-v1'
    $legacyClosure = 'D' * 64
    Set-TestFile (Join-Path $root 'config\build\runtime-release-consensus.json') (([ordered]@{
        schema='cf7-runtime-release-consensus.v1'
        sourceTreeHash=('A' * 64)
        toolchainLockHash=('B' * 64)
        buildRecipeHash=('C' * 64)
        artifactClosureHash=$legacyClosure
        builders=@('fixture-a','fixture-b')
        promotedAtUtc='2026-01-01T00:00:00Z'
    } | ConvertTo-Json -Depth 5) + "`n")
    if ($BaseRegistry) { Set-TestFile (Join-Path $root 'config\build\runtime-builders.v2.json') '{"schema":"legacy-placeholder"}' }
    if ($ManifestVersion -eq 'v2') {
        Set-TestFile (Join-Path $root 'config\build\runtime-builders.v2.json') '{"schema":"fixture-v2-registry"}'
        Set-TestFile (Join-Path $root 'config\build\runtime-v2-migration-bootstrap.json') '{"schema":"fixture-permanent-fuse"}'
    }
    Set-TestFile (Join-Path $root 'source.txt') 'source-v1'
    $runtimeInputs = [ordered]@{
        schema = 'cf7-runtime-inputs.v2'
        domains = [ordered]@{
            artifactSource = [ordered]@{
                fixedFiles=@()
                trees=@([ordered]@{
                    path='launcher/src'
                    includeExtensions=@('.cs')
                    excludePaths=@()
                    excludePrefixes=@()
                })
            }
            producerRecipe = [ordered]@{ fixedFiles=@(); trees=@() }
            toolchainLock = [ordered]@{ fixedFiles=@(); trees=@() }
            policy = [ordered]@{
                fixedFiles=@(
                    'config/build/runtime-inputs.v2.json',
                    'config/build/main-branch-admission.v2.json',
                    'config/build/native-change-gate.v1.json',
                    'data/map/map_catalog.json',
                    'tools/derive-map-catalog.js',
                    'tools/classify-runtime-release-state.ps1',
                    'tools/verify-runtime-bundle.ps1',
                    'tools/verify-runtime-bundle-v2.ps1',
                    'tools/verify-runtime-consensus.ps1'
                )
                trees=@(
                    [ordered]@{
                        path='amf0-help/sol_parser'
                        includeExtensions=@('.rs','.toml','.lock','.sol')
                        excludePaths=@()
                        excludePrefixes=@('amf0-help/sol_parser/target/')
                    },
                    [ordered]@{
                        path='launcher/native/sol_parser/tests'
                        includeExtensions=@('.rs','.sol')
                        excludePaths=@()
                        excludePrefixes=@()
                    },
                    [ordered]@{
                        path='launcher/tests'
                        includeExtensions=@('.cs','.csproj','.json','.ps1')
                        excludePaths=@()
                        excludePrefixes=@('launcher/tests/bin/','launcher/tests/obj/')
                    },
                    [ordered]@{
                        path='launcher/scripts'
                        includeExtensions=@('.ts')
                        excludePaths=@()
                        excludePrefixes=@()
                    }
                )
            }
        }
        payload = [ordered]@{ fixedRoots=@('CRAZYFLASHER7MercenaryEmpire.exe'); trees=@('runtime') }
    }
    Set-TestFile (Join-Path $root 'config\build\runtime-inputs.v2.json') (($runtimeInputs | ConvertTo-Json -Depth 10) + "`n")
    Set-TestFile (Join-Path $root 'data\map\map_catalog.json') '{"schema":"fixture-content-policy"}'
    Set-TestFile (Join-Path $root 'tools\derive-map-catalog.js') 'export const derive = true;'
    Set-TestFile (Join-Path $root 'launcher\scripts\catalog.ts') 'export const catalog = true;'
    Set-TestBytes (Join-Path $root 'config\build\native-change-gate.v1.json') $script:nativeGateBytes
    Set-TestBytes (Join-Path $root 'config\build\main-branch-admission.v2.json') $script:admissionConfigBytes
    Set-TestFile (Join-Path $root '.gitignore') ".cf7-test-control.json`n.cf7-calls.log`n"

    [void](Invoke-TestGit $root @('init'))
    [void](Invoke-TestGit $root @('config','core.autocrlf','false'))
    [void](Invoke-TestGit $root @('config','core.ignorecase','false'))
    [void](Invoke-TestGit $root @('config','user.name','CF7 Runtime Test'))
    [void](Invoke-TestGit $root @('config','user.email','runtime-test@example.invalid'))
    [void](Invoke-TestGit $root @('add','-A'))
    [void](Invoke-TestGit $root @('commit','-m','fixture baseline'))
    $baseLines = @(Invoke-TestGit $root @('rev-parse','HEAD'))
    $base = ([string]$baseLines[0]).Trim()
    $fixture = [pscustomobject]@{ Root=$root; Base=$base; Version=$ManifestVersion; LegacyClosure=$legacyClosure }
    Set-TestControl $fixture
    return $fixture
}

function Add-TestCommit($Fixture, [string]$RelativePath, [string]$Content) {
    Set-TestFile (Join-Path $Fixture.Root ($RelativePath -replace '/','\')) $Content
    [void](Invoke-TestGit $Fixture.Root @('add','--',$RelativePath))
    [void](Invoke-TestGit $Fixture.Root @('commit','-m',"change $RelativePath"))
    $headLines = @(Invoke-TestGit $Fixture.Root @('rev-parse','HEAD'))
    return ([string]$headLines[0]).Trim()
}

function Add-TestFilesCommit($Fixture, [Collections.IDictionary]$Files, [string]$Message = 'change multiple files') {
    foreach ($relativePath in @($Files.Keys)) {
        Set-TestFile (Join-Path $Fixture.Root ([string]$relativePath -replace '/','\')) ([string]$Files[$relativePath])
    }
    [void](Invoke-TestGit $Fixture.Root (@('add','--') + [string[]]@($Files.Keys)))
    [void](Invoke-TestGit $Fixture.Root @('commit','-m',$Message))
    $headLines = @(Invoke-TestGit $Fixture.Root @('rev-parse','HEAD'))
    return ([string]$headLines[0]).Trim()
}

function Add-TestSpecialModeCommit($Fixture, [string]$RelativePath, [ValidateSet('120000','160000')][string]$Mode) {
    if ($Mode -eq '160000') {
        $objectOid = $Fixture.Base
    } else {
        $hashLines = @(Invoke-TestGit $Fixture.Root @('hash-object','source.txt'))
        $objectOid = ([string]$hashLines[0]).Trim()
    }
    [void](Invoke-TestGit $Fixture.Root @('update-index','--add','--cacheinfo',"$Mode,$objectOid,$RelativePath"))
    [void](Invoke-TestGit $Fixture.Root @('commit','-m',"add special mode $RelativePath"))
    $headLines = @(Invoke-TestGit $Fixture.Root @('rev-parse','HEAD'))
    return ([string]$headLines[0]).Trim()
}

function New-TestMigrationMarker(
    [string]$BaseCommitOid,
    [string]$LegacyClosure,
    [string]$RegistrySha256,
    [string]$ExtraJson = ''
) {
    return '{"schema":"cf7-runtime-v2-migration-bootstrap.v1","migrationId":"runtime-release-v2-bootstrap-2026-07","baseCommitOid":"' +
        $BaseCommitOid + '","fromManifest":"cf7-runtime-manifest-v1","toManifest":"cf7-runtime-manifest-v2","legacyArtifactClosureHash":"' +
        $LegacyClosure + '","targetBuilderRegistrySha256":"' + $RegistrySha256 + '"' + $ExtraJson + '}' + "`n"
}

function Add-TestMigrationCommit(
    $Fixture,
    [byte[]]$RegistryBytes,
    [string]$MarkerBaseCommitOid,
    [string]$MarkerLegacyClosure,
    [string]$MarkerRegistrySha256,
    [string]$MarkerExtraJson = '',
    [switch]$ChangeLegacyRuntime
) {
    if ($null -eq $RegistryBytes) { $RegistryBytes = $script:targetRegistryBytes }
    if (-not $MarkerBaseCommitOid) { $MarkerBaseCommitOid = $Fixture.Base }
    if (-not $MarkerLegacyClosure) { $MarkerLegacyClosure = $Fixture.LegacyClosure }
    if (-not $MarkerRegistrySha256) { $MarkerRegistrySha256 = Get-TestSha256 $RegistryBytes }
    Set-TestFile (Join-Path $Fixture.Root 'source.txt') 'migration-bootstrap-source'
    Set-TestBytes (Join-Path $Fixture.Root 'config\build\runtime-builders.v2.json') $RegistryBytes
    $marker = New-TestMigrationMarker -BaseCommitOid $MarkerBaseCommitOid -LegacyClosure $MarkerLegacyClosure `
        -RegistrySha256 $MarkerRegistrySha256 -ExtraJson $MarkerExtraJson
    Set-TestFile (Join-Path $Fixture.Root 'config\build\runtime-v2-migration-bootstrap.json') $marker
    if ($ChangeLegacyRuntime) { Set-TestFile (Join-Path $Fixture.Root 'runtime\core.bin') 'forbidden-runtime-change' }
    [void](Invoke-TestGit $Fixture.Root @('add','-A'))
    [void](Invoke-TestGit $Fixture.Root @('commit','-m','runtime v2 migration bootstrap'))
    $headLines = @(Invoke-TestGit $Fixture.Root @('rev-parse','HEAD'))
    return ([string]$headLines[0]).Trim()
}

function Invoke-Classifier($Fixture, [string]$Mode, [AllowNull()][string]$BaseRevision, [AllowNull()][string]$TrustedBaseRevision, [switch]$DisableFastPath, [switch]$OmitTrustedBase, [string[]]$ExtraArguments = @()) {
    $headLines = @(Invoke-TestGit $Fixture.Root @('rev-parse','HEAD'))
    $head = ([string]$headLines[0]).Trim()
    $arguments = @(
        '-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $Fixture.Root 'tools\classify-runtime-release-state.ps1'),
        '-ProjectRoot',$Fixture.Root,'-Mode',$Mode,'-HeadRevision',$head
    )
    if (-not [string]::IsNullOrEmpty($BaseRevision)) { $arguments += @('-BaseRevision',$BaseRevision) }
    if ($Mode -eq 'Protected' -and [string]::IsNullOrEmpty($TrustedBaseRevision) -and -not $DisableFastPath -and -not $OmitTrustedBase -and
            -not [string]::IsNullOrEmpty($BaseRevision) -and $BaseRevision -notmatch '^0+$') {
        $TrustedBaseRevision = $BaseRevision
    }
    if (-not [string]::IsNullOrEmpty($TrustedBaseRevision)) { $arguments += @('-TrustedBaseRevision',$TrustedBaseRevision) }
    if ($DisableFastPath) { $arguments += '-DisableFastPath' }
    $arguments += $ExtraArguments
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& $script:powerShellExecutable @arguments 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorAction
    }
    return [pscustomobject]@{ ExitCode=[int]$exitCode; Output=($output | ForEach-Object { [string]$_ }) -join "`n" }
}

function Get-TestCalls($Fixture) {
    $path = Join-Path $Fixture.Root '.cf7-calls.log'
    if (-not (Test-Path -LiteralPath $path)) { return @() }
    return @(Get-Content -LiteralPath $path | Where-Object { $_ -ne '' })
}

function Assert-Test([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Run-Test([string]$Name, [scriptblock]$Body) {
    if ($script:TestNamePattern -and $Name -notmatch $script:TestNamePattern) { return }
    try {
        & $Body
        $script:passed++
        Write-Host "[PASS] $Name" -ForegroundColor Green
    } catch {
        $script:failed++
        Write-Host "[FAIL] $Name :: $($_.Exception.Message)" -ForegroundColor Red
    }
}

[void](New-Item -ItemType Directory -Path $testRoot -Force)
try {
    Run-Test 'Audit source-only native change reports source-ahead without reading runtime payload' {
        $f = New-TestFixture v2
        [void](Add-TestCommit $f 'launcher/src/App.cs' 'source-v2')
        [void](Invoke-TestGit $f.Root @('sparse-checkout','set','--no-cone','/config/build/','/launcher/src/','/tools/','/.gitignore'))
        foreach ($payloadPath in @('CRAZYFLASHER7MercenaryEmpire.exe','runtime/cf7-runtime-manifest.tsv','runtime/core.bin')) {
            Remove-TestLooseBlob $f 'HEAD' $payloadPath
        }
        Set-TestControl $f -Integrity 1 -Strict 1 -Consensus 1
        $result = Invoke-Classifier $f Audit $f.Base
        Assert-Test ($result.ExitCode -eq 0) $result.Output
        Assert-Test ($result.Output -match 'state=source-ahead') $result.Output
        Assert-Test ($result.Output -match 'mode=Audit') $result.Output
        Assert-Test ($result.Output -match 'manifest=unread') $result.Output
        Assert-Test ($result.Output -match 'deploymentChanged=false') $result.Output
        Assert-Test ($result.Output -match 'verifierCount=0') $result.Output
        Assert-Test ((Get-TestCalls $f).Count -eq 0) 'source-only audit must invoke zero payload or consensus verifiers'
    }

    Run-Test 'Audit deployment mutation enters byte and strict verification' {
        $f = New-TestFixture v2
        [void](Add-TestCommit $f 'runtime/core.bin' 'runtime-v2')
        Set-TestControl $f -Strict 2
        $result = Invoke-Classifier $f Audit $f.Base
        Assert-Test ($result.ExitCode -ne 0) 'unpromoted runtime mutation unexpectedly passed audit'
        Assert-Test ((Get-TestCalls $f) -join ',' -eq 'v2:integrity,v2:strict') `
            'deployment audit must run byte integrity before strict identity and stop before consensus on failure'
    }

    Run-Test 'Audit promoted deployment requires strict consensus' {
        $passing = New-TestFixture v2
        [void](Add-TestCommit $passing 'runtime/core.bin' 'runtime-promoted')
        Set-TestControl $passing
        $passedResult = Invoke-Classifier $passing Audit $passing.Base
        Assert-Test ($passedResult.ExitCode -eq 0 -and $passedResult.Output -match 'state=promoted') $passedResult.Output
        Assert-Test ((Get-TestCalls $passing) -join ',' -eq 'v2:integrity,v2:strict,consensus:strict') `
            'promoted deployment audit must complete byte, identity, and consensus verification'

        $failing = New-TestFixture v2
        [void](Add-TestCommit $failing 'runtime/core.bin' 'runtime-unconfirmed')
        Set-TestControl $failing -Consensus 2
        $failedResult = Invoke-Classifier $failing Audit $failing.Base
        Assert-Test ($failedResult.ExitCode -ne 0) 'deployment without strict consensus unexpectedly passed audit'
        Assert-Test ((Get-TestCalls $failing) -join ',' -eq 'v2:integrity,v2:strict,consensus:strict') `
            'failed deployment audit must reach and enforce strict consensus'
    }

    Run-Test 'Manual Audit release-readiness forces the complete verifier chain' {
        $f = New-TestFixture v2
        [void](Add-TestCommit $f 'docs/manual-audit.md' 'request full verification')
        Set-TestControl $f
        $result = Invoke-Classifier $f Audit $f.Base -ExtraArguments @('-ForceDeploymentVerification')
        Assert-Test ($result.ExitCode -eq 0) $result.Output
        Assert-Test ($result.Output -match 'state=release-ready' -and
            $result.Output -match 'deploymentChanged=false' -and
            $result.Output -match 'forcedDeploymentVerification=true') $result.Output
        Assert-Test ((Get-TestCalls $f) -join ',' -eq 'v2:integrity,v2:strict,consensus:strict') `
            'manual release-readiness audit must run byte, source-identity, and consensus verification'
    }

    Run-Test 'Protected docs-only change inherits consensus without invoking a verifier' {
        $f = New-TestFixture v2
        [void](Add-TestCommit $f 'docs/artist-note.md' 'content-only')
        $result = Invoke-Classifier $f Protected $f.Base
        Assert-Test ($result.ExitCode -eq 0) $result.Output
        Assert-Test ($result.Output -match 'state=protected-nonnative-fastpath') $result.Output
        Assert-Test ($result.Output -match 'consensus=inherited-from-trusted-base') $result.Output
        Assert-Test ($result.Output -match 'changedCount=1') $result.Output
        Assert-Test ($result.Output -match 'changedPathsSha256=[0-9A-F]{64}') $result.Output
        Assert-Test ((Get-TestOutputField $result.Output 'baseSentinelCount') -eq '8') $result.Output
        Assert-Test ((Get-TestOutputField $result.Output 'baseSentinelsSha256') -ceq (Get-TestBaseSentinelsSha256 $f)) $result.Output
        Assert-Test ((Get-TestCalls $f).Count -eq 0) 'docs fast path must invoke zero verifiers'
    }

    Run-Test 'Trusted green anchor keeps earlier native drift sticky across a later docs commit' {
        $f = New-TestFixture v2
        $trustedGreen = $f.Base
        $eventBase = Add-TestCommit $f 'launcher/src/UnverifiedDrift.cs' 'native drift'
        [void](Add-TestCommit $f 'docs/after-native-drift.md' 'ordinary content')
        Set-TestControl $f -Strict 2
        $result = Invoke-Classifier $f Protected $eventBase $trustedGreen
        Assert-Test ($result.ExitCode -ne 0) 'later docs commit washed an unverified native drift green'
        Assert-Test ($result.Output -notmatch 'state=protected-nonnative-fastpath') $result.Output
        Assert-Test ((Get-TestCalls $f) -join ',' -eq 'v2:integrity,v2:strict') 'sticky native drift did not enter strict verification'
    }

    Run-Test 'Missing external anchor cannot emit a reusable required-check success' {
        foreach ($variant in @('explicit-disable','omitted-anchor')) {
            $f = New-TestFixture v2
            [void](Add-TestCommit $f 'docs/api-outage.md' 'ordinary content')
            $result = if ($variant -eq 'explicit-disable') {
                Invoke-Classifier $f Protected $f.Base $null -DisableFastPath
            } else {
                Invoke-Classifier $f Protected $f.Base $null -OmitTrustedBase
            }
            Assert-Test ($result.ExitCode -ne 0) "$variant unexpectedly emitted a green result"
            Assert-Test ($result.Output -match 'No externally verified green main anchor') "$variant`: $($result.Output)"
            Assert-Test ((Get-TestCalls $f).Count -eq 0) "$variant must fail before local verifiers can create a reusable green result"
        }
    }

    Run-Test 'Resolver outage cannot wash an earlier unbound native drift green' {
        $f = New-TestFixture v2
        $eventBase = Add-TestCommit $f 'foreign/Unbound.dll' 'unbound drift'
        [void](Add-TestCommit $f 'docs/after-api-outage.md' 'ordinary content')
        $result = Invoke-Classifier $f Protected $eventBase $null -DisableFastPath
        Assert-Test ($result.ExitCode -ne 0 -and $result.Output -match 'No externally verified green main anchor') $result.Output
        Assert-Test ($result.Output -notmatch 'state=protected-(?:nonnative-fastpath|coherent)') $result.Output
        Assert-Test ((Get-TestCalls $f).Count -eq 0) 'resolver outage must not create a reusable green result from local verifiers'
    }

    Run-Test 'Sparse fast path neither materializes nor reads runtime payload blobs' {
        $f = New-TestFixture v2
        [void](Add-TestCommit $f 'docs/sparse-note.md' 'content-only')
        [void](Invoke-TestGit $f.Root @('sparse-checkout','set','--no-cone','/docs/','/config/build/','/tools/','/.gitignore','/source.txt'))
        Assert-Test (-not (Test-Path -LiteralPath (Join-Path $f.Root 'CRAZYFLASHER7MercenaryEmpire.exe'))) 'sparse checkout materialized the root bootstrap'
        Assert-Test (-not (Test-Path -LiteralPath (Join-Path $f.Root 'runtime'))) 'sparse checkout materialized the runtime tree'

        foreach ($payloadPath in @('CRAZYFLASHER7MercenaryEmpire.exe','runtime/cf7-runtime-manifest.tsv','runtime/core.bin')) {
            Remove-TestLooseBlob $f 'HEAD' $payloadPath
        }
        $result = Invoke-Classifier $f Protected $f.Base
        Assert-Test ($result.ExitCode -eq 0) $result.Output
        Assert-Test ($result.Output -match 'state=protected-nonnative-fastpath') $result.Output
        Assert-Test ((Get-TestCalls $f).Count -eq 0) 'sparse fast path must invoke zero verifiers'
        Assert-Test (-not (Test-Path -LiteralPath (Join-Path $f.Root 'CRAZYFLASHER7MercenaryEmpire.exe'))) 'classifier materialized the root bootstrap'
        Assert-Test (-not (Test-Path -LiteralPath (Join-Path $f.Root 'runtime'))) 'classifier materialized the runtime tree'
    }

    Run-Test 'Sparse strict path reads indexed runtime blobs without worktree materialization' {
        $f = New-TestFixture v2
        [void](Add-TestCommit $f 'launcher/src/App.cs' 'protected source change')
        [void](Invoke-TestGit $f.Root @('sparse-checkout','set','--no-cone','/docs/','/config/build/','/tools/','/launcher/src/','/.gitignore'))
        Assert-Test (-not (Test-Path -LiteralPath (Join-Path $f.Root 'CRAZYFLASHER7MercenaryEmpire.exe'))) 'sparse checkout materialized the root bootstrap'
        Assert-Test (-not (Test-Path -LiteralPath (Join-Path $f.Root 'runtime'))) 'sparse checkout materialized the runtime tree'
        $result = Invoke-Classifier $f Protected $f.Base
        Assert-Test ($result.ExitCode -eq 0) $result.Output
        Assert-Test ($result.Output -match 'state=protected-coherent') $result.Output
        Assert-Test ((Get-TestCalls $f) -join ',' -eq 'v2:integrity,v2:strict,consensus:strict') 'sparse protected change did not use the full verifier chain'
        Assert-Test (-not (Test-Path -LiteralPath (Join-Path $f.Root 'CRAZYFLASHER7MercenaryEmpire.exe'))) 'strict classifier materialized the root bootstrap'
        Assert-Test (-not (Test-Path -LiteralPath (Join-Path $f.Root 'runtime'))) 'strict classifier materialized the runtime tree'
    }

    Run-Test 'AS2 Flash Web data config and docs share the non-native zero-verifier fast path' {
        $f = New-TestFixture v2
        $files = [ordered]@{
            'scripts/logic/Test.as' = 'trace("test");'
            'CRAZYFLASHER7MercenaryEmpire.xfl' = '<DOMDocument />'
            'CRAZYFLASHER7MercenaryEmpire.swf' = 'flash-binary-fixture'
            'launcher/web/modules/map/panel.js' = 'export const value = 1;'
            'flashswf/UI/test/asset.swf' = 'asset'
            'data/items/new.xml' = '<item />'
            'config/gameplay/new.xml' = '<config />'
            'docs/artist-note.md' = 'docs'
        }
        [void](Add-TestFilesCommit $f $files 'non-native roots')
        $result = Invoke-Classifier $f Protected $f.Base
        Assert-Test ($result.ExitCode -eq 0) $result.Output
        Assert-Test ($result.Output -match 'state=protected-nonnative-fastpath') $result.Output
        Assert-Test ($result.Output -match 'changedCount=8') $result.Output
        Assert-Test ((Get-TestCalls $f).Count -eq 0) 'non-native fast path must invoke zero verifiers'
    }

    Run-Test 'Formal content-policy inputs remain receipt-bound without becoming native admission paths' {
        $f = New-TestFixture v2
        [void](Add-TestFilesCommit $f ([ordered]@{
            'data/map/map_catalog.json' = '{"schema":"updated-content-policy"}'
            'tools/derive-map-catalog.js' = 'export const derive = false;'
            'launcher/scripts/catalog.ts' = 'export const catalog = false;'
        }) 'change broad content policy')
        $result = Invoke-Classifier $f Protected $f.Base
        Assert-Test ($result.ExitCode -eq 0) $result.Output
        Assert-Test ($result.Output -match 'state=protected-nonnative-fastpath') $result.Output
        Assert-Test ((Get-TestCalls $f).Count -eq 0) 'content-policy input unexpectedly invoked native strict verification'
    }

    Run-Test 'Protected-set audit hash canonicalizes every tree-rule field' {
        $captureHash = {
            param($TreeRule)
            $f = New-TestFixture v2
            $descriptorPath = Join-Path $f.Root 'config\build\runtime-inputs.v2.json'
            $descriptor = [IO.File]::ReadAllText($descriptorPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
            $descriptor.domains.artifactSource.trees = @($TreeRule)
            $newBase = Add-TestCommit $f 'config/build/runtime-inputs.v2.json' (($descriptor | ConvertTo-Json -Depth 12) + "`n")
            $f.Base = $newBase
            [void](Add-TestCommit $f 'docs/tree-rule-audit.md' 'content')
            $result = Invoke-Classifier $f Protected $f.Base
            Assert-Test ($result.ExitCode -eq 0) $result.Output
            Assert-Test ($result.Output -match 'state=protected-nonnative-fastpath') $result.Output
            return Get-TestOutputField $result.Output 'protectedSetSha256'
        }

        $canonicalA = [ordered]@{
            path='tools'
            includeExtensions=@('.txt','.ps1')
            excludePaths=@('tools/missing-b.ps1','tools/missing-a.ps1')
            excludePrefixes=@('tools/z/','tools/y/')
        }
        $canonicalB = [ordered]@{
            path='tools'
            includeExtensions=@('.ps1','.txt')
            excludePaths=@('tools/missing-a.ps1','tools/missing-b.ps1')
            excludePrefixes=@('tools/y/','tools/z/')
        }
        $changedExtensions = [ordered]@{
            path='tools'; includeExtensions=@('.ps1'); excludePaths=$canonicalA.excludePaths; excludePrefixes=$canonicalA.excludePrefixes
        }
        $changedExcludePaths = [ordered]@{
            path='tools'; includeExtensions=$canonicalA.includeExtensions; excludePaths=@('tools/missing-a.ps1'); excludePrefixes=$canonicalA.excludePrefixes
        }
        $changedExcludePrefixes = [ordered]@{
            path='tools'; includeExtensions=$canonicalA.includeExtensions; excludePaths=$canonicalA.excludePaths; excludePrefixes=@('tools/y/')
        }

        $hashA = & $captureHash $canonicalA
        $hashB = & $captureHash $canonicalB
        $hashExtensions = & $captureHash $changedExtensions
        $hashExcludePaths = & $captureHash $changedExcludePaths
        $hashExcludePrefixes = & $captureHash $changedExcludePrefixes
        Assert-Test ($hashA -ceq $hashB) 'equivalent tree-rule arrays did not canonicalize to one audit hash'
        $distinctHashes = @(@($hashA,$hashExtensions,$hashExcludePaths,$hashExcludePrefixes) | Sort-Object -Unique)
        Assert-Test ($distinctHashes.Count -eq 4) 'one or more tree-rule fields are missing from protectedSetSha256'
    }

    Run-Test 'Native gate extensions basenames files and prefixes are all audit-hash bound' {
        $captureHash = {
            param([string]$Mutation)
            $f = New-TestFixture v2
            $gatePath = Join-Path $f.Root 'config\build\native-change-gate.v1.json'
            $gate = [IO.File]::ReadAllText($gatePath, [Text.Encoding]::UTF8) | ConvertFrom-Json
            switch ($Mutation) {
                'reorder' {
                    $gate.protectedExtensions = @($gate.protectedExtensions | Sort-Object -Descending)
                    $gate.protectedBasenames = @($gate.protectedBasenames | Sort-Object -Descending)
                    $gate.protectedFiles = @($gate.protectedFiles | Sort-Object -Descending)
                    $gate.protectedPrefixes = @($gate.protectedPrefixes | Sort-Object -Descending)
                }
                'extension' { $gate.protectedExtensions = @($gate.protectedExtensions) + '.xyz' }
                'basename' { $gate.protectedBasenames = @($gate.protectedBasenames) + 'native.fixture' }
                'file' { $gate.protectedFiles = @($gate.protectedFiles) + 'security/native-fixture.json' }
                'prefix' { $gate.protectedPrefixes = @($gate.protectedPrefixes) + 'security/native-' }
            }
            $newBase = Add-TestCommit $f 'config/build/native-change-gate.v1.json' (($gate | ConvertTo-Json -Depth 10) + "`n")
            $f.Base = $newBase
            [void](Add-TestCommit $f 'docs/native-gate-audit.md' 'content')
            $result = Invoke-Classifier $f Protected $f.Base
            Assert-Test ($result.ExitCode -eq 0) $result.Output
            Assert-Test ($result.Output -match 'state=protected-nonnative-fastpath') $result.Output
            return Get-TestOutputField $result.Output 'protectedSetSha256'
        }

        $baseline = & $captureHash 'none'
        $reordered = & $captureHash 'reorder'
        Assert-Test ($baseline -ceq $reordered) 'native gate array order changed the canonical audit hash'
        $changed = @('extension','basename','file','prefix' | ForEach-Object { & $captureHash $_ })
        Assert-Test (@(@($baseline) + $changed | Sort-Object -Unique).Count -eq 5) 'one or more native gate fields are missing from protectedSetSha256'
    }

    Run-Test 'Trusted-base native gate rejects scalar uppercase and unsafe contracts' {
        $invalidConfigs = @(
            '{"schema":"cf7-native-change-gate.v1","protectedExtensions":".cs","protectedBasenames":["Cargo.toml"],"protectedFiles":["gate.json"],"protectedPrefixes":["runtime/"]}',
            '{"schema":"cf7-native-change-gate.v1","protectedExtensions":[".CS"],"protectedBasenames":["Cargo.toml"],"protectedFiles":["gate.json"],"protectedPrefixes":["runtime/"]}',
            '{"schema":"cf7-native-change-gate.v1","protectedExtensions":[".cs"],"protectedBasenames":["Cargo.toml"],"protectedFiles":["gate.json"],"protectedPrefixes":["config/build/../"]}',
            '{"schema":"cf7-native-change-gate.v1","protectedExtensions":[".cs"],"protectedBasenames":["Cargo.toml"],"protectedFiles":["docs/unsafe?.md"],"protectedPrefixes":["runtime/"]}',
            ('{"schema":"cf7-native-change-gate.v1","protectedExtensions":[".cs"],"protectedBasenames":["Cargo.toml"],"protectedFiles":["docs/' + ('a' * 256) + '.md"],"protectedPrefixes":["runtime/"]}'),
            '{"schema":"cf7-native-change-gate.v1","protectedExtensions":[],"protectedBasenames":["Cargo.toml"],"protectedFiles":["gate.json"],"protectedPrefixes":["runtime/"]}',
            '{"schema":"cf7-native-change-gate.v1","protectedExtensions":[".cs",".cs"],"protectedBasenames":["Cargo.toml"],"protectedFiles":["gate.json"],"protectedPrefixes":["runtime/"]}'
        )
        foreach ($invalidConfig in $invalidConfigs) {
            $f = New-TestFixture v2
            $invalidBase = Add-TestCommit $f 'config/build/native-change-gate.v1.json' ($invalidConfig + "`n")
            $f.Base = $invalidBase
            [void](Add-TestCommit $f 'docs/head.md' 'content')
            $result = Invoke-Classifier $f Protected $f.Base
            Assert-Test ($result.ExitCode -ne 0) 'invalid trusted-base native gate unexpectedly passed'
            Assert-Test ($result.Output -match 'must be a JSON array|invalid lowercase extension|unsafe path segment|safe repository-relative path|longer than 255 UTF-16 code units|at least one extension|duplicate extension') $result.Output
            Assert-Test ((Get-TestCalls $f).Count -eq 0) 'invalid native gate must fail before verifiers'
        }
    }

    Run-Test 'Trusted-base runtime descriptor must retain the broad policy domain schema' {
        $f = New-TestFixture v2
        $descriptorPath = Join-Path $f.Root 'config\build\runtime-inputs.v2.json'
        $descriptor = [IO.File]::ReadAllText($descriptorPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
        $descriptor.domains.PSObject.Properties.Remove('policy')
        $invalidBase = Add-TestCommit $f 'config/build/runtime-inputs.v2.json' (($descriptor | ConvertTo-Json -Depth 12) + "`n")
        $f.Base = $invalidBase
        [void](Add-TestCommit $f 'docs/head.md' 'content')
        $result = Invoke-Classifier $f Protected $f.Base
        Assert-Test ($result.ExitCode -ne 0) 'descriptor without policy domain unexpectedly passed'
        Assert-Test ($result.Output -match 'well-formed domain: policy') $result.Output
        Assert-Test ((Get-TestCalls $f).Count -eq 0) 'malformed descriptor must fail before verifiers'
    }

    Run-Test 'Admission v1 to v2 transition is accepted only on the event base side' {
        $retiredControlPath = '.github/legacy-native-control.json'
        $setLegacyAdmission = {
            param($Fixture, [switch]$KeepCurrentFile, [switch]$IncludeExtraRetiredControl)
            $gatePath = Join-Path $Fixture.Root 'config\build\native-change-gate.v1.json'
            $gate = [IO.File]::ReadAllText($gatePath, [Text.Encoding]::UTF8) | ConvertFrom-Json
            $legacyProtectedFiles = @($gate.protectedFiles | ForEach-Object {
                if ([string]$_ -ceq 'config/build/main-branch-admission.v2.json') {
                    'config/build/main-branch-admission.v1.json'
                } else { [string]$_ }
            })
            $legacyProtectedFiles += '.github/CODEOWNERS'
            if ($IncludeExtraRetiredControl) { $legacyProtectedFiles += $retiredControlPath }
            $gate.protectedFiles = $legacyProtectedFiles
            Set-TestFile $gatePath (($gate | ConvertTo-Json -Depth 10) + "`n")

            $descriptorPath = Join-Path $Fixture.Root 'config\build\runtime-inputs.v2.json'
            $descriptor = [IO.File]::ReadAllText($descriptorPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
            $legacyPolicyFiles = @($descriptor.domains.policy.fixedFiles | ForEach-Object {
                if ([string]$_ -ceq 'config/build/main-branch-admission.v2.json') {
                    'config/build/main-branch-admission.v1.json'
                } else { [string]$_ }
            })
            $legacyPolicyFiles += '.github/CODEOWNERS'
            if ($IncludeExtraRetiredControl) { $legacyPolicyFiles += $retiredControlPath }
            $descriptor.domains.policy.fixedFiles = $legacyPolicyFiles
            Set-TestFile $descriptorPath (($descriptor | ConvertTo-Json -Depth 12) + "`n")

            Copy-Item -LiteralPath (Join-Path $Fixture.Root 'config\build\main-branch-admission.v2.json') `
                -Destination (Join-Path $Fixture.Root 'config\build\main-branch-admission.v1.json')
            if (-not $KeepCurrentFile) {
                Remove-Item -LiteralPath (Join-Path $Fixture.Root 'config\build\main-branch-admission.v2.json') -Force
            }
            Set-TestFile (Join-Path $Fixture.Root '.github\CODEOWNERS') '* @legacy-owner'
            if ($IncludeExtraRetiredControl) {
                Set-TestFile (Join-Path $Fixture.Root ($retiredControlPath -replace '/','\')) '{"legacy":true}'
            }
        }
        $setCurrentAdmission = {
            param($Fixture, [switch]$ChangeConsensus)
            $legacyAdmissionPath = Join-Path $Fixture.Root 'config\build\main-branch-admission.v1.json'
            if (Test-Path -LiteralPath $legacyAdmissionPath) { Remove-Item -LiteralPath $legacyAdmissionPath -Force }
            Set-TestBytes (Join-Path $Fixture.Root 'config\build\main-branch-admission.v2.json') $script:admissionConfigBytes
            Set-TestBytes (Join-Path $Fixture.Root 'config\build\native-change-gate.v1.json') $script:nativeGateBytes
            $descriptorPath = Join-Path $Fixture.Root 'config\build\runtime-inputs.v2.json'
            $descriptor = [IO.File]::ReadAllText($descriptorPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
            $descriptor.domains.policy.fixedFiles = @($descriptor.domains.policy.fixedFiles | Where-Object {
                [string]$_ -cnotin @(
                    'config/build/main-branch-admission.v1.json',
                    'config/build/main-branch-admission.v2.json',
                    '.github/CODEOWNERS',
                    $retiredControlPath
                )
            }) + 'config/build/main-branch-admission.v2.json'
            Set-TestFile $descriptorPath (($descriptor | ConvertTo-Json -Depth 12) + "`n")
            Set-TestFile (Join-Path $Fixture.Root '.github\CODEOWNERS') '# advisory only'
            $retiredControl = Join-Path $Fixture.Root ($retiredControlPath -replace '/','\')
            if (Test-Path -LiteralPath $retiredControl) { Set-TestFile $retiredControl '{"legacy":false}' }
            if ($ChangeConsensus) {
                $consensusPath = Join-Path $Fixture.Root 'config\build\runtime-release-consensus.json'
                $consensus = [IO.File]::ReadAllText($consensusPath, [Text.Encoding]::UTF8).TrimEnd()
                Set-TestFile $consensusPath ($consensus + "`n `n")
            }
        }

        $passing = New-TestFixture v2
        & $setLegacyAdmission $passing
        [void](Invoke-TestGit $passing.Root @('add','-A'))
        [void](Invoke-TestGit $passing.Root @('commit','-m','legacy admission baseline'))
        $legacyBaseLines = @(Invoke-TestGit $passing.Root @('rev-parse','HEAD'))
        $passing.Base = ([string]$legacyBaseLines[0]).Trim()

        & $setCurrentAdmission $passing -ChangeConsensus
        [void](Invoke-TestGit $passing.Root @('add','-A'))
        [void](Invoke-TestGit $passing.Root @('commit','-m','migrate admission contract to v2'))
        $passingResult = Invoke-Classifier $passing Audit $passing.Base
        Assert-Test ($passingResult.ExitCode -eq 0 -and $passingResult.Output -match 'state=promoted') $passingResult.Output
        Assert-Test ((Get-TestCalls $passing) -join ',' -eq 'v2:integrity,v2:strict,consensus:strict') `
            'promoted admission transition must run the complete verifier chain'

        $missingConsensus = New-TestFixture v2
        & $setLegacyAdmission $missingConsensus
        [void](Invoke-TestGit $missingConsensus.Root @('add','-A'))
        [void](Invoke-TestGit $missingConsensus.Root @('commit','-m','legacy admission baseline'))
        $missingConsensusBase = @(Invoke-TestGit $missingConsensus.Root @('rev-parse','HEAD'))
        $missingConsensus.Base = ([string]$missingConsensusBase[0]).Trim()
        & $setCurrentAdmission $missingConsensus
        [void](Invoke-TestGit $missingConsensus.Root @('add','-A'))
        [void](Invoke-TestGit $missingConsensus.Root @('commit','-m','unpromoted admission transition'))
        $missingConsensusResult = Invoke-Classifier $missingConsensus Audit $missingConsensus.Base
        Assert-Test ($missingConsensusResult.ExitCode -ne 0 -and
            $missingConsensusResult.Output -match 'not bound.*\.github/CODEOWNERS') `
            'CODEOWNERS retirement passed without a changed signed consensus'

        $extraRetirement = New-TestFixture v2
        & $setLegacyAdmission $extraRetirement -IncludeExtraRetiredControl
        [void](Invoke-TestGit $extraRetirement.Root @('add','-A'))
        [void](Invoke-TestGit $extraRetirement.Root @('commit','-m','legacy admission with extra control'))
        $extraRetirementBase = @(Invoke-TestGit $extraRetirement.Root @('rev-parse','HEAD'))
        $extraRetirement.Base = ([string]$extraRetirementBase[0]).Trim()
        & $setCurrentAdmission $extraRetirement -ChangeConsensus
        [void](Invoke-TestGit $extraRetirement.Root @('add','-A'))
        [void](Invoke-TestGit $extraRetirement.Root @('commit','-m','attempt broad control retirement'))
        $extraRetirementResult = Invoke-Classifier $extraRetirement Audit $extraRetirement.Base
        Assert-Test ($extraRetirementResult.ExitCode -ne 0 -and
            $extraRetirementResult.Output -match 'not bound.*\.github/legacy-native-control.json') `
            'admission migration retired an arbitrary base-only native control'

        $inconsistentHead = New-TestFixture v2
        & $setLegacyAdmission $inconsistentHead
        [void](Invoke-TestGit $inconsistentHead.Root @('add','-A'))
        [void](Invoke-TestGit $inconsistentHead.Root @('commit','-m','legacy CODEOWNERS gate baseline'))
        $inconsistentHeadBase = @(Invoke-TestGit $inconsistentHead.Root @('rev-parse','HEAD'))
        $inconsistentHead.Base = ([string]$inconsistentHeadBase[0]).Trim()
        & $setCurrentAdmission $inconsistentHead -ChangeConsensus
        $headGatePath = Join-Path $inconsistentHead.Root 'config\build\native-change-gate.v1.json'
        $headGate = [IO.File]::ReadAllText($headGatePath, [Text.Encoding]::UTF8) | ConvertFrom-Json
        $headGate.protectedFiles = @($headGate.protectedFiles) + '.github/CODEOWNERS'
        Set-TestFile $headGatePath (($headGate | ConvertTo-Json -Depth 10) + "`n")
        [void](Invoke-TestGit $inconsistentHead.Root @('add','-A'))
        [void](Invoke-TestGit $inconsistentHead.Root @('commit','-m','retain CODEOWNERS only in head gate'))
        $inconsistentHeadResult = Invoke-Classifier $inconsistentHead Audit $inconsistentHead.Base
        Assert-Test ($inconsistentHeadResult.ExitCode -ne 0 -and
            $inconsistentHeadResult.Output -match 'not bound.*\.github/CODEOWNERS') `
            'CODEOWNERS retirement passed while the head gate still protected it'

        $downgradedHead = New-TestFixture v2
        & $setLegacyAdmission $downgradedHead
        [void](Invoke-TestGit $downgradedHead.Root @('add','-A'))
        [void](Invoke-TestGit $downgradedHead.Root @('commit','-m','attempt admission downgrade'))
        $downgradeResult = Invoke-Classifier $downgradedHead Audit $downgradedHead.Base
        Assert-Test ($downgradeResult.ExitCode -ne 0 -and
            $downgradeResult.Output -match 'missing mandatory fixed file: config/build/main-branch-admission.v2.json') `
            'head-side admission downgrade unexpectedly passed'

        $ambiguousBase = New-TestFixture v2
        & $setLegacyAdmission $ambiguousBase -KeepCurrentFile
        [void](Invoke-TestGit $ambiguousBase.Root @('add','-A'))
        [void](Invoke-TestGit $ambiguousBase.Root @('commit','-m','ambiguous legacy admission baseline'))
        $ambiguousBaseLines = @(Invoke-TestGit $ambiguousBase.Root @('rev-parse','HEAD'))
        $ambiguousBase.Base = ([string]$ambiguousBaseLines[0]).Trim()
        [void](Add-TestCommit $ambiguousBase 'docs/head.md' 'content')
        $ambiguousResult = Invoke-Classifier $ambiguousBase Audit $ambiguousBase.Base
        Assert-Test ($ambiguousResult.ExitCode -ne 0 -and
            $ambiguousResult.Output -match 'Legacy admission compatibility requires') `
            'legacy base compatibility accepted a commit that already contained v2'
    }

    Run-Test 'Bound native changes use strict verification while unbound native writes fail before verifiers' {
        $cases = @(
            [pscustomobject]@{ Name='runtime'; Path='runtime/core.bin'; Content='runtime-v2'; Bound=$true },
            [pscustomobject]@{ Name='manifest'; Path='runtime/cf7-runtime-manifest.tsv'; Content="cf7-runtime-manifest-v2`npayload-v2`n"; Bound=$true },
            [pscustomobject]@{ Name='policy'; Path='tools/verify-runtime-consensus.ps1'; Content=$null; Bound=$true },
            [pscustomobject]@{ Name='descriptor'; Path='config/build/runtime-inputs.v2.json'; Content=$null; Bound=$true },
            [pscustomobject]@{ Name='artifact-tree'; Path='launcher/src/Bound.cs'; Content='native source'; Bound=$true },
            [pscustomobject]@{ Name='launcher-test-tree'; Path='launcher/tests/BoundTest.cs'; Content='native test'; Bound=$true },
            [pscustomobject]@{ Name='sol-test-tree'; Path='launcher/native/sol_parser/tests/bound.rs'; Content='native test'; Bound=$true },
            [pscustomobject]@{ Name='amf0-lock-tree'; Path='amf0-help/sol_parser/Cargo.lock'; Content='native lock'; Bound=$true },
            [pscustomobject]@{ Name='global-extension'; Path='foreign/native/new.dll'; Content='dll'; Bound=$false },
            [pscustomobject]@{ Name='global-basename'; Path='foreign/native/Cargo.toml'; Content='[package]'; Bound=$false },
            [pscustomobject]@{ Name='host-prefix'; Path='launcher/src/native-metadata.json'; Content='{}'; Bound=$false },
            [pscustomobject]@{ Name='workflow-prefix'; Path='.github/workflows/content.yml'; Content='name: content'; Bound=$false },
            [pscustomobject]@{ Name='build-config-prefix'; Path='config/build/future-control.json'; Content='{}'; Bound=$false }
        )
        foreach ($case in $cases) {
            $f = New-TestFixture v2
            $caseContent = [string]$case.Content
            if ($case.Name -eq 'policy') {
                $caseContent = [IO.File]::ReadAllText((Join-Path $f.Root ($case.Path -replace '/','\'))) + "`n# policy change`n"
            } elseif ($case.Name -eq 'descriptor') {
                $caseContent = [IO.File]::ReadAllText((Join-Path $f.Root ($case.Path -replace '/','\'))) + " `n"
            }
            $files = [ordered]@{ 'docs/mixed.md'='content'; ([string]$case.Path)=$caseContent }
            [void](Add-TestFilesCommit $f $files ("mixed " + $case.Name))
            $result = Invoke-Classifier $f Protected $f.Base
            if ([bool]$case.Bound) {
                Assert-Test ($result.ExitCode -eq 0) "$($case.Name): $($result.Output)"
                Assert-Test ($result.Output -match 'state=protected-coherent') "$($case.Name): $($result.Output)"
                Assert-Test ((Get-TestCalls $f) -join ',' -eq 'v2:integrity,v2:strict,consensus:strict') "$($case.Name) did not use full verification"
            } else {
                Assert-Test ($result.ExitCode -ne 0) "$($case.Name) unbound write unexpectedly passed"
                Assert-Test ($result.Output -match 'not bound by the indexed release descriptor') "$($case.Name): $($result.Output)"
                Assert-Test ((Get-TestCalls $f).Count -eq 0) "$($case.Name) must fail before verifiers"
            }
        }
    }

    Run-Test 'Native add modify delete rename gate edit and missing-gate base obey release binding' {
        $f = New-TestFixture v2
        [void](Add-TestCommit $f 'foreign/NATIVE.DLL' 'dll')
        $result = Invoke-Classifier $f Protected $f.Base
        Assert-Test ($result.ExitCode -ne 0 -and $result.Output -match 'not bound by the indexed release descriptor') $result.Output
        Assert-Test ((Get-TestCalls $f).Count -eq 0) 'unbound uppercase native extension must fail before verifiers'

        $f = New-TestFixture v2
        $legacyBase = Add-TestCommit $f 'foreign/Legacy.dll' 'grandfathered bytes'
        $f.Base = $legacyBase
        [void](Add-TestCommit $f 'foreign/Legacy.dll' 'modified bytes')
        $result = Invoke-Classifier $f Protected $f.Base
        Assert-Test ($result.ExitCode -ne 0 -and $result.Output -match 'not bound by the indexed release descriptor') $result.Output
        Assert-Test ((Get-TestCalls $f).Count -eq 0) 'modifying an unbound native path must fail before verifiers'

        $f = New-TestFixture v2
        [void](Add-TestCommit $f 'launcher/src/Bound.cs' 'native source')
        $result = Invoke-Classifier $f Protected $f.Base
        Assert-Test ($result.ExitCode -eq 0 -and $result.Output -match 'state=protected-coherent') $result.Output
        Assert-Test ((Get-TestCalls $f) -join ',' -eq 'v2:integrity,v2:strict,consensus:strict') 'descriptor-bound native source did not use strict verification'

        $f = New-TestFixture v2
        $nativeBase = Add-TestCommit $f 'launcher/src/DeleteMe.cs' 'native source'
        $f.Base = $nativeBase
        [void](Invoke-TestGit $f.Root @('rm','launcher/src/DeleteMe.cs'))
        [void](Invoke-TestGit $f.Root @('commit','-m','delete native source'))
        $result = Invoke-Classifier $f Protected $f.Base
        Assert-Test ($result.ExitCode -eq 0 -and $result.Output -match 'state=protected-coherent') $result.Output
        Assert-Test ((Get-TestCalls $f) -join ',' -eq 'v2:integrity,v2:strict,consensus:strict') 'native deletion did not use strict verification'

        $f = New-TestFixture v2
        $nativeBase = Add-TestCommit $f 'launcher/src/RenameMe.cs' 'native source'
        $f.Base = $nativeBase
        [void](Invoke-TestGit $f.Root @('mv','launcher/src/RenameMe.cs','launcher/src/RenameMe.md'))
        [void](Invoke-TestGit $f.Root @('commit','-m','rename native source'))
        $result = Invoke-Classifier $f Protected $f.Base
        Assert-Test ($result.ExitCode -ne 0 -and $result.Output -match 'not bound by the indexed release descriptor') $result.Output
        Assert-Test ((Get-TestCalls $f).Count -eq 0) 'rename target inside a native prefix must be release-bound'

        $f = New-TestFixture v2
        $gatePath = Join-Path $f.Root 'config\build\native-change-gate.v1.json'
        $gateText = [IO.File]::ReadAllText($gatePath, [Text.Encoding]::UTF8)
        [void](Add-TestCommit $f 'config/build/native-change-gate.v1.json' ($gateText.TrimEnd() + "`n "))
        $result = Invoke-Classifier $f Protected $f.Base
        Assert-Test ($result.ExitCode -eq 0 -and $result.Output -match 'state=protected-coherent') $result.Output
        Assert-Test ((Get-TestCalls $f) -join ',' -eq 'v2:integrity,v2:strict,consensus:strict') 'native gate edit did not use strict verification'

        $f = New-TestFixture v2
        [void](Invoke-TestGit $f.Root @('rm','config/build/native-change-gate.v1.json'))
        [void](Invoke-TestGit $f.Root @('commit','-m','remove native gate from trusted base'))
        $missingGateBaseLines = @(Invoke-TestGit $f.Root @('rev-parse','HEAD'))
        $f.Base = ([string]$missingGateBaseLines[0]).Trim()
        [void](Add-TestCommit $f 'docs/after-missing-gate.md' 'content')
        $result = Invoke-Classifier $f Protected $f.Base
        Assert-Test ($result.ExitCode -ne 0 -and $result.Output -match 'retain a valid native change gate') $result.Output
        Assert-Test ((Get-TestCalls $f).Count -eq 0) 'missing head gate must fail before verifiers'
    }

    Run-Test 'Unknown regular non-native roots inherit consensus by blacklist default' {
        foreach ($path in @('source.txt','misc/unknown.md','tools/ordinary-helper.js','launcher/web/modules/new-panel.js')) {
            $f = New-TestFixture v2
            [void](Add-TestCommit $f $path 'unknown')
            $result = Invoke-Classifier $f Protected $f.Base
            Assert-Test ($result.ExitCode -eq 0) "$path`: $($result.Output)"
            Assert-Test ($result.Output -match 'state=protected-nonnative-fastpath') "$path`: $($result.Output)"
            Assert-Test ((Get-TestCalls $f).Count -eq 0) "$path unexpectedly invoked strict verification"
        }
    }

    Run-Test 'Case-colliding protected directory spelling is rejected' {
        $f = New-TestFixture v2
        [void](Add-TestCommit $f 'config/Build/spoof.json' '{}')
        $result = Invoke-Classifier $f Protected $f.Base
        Assert-Test ($result.ExitCode -ne 0) 'case-colliding config/Build path unexpectedly passed'
        Assert-Test ($result.Output -match 'case-colliding path component') $result.Output
        Assert-Test ((Get-TestCalls $f).Count -eq 0) 'unsafe case collision must fail before verifiers'
    }

    Run-Test 'Explicit non-ancestor base is rejected before fast-path classification' {
        $f = New-TestFixture v2
        [void](Invoke-TestGit $f.Root @('checkout','-q','-b','sibling',$f.Base))
        $sibling = Add-TestCommit $f 'source.txt' 'sibling'
        [void](Invoke-TestGit $f.Root @('checkout','-q','--detach',$f.Base))
        [void](Add-TestCommit $f 'docs/head.md' 'head')
        $result = Invoke-Classifier $f Protected $sibling
        Assert-Test ($result.ExitCode -ne 0) 'non-ancestor base unexpectedly passed'
        Assert-Test ($result.Output -match 'must be an ancestor') $result.Output
        Assert-Test ((Get-TestCalls $f).Count -eq 0) 'topology failure must precede verifiers'
    }

    Run-Test 'Symlink and gitlink changes are rejected before fast-path classification' {
        foreach ($mode in @('120000','160000')) {
            $f = New-TestFixture v2
            [void](Add-TestSpecialModeCommit $f ("docs/special-$mode") $mode)
            $result = Invoke-Classifier $f Protected $f.Base
            Assert-Test ($result.ExitCode -ne 0) "$mode unexpectedly passed"
            Assert-Test ($result.Output -match 'symlink, gitlink, executable, or non-regular') "$mode`: $($result.Output)"
            Assert-Test ((Get-TestCalls $f).Count -eq 0) "$mode must fail before verifiers"
        }
    }

    Run-Test 'Unchanged legacy unsafe path is grandfathered but touching it is rejected' {
        $f = New-TestFixture v2
        $legacyPath = 'docs/legacy-' + [char]0xFFFF + '.txt'
        $legacyBase = Add-TestFilesCommit $f ([ordered]@{ $legacyPath='legacy' }) 'add legacy unsafe path'
        $f.Base = $legacyBase
        [void](Add-TestCommit $f 'docs/safe-after-legacy.md' 'safe')
        $result = Invoke-Classifier $f Protected $f.Base
        Assert-Test ($result.ExitCode -eq 0) $result.Output
        Assert-Test ($result.Output -match 'state=protected-nonnative-fastpath') $result.Output
        Assert-Test ((Get-TestCalls $f).Count -eq 0) 'unchanged legacy path should not invoke verifiers'

        $f = New-TestFixture v2
        $legacyBase = Add-TestFilesCommit $f ([ordered]@{ $legacyPath='legacy' }) 'add legacy unsafe path'
        $f.Base = $legacyBase
        [void](Add-TestFilesCommit $f ([ordered]@{ $legacyPath='touched' }) 'touch legacy unsafe path')
        $result = Invoke-Classifier $f Protected $f.Base
        Assert-Test ($result.ExitCode -ne 0) 'touching legacy unsafe path unexpectedly passed'
        Assert-Test ($result.Output -match 'Changed or newly introduced head path|changed path') $result.Output
        Assert-Test ((Get-TestCalls $f).Count -eq 0) 'unsafe path touch must fail before verifiers'
    }

    Run-Test 'Protected accepts legacy v1 only after strict and consensus checks' {
        $f = New-TestFixture v1
        [void](Add-TestCommit $f 'launcher/src/App.cs' 'source-v2')
        $result = Invoke-Classifier $f Protected $f.Base
        Assert-Test ($result.ExitCode -eq 0) $result.Output
        Assert-Test ($result.Output -match 'state=protected-coherent') $result.Output
        Assert-Test ((Get-TestCalls $f) -join ',' -eq 'v1:integrity,v1:strict,consensus:strict') 'expected legacy strict+consensus sequence'
    }

    Run-Test 'Protected fails closed when consensus fails' {
        $f = New-TestFixture v2
        [void](Add-TestCommit $f 'launcher/src/App.cs' 'source-v2')
        Set-TestControl $f -Consensus 2
        $result = Invoke-Classifier $f Protected $f.Base
        Assert-Test ($result.ExitCode -ne 0) 'consensus failure unexpectedly passed'
        Assert-Test ($result.Output -match 'release consensus verification failed') $result.Output
    }

    Run-Test 'Protected v1 cannot change the builder registry without the exact migration marker' {
        $f = New-TestFixture v1
        [void](Add-TestCommit $f 'config/build/runtime-builders.v2.json' '{"schema":"unbound-registry"}')
        $result = Invoke-Classifier $f Protected $f.Base
        Assert-Test ($result.ExitCode -ne 0) 'unbound protected registry change unexpectedly passed'
        Assert-Test ($result.Output -match 'exact one-time migration bootstrap or a complete v2 promotion') $result.Output
        Assert-Test ((Get-TestCalls $f) -join ',' -eq 'v1:integrity') 'unbound registry change must fail before strict/consensus checks'
    }

    Run-Test 'A v2-to-v1 manifest downgrade is rejected before payload verification' {
        $f = New-TestFixture v2
        [void](Add-TestCommit $f 'runtime/cf7-runtime-manifest.tsv' "cf7-runtime-manifest-v1`npayload`n")
        $result = Invoke-Classifier $f Protected $f.Base
        Assert-Test ($result.ExitCode -ne 0) 'manifest downgrade unexpectedly passed'
        Assert-Test ($result.Output -match 'downgrade from v2 to v1') $result.Output
        Assert-Test ((Get-TestCalls $f).Count -eq 0) 'manifest downgrade should fail before allocating payload verification'
    }

    Run-Test 'All-zero event base without an external anchor cannot emit green' {
        $f = New-TestFixture v1
        [void](Add-TestCommit $f 'docs/zero-base.md' 'content')
        $result = Invoke-Classifier $f Protected ('0' * 40)
        Assert-Test ($result.ExitCode -ne 0 -and $result.Output -match 'No externally verified green main anchor') $result.Output
        Assert-Test ((Get-TestCalls $f).Count -eq 0) 'zero base without an anchor must fail before verifiers'
    }

    Run-Test 'Initial protected commit without an external anchor cannot emit green' {
        $f = New-TestFixture v1
        $result = Invoke-Classifier $f Protected $null
        Assert-Test ($result.ExitCode -ne 0 -and $result.Output -match 'No externally verified green main anchor') $result.Output
        Assert-Test ((Get-TestCalls $f).Count -eq 0) 'initial protected commit must fail closed before verifiers'
    }

    Run-Test 'Unexpected verifier errors cannot masquerade as source-ahead' {
        $f = New-TestFixture v1
        [void](Add-TestCommit $f 'launcher/src/App.cs' 'source-v2')
        Set-TestControl $f -Strict 1
        $result = Invoke-Classifier $f Protected $f.Base
        Assert-Test ($result.ExitCode -ne 0) 'verifier infrastructure failure unexpectedly passed'
        Assert-Test ($result.Output -match 'strict identity verification failed with exit code 1') $result.Output
    }

    Run-Test 'Protected permits the exact one-time v1 migration bootstrap with a hash-bound enabled registry' {
        $f = New-TestFixture v1
        [void](Add-TestMigrationCommit $f)
        $result = Invoke-Classifier $f Protected $f.Base
        Assert-Test ($result.ExitCode -eq 0) $result.Output
        Assert-Test ($result.Output -match 'state=migration-bootstrap') $result.Output
        Assert-Test ($result.Output -match ('registrySha256=' + (Get-TestSha256 $script:targetRegistryBytes))) $result.Output
        Assert-Test ((Get-TestCalls $f) -join ',' -eq 'v1:integrity,consensus:integrity') 'bootstrap must run only v1 byte and consensus integrity checks'
    }

    Run-Test 'Migration bootstrap may replace a pre-existing registry only with the exact hash-bound v2 registry' {
        $f = New-TestFixture v1 -BaseRegistry
        [void](Add-TestMigrationCommit $f)
        $result = Invoke-Classifier $f Protected $f.Base
        Assert-Test ($result.ExitCode -eq 0) $result.Output
        Assert-Test ($result.Output -match 'state=migration-bootstrap') $result.Output
    }

    Run-Test 'Audit never receives the migration-bootstrap exemption' {
        $f = New-TestFixture v1
        [void](Add-TestMigrationCommit $f)
        $result = Invoke-Classifier $f Audit $f.Base
        Assert-Test ($result.ExitCode -ne 0) 'audit migration marker unexpectedly passed'
        Assert-Test ($result.Output -match 'allowed only against a protected ref') $result.Output
        Assert-Test ((Get-TestCalls $f).Count -eq 0) 'audit migration rejection must occur before all verifiers'
    }

    Run-Test 'Migration marker must bind the exact classified base commit' {
        $f = New-TestFixture v1
        [void](Add-TestMigrationCommit $f -MarkerBaseCommitOid ('0' * 40))
        $result = Invoke-Classifier $f Protected $f.Base
        Assert-Test ($result.ExitCode -ne 0) 'wrong marker base unexpectedly passed'
        Assert-Test ($result.Output -match 'exact classified base commit') $result.Output
    }

    Run-Test 'Migration marker base must be an ancestor of the classified head' {
        $f = New-TestFixture v1
        [void](Invoke-TestGit $f.Root @('checkout','-q','-b','sibling-base',$f.Base))
        $sibling = Add-TestCommit $f 'source.txt' 'sibling-base-change'
        [void](Invoke-TestGit $f.Root @('checkout','-q','--detach',$f.Base))
        [void](Add-TestMigrationCommit $f -MarkerBaseCommitOid $sibling)
        $result = Invoke-Classifier $f Protected $sibling
        Assert-Test ($result.ExitCode -ne 0) 'non-ancestor marker base unexpectedly passed'
        Assert-Test ($result.Output -match 'must be an ancestor') $result.Output
    }

    Run-Test 'Migration marker rejects extra fields even when JSON is otherwise valid' {
        $f = New-TestFixture v1
        [void](Add-TestMigrationCommit $f -MarkerExtraJson ',"unexpected":true')
        $result = Invoke-Classifier $f Protected $f.Base
        Assert-Test ($result.ExitCode -ne 0) 'marker with an extra field unexpectedly passed'
        Assert-Test ($result.Output -match 'exact allowed set') $result.Output
    }

    Run-Test 'Migration marker must bind the exact legacy artifact closure' {
        $f = New-TestFixture v1
        [void](Add-TestMigrationCommit $f -MarkerLegacyClosure ('E' * 64))
        $result = Invoke-Classifier $f Protected $f.Base
        Assert-Test ($result.ExitCode -ne 0) 'wrong legacy closure unexpectedly passed'
        Assert-Test ($result.Output -match 'legacy consensus artifact closure') $result.Output
    }

    Run-Test 'Migration builder registry bytes must match the marker SHA-256' {
        $f = New-TestFixture v1
        [void](Add-TestMigrationCommit $f -MarkerRegistrySha256 ('E' * 64))
        $result = Invoke-Classifier $f Protected $f.Base
        Assert-Test ($result.ExitCode -ne 0) 'registry hash mismatch unexpectedly passed'
        Assert-Test ($result.Output -match 'registry SHA-256 mismatch') $result.Output
    }

    Run-Test 'Migration builder registry structure is parsed after its hash matches' {
        $f = New-TestFixture v1
        $registry = [Text.Encoding]::UTF8.GetString($script:targetRegistryBytes) | ConvertFrom-Json
        $registry.builders[0].keyId = '0' * 64
        $badBytes = [Text.Encoding]::UTF8.GetBytes(($registry | ConvertTo-Json -Depth 12) + "`n")
        [void](Add-TestMigrationCommit $f -RegistryBytes $badBytes)
        $result = Invoke-Classifier $f Protected $f.Base
        Assert-Test ($result.ExitCode -ne 0) 'hash-bound but malformed registry unexpectedly passed'
        Assert-Test ($result.Output -match 'certificate does not match keyId') $result.Output
    }

    Run-Test 'Migration builder registry requires at least one enabled public-key identity' {
        $f = New-TestFixture v1
        $registry = [Text.Encoding]::UTF8.GetString($script:targetRegistryBytes) | ConvertFrom-Json
        $registry.builders[0].enabled = $false
        $disabledBytes = [Text.Encoding]::UTF8.GetBytes(($registry | ConvertTo-Json -Depth 12) + "`n")
        [void](Add-TestMigrationCommit $f -RegistryBytes $disabledBytes)
        $result = Invoke-Classifier $f Protected $f.Base
        Assert-Test ($result.ExitCode -ne 0) 'registry without an enabled identity unexpectedly passed'
        Assert-Test ($result.Output -match 'at least one enabled public-key identity') $result.Output
    }

    Run-Test 'Migration bootstrap cannot change any legacy deployment byte' {
        $f = New-TestFixture v1
        [void](Add-TestMigrationCommit $f -ChangeLegacyRuntime)
        $result = Invoke-Classifier $f Protected $f.Base
        Assert-Test ($result.ExitCode -ne 0) 'migration with changed runtime bytes unexpectedly passed'
        Assert-Test ($result.Output -match 'cannot alter legacy deployment bytes') $result.Output
        Assert-Test ((Get-TestCalls $f) -join ',' -eq 'v1:integrity') 'legacy byte-diff rejection must precede consensus'
    }

    Run-Test 'Migration bootstrap fails closed when legacy consensus integrity fails' {
        $f = New-TestFixture v1
        [void](Add-TestMigrationCommit $f)
        Set-TestControl $f -ConsensusIntegrity 2
        $result = Invoke-Classifier $f Protected $f.Base
        Assert-Test ($result.ExitCode -ne 0) 'failed legacy consensus integrity unexpectedly passed'
        Assert-Test ($result.Output -match 'legacy runtime consensus integrity verification failed') $result.Output
        Assert-Test ((Get-TestCalls $f) -join ',' -eq 'v1:integrity,consensus:integrity') 'unexpected migration verifier sequence'
    }

    Run-Test 'Once the marker exists in base, a later v1 commit must perform a v2 promotion' {
        $f = New-TestFixture v1
        $migrationHead = Add-TestMigrationCommit $f
        [void](Add-TestCommit $f 'launcher/src/App.cs' 'post-bootstrap-v1-change')
        Set-TestControl $f
        $result = Invoke-Classifier $f Protected $migrationHead
        Assert-Test ($result.ExitCode -ne 0) 'post-bootstrap v1 commit unexpectedly passed'
        Assert-Test ($result.Output -match 'already been consumed') $result.Output
        Assert-Test ((Get-TestCalls $f).Count -eq 0) 'consumed fuse should fail before allocating payload verification'
    }

    Run-Test 'The permanent migration fuse cannot be removed after bootstrap' {
        $f = New-TestFixture v1
        $migrationHead = Add-TestMigrationCommit $f
        [void](Invoke-TestGit $f.Root @('rm','config/build/runtime-v2-migration-bootstrap.json'))
        [void](Invoke-TestGit $f.Root @('commit','-m','remove marker'))
        Set-TestControl $f
        $result = Invoke-Classifier $f Protected $migrationHead
        Assert-Test ($result.ExitCode -ne 0) 'removed migration fuse unexpectedly passed'
        Assert-Test ($result.Output -match 'cannot be removed') $result.Output
    }

    Run-Test 'The permanent migration fuse cannot be modified after bootstrap' {
        $f = New-TestFixture v1
        $migrationHead = Add-TestMigrationCommit $f
        Set-TestFile (Join-Path $f.Root 'config\build\runtime-v2-migration-bootstrap.json') 'tampered'
        [void](Invoke-TestGit $f.Root @('add','config/build/runtime-v2-migration-bootstrap.json'))
        [void](Invoke-TestGit $f.Root @('commit','-m','modify marker'))
        Set-TestControl $f
        $result = Invoke-Classifier $f Protected $migrationHead
        Assert-Test ($result.ExitCode -ne 0) 'modified migration fuse unexpectedly passed'
        Assert-Test ($result.Output -match 'cannot be modified') $result.Output
    }

    Run-Test 'The commit after migration bootstrap may pass only as a complete v2 protected state' {
        $f = New-TestFixture v1
        $migrationHead = Add-TestMigrationCommit $f
        [void](Add-TestCommit $f 'runtime/cf7-runtime-manifest.tsv' "cf7-runtime-manifest-v2`npayload`n")
        Set-TestControl $f
        $result = Invoke-Classifier $f Protected $migrationHead
        Assert-Test ($result.ExitCode -eq 0) $result.Output
        Assert-Test ($result.Output -match 'state=protected-coherent') $result.Output
        Assert-Test ((Get-TestCalls $f) -join ',' -eq 'v2:integrity,v2:strict,consensus:strict') 'v2 transition must use the normal strict path'
    }

    Run-Test 'Workflow is a path-scoped native audit rather than a reusable required context' {
        $workflow = [IO.File]::ReadAllText($script:workflowSource, [Text.Encoding]::UTF8)
        Assert-Test ($workflow -match '(?m)^name:\s*Runtime native audit\s*$') 'workflow must identify itself as a post-push audit'
        Assert-Test ($workflow -match '(?m)^\s{2}audit-native-runtime:\s*$') 'native audit job key changed'
        Assert-Test ($workflow -match '(?m)^\s{4}name:\s*audit-native-runtime\s*$') 'native audit job name changed'
        Assert-Test ($workflow -notmatch 'verify-staged-bundle|required context|CF7_TRUST_|TrustedBaseRevision|DisableFastPath') `
            'audit workflow must not emit or resolve the retired reusable required context'
        Assert-Test ($workflow -match '(?m)^\s{2}workflow_dispatch:\s*$') 'native maintainers need an explicit manual audit entrypoint'
        Assert-Test ($workflow -match '(?m)^\s{2}pull_request:\s*$' -and $workflow -match '(?m)^\s{2}push:\s*$') `
            'native audit must observe filtered main pull requests and pushes'
        Assert-Test ($workflow -notmatch '(?m)^\s{2}merge_group:\s*$') 'non-required audit must not allocate merge-queue runners'
        Assert-Test (($workflow | Select-String -Pattern '(?m)^\s+- main\s*$' -AllMatches).Matches.Count -eq 2) `
            'only filtered push and pull_request events should target main'

        $pathsMatch = [regex]::Match($workflow, '(?ms)^\s{4}paths:\s*&native_runtime_paths\s*\r?\n(?<paths>(?:\s{6}- [^\r\n]+\r?\n)+)')
        Assert-Test $pathsMatch.Success 'cannot parse canonical native/runtime trigger paths'
        $actualPathSet = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        foreach ($line in @([string]$pathsMatch.Groups['paths'].Value -split "`r?`n")) {
            $match = [regex]::Match($line, '^\s*-\s+(.+?)\s*$')
            if (-not $match.Success) { continue }
            $value = [string]$match.Groups[1].Value
            if (($value.StartsWith("'") -and $value.EndsWith("'")) -or
                    ($value.StartsWith('"') -and $value.EndsWith('"'))) {
                $value = $value.Substring(1, $value.Length - 2)
            }
            Assert-Test ($actualPathSet.Add($value)) "workflow trigger contains a duplicate path pattern: $value"
        }

        $expectedPathSet = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        $gate = [Text.Encoding]::UTF8.GetString($script:nativeGateBytes).TrimStart([char]0xFEFF) | ConvertFrom-Json
        $inputs = [IO.File]::ReadAllText((Join-Path $repoRoot 'config\build\runtime-inputs.v2.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
        foreach ($extension in @($gate.protectedExtensions)) { [void]$expectedPathSet.Add("**/*$extension") }
        foreach ($basename in @($gate.protectedBasenames)) { [void]$expectedPathSet.Add("**/$basename") }
        foreach ($path in @($gate.protectedFiles)) { [void]$expectedPathSet.Add([string]$path) }
        foreach ($prefix in @($gate.protectedPrefixes)) { [void]$expectedPathSet.Add(([string]$prefix) + '**') }
        foreach ($domainName in @('artifactSource','producerRecipe','toolchainLock')) {
            $domain = $inputs.domains.$domainName
            foreach ($path in @($domain.fixedFiles)) { [void]$expectedPathSet.Add([string]$path) }
            foreach ($tree in @($domain.trees)) { [void]$expectedPathSet.Add(([string]$tree.path).TrimEnd('/') + '/**') }
        }
        foreach ($path in @($inputs.payload.fixedRoots)) { [void]$expectedPathSet.Add([string]$path) }
        foreach ($tree in @($inputs.payload.trees)) { [void]$expectedPathSet.Add(([string]$tree).TrimEnd('/') + '/**') }
        $missingPaths = @($expectedPathSet | Where-Object { -not $actualPathSet.Contains([string]$_) } | Sort-Object)
        $unexpectedPaths = @($actualPathSet | Where-Object { -not $expectedPathSet.Contains([string]$_) } | Sort-Object)
        Assert-Test ($missingPaths.Count -eq 0) "workflow trigger omits native/runtime admission paths: $($missingPaths -join ',')"
        Assert-Test ($unexpectedPaths.Count -eq 0) "workflow trigger contains paths outside the native/runtime admission contract: $($unexpectedPaths -join ',')"
        Assert-Test ($actualPathSet.Contains('**') -eq $false -and
            -not $actualPathSet.Contains('docs/**') -and
            -not $actualPathSet.Contains('data/**') -and
            -not $actualPathSet.Contains('flashswf/**') -and
            -not $actualPathSet.Contains('sounds/**')) 'ordinary content roots must not allocate the Windows audit runner'
        Assert-Test ($workflow -match '(?m)^\s{4}paths:\s*\*native_runtime_paths\s*$') `
            'push and pull_request must share one immutable native/runtime path set'

        Assert-Test ($workflow -match '(?m)^\s+filter:\s*blob:none\s*$') 'checkout must use blob:none filtering'
        Assert-Test ($workflow -match '(?m)^\s+fetch-depth:\s*0\s*$') 'checkout must retain complete topology'
        Assert-Test ($workflow -match '(?m)^\s+sparse-checkout:\s*\|\s*$') 'checkout must declare sparse materialization'
        $sparseMatch = [regex]::Match($workflow, '(?ms)^\s{10}sparse-checkout:\s*\|\s*\r?\n(?<paths>(?:\s{12}\S[^\r\n]*\r?\n)+)')
        Assert-Test $sparseMatch.Success 'cannot parse checkout sparse materialization paths'
        $sparsePaths = [string]$sparseMatch.Groups['paths'].Value
        Assert-Test ($sparsePaths -notmatch '(?m)^\s{12}CRAZYFLASHER7MercenaryEmpire\.exe\s*$') 'source-ahead audit must not materialize the root bootstrap'
        Assert-Test ($sparsePaths -notmatch '(?m)^\s{12}runtime(?:/|\s*$)') 'source-ahead audit must not materialize the runtime payload tree'
        Assert-Test ($sparsePaths -match '(?m)^\s{12}config/build/\s*$') 'sparse checkout must retain build-control metadata'
        Assert-Test ($sparsePaths -match '(?m)^\s{12}tools/classify-runtime-release-state\.ps1\s*$') 'sparse checkout must retain the classifier'
        Assert-Test ($sparsePaths -notmatch '(?m)^\s{12}tools/resolve-runtime-trusted-base\.ps1\s*$') `
            'audit checkout must not materialize the retired external trusted-base resolver'
        Assert-Test ($workflow -notmatch '(?m)^\s{2}(?:actions|checks):\s*read\s*$') 'audit must not request retired trusted-anchor API permissions'
        Assert-Test ($workflow -match '(?m)^\s{2}group:\s*runtime-native-audit-v2-\$\{\{ github\.sha \}\}\s*$' -and
            $workflow -match '(?m)^\s{2}cancel-in-progress:\s*false\s*$') 'each native head needs an uncancelled audit identity'
        Assert-Test ($workflow -match [regex]::Escape("@('-BaseRevision', `$baseRevision)")) 'workflow must preserve the event base for strict state semantics'
        Assert-Test ($workflow -match "'-Mode', 'Audit'") 'workflow must pass Audit mode literally'
        Assert-Test ($workflow -match "github\.actor_id == '91271520'" -and $workflow -match "github\.actor_id == '138298913'") `
            'manual audit allocation must use the immutable native maintainer IDs'
        $auditJob = [regex]::Match($workflow, '(?ms)^  audit-native-runtime:\s.*$').Value
        Assert-Test ($auditJob.Contains('github.run_attempt == 1') -and
            $auditJob.IndexOf('if: >-', [StringComparison]::Ordinal) -lt
            $auditJob.IndexOf('runs-on: windows-latest', [StringComparison]::Ordinal)) `
            'native audit reruns must be rejected by a job-level guard before runner allocation'
        Assert-Test ($workflow -match "CF7_EVENT_NAME -eq 'workflow_dispatch'" -and
            $workflow -match "classifierArguments \+= '-ForceDeploymentVerification'") `
            'manual audit must force full release-readiness verification instead of comparing only the last diff'
    }
} finally {
    $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot).TrimEnd('\')
    if ($resolvedTestRoot.StartsWith($tempBase + '\', [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedTestRoot).StartsWith('cf7-runtime-release-state-tests-', [StringComparison]::Ordinal)) {
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "[RuntimeReleaseStateTests] passed=$passed failed=$failed"
if ($failed -ne 0) { exit 1 }
