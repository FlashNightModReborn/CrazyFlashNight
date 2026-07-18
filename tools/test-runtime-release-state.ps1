param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$classifierSource = Join-Path $repoRoot 'tools\classify-runtime-release-state.ps1'
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
    Set-TestFile (Join-Path $root 'source.txt') 'source-v1'
    Set-TestFile (Join-Path $root '.gitignore') ".cf7-test-control.json`n.cf7-calls.log`n"

    [void](Invoke-TestGit $root @('init'))
    [void](Invoke-TestGit $root @('config','core.autocrlf','false'))
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

function Invoke-Classifier($Fixture, [string]$Mode, [AllowNull()][string]$BaseRevision) {
    $headLines = @(Invoke-TestGit $Fixture.Root @('rev-parse','HEAD'))
    $head = ([string]$headLines[0]).Trim()
    $arguments = @(
        '-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $Fixture.Root 'tools\classify-runtime-release-state.ps1'),
        '-ProjectRoot',$Fixture.Root,'-Mode',$Mode,'-HeadRevision',$head
    )
    if (-not [string]::IsNullOrEmpty($BaseRevision)) { $arguments += @('-BaseRevision',$BaseRevision) }
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
    Run-Test 'Development permits source-ahead when deployment is unchanged' {
        $f = New-TestFixture v1
        [void](Add-TestCommit $f 'source.txt' 'source-v2')
        Set-TestControl $f -Strict 2
        $result = Invoke-Classifier $f Development $f.Base
        Assert-Test ($result.ExitCode -eq 0) "unexpected exit $($result.ExitCode): $($result.Output)"
        Assert-Test ($result.Output -match 'state=source-ahead') $result.Output
        Assert-Test ((Get-TestCalls $f) -join ',' -eq 'v1:integrity,v1:strict') 'expected integrity then strict only'
    }

    Run-Test 'Development reports coherent when strict identity still matches' {
        $f = New-TestFixture v2
        [void](Add-TestCommit $f 'source.txt' 'policy-only-change')
        $result = Invoke-Classifier $f Development $f.Base
        Assert-Test ($result.ExitCode -eq 0) $result.Output
        Assert-Test ($result.Output -match 'state=coherent') $result.Output
        Assert-Test ((Get-TestCalls $f) -join ',' -eq 'v2:integrity,v2:strict') 'unexpected verifier sequence'
    }

    Run-Test 'Development rejects changed deployment on a v1 manifest' {
        $f = New-TestFixture v1
        [void](Add-TestCommit $f 'runtime/core.bin' 'runtime-v2')
        $result = Invoke-Classifier $f Development $f.Base
        Assert-Test ($result.ExitCode -ne 0) 'v1 deployment change unexpectedly passed'
        Assert-Test ($result.Output -match 'require a complete v2 promotion') $result.Output
        Assert-Test ((Get-TestCalls $f) -join ',' -eq 'v1:integrity') 'strict verifier must not run for forbidden v1 deployment change'
    }

    Run-Test 'Development accepts a complete changed v2 promotion' {
        $f = New-TestFixture v2
        [void](Add-TestCommit $f 'CRAZYFLASHER7MercenaryEmpire.exe' 'bootstrap-v2')
        $result = Invoke-Classifier $f Development $f.Base
        Assert-Test ($result.ExitCode -eq 0) $result.Output
        Assert-Test ($result.Output -match 'state=promoted') $result.Output
        Assert-Test ((Get-TestCalls $f) -join ',' -eq 'v2:integrity,v2:strict,consensus:strict') 'expected full v2 verification sequence'
    }

    Run-Test 'Development rejects changed v2 deployment when strict identity fails' {
        $f = New-TestFixture v2
        [void](Add-TestCommit $f 'runtime/core.bin' 'runtime-v2')
        Set-TestControl $f -Strict 2
        $result = Invoke-Classifier $f Development $f.Base
        Assert-Test ($result.ExitCode -ne 0) 'incoherent v2 deployment unexpectedly passed'
        Assert-Test ($result.Output -match 'strict identity verification failed') $result.Output
    }

    Run-Test 'Protected accepts legacy v1 only after strict and consensus checks' {
        $f = New-TestFixture v1
        [void](Add-TestCommit $f 'source.txt' 'source-v2')
        $result = Invoke-Classifier $f Protected $f.Base
        Assert-Test ($result.ExitCode -eq 0) $result.Output
        Assert-Test ($result.Output -match 'state=protected-coherent') $result.Output
        Assert-Test ((Get-TestCalls $f) -join ',' -eq 'v1:integrity,v1:strict,consensus:strict') 'expected legacy strict+consensus sequence'
    }

    Run-Test 'Protected fails closed when consensus fails' {
        $f = New-TestFixture v2
        [void](Add-TestCommit $f 'source.txt' 'source-v2')
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

    Run-Test 'A v2-to-v1 manifest downgrade is forbidden after integrity verification' {
        $f = New-TestFixture v2
        [void](Add-TestCommit $f 'runtime/cf7-runtime-manifest.tsv' "cf7-runtime-manifest-v1`npayload`n")
        $result = Invoke-Classifier $f Development $f.Base
        Assert-Test ($result.ExitCode -ne 0) 'manifest downgrade unexpectedly passed'
        Assert-Test ($result.Output -match 'downgrade from v2 to v1') $result.Output
        Assert-Test ((Get-TestCalls $f) -join ',' -eq 'v1:integrity') 'integrity must run before downgrade rejection'
    }

    Run-Test 'All-zero event base falls back to the head parent' {
        $f = New-TestFixture v1
        [void](Add-TestCommit $f 'source.txt' 'source-v2')
        Set-TestControl $f -Strict 2
        $result = Invoke-Classifier $f Development ('0' * 40)
        Assert-Test ($result.ExitCode -eq 0) $result.Output
        Assert-Test ($result.Output -match 'state=source-ahead') $result.Output
    }

    Run-Test 'Initial protected commit is handled without a base' {
        $f = New-TestFixture v1
        $result = Invoke-Classifier $f Protected $null
        Assert-Test ($result.ExitCode -eq 0) $result.Output
        Assert-Test ($result.Output -match 'base=none') $result.Output
        Assert-Test ((Get-TestCalls $f) -join ',' -eq 'v1:integrity,v1:strict,consensus:strict') 'initial protected commit must fail closed through strict checks'
    }

    Run-Test 'Unexpected verifier errors cannot masquerade as source-ahead' {
        $f = New-TestFixture v1
        [void](Add-TestCommit $f 'source.txt' 'source-v2')
        Set-TestControl $f -Strict 1
        $result = Invoke-Classifier $f Development $f.Base
        Assert-Test ($result.ExitCode -ne 0) 'verifier infrastructure failure unexpectedly passed'
        Assert-Test ($result.Output -match 'failed unexpectedly with exit code 1') $result.Output
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

    Run-Test 'Development never receives the migration-bootstrap exemption' {
        $f = New-TestFixture v1
        [void](Add-TestMigrationCommit $f)
        $result = Invoke-Classifier $f Development $f.Base
        Assert-Test ($result.ExitCode -ne 0) 'development migration marker unexpectedly passed'
        Assert-Test ($result.Output -match 'allowed only against a protected ref') $result.Output
        Assert-Test ((Get-TestCalls $f) -join ',' -eq 'v1:integrity') 'development rejection must occur before consensus'
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
        [void](Add-TestCommit $f 'source.txt' 'post-bootstrap-v1-change')
        Set-TestControl $f
        $result = Invoke-Classifier $f Protected $migrationHead
        Assert-Test ($result.ExitCode -ne 0) 'post-bootstrap v1 commit unexpectedly passed'
        Assert-Test ($result.Output -match 'already been consumed') $result.Output
        Assert-Test ((Get-TestCalls $f) -join ',' -eq 'v1:integrity') 'consumed fuse must reject before strict identity checks'
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
} finally {
    $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot).TrimEnd('\')
    if ($resolvedTestRoot.StartsWith($tempBase + '\', [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedTestRoot).StartsWith('cf7-runtime-release-state-tests-', [StringComparison]::Ordinal)) {
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "[RuntimeReleaseStateTests] passed=$passed failed=$failed"
if ($failed -ne 0) { exit 1 }
