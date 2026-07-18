param([string]$TestNamePattern)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$classifierSource = Join-Path $repoRoot 'tools\classify-runtime-release-state.ps1'
$workflowSource = Join-Path $repoRoot '.github\workflows\runtime-bundle-integrity.yml'
$lanesConfigSource = Join-Path $repoRoot 'config\build\contribution-lanes.v1.json'
$lanesConfigBytes = [IO.File]::ReadAllBytes($lanesConfigSource)
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
        'config/build/contribution-lanes.v1.json',
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
            artifactSource = [ordered]@{ fixedFiles=@(); trees=@() }
            producerRecipe = [ordered]@{ fixedFiles=@(); trees=@() }
            toolchainLock = [ordered]@{ fixedFiles=@(); trees=@() }
            policy = [ordered]@{
                fixedFiles=@(
                    'config/build/runtime-inputs.v2.json',
                    'tools/classify-runtime-release-state.ps1',
                    'tools/verify-runtime-bundle.ps1',
                    'tools/verify-runtime-bundle-v2.ps1',
                    'tools/verify-runtime-consensus.ps1'
                )
                trees=@()
            }
        }
        payload = [ordered]@{ fixedRoots=@('CRAZYFLASHER7MercenaryEmpire.exe'); trees=@('runtime') }
    }
    Set-TestFile (Join-Path $root 'config\build\runtime-inputs.v2.json') (($runtimeInputs | ConvertTo-Json -Depth 10) + "`n")
    Set-TestBytes (Join-Path $root 'config\build\contribution-lanes.v1.json') $script:lanesConfigBytes
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
    Run-Test 'Development mode cannot emit the protected required context' {
        $f = New-TestFixture v1
        [void](Add-TestCommit $f 'source.txt' 'source-v2')
        Set-TestControl $f -Strict 2
        $result = Invoke-Classifier $f Development $f.Base
        Assert-Test ($result.ExitCode -ne 0) 'Development mode unexpectedly passed'
        Assert-Test ($result.Output -match 'Development mode is forbidden') $result.Output
        Assert-Test ((Get-TestCalls $f).Count -eq 0) 'Development mode must fail before every verifier'
    }

    Run-Test 'Protected docs-only change inherits consensus without invoking a verifier' {
        $f = New-TestFixture v2
        [void](Add-TestCommit $f 'docs/artist-note.md' 'content-only')
        $result = Invoke-Classifier $f Protected $f.Base
        Assert-Test ($result.ExitCode -eq 0) $result.Output
        Assert-Test ($result.Output -match 'state=protected-content-fastpath') $result.Output
        Assert-Test ($result.Output -match 'consensus=inherited-from-base') $result.Output
        Assert-Test ($result.Output -match 'changedCount=1') $result.Output
        Assert-Test ($result.Output -match 'changedPathsSha256=[0-9A-F]{64}') $result.Output
        Assert-Test ((Get-TestOutputField $result.Output 'baseSentinelCount') -eq '7') $result.Output
        Assert-Test ((Get-TestOutputField $result.Output 'baseSentinelsSha256') -ceq (Get-TestBaseSentinelsSha256 $f)) $result.Output
        Assert-Test ((Get-TestCalls $f).Count -eq 0) 'docs fast path must invoke zero verifiers'
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
        Assert-Test ($result.Output -match 'state=protected-content-fastpath') $result.Output
        Assert-Test ((Get-TestCalls $f).Count -eq 0) 'sparse fast path must invoke zero verifiers'
        Assert-Test (-not (Test-Path -LiteralPath (Join-Path $f.Root 'CRAZYFLASHER7MercenaryEmpire.exe'))) 'classifier materialized the root bootstrap'
        Assert-Test (-not (Test-Path -LiteralPath (Join-Path $f.Root 'runtime'))) 'classifier materialized the runtime tree'
    }

    Run-Test 'Sparse strict path reads indexed runtime blobs without worktree materialization' {
        $f = New-TestFixture v2
        [void](Add-TestCommit $f 'source.txt' 'protected source change')
        [void](Invoke-TestGit $f.Root @('sparse-checkout','set','--no-cone','/docs/','/config/build/','/tools/','/.gitignore','/source.txt'))
        Assert-Test (-not (Test-Path -LiteralPath (Join-Path $f.Root 'CRAZYFLASHER7MercenaryEmpire.exe'))) 'sparse checkout materialized the root bootstrap'
        Assert-Test (-not (Test-Path -LiteralPath (Join-Path $f.Root 'runtime'))) 'sparse checkout materialized the runtime tree'
        $result = Invoke-Classifier $f Protected $f.Base
        Assert-Test ($result.ExitCode -eq 0) $result.Output
        Assert-Test ($result.Output -match 'state=protected-coherent') $result.Output
        Assert-Test ((Get-TestCalls $f) -join ',' -eq 'v2:integrity,v2:strict,consensus:strict') 'sparse protected change did not use the full verifier chain'
        Assert-Test (-not (Test-Path -LiteralPath (Join-Path $f.Root 'CRAZYFLASHER7MercenaryEmpire.exe'))) 'strict classifier materialized the root bootstrap'
        Assert-Test (-not (Test-Path -LiteralPath (Join-Path $f.Root 'runtime'))) 'strict classifier materialized the runtime tree'
    }

    Run-Test 'Protected content roots share the same zero-verifier fast path' {
        $f = New-TestFixture v2
        $laneConfig = [Text.Encoding]::UTF8.GetString($script:lanesConfigBytes).TrimStart([char]0xFEFF) | ConvertFrom-Json
        $fontPrefix = [string]@($laneConfig.contentPrefixes | Where-Object { $_ -notmatch '^[\x00-\x7F]+$' })[0]
        $files = [ordered]@{
            'flashswf/arts/new/item.txt' = 'asset'
            'data/items/new.xml' = '<item />'
            'config/gameplay/new.xml' = '<config />'
        }
        $files[$fontPrefix + 'font-note.txt'] = 'font'
        [void](Add-TestFilesCommit $f $files 'content roots')
        $result = Invoke-Classifier $f Protected $f.Base
        Assert-Test ($result.ExitCode -eq 0) $result.Output
        Assert-Test ($result.Output -match 'state=protected-content-fastpath') $result.Output
        Assert-Test ($result.Output -match 'changedCount=4') $result.Output
        Assert-Test ((Get-TestCalls $f).Count -eq 0) 'content fast path must invoke zero verifiers'
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
            Assert-Test ($result.Output -match 'state=protected-content-fastpath') $result.Output
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

    Run-Test 'Trusted-base lane config rejects scalar and overlapping prefix contracts' {
        $invalidConfigs = @(
            '{"schema":"cf7-contribution-lanes.v1","docsPrefixes":"docs/","contentPrefixes":["data/"]}',
            '{"schema":"cf7-contribution-lanes.v1","docsPrefixes":["docs/"],"contentPrefixes":["docs/sub/"]}'
        )
        foreach ($invalidConfig in $invalidConfigs) {
            $f = New-TestFixture v2
            $invalidBase = Add-TestCommit $f 'config/build/contribution-lanes.v1.json' ($invalidConfig + "`n")
            $f.Base = $invalidBase
            [void](Add-TestCommit $f 'docs/head.md' 'content')
            $result = Invoke-Classifier $f Protected $f.Base
            Assert-Test ($result.ExitCode -ne 0) 'invalid trusted-base lane contract unexpectedly passed'
            Assert-Test ($result.Output -match 'must be a JSON array|prefixes overlap') $result.Output
            Assert-Test ((Get-TestCalls $f).Count -eq 0) 'invalid lane contract must fail before verifiers'
        }
    }

    Run-Test 'Content mixed with runtime manifest policy or descriptor uses full verification' {
        $cases = @(
            [pscustomobject]@{ Name='runtime'; Path='runtime/core.bin'; Content='runtime-v2' },
            [pscustomobject]@{ Name='manifest'; Path='runtime/cf7-runtime-manifest.tsv'; Content="cf7-runtime-manifest-v2`npayload-v2`n" },
            [pscustomobject]@{ Name='policy'; Path='tools/verify-runtime-consensus.ps1'; Content=$null },
            [pscustomobject]@{ Name='descriptor'; Path='config/build/runtime-inputs.v2.json'; Content=$null }
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
            Assert-Test ($result.ExitCode -eq 0) "$($case.Name): $($result.Output)"
            Assert-Test ($result.Output -match 'state=protected-coherent') "$($case.Name): $($result.Output)"
            Assert-Test ((Get-TestCalls $f) -join ',' -eq 'v2:integrity,v2:strict,consensus:strict') "$($case.Name) did not use full verification"
        }
    }

    Run-Test 'Unknown and case-spoofed roots never enter the content fast path' {
        foreach ($path in @('source.txt','Docs/spoof.md')) {
            $f = New-TestFixture v2
            [void](Add-TestCommit $f $path 'unknown')
            $result = Invoke-Classifier $f Protected $f.Base
            Assert-Test ($result.ExitCode -eq 0) "$path`: $($result.Output)"
            Assert-Test ($result.Output -match 'state=protected-coherent') "$path`: $($result.Output)"
            Assert-Test ((Get-TestCalls $f) -join ',' -eq 'v2:integrity,v2:strict,consensus:strict') "$path unexpectedly used fast path"
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
        Assert-Test ($result.Output -match 'state=protected-content-fastpath') $result.Output
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
        $result = Invoke-Classifier $f Protected $f.Base
        Assert-Test ($result.ExitCode -ne 0) 'manifest downgrade unexpectedly passed'
        Assert-Test ($result.Output -match 'downgrade from v2 to v1') $result.Output
        Assert-Test ((Get-TestCalls $f) -join ',' -eq 'v1:integrity') 'integrity must run before downgrade rejection'
    }

    Run-Test 'All-zero event base cannot use the content fast path' {
        $f = New-TestFixture v1
        [void](Add-TestCommit $f 'docs/zero-base.md' 'content')
        $result = Invoke-Classifier $f Protected ('0' * 40)
        Assert-Test ($result.ExitCode -eq 0) $result.Output
        Assert-Test ($result.Output -match 'state=protected-coherent') $result.Output
        Assert-Test ((Get-TestCalls $f) -join ',' -eq 'v1:integrity,v1:strict,consensus:strict') 'zero base must use the complete verifier chain'
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

    Run-Test 'Development never receives the migration-bootstrap exemption' {
        $f = New-TestFixture v1
        [void](Add-TestMigrationCommit $f)
        $result = Invoke-Classifier $f Development $f.Base
        Assert-Test ($result.ExitCode -ne 0) 'development migration marker unexpectedly passed'
        Assert-Test ($result.Output -match 'Development mode is forbidden') $result.Output
        Assert-Test ((Get-TestCalls $f).Count -eq 0) 'development rejection must occur before all verifiers'
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

    Run-Test 'Workflow keeps one main-only required context without path filters' {
        $workflow = [IO.File]::ReadAllText($script:workflowSource, [Text.Encoding]::UTF8)
        Assert-Test ($workflow -match '(?m)^\s{2}verify-staged-bundle:\s*$') 'required job key changed'
        Assert-Test ($workflow -match '(?m)^\s{4}name:\s*verify-staged-bundle\s*$') 'required job name changed'
        Assert-Test ($workflow -notmatch '(?m)^\s+paths(?:-ignore)?:\s*') 'workflow must not use paths or paths-ignore filters'
        Assert-Test ($workflow -match '(?m)^\s+filter:\s*blob:none\s*$') 'checkout must use blob:none filtering'
        Assert-Test ($workflow -match '(?m)^\s+fetch-depth:\s*0\s*$') 'checkout must retain complete topology'
        Assert-Test ($workflow -match '(?m)^\s+sparse-checkout:\s*\|\s*$') 'checkout must declare sparse materialization'
        $sparseMatch = [regex]::Match($workflow, '(?ms)^\s{10}sparse-checkout:\s*\|\s*\r?\n(?<paths>(?:\s{12}\S[^\r\n]*\r?\n)+)')
        Assert-Test $sparseMatch.Success 'cannot parse checkout sparse materialization paths'
        $sparsePaths = [string]$sparseMatch.Groups['paths'].Value
        Assert-Test ($sparsePaths -notmatch '(?m)^\s{12}CRAZYFLASHER7MercenaryEmpire\.exe\s*$') 'content fast path must not materialize the root bootstrap'
        Assert-Test ($sparsePaths -notmatch '(?m)^\s{12}runtime(?:/|\s*$)') 'content fast path must not materialize the runtime payload tree'
        Assert-Test ($sparsePaths -match '(?m)^\s{12}config/build/\s*$') 'sparse checkout must retain build-control metadata'
        Assert-Test ($sparsePaths -match '(?m)^\s{12}tools/classify-runtime-release-state\.ps1\s*$') 'sparse checkout must retain the classifier'
        Assert-Test (($workflow | Select-String -Pattern '(?m)^\s+- main\s*$' -AllMatches).Matches.Count -eq 3) 'all three events must target main'
        Assert-Test ($workflow -notmatch '(?m)^\s+- (?:master|''release/\*\*'')\s*$') 'unprotected refs must not emit the required context'
        Assert-Test ($workflow -match "'-Mode', 'Protected'") 'workflow must pass Protected mode literally'
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
