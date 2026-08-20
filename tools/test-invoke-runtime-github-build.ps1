param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$helperSource = Join-Path $repoRoot 'tools\invoke-runtime-github-build.ps1'
$powerShell = (Get-Process -Id $PID).Path
$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$testRoot = Join-Path $tempBase ('cf7-runtime-github-helper-tests-' + [Guid]::NewGuid().ToString('N'))
$utf8NoBom = New-Object Text.UTF8Encoding($false)
$passed = 0
$failed = 0

function Set-TestFile([string]$Path, [string]$Content) {
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    [IO.File]::WriteAllText($Path, $Content, $script:utf8NoBom)
}

function Invoke-TestGit([string]$Root, [string[]]$Arguments) {
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& git -C $Root @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousPreference }
    if ($exitCode -ne 0) { throw "git $($Arguments -join ' ') failed: $($output -join ' ')" }
    return @($output)
}

function Add-TestZipBytes($Archive, [string]$Path, [byte[]]$Bytes, [Nullable[int]]$ExternalAttributes) {
    $entry = $Archive.CreateEntry($Path, [IO.Compression.CompressionLevel]::Optimal)
    if ($null -ne $ExternalAttributes) { $entry.ExternalAttributes = [int]$ExternalAttributes }
    $stream = $entry.Open()
    try {
        $stream.Write($Bytes, 0, $Bytes.Length)
    } finally { $stream.Dispose() }
}

function Add-TestZipEntry($Archive, [string]$Path, [string]$Content, [Nullable[int]]$ExternalAttributes) {
    Add-TestZipBytes $Archive $Path ([Text.Encoding]::UTF8.GetBytes($Content)) $ExternalAttributes
}

function New-TestCandidateZip([string]$Path, [switch]$MaliciousTraversal) {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::Open($Path, [IO.Compression.ZipArchiveMode]::Create)
    try {
        Add-TestZipEntry $archive 'CRAZYFLASHER7MercenaryEmpire.exe' 'fixture-bootstrap' $null
        if ($MaliciousTraversal) {
            Add-TestZipEntry $archive '../escaped.txt' 'must-not-extract' $null
        } else {
            Add-TestZipEntry $archive 'runtime/cf7-runtime-manifest.tsv' "cf7-runtime-manifest-v2`n" $null
            Add-TestZipEntry $archive 'runtime/CRAZYFLASHER7MercenaryEmpire.Core.dll' 'fixture-core' $null
            Add-TestZipEntry $archive 'runtime-build-metadata.v2.json' '{"schema":"fixture"}' $null
        }
    } finally { $archive.Dispose() }
}

function New-TestAttestationZip([string]$Path, [string]$EnvelopeContent, [switch]$ExtraFile) {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::Open($Path, [IO.Compression.ZipArchiveMode]::Create)
    try {
        Add-TestZipEntry $archive 'runtime-build-envelope.v2.json' $EnvelopeContent $null
        Add-TestZipEntry $archive 'runtime-build-envelope.v2.sigstore.json' '{"bundle":"fixture"}' $null
        if ($ExtraFile) { Add-TestZipEntry $archive 'runtime-candidate.v2.zip' 'must-not-be-here' $null }
    } finally { $archive.Dispose() }
}

function New-TestOuterZip(
    [string]$Path,
    [string]$CandidatePath,
    [string]$EnvelopeContent,
    [switch]$MaliciousTraversal,
    [switch]$MaliciousLink,
    [switch]$ExtraFile
) {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::Open($Path, [IO.Compression.ZipArchiveMode]::Create)
    try {
        Add-TestZipBytes $archive 'runtime-candidate.v2.zip' ([IO.File]::ReadAllBytes($CandidatePath)) $null
        Add-TestZipEntry $archive 'runtime-build-envelope.v2.json' $EnvelopeContent $null
        $bundleName = if ($MaliciousTraversal) { '../runtime-build-envelope.v2.sigstore.json' } else { 'runtime-build-envelope.v2.sigstore.json' }
        $linkAttributes = if ($MaliciousLink) {
            [BitConverter]::ToInt32([byte[]](0,0,0,160), 0)
        } else { $null }
        Add-TestZipEntry $archive $bundleName '{"bundle":"fixture"}' $linkAttributes
        if ($ExtraFile) { Add-TestZipEntry $archive 'unexpected.txt' 'not allowed' $null }
    } finally { $archive.Dispose() }
}

function New-TestFixture(
    [switch]$MaliciousInnerTraversal,
    [switch]$MaliciousOuterTraversal,
    [switch]$MaliciousOuterLink,
    [switch]$ExtraOuterFile,
    [Int64]$MetadataSizeDelta = 0,
    [switch]$WrongArtifactDigest,
    [switch]$ExpiredArtifact,
    [switch]$WrongArtifactRun,
    [switch]$WrongArtifactHead,
    [string]$Conclusion = 'success',
    [int]$CompleteAfterViews = 2,
    [string]$HeadBranch = 'runtime-build-v2/test-release',
    [string]$SourceRef = 'refs/tags/runtime-build-v2/test-release',
    [switch]$AnnotatedTag,
    [switch]$WrongTagTarget,
    [switch]$WrongListHeadSha,
    [switch]$WrongViewHeadSha
) {
    $caseRoot = Join-Path $script:testRoot ([Guid]::NewGuid().ToString('N'))
    $projectRoot = Join-Path $caseRoot 'repo'
    $controlRoot = Join-Path $caseRoot 'control'
    $artifactRoot = Join-Path $controlRoot 'artifact'
    New-Item -ItemType Directory -Path (Join-Path $projectRoot 'tools'),(Join-Path $projectRoot 'config\build'),$artifactRoot -Force | Out-Null
    Copy-Item -LiteralPath $script:helperSource -Destination (Join-Path $projectRoot 'tools\invoke-runtime-github-build.ps1')
    Copy-Item -LiteralPath (Join-Path $script:repoRoot 'tools\runtime-build-queue-common.ps1') `
        -Destination (Join-Path $projectRoot 'tools\runtime-build-queue-common.ps1')

    $cloudConfig = [ordered]@{
        schema='cf7-runtime-github-builder.v2';enabled=$true;repository='ExampleOrg/ExampleRepo'
        signerWorkflow='ExampleOrg/ExampleRepo/.github/workflows/runtime-cloud-builder.yml'
        sourceRef=$SourceRef;faultDomain='github-hosted-windows';runnerClass='github-hosted-windows'
        identityProvider='github-oidc-sigstore';longLivedPrivateKey=$false
    }
    Set-TestFile (Join-Path $projectRoot 'config\build\runtime-github-builder.v2.json') (($cloudConfig | ConvertTo-Json -Depth 5) + "`n")
    Set-TestFile (Join-Path $projectRoot 'tools\verify-runtime-github-attestation.ps1') @'
param(
    [string]$EnvelopePath, [string]$BundlePath, [string]$CandidateRoot,
    [string]$ProjectRoot, [string]$GitHubCliPath, [string]$ExpectedSourceCommitOid,
    [string]$OutputPath, [switch]$WithoutCandidateArchive
)
$ErrorActionPreference = 'Stop'
if ($WithoutCandidateArchive -and -not [string]::IsNullOrWhiteSpace($CandidateRoot)) { throw 'stub rejects CandidateRoot in no-archive mode' }
$requiredPaths = @($EnvelopePath,$BundlePath)
if (-not $WithoutCandidateArchive) {
    if ([string]::IsNullOrWhiteSpace($CandidateRoot)) { throw 'stub requires CandidateRoot outside no-archive mode' }
    $requiredPaths += @((Join-Path $CandidateRoot 'CRAZYFLASHER7MercenaryEmpire.exe'),(Join-Path $CandidateRoot 'runtime\cf7-runtime-manifest.tsv'))
}
foreach ($path in $requiredPaths) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "stub verifier input missing: $path" }
}
$envelope = Get-Content -LiteralPath $EnvelopePath -Raw | ConvertFrom-Json
if ([string]$envelope.sourceCommitOid -cne $ExpectedSourceCommitOid) { throw 'stub source mismatch' }
$wrapper = [pscustomobject][ordered]@{
    schema='cf7-runtime-github-build-attestation.v2'
    payload=[pscustomobject][ordered]@{
        schema='cf7-runtime-github-build-attestation-payload.v2'
        sourceCommitOid=$ExpectedSourceCommitOid
        buildIdentityHash=('A' * 64)
        payloadClosureHash=('B' * 64)
    }
    canonicalPayloadSha256=('C' * 64)
    envelopeBase64='e30='
    bundleBase64='e30='
}
$parent = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
[IO.File]::WriteAllText($OutputPath, ($wrapper | ConvertTo-Json -Depth 8) + "`n", (New-Object Text.UTF8Encoding($false)))
[IO.File]::WriteAllText($env:CF7_FAKE_VERIFIER_MARKER, $(if ($WithoutCandidateArchive) { 'called-no-archive' } else { 'called' }), (New-Object Text.UTF8Encoding($false)))
Write-Output $wrapper
'@

    Set-TestFile (Join-Path $controlRoot 'fake-gh.ps1') @'
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$CliArgs)
$ErrorActionPreference = 'Stop'
$statePath = $env:CF7_FAKE_GH_STATE
$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
[IO.File]::AppendAllText([string]$state.logPath, (($CliArgs | ConvertTo-Json -Compress) + "`n"), (New-Object Text.UTF8Encoding($false)))
function Save-State { [IO.File]::WriteAllText($statePath, (($state | ConvertTo-Json -Depth 8) + "`n"), (New-Object Text.UTF8Encoding($false))) }
function New-Run([Int64]$Id, [string]$Status, [AllowNull()][string]$RunConclusion, [string]$CreatedAt, [string]$HeadSha) {
    return [pscustomobject][ordered]@{
        databaseId=$Id; displayTitle=('Runtime cloud builder ' + [string]$state.sourceCommitOid)
        headBranch=[string]$state.headBranch; headSha=$HeadSha; status=$Status; conclusion=$RunConclusion
        createdAt=$CreatedAt; event='workflow_dispatch'; url=('https://example.invalid/runs/' + $Id)
    }
}
if ($CliArgs.Count -ge 2 -and $CliArgs[0] -eq 'api') {
    $endpoint = [string]$CliArgs[$CliArgs.Count - 1]
    $relativeRef = ([string]$state.sourceRef).Substring('refs/'.Length)
    $refEndpoint = 'repos/ExampleOrg/ExampleRepo/git/ref/' + $relativeRef
    if ($endpoint -ceq $refEndpoint) {
        $objectType = if ([bool]$state.annotatedTag) { 'tag' } else { 'commit' }
        $objectSha = if ([bool]$state.annotatedTag) { [string]$state.tagObjectSha } else { [string]$state.tagTargetCommit }
        Write-Output ([ordered]@{
            ref=[string]$state.sourceRef
            object=[ordered]@{ type=$objectType; sha=$objectSha }
        } | ConvertTo-Json -Depth 5 -Compress)
        exit 0
    }
    $tagEndpoint = 'repos/ExampleOrg/ExampleRepo/git/tags/' + [string]$state.tagObjectSha
    if ([bool]$state.annotatedTag -and $endpoint -ceq $tagEndpoint) {
        Write-Output ([ordered]@{
            sha=[string]$state.tagObjectSha
            object=[ordered]@{ type='commit'; sha=[string]$state.tagTargetCommit }
        } | ConvertTo-Json -Depth 5 -Compress)
        exit 0
    }
    $artifactEndpointPrefix = 'repos/ExampleOrg/ExampleRepo/actions/runs/' + [string]$state.runId + '/artifacts?'
    if ($endpoint.StartsWith($artifactEndpointPrefix, [StringComparison]::Ordinal)) {
        $nameMatch = [regex]::Match($endpoint, '[?&]name=([^&]+)')
        $requestedName = if ($nameMatch.Success) { [Uri]::UnescapeDataString($nameMatch.Groups[1].Value) } else { '' }
        $attestationName = 'runtime-cloud-attestation-' + [string]$state.sourceCommitOid
        $builderName = 'runtime-cloud-builder-' + [string]$state.sourceCommitOid
        $artifacts = @()
        if ($requestedName -ceq $builderName) {
            $artifacts = @([ordered]@{
                id=[Int64]$state.artifactId
                name=$builderName
                size_in_bytes=[Int64]$state.artifactSize
                digest=[string]$state.artifactDigest
                expired=[bool]$state.artifactExpired
                archive_download_url=('https://api.github.com/repos/ExampleOrg/ExampleRepo/actions/artifacts/' + [string]$state.artifactId + '/zip')
                workflow_run=[ordered]@{
                    id=$(if([bool]$state.wrongArtifactRun){9999}else{[Int64]$state.runId})
                    head_sha=$(if([bool]$state.wrongArtifactHead){'b' * 40}else{[string]$state.sourceCommitOid})
                }
            })
        } elseif ($requestedName -ceq $attestationName) {
            $artifacts = @([ordered]@{
                id=[Int64]$state.attestationArtifactId
                name=$attestationName
                size_in_bytes=[Int64]$state.attestationArtifactSize
                digest=[string]$state.attestationArtifactDigest
                expired=[bool]$state.artifactExpired
                archive_download_url=('https://api.github.com/repos/ExampleOrg/ExampleRepo/actions/artifacts/' + [string]$state.attestationArtifactId + '/zip')
                workflow_run=[ordered]@{
                    id=$(if([bool]$state.wrongArtifactRun){9999}else{[Int64]$state.runId})
                    head_sha=$(if([bool]$state.wrongArtifactHead){'b' * 40}else{[string]$state.sourceCommitOid})
                }
            })
        }
        Write-Output ([ordered]@{
            total_count=$artifacts.Count
            artifacts=$artifacts
        } | ConvertTo-Json -Depth 6 -Compress)
        exit 0
    }
    exit 46
}
if ($CliArgs.Count -ge 2 -and $CliArgs[0] -eq 'workflow' -and $CliArgs[1] -eq 'run') {
    $sourceArgument = @($CliArgs | Where-Object { $_ -like 'source_commit=*' })
    if ($sourceArgument.Count -ne 1 -or $sourceArgument[0].Substring('source_commit='.Length) -cne [string]$state.sourceCommitOid) { exit 41 }
    $state.dispatched = $true
    Save-State
    exit 0
}
if ($CliArgs.Count -ge 2 -and $CliArgs[0] -eq 'run' -and $CliArgs[1] -eq 'list') {
    $runs = @()
    if ([bool]$state.includePreexisting) { $runs += New-Run 4000 'completed' 'success' '2026-01-01T00:00:00Z' ([string]$state.sourceCommitOid) }
    if ([bool]$state.dispatched) { $runs += New-Run ([Int64]$state.runId) 'queued' $null ([string]$state.createdAt) ([string]$state.listHeadSha) }
    Write-Output (ConvertTo-Json -InputObject @($runs) -Depth 6 -Compress)
    exit 0
}
if ($CliArgs.Count -ge 3 -and $CliArgs[0] -eq 'run' -and $CliArgs[1] -eq 'view') {
    if ([Int64]$CliArgs[2] -ne [Int64]$state.runId) { exit 42 }
    $state.viewCount = [int]$state.viewCount + 1
    $complete = [int]$state.viewCount -ge [int]$state.completeAfterViews
    $run = New-Run ([Int64]$state.runId) $(if($complete){'completed'}else{'in_progress'}) $(if($complete){[string]$state.conclusion}else{$null}) ([string]$state.createdAt) ([string]$state.viewHeadSha)
    Save-State
    Write-Output ($run | ConvertTo-Json -Depth 6 -Compress)
    exit 0
}
exit 45
'@
    Set-TestFile (Join-Path $controlRoot 'fake-gh.cmd') @'
@echo off
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0fake-gh.ps1" %*
exit /b %ERRORLEVEL%
'@

    Set-TestFile (Join-Path $projectRoot 'source.txt') 'fixture source'
    [void](Invoke-TestGit $projectRoot @('init'))
    [void](Invoke-TestGit $projectRoot @('config','core.autocrlf','false'))
    [void](Invoke-TestGit $projectRoot @('config','user.name','CF7 GitHub Helper Test'))
    [void](Invoke-TestGit $projectRoot @('config','user.email','github-helper@example.invalid'))
    [void](Invoke-TestGit $projectRoot @('add','-A'))
    [void](Invoke-TestGit $projectRoot @('commit','-m','fixture'))
    $headLines = @(Invoke-TestGit $projectRoot @('rev-parse','HEAD'))
    $sourceCommit = ([string]$headLines[0]).Trim().ToLowerInvariant()

    $candidatePath = Join-Path $artifactRoot 'runtime-candidate.v2.zip'
    $outerArchivePath = Join-Path $controlRoot 'runtime-cloud-artifact.zip'
    $envelopeContent = (([ordered]@{ sourceCommitOid=$sourceCommit } | ConvertTo-Json -Compress) + "`n")
    New-TestCandidateZip -Path $candidatePath -MaliciousTraversal:$MaliciousInnerTraversal
    New-TestOuterZip -Path $outerArchivePath -CandidatePath $candidatePath -EnvelopeContent $envelopeContent `
        -MaliciousTraversal:$MaliciousOuterTraversal -MaliciousLink:$MaliciousOuterLink -ExtraFile:$ExtraOuterFile
    $attestationArchivePath = Join-Path $controlRoot 'runtime-cloud-attestation.zip'
    New-TestAttestationZip -Path $attestationArchivePath -EnvelopeContent $envelopeContent
    $statePath = Join-Path $controlRoot 'state.json'
    $logPath = Join-Path $controlRoot 'calls.jsonl'
    $markerPath = Join-Path $controlRoot 'verifier.marker'
    $state = [ordered]@{
        sourceCommitOid=$sourceCommit; runId=4242; dispatched=$false; includePreexisting=$true
        sourceRef=$SourceRef; annotatedTag=[bool]$AnnotatedTag; tagObjectSha=('e' * 40)
        tagTargetCommit=$(if($WrongTagTarget){'f' * 40}else{$sourceCommit})
        headBranch=$HeadBranch
        listHeadSha=$(if($WrongListHeadSha){'d' * 40}else{$sourceCommit})
        viewHeadSha=$(if($WrongViewHeadSha){'c' * 40}else{$sourceCommit})
        viewCount=0; completeAfterViews=$CompleteAfterViews; conclusion=$Conclusion
        createdAt=[DateTime]::UtcNow.ToString('o'); artifactRoot=$artifactRoot; artifactId=8442
        artifactSize=(Get-Item -LiteralPath $outerArchivePath).Length + $MetadataSizeDelta
        artifactDigest=$(if($WrongArtifactDigest){'sha256:' + ('0' * 64)}else{'sha256:' + (Get-FileHash -LiteralPath $outerArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()})
        attestationArtifactId=8443
        attestationArtifactSize=(Get-Item -LiteralPath $attestationArchivePath).Length
        attestationArtifactDigest=('sha256:' + (Get-FileHash -LiteralPath $attestationArchivePath -Algorithm SHA256).Hash.ToLowerInvariant())
        artifactExpired=[bool]$ExpiredArtifact; wrongArtifactRun=[bool]$WrongArtifactRun
        wrongArtifactHead=[bool]$WrongArtifactHead; logPath=$logPath
    }
    Set-TestFile $statePath (($state | ConvertTo-Json -Depth 6) + "`n")
    Set-TestFile $logPath ''
    return [pscustomobject]@{
        CaseRoot=$caseRoot; ProjectRoot=$projectRoot; ControlRoot=$controlRoot
        SourceCommit=$sourceCommit; FakeGh=(Join-Path $controlRoot 'fake-gh.cmd')
        StatePath=$statePath; LogPath=$logPath; MarkerPath=$markerPath; OutputRoot=(Join-Path $caseRoot 'output')
        ArtifactArchive=$outerArchivePath; AttestationArchive=$attestationArchivePath
    }
}

function Invoke-TestHelper($Fixture, [switch]$ResumeRun, [switch]$AttestationOnly, [string[]]$ExtraArguments) {
    $preDownloaded = if ($AttestationOnly) { $Fixture.AttestationArchive } else { $Fixture.ArtifactArchive }
    $arguments = @(
        '-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $Fixture.ProjectRoot 'tools\invoke-runtime-github-build.ps1'),
        '-ProjectRoot',$Fixture.ProjectRoot,'-SourceCommitOid',$Fixture.SourceCommit,
        '-OutputRoot',$Fixture.OutputRoot,'-GitHubCliPath',$Fixture.FakeGh,
        '-PreDownloadedArtifactArchive',$preDownloaded,
        '-DiscoveryTimeoutSeconds','5','-RunTimeoutSeconds','30','-PollSeconds','1'
    )
    if ($ResumeRun) { $arguments += @('-ResumeRunId','4242') }
    if (-not $AttestationOnly) { $arguments += '-IncludeCandidateArchive' }
    if ($ExtraArguments) { $arguments += $ExtraArguments }
    $oldState = $env:CF7_FAKE_GH_STATE
    $oldMarker = $env:CF7_FAKE_VERIFIER_MARKER
    $env:CF7_FAKE_GH_STATE = $Fixture.StatePath
    $env:CF7_FAKE_VERIFIER_MARKER = $Fixture.MarkerPath
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& $script:powerShell @arguments 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
        $env:CF7_FAKE_GH_STATE = $oldState
        $env:CF7_FAKE_VERIFIER_MARKER = $oldMarker
    }
    return [pscustomobject]@{ ExitCode=[int]$exitCode; Output=($output | ForEach-Object { [string]$_ }) -join "`n" }
}

function Get-TestCalls($Fixture) {
    return @(Get-Content -LiteralPath $Fixture.LogPath | Where-Object { $_ -ne '' } | ForEach-Object { ,($_ | ConvertFrom-Json) })
}

function Assert-Test([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Run-Test([string]$Name, [scriptblock]$Body) {
    try { & $Body; $script:passed++; Write-Host "[PASS] $Name" -ForegroundColor Green }
    catch { $script:failed++; Write-Host "[FAIL] $Name :: $($_.Exception.Message)" -ForegroundColor Red }
}

New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
try {
    Run-Test 'peels the configured annotated tag, dispatches exact SHA, and produces a verified wrapper' {
        $fixture = New-TestFixture -AnnotatedTag
        $result = Invoke-TestHelper $fixture
        Assert-Test ($result.ExitCode -eq 0) $result.Output
        $resultPath = Join-Path $fixture.OutputRoot 'run-4242\runtime-github-build-result.v2.json'
        Assert-Test (Test-Path -LiteralPath $resultPath -PathType Leaf) 'result metadata missing'
        $metadata = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
        Assert-Test ([Int64]$metadata.runId -eq 4242) 'helper selected the preexisting run instead of the new run'
        Assert-Test ([Int64]$metadata.artifactId -eq 8442) 'result does not bind exact artifact metadata'
        Assert-Test ([string]$metadata.artifactArchiveSha256 -match '^[0-9a-f]{64}$') 'result does not retain the exact artifact digest'
        Assert-Test ([string]$metadata.artifactTransport -ceq 'pre-downloaded-outer-archive') 'fixture did not use the validated outer-archive seam'
        Assert-Test ([string]$metadata.sourceCommitOid -ceq $fixture.SourceCommit) 'result source commit mismatch'
        Assert-Test (Test-Path -LiteralPath ([string]$metadata.proofPath) -PathType Leaf) 'normalized proof missing'
        Assert-Test (Test-Path -LiteralPath (Join-Path ([string]$metadata.candidateRoot) 'runtime\cf7-runtime-manifest.tsv') -PathType Leaf) 'candidate was not extracted'
        Assert-Test (Test-Path -LiteralPath $fixture.MarkerPath -PathType Leaf) 'proof verifier was not called'
        $calls = @(Get-TestCalls $fixture)
        $dispatch = @($calls | Where-Object { $_[0] -eq 'workflow' -and $_[1] -eq 'run' })
        Assert-Test ($dispatch.Count -eq 1) 'expected exactly one workflow dispatch'
        Assert-Test (@($dispatch[0] | Where-Object { $_ -eq "source_commit=$($fixture.SourceCommit)" }).Count -eq 1) 'dispatch did not bind the exact source SHA'
        $refIndex = [Array]::IndexOf([object[]]$dispatch[0], '--ref')
        Assert-Test ($refIndex -ge 0 -and [string]$dispatch[0][$refIndex + 1] -ceq 'runtime-build-v2/test-release') 'dispatch did not select the configured immutable release tag'
        $apiCalls = @($calls | Where-Object { $_[0] -eq 'api' })
        Assert-Test ($apiCalls.Count -eq 3) 'tag peeling plus exact run artifact metadata query did not occur'
        Assert-Test (@($apiCalls | Where-Object { [string]$_[-1] -like 'repos/ExampleOrg/ExampleRepo/actions/runs/4242/artifacts?*' }).Count -eq 1) 'selected run artifact metadata was not queried exactly once'
        $download = @($calls | Where-Object { $_[0] -eq 'run' -and $_[1] -eq 'download' })
        Assert-Test ($download.Count -eq 0) 'legacy gh run download transport must not be used'
    }

    Run-Test 'rejects inner candidate ZIP traversal before calling the provenance verifier' {
        $fixture = New-TestFixture -MaliciousInnerTraversal -CompleteAfterViews 1
        $result = Invoke-TestHelper $fixture
        Assert-Test ($result.ExitCode -ne 0) 'malicious candidate archive unexpectedly passed'
        Assert-Test ($result.Output -match 'Unsafe candidate archive path|path segments') $result.Output
        Assert-Test (-not (Test-Path -LiteralPath $fixture.MarkerPath)) 'verifier must not run after unsafe extraction'
        Assert-Test (-not (Test-Path -LiteralPath (Join-Path $fixture.OutputRoot 'run-4242\escaped.txt'))) 'ZIP traversal wrote outside candidate root'
    }

    Run-Test 'rejects outer artifact traversal before extracting signed files' {
        $fixture = New-TestFixture -MaliciousOuterTraversal -CompleteAfterViews 1
        $result = Invoke-TestHelper $fixture
        Assert-Test ($result.ExitCode -ne 0) 'malicious outer artifact unexpectedly passed'
        Assert-Test ($result.Output -match 'exact file allowlist') $result.Output
        Assert-Test (-not (Test-Path -LiteralPath $fixture.MarkerPath)) 'verifier must not run after unsafe outer extraction'
        Assert-Test (-not (Test-Path -LiteralPath (Join-Path $fixture.OutputRoot 'run-4242\runtime-build-envelope.v2.sigstore.json'))) 'outer traversal wrote outside signed-artifact root'
    }

    Run-Test 'reinterprets negative external attributes and rejects an outer link entry' {
        $fixture = New-TestFixture -MaliciousOuterLink -CompleteAfterViews 1
        $result = Invoke-TestHelper $fixture
        Assert-Test ($result.ExitCode -ne 0) 'outer link artifact unexpectedly passed'
        Assert-Test ($result.Output -match 'link/reparse entry') $result.Output
        Assert-Test (-not (Test-Path -LiteralPath $fixture.MarkerPath)) 'verifier must not run after outer link detection'
    }

    Run-Test 'rejects extra files in the outer artifact archive' {
        $fixture = New-TestFixture -ExtraOuterFile -CompleteAfterViews 1
        $result = Invoke-TestHelper $fixture
        Assert-Test ($result.ExitCode -ne 0) 'outer artifact with an extra file unexpectedly passed'
        Assert-Test ($result.Output -match 'exactly three files') $result.Output
        Assert-Test (-not (Test-Path -LiteralPath $fixture.MarkerPath)) 'verifier must not run for an unexpected outer file set'
    }

    Run-Test 'rejects pre-downloaded outer archive size drift from exact run metadata' {
        $fixture = New-TestFixture -MetadataSizeDelta 1 -CompleteAfterViews 1
        $result = Invoke-TestHelper $fixture
        Assert-Test ($result.ExitCode -ne 0) 'metadata size drift unexpectedly passed'
        Assert-Test ($result.Output -match 'length exactly matches GitHub metadata') $result.Output
        Assert-Test (-not (Test-Path -LiteralPath $fixture.MarkerPath)) 'verifier must not run after metadata size drift'
    }

    Run-Test 'rejects outer archive digest drift from exact run metadata' {
        $fixture = New-TestFixture -WrongArtifactDigest -CompleteAfterViews 1
        $result = Invoke-TestHelper $fixture
        Assert-Test ($result.ExitCode -ne 0) 'metadata digest drift unexpectedly passed'
        Assert-Test ($result.Output -match 'SHA-256 does not match GitHub metadata') $result.Output
        Assert-Test (-not (Test-Path -LiteralPath $fixture.MarkerPath)) 'verifier must not run after artifact digest drift'
    }

    Run-Test 'rejects expired or wrong-run artifact metadata' {
        foreach ($fixture in @(
            (New-TestFixture -ExpiredArtifact -CompleteAfterViews 1),
            (New-TestFixture -WrongArtifactRun -CompleteAfterViews 1),
            (New-TestFixture -WrongArtifactHead -CompleteAfterViews 1)
        )) {
            $result = Invoke-TestHelper $fixture
            Assert-Test ($result.ExitCode -ne 0) 'unsafe artifact metadata unexpectedly passed'
            Assert-Test ($result.Output -match 'expired|does not bind the selected workflow run') $result.Output
            Assert-Test (-not (Test-Path -LiteralPath $fixture.MarkerPath)) 'verifier must not run after unsafe metadata'
        }
    }

    Run-Test 'can select an existing exact run for interrupted-download recovery without redispatch' {
        $fixture = New-TestFixture -CompleteAfterViews 1
        $result = Invoke-TestHelper $fixture -ResumeRun
        Assert-Test ($result.ExitCode -eq 0) $result.Output
        $calls = @(Get-TestCalls $fixture)
        Assert-Test (@($calls | Where-Object { $_[0] -eq 'workflow' -and $_[1] -eq 'run' }).Count -eq 0) 'resume mode must not dispatch another hosted build'
        Assert-Test (@($calls | Where-Object { $_[0] -eq 'run' -and $_[1] -eq 'view' -and [string]$_[2] -eq '4242' }).Count -ge 1) 'resume mode did not revalidate the selected run'
        Assert-Test (@($calls | Where-Object { $_[0] -eq 'api' -and [string]$_[-1] -like 'repos/ExampleOrg/ExampleRepo/actions/runs/4242/artifacts?*' }).Count -eq 1) 'resume mode did not requery exact artifact metadata'
    }

    Run-Test 'fails a non-successful workflow without downloading artifacts' {
        $fixture = New-TestFixture -Conclusion failure -CompleteAfterViews 1
        $result = Invoke-TestHelper $fixture
        Assert-Test ($result.ExitCode -ne 0) 'failed workflow unexpectedly passed'
        Assert-Test ($result.Output -match 'conclusion=failure') $result.Output
        $calls = @(Get-TestCalls $fixture)
        Assert-Test (@($calls | Where-Object { $_[0] -eq 'run' -and $_[1] -eq 'download' }).Count -eq 0) 'artifact download must not run after workflow failure'
    }

    Run-Test 'rejects a same-title run dispatched from an unexpected source branch' {
        $fixture = New-TestFixture -HeadBranch attacker-branch -CompleteAfterViews 1
        $result = Invoke-TestHelper $fixture
        Assert-Test ($result.ExitCode -ne 0) 'wrong-branch workflow run unexpectedly passed'
        Assert-Test ($result.Output -match 'Timed out locating dispatched GitHub run') $result.Output
        $calls = @(Get-TestCalls $fixture)
        Assert-Test (@($calls | Where-Object { $_[0] -eq 'run' -and $_[1] -eq 'download' }).Count -eq 0) 'wrong-branch run must not download artifacts'
    }

    Run-Test 'rejects a configured tag that peels to the wrong source commit before dispatch' {
        $fixture = New-TestFixture -AnnotatedTag -WrongTagTarget
        $result = Invoke-TestHelper $fixture
        Assert-Test ($result.ExitCode -ne 0) 'wrong tag target unexpectedly passed'
        Assert-Test ($result.Output -match 'source tag does not resolve to SourceCommitOid') $result.Output
        $calls = @(Get-TestCalls $fixture)
        Assert-Test (@($calls | Where-Object { $_[0] -eq 'workflow' -and $_[1] -eq 'run' }).Count -eq 0) 'wrong tag target must fail before workflow dispatch'
    }

    Run-Test 'rejects source refs outside the protected single-segment runtime tag namespace' {
        foreach ($sourceRef in @('refs/tags/unprotected-release','refs/tags/runtime-build-v2/nested/release')) {
            $fixture = New-TestFixture -SourceRef $sourceRef
            $result = Invoke-TestHelper $fixture
            Assert-Test ($result.ExitCode -ne 0) "unsafe source ref unexpectedly passed: $sourceRef"
            Assert-Test ($result.Output -match 'canonical protected runtime-build-v2 tag') $result.Output
            Assert-Test ((Get-TestCalls $fixture).Count -eq 0) "unsafe source ref must fail before every GitHub API call: $sourceRef"
        }
    }

    Run-Test 'rejects a discovered run whose head SHA differs from the requested source commit' {
        $fixture = New-TestFixture -WrongListHeadSha -CompleteAfterViews 1
        $result = Invoke-TestHelper $fixture
        Assert-Test ($result.ExitCode -ne 0) 'wrong discovery head SHA unexpectedly passed'
        Assert-Test ($result.Output -match 'Timed out locating dispatched GitHub run') $result.Output
        $calls = @(Get-TestCalls $fixture)
        Assert-Test (@($calls | Where-Object { $_[0] -eq 'run' -and $_[1] -eq 'download' }).Count -eq 0) 'wrong discovery head SHA must not download artifacts'
    }

    Run-Test 'rejects a selected run whose head SHA changes while waiting' {
        $fixture = New-TestFixture -WrongViewHeadSha -CompleteAfterViews 1
        $result = Invoke-TestHelper $fixture
        Assert-Test ($result.ExitCode -ne 0) 'wrong wait head SHA unexpectedly passed'
        Assert-Test ($result.Output -match 'head SHA does not match the requested source commit') $result.Output
        $calls = @(Get-TestCalls $fixture)
        Assert-Test (@($calls | Where-Object { $_[0] -eq 'run' -and $_[1] -eq 'download' }).Count -eq 0) 'changed wait head SHA must not download artifacts'
    }

    Run-Test 'default scope downloads only the attestation artifact and verifies without a candidate' {
        $fixture = New-TestFixture -CompleteAfterViews 1
        $result = Invoke-TestHelper $fixture -AttestationOnly
        Assert-Test ($result.ExitCode -eq 0) $result.Output
        $resultPath = Join-Path $fixture.OutputRoot 'run-4242\runtime-github-build-result.v2.json'
        Assert-Test (Test-Path -LiteralPath $resultPath -PathType Leaf) 'attestation-only result metadata missing'
        $metadata = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
        Assert-Test ([Int64]$metadata.artifactId -eq 8443) 'default scope did not select the small attestation artifact'
        Assert-Test ([string]$metadata.artifactName -ceq ('runtime-cloud-attestation-' + $fixture.SourceCommit)) 'default scope artifact name mismatch'
        Assert-Test ([string]$metadata.artifactScope -ceq 'attestation-only') 'default scope label mismatch'
        Assert-Test ([string]$metadata.artifactTransportMode -ceq 'auto') 'default transport mode must be auto'
        Assert-Test ($null -eq $metadata.candidateRoot -or [string]::IsNullOrWhiteSpace([string]$metadata.candidateRoot)) 'attestation-only scope must not materialize a candidate root'
        Assert-Test (Test-Path -LiteralPath ([string]$metadata.envelopePath) -PathType Leaf) 'envelope missing from the small artifact extraction'
        Assert-Test (Test-Path -LiteralPath ([string]$metadata.bundlePath) -PathType Leaf) 'sigstore bundle missing from the small artifact extraction'
        Assert-Test ([IO.File]::ReadAllText($fixture.MarkerPath) -eq 'called-no-archive') 'verifier did not run in no-archive mode'
        Assert-Test (-not (Test-Path -LiteralPath (Join-Path $fixture.OutputRoot 'run-4242\candidate'))) 'attestation-only scope extracted a candidate archive'
        $calls = @(Get-TestCalls $fixture)
        Assert-Test (@($calls | Where-Object { $_[0] -eq 'api' -and [string]$_[-1] -like '*artifacts?*' }).Count -eq 1) 'attestation-only scope must query artifact metadata exactly once'
    }

    Run-Test 'attestation-only scope rejects unexpected files inside the small artifact' {
        $fixture = New-TestFixture -CompleteAfterViews 1
        Remove-Item -LiteralPath $fixture.AttestationArchive -Force
        New-TestAttestationZip -Path $fixture.AttestationArchive -EnvelopeContent (([ordered]@{ sourceCommitOid=$fixture.SourceCommit } | ConvertTo-Json -Compress) + "`n") -ExtraFile
        $state = Get-Content -LiteralPath $fixture.StatePath -Raw | ConvertFrom-Json
        $state.attestationArtifactSize = (Get-Item -LiteralPath $fixture.AttestationArchive).Length
        $state.attestationArtifactDigest = 'sha256:' + (Get-FileHash -LiteralPath $fixture.AttestationArchive -Algorithm SHA256).Hash.ToLowerInvariant()
        Set-TestFile $fixture.StatePath (($state | ConvertTo-Json -Depth 6) + "`n")
        $result = Invoke-TestHelper $fixture -AttestationOnly
        Assert-Test ($result.ExitCode -ne 0) 'attestation artifact with an unexpected member unexpectedly passed'
        Assert-Test ($result.Output -match 'exactly two files|exact file allowlist') $result.Output
        Assert-Test (-not (Test-Path -LiteralPath $fixture.MarkerPath)) 'verifier must not run after an unsafe attestation artifact'
    }

    $helperTokens = $null
    $helperParseErrors = $null
    $helperAst = [Management.Automation.Language.Parser]::ParseFile($script:helperSource, [ref]$helperTokens, [ref]$helperParseErrors)
    Assert-Test (@($helperParseErrors).Count -eq 0) 'helper script must parse for route unit tests'
    foreach ($functionName in @(
        'Resolve-Cf7ArtifactTransportMode','Get-Cf7ArtifactRouteCandidates','Get-Cf7ArtifactRouteCachePath',
        'Read-Cf7ArtifactRouteCache','Save-Cf7ArtifactRouteCache','Clear-Cf7ArtifactRouteCache',
        'New-Cf7HttpClient','Get-Cf7ArtifactRedirect','Invoke-Cf7ArtifactStreamAttempt'
    )) {
        $functionAsts = @($helperAst.FindAll({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName
        }, $true))
        Assert-Test ($functionAsts.Count -eq 1) "helper must export exactly one $functionName"
        Invoke-Expression $functionAsts[0].Extent.Text
    }
    . (Join-Path $repoRoot 'tools\runtime-build-queue-common.ps1')

    Run-Test 'artifact transport mode resolves parameter, environment, and fail-closed validation' {
        Assert-Test ((Resolve-Cf7ArtifactTransportMode -ParameterValue '' -EnvironmentValue $null) -eq 'auto') 'default transport must be auto'
        Assert-Test ((Resolve-Cf7ArtifactTransportMode -ParameterValue 'proxy' -EnvironmentValue 'direct') -eq 'proxy') 'parameter must override environment'
        Assert-Test ((Resolve-Cf7ArtifactTransportMode -ParameterValue '' -EnvironmentValue 'direct') -eq 'direct') 'environment must apply when parameter is empty'
        Assert-Test ((Resolve-Cf7ArtifactTransportMode -ParameterValue 'AUTO' -EnvironmentValue $null) -eq 'auto') 'transport value must normalize case'
        $rejected = $false
        try { Resolve-Cf7ArtifactTransportMode -ParameterValue '' -EnvironmentValue 'bogus' | Out-Null } catch { $rejected = $true }
        Assert-Test $rejected 'unknown transport value must fail closed'
    }

    Run-Test 'artifact route candidates order the sticky route first and demote failed routes' {
        Assert-Test (((Get-Cf7ArtifactRouteCandidates -Mode 'auto' -PersistedRoute $null -FailedRoutes @()) -join ',') -ceq 'proxy,direct') 'auto without a sticky route must probe proxy then direct'
        Assert-Test (((Get-Cf7ArtifactRouteCandidates -Mode 'auto' -PersistedRoute 'direct' -FailedRoutes @()) -join ',') -ceq 'direct,proxy') 'sticky route must come first'
        Assert-Test (((Get-Cf7ArtifactRouteCandidates -Mode 'auto' -PersistedRoute 'direct' -FailedRoutes @('direct')) -join ',') -ceq 'proxy,direct') 'failed route must be demoted behind fresh candidates'
        Assert-Test (((Get-Cf7ArtifactRouteCandidates -Mode 'proxy' -PersistedRoute 'direct' -FailedRoutes @()) -join ',') -ceq 'proxy') 'explicit proxy must pin one route'
        Assert-Test (((Get-Cf7ArtifactRouteCandidates -Mode 'direct' -PersistedRoute 'proxy' -FailedRoutes @('proxy')) -join ',') -ceq 'direct') 'explicit direct must pin one route'
    }

    Run-Test 'artifact route cache persists, validates, and invalidates' {
        $cacheQueue = Join-Path $testRoot ('route-cache-' + [Guid]::NewGuid().ToString('N'))
        Assert-Test ($null -eq (Read-Cf7ArtifactRouteCache -QueueRoot $cacheQueue)) 'missing cache must read as absent'
        Save-Cf7ArtifactRouteCache -QueueRoot $cacheQueue -Route 'direct' -Source 'canary'
        Assert-Test ((Read-Cf7ArtifactRouteCache -QueueRoot $cacheQueue) -eq 'direct') 'persisted route must round-trip'
        $cacheRecord = Get-Content -LiteralPath (Get-Cf7ArtifactRouteCachePath -QueueRoot $cacheQueue) -Raw | ConvertFrom-Json
        Assert-Test ([string]$cacheRecord.schema -eq 'cf7-github-artifact-route.v1' -and -not [string]::IsNullOrWhiteSpace([string]$cacheRecord.updatedAtUtc)) 'cache record must carry schema and timestamp'
        Set-TestFile (Get-Cf7ArtifactRouteCachePath -QueueRoot $cacheQueue) '{"schema":"cf7-github-artifact-route.v1","route":"bogus"}'
        Assert-Test ($null -eq (Read-Cf7ArtifactRouteCache -QueueRoot $cacheQueue)) 'a tampered route value must be ignored'
        Set-TestFile (Get-Cf7ArtifactRouteCachePath -QueueRoot $cacheQueue) 'not json'
        Assert-Test ($null -eq (Read-Cf7ArtifactRouteCache -QueueRoot $cacheQueue)) 'corrupt cache JSON must be ignored'
        Save-Cf7ArtifactRouteCache -QueueRoot $cacheQueue -Route 'proxy' -Source 'sticky'
        Clear-Cf7ArtifactRouteCache -QueueRoot $cacheQueue
        Assert-Test (-not (Test-Path -LiteralPath (Get-Cf7ArtifactRouteCachePath -QueueRoot $cacheQueue))) 'invalidation must remove the cache file'
    }

    function New-TestRawHttpServer([scriptblock]$Handler) {
        $listener = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, 0)
        $listener.Start()
        $server = [System.Management.Automation.PowerShell]::Create()
        [void]$server.AddScript($Handler).AddArgument($listener)
        return [pscustomobject]@{
            Listener = $listener
            Port = ([Net.IPEndPoint]$listener.LocalEndpoint).Port
            Server = $server
            Handle = $server.BeginInvoke()
        }
    }
    function Close-TestRawHttpServer($Server) {
        try { $Server.Listener.Stop() } catch { }
        try { [void]$Server.Handle.AsyncWaitHandle.WaitOne(20000) } catch { }
        try { $Server.Server.EndInvoke($Server.Handle) } catch { }
        try { $Server.Server.Dispose() } catch { }
    }
    $readThenStallServer = {
        param($listener)
        $client = $listener.AcceptTcpClient()
        try {
            $stream = $client.GetStream()
            $buffer = New-Object byte[] 65536
            $header = ''
            while (-not $header.Contains("`r`n`r`n")) {
                $read = $stream.Read($buffer, 0, $buffer.Length)
                if ($read -le 0) { return }
                $header += [Text.Encoding]::ASCII.GetString($buffer, 0, $read)
            }
            $head = [Text.Encoding]::ASCII.GetBytes("HTTP/1.1 200 OK`r`nContent-Length: 1048576`r`nConnection: close`r`n`r`n")
            $stream.Write($head, 0, $head.Length)
            $body = [Text.Encoding]::ASCII.GetBytes('partial-payload')
            $stream.Write($body, 0, $body.Length)
            $stream.Flush()
            Start-Sleep -Seconds 6
        } finally {
            try { $client.Close() } catch { }
        }
    }

    Run-Test 'stalled artifact stream aborts the attempt and retains the partial bytes' {
        $server = New-TestRawHttpServer -Handler $readThenStallServer
        $partialPath = Join-Path $testRoot ('stall-' + [Guid]::NewGuid().ToString('N') + '.partial')
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $failed = $false
            try {
                Invoke-Cf7ArtifactStreamAttempt -BlobUri ("http://127.0.0.1:$($server.Port)/blob") -PartialPath $partialPath `
                    -ExpectedSize 1048576 -UseProxy $false -TimeoutSeconds 120 -ConnectTimeoutSeconds 10 -StallTimeoutSeconds 1
            } catch { $failed = $true }
            $watch.Stop()
            Assert-Test $failed 'a stalled data phase must abort the attempt'
            Assert-Test ($watch.Elapsed.TotalSeconds -lt 30) "stall detection took too long: $($watch.Elapsed.TotalSeconds)s"
            Assert-Test ((Get-Item -LiteralPath $partialPath -Force).Length -eq 15) 'stall abort must retain the already-received partial bytes'
        } finally {
            Close-TestRawHttpServer $server
        }
    }

    Run-Test 'a header-less connection dies at the connect watchdog instead of the attempt ceiling' {
        $silentServer = {
            param($listener)
            $client = $listener.AcceptTcpClient()
            try { Start-Sleep -Seconds 6 } finally { try { $client.Close() } catch { } }
        }
        $server = New-TestRawHttpServer -Handler $silentServer
        $partialPath = Join-Path $testRoot ('connect-' + [Guid]::NewGuid().ToString('N') + '.partial')
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $failed = $false
            try {
                Invoke-Cf7ArtifactStreamAttempt -BlobUri ("http://127.0.0.1:$($server.Port)/blob") -PartialPath $partialPath `
                    -ExpectedSize 1048576 -UseProxy $false -TimeoutSeconds 120 -ConnectTimeoutSeconds 1 -StallTimeoutSeconds 10
            } catch { $failed = $true }
            $watch.Stop()
            Assert-Test $failed 'a header-less connection must fail the attempt'
            Assert-Test ($watch.Elapsed.TotalSeconds -lt 30) "connect watchdog took too long: $($watch.Elapsed.TotalSeconds)s"
            Assert-Test (-not (Test-Path -LiteralPath $partialPath)) 'connect failure must not create a partial file'
        } finally {
            Close-TestRawHttpServer $server
        }
    }

    Run-Test 'redirect probe reports the winning route and fails closed without candidates' {
        $redirectServer = {
            param($listener)
            $client = $listener.AcceptTcpClient()
            try {
                $stream = $client.GetStream()
                $buffer = New-Object byte[] 65536
                $header = ''
                while (-not $header.Contains("`r`n`r`n")) {
                    $read = $stream.Read($buffer, 0, $buffer.Length)
                    if ($read -le 0) { return }
                    $header += [Text.Encoding]::ASCII.GetString($buffer, 0, $read)
                }
                $head = [Text.Encoding]::ASCII.GetBytes("HTTP/1.1 302 Found`r`nLocation: https://example.invalid/payload.zip`r`nContent-Length: 0`r`nConnection: close`r`n`r`n")
                $stream.Write($head, 0, $head.Length)
                $stream.Flush()
            } finally {
                try { $client.Close() } catch { }
            }
        }
        $server = New-TestRawHttpServer -Handler $redirectServer
        try {
            $probe = Get-Cf7ArtifactRedirect -DownloadUri ([Uri]"http://127.0.0.1:$($server.Port)/actions/artifacts/1/zip") `
                -Token 'fixture-token' -RouteCandidates @('direct') -TimeoutSeconds 10
            Assert-Test ($probe.Route -eq 'direct') 'redirect probe must report the route that produced the redirect'
            Assert-Test ($probe.Redirect.Host -eq 'example.invalid') 'redirect probe must surface the redirect target'
        } finally {
            Close-TestRawHttpServer $server
        }
        $closedListener = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, 0)
        $closedListener.Start()
        $closedPort = ([Net.IPEndPoint]$closedListener.LocalEndpoint).Port
        $closedListener.Stop()
        $failed = $false
        try {
            Get-Cf7ArtifactRedirect -DownloadUri ([Uri]"http://127.0.0.1:$closedPort/actions/artifacts/1/zip") `
                -Token 'fixture-token' -RouteCandidates @('direct') -TimeoutSeconds 5 | Out-Null
        } catch { $failed = $true }
        Assert-Test $failed 'redirect probe must fail closed when every route candidate fails'
    }

    Run-Test 'keeps the unified-route resumable HTTPS transport contract explicit in the helper source' {
        $source = Get-Content -LiteralPath $script:helperSource -Raw -Encoding UTF8
        foreach ($required in @(
            'StatusCode]::PartialContent',
            'ContentRange',
            '[IO.FileMode]::CreateNew',
            '[IO.FileMode]::Append',
            'Artifact bytes received=',
            'Get-Cf7ArtifactRedirect',
            'Resolve-Cf7ArtifactTransportMode',
            'Get-Cf7ArtifactRouteCandidates',
            'github-artifact-route.v1.json',
            'CF7_GITHUB_ARTIFACT_TRANSPORT',
            '$connectWatchdog.CancelAfter',
            '$stallWatchdog.CancelAfter',
            'CreateLinkedTokenSource',
            '-UseProxy ($route -eq ''proxy'')',
            'Route = $route',
            'Save-Cf7ArtifactRouteCache',
            'Clear-Cf7ArtifactRouteCache',
            'Expand-Cf7AttestationArtifactSafely',
            'runtime-cloud-attestation-',
            '-WithoutCandidateArchive'
        )) {
            Assert-Test ($source.Contains($required)) "helper source lacks transport contract token: $required"
        }
        Assert-Test (-not $source.Contains('($attempt % 2) -eq 0')) 'odd/even proxy alternation must be gone'
    }
} finally {
    $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot).TrimEnd('\')
    if ($resolvedTestRoot.StartsWith($tempBase + '\', [StringComparison]::OrdinalIgnoreCase) -and
            (Split-Path -Leaf $resolvedTestRoot).StartsWith('cf7-runtime-github-helper-tests-', [StringComparison]::Ordinal)) {
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "[RuntimeGitHubBuildHelperTests] passed=$passed failed=$failed"
if ($failed -ne 0) { exit 1 }
