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

function Add-TestZipEntry($Archive, [string]$Path, [string]$Content) {
    $entry = $Archive.CreateEntry($Path, [IO.Compression.CompressionLevel]::Optimal)
    $stream = $entry.Open()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Content)
        $stream.Write($bytes, 0, $bytes.Length)
    } finally { $stream.Dispose() }
}

function New-TestCandidateZip([string]$Path, [switch]$MaliciousTraversal) {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::Open($Path, [IO.Compression.ZipArchiveMode]::Create)
    try {
        Add-TestZipEntry $archive 'CRAZYFLASHER7MercenaryEmpire.exe' 'fixture-bootstrap'
        if ($MaliciousTraversal) {
            Add-TestZipEntry $archive '../escaped.txt' 'must-not-extract'
        } else {
            Add-TestZipEntry $archive 'runtime/cf7-runtime-manifest.tsv' "cf7-runtime-manifest-v2`n"
            Add-TestZipEntry $archive 'runtime/CRAZYFLASHER7MercenaryEmpire.Core.dll' 'fixture-core'
            Add-TestZipEntry $archive 'runtime-build-metadata.v2.json' '{"schema":"fixture"}'
        }
    } finally { $archive.Dispose() }
}

function New-TestFixture(
    [switch]$MaliciousTraversal,
    [string]$Conclusion = 'success',
    [int]$CompleteAfterViews = 2,
    [string]$HeadBranch = 'main',
    [string]$SourceRef = 'refs/heads/main'
) {
    $caseRoot = Join-Path $script:testRoot ([Guid]::NewGuid().ToString('N'))
    $projectRoot = Join-Path $caseRoot 'repo'
    $controlRoot = Join-Path $caseRoot 'control'
    $artifactRoot = Join-Path $controlRoot 'artifact'
    New-Item -ItemType Directory -Path (Join-Path $projectRoot 'tools'),(Join-Path $projectRoot 'config\build'),$artifactRoot -Force | Out-Null
    Copy-Item -LiteralPath $script:helperSource -Destination (Join-Path $projectRoot 'tools\invoke-runtime-github-build.ps1')

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
    [string]$OutputPath
)
$ErrorActionPreference = 'Stop'
foreach ($path in @($EnvelopePath,$BundlePath,(Join-Path $CandidateRoot 'CRAZYFLASHER7MercenaryEmpire.exe'),(Join-Path $CandidateRoot 'runtime\cf7-runtime-manifest.tsv'))) {
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
[IO.File]::WriteAllText($env:CF7_FAKE_VERIFIER_MARKER, 'called', (New-Object Text.UTF8Encoding($false)))
Write-Output $wrapper
'@

    Set-TestFile (Join-Path $controlRoot 'fake-gh.ps1') @'
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$CliArgs)
$ErrorActionPreference = 'Stop'
$statePath = $env:CF7_FAKE_GH_STATE
$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
[IO.File]::AppendAllText([string]$state.logPath, (($CliArgs | ConvertTo-Json -Compress) + "`n"), (New-Object Text.UTF8Encoding($false)))
function Save-State { [IO.File]::WriteAllText($statePath, (($state | ConvertTo-Json -Depth 8) + "`n"), (New-Object Text.UTF8Encoding($false))) }
function New-Run([Int64]$Id, [string]$Status, [AllowNull()][string]$RunConclusion, [string]$CreatedAt) {
    return [pscustomobject][ordered]@{
        databaseId=$Id; displayTitle=('Runtime cloud builder ' + [string]$state.sourceCommitOid)
        headBranch=[string]$state.headBranch; headSha=[string]$state.sourceCommitOid; status=$Status; conclusion=$RunConclusion
        createdAt=$CreatedAt; event='workflow_dispatch'; url=('https://example.invalid/runs/' + $Id)
    }
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
    if ([bool]$state.includePreexisting) { $runs += New-Run 4000 'completed' 'success' '2026-01-01T00:00:00Z' }
    if ([bool]$state.dispatched) { $runs += New-Run ([Int64]$state.runId) 'queued' $null ([string]$state.createdAt) }
    Write-Output (ConvertTo-Json -InputObject @($runs) -Depth 6 -Compress)
    exit 0
}
if ($CliArgs.Count -ge 3 -and $CliArgs[0] -eq 'run' -and $CliArgs[1] -eq 'view') {
    if ([Int64]$CliArgs[2] -ne [Int64]$state.runId) { exit 42 }
    $state.viewCount = [int]$state.viewCount + 1
    $complete = [int]$state.viewCount -ge [int]$state.completeAfterViews
    $run = New-Run ([Int64]$state.runId) $(if($complete){'completed'}else{'in_progress'}) $(if($complete){[string]$state.conclusion}else{$null}) ([string]$state.createdAt)
    Save-State
    Write-Output ($run | ConvertTo-Json -Depth 6 -Compress)
    exit 0
}
if ($CliArgs.Count -ge 3 -and $CliArgs[0] -eq 'run' -and $CliArgs[1] -eq 'download') {
    if ([Int64]$CliArgs[2] -ne [Int64]$state.runId) { exit 43 }
    $dirIndex = [Array]::IndexOf($CliArgs, '--dir')
    $nameIndex = [Array]::IndexOf($CliArgs, '--name')
    if ($dirIndex -lt 0 -or $nameIndex -lt 0 -or [string]$CliArgs[$nameIndex + 1] -cne ('runtime-cloud-builder-' + [string]$state.sourceCommitOid)) { exit 44 }
    $destination = [string]$CliArgs[$dirIndex + 1]
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    Get-ChildItem -LiteralPath ([string]$state.artifactRoot) -File | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $destination $_.Name) }
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

    Set-TestFile (Join-Path $artifactRoot 'runtime-build-envelope.v2.json') (([ordered]@{ sourceCommitOid=$sourceCommit } | ConvertTo-Json -Compress) + "`n")
    Set-TestFile (Join-Path $artifactRoot 'runtime-build-envelope.v2.sigstore.json') '{"bundle":"fixture"}'
    New-TestCandidateZip -Path (Join-Path $artifactRoot 'runtime-candidate.v2.zip') -MaliciousTraversal:$MaliciousTraversal
    $statePath = Join-Path $controlRoot 'state.json'
    $logPath = Join-Path $controlRoot 'calls.jsonl'
    $markerPath = Join-Path $controlRoot 'verifier.marker'
    $state = [ordered]@{
        sourceCommitOid=$sourceCommit; runId=4242; dispatched=$false; includePreexisting=$true
        headBranch=$HeadBranch
        viewCount=0; completeAfterViews=$CompleteAfterViews; conclusion=$Conclusion
        createdAt=[DateTime]::UtcNow.ToString('o'); artifactRoot=$artifactRoot; logPath=$logPath
    }
    Set-TestFile $statePath (($state | ConvertTo-Json -Depth 6) + "`n")
    Set-TestFile $logPath ''
    return [pscustomobject]@{
        CaseRoot=$caseRoot; ProjectRoot=$projectRoot; ControlRoot=$controlRoot
        SourceCommit=$sourceCommit; FakeGh=(Join-Path $controlRoot 'fake-gh.cmd')
        StatePath=$statePath; LogPath=$logPath; MarkerPath=$markerPath; OutputRoot=(Join-Path $caseRoot 'output')
    }
}

function Invoke-TestHelper($Fixture) {
    $arguments = @(
        '-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $Fixture.ProjectRoot 'tools\invoke-runtime-github-build.ps1'),
        '-ProjectRoot',$Fixture.ProjectRoot,'-SourceCommitOid',$Fixture.SourceCommit,
        '-OutputRoot',$Fixture.OutputRoot,'-GitHubCliPath',$Fixture.FakeGh,
        '-DiscoveryTimeoutSeconds','5','-RunTimeoutSeconds','30','-PollSeconds','1'
    )
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
    Run-Test 'dispatches exact SHA, ignores the preexisting same-SHA run, and produces a verified wrapper' {
        $fixture = New-TestFixture -HeadBranch 'runtime-build-v2/test-release' -SourceRef 'refs/tags/runtime-build-v2/test-release'
        $result = Invoke-TestHelper $fixture
        Assert-Test ($result.ExitCode -eq 0) $result.Output
        $resultPath = Join-Path $fixture.OutputRoot 'run-4242\runtime-github-build-result.v2.json'
        Assert-Test (Test-Path -LiteralPath $resultPath -PathType Leaf) 'result metadata missing'
        $metadata = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
        Assert-Test ([Int64]$metadata.runId -eq 4242) 'helper selected the preexisting run instead of the new run'
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
        $download = @($calls | Where-Object { $_[0] -eq 'run' -and $_[1] -eq 'download' })
        Assert-Test ($download.Count -eq 1 -and [string]$download[0][2] -eq '4242') 'signed artifact was not downloaded from the selected run id'
    }

    Run-Test 'rejects ZIP traversal before calling the provenance verifier' {
        $fixture = New-TestFixture -MaliciousTraversal -CompleteAfterViews 1
        $result = Invoke-TestHelper $fixture
        Assert-Test ($result.ExitCode -ne 0) 'malicious candidate archive unexpectedly passed'
        Assert-Test ($result.Output -match 'Unsafe candidate archive path|path segments') $result.Output
        Assert-Test (-not (Test-Path -LiteralPath $fixture.MarkerPath)) 'verifier must not run after unsafe extraction'
        Assert-Test (-not (Test-Path -LiteralPath (Join-Path $fixture.OutputRoot 'run-4242\escaped.txt'))) 'ZIP traversal wrote outside candidate root'
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
} finally {
    $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot).TrimEnd('\')
    if ($resolvedTestRoot.StartsWith($tempBase + '\', [StringComparison]::OrdinalIgnoreCase) -and
            (Split-Path -Leaf $resolvedTestRoot).StartsWith('cf7-runtime-github-helper-tests-', [StringComparison]::Ordinal)) {
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "[RuntimeGitHubBuildHelperTests] passed=$passed failed=$failed"
if ($failed -ne 0) { exit 1 }
