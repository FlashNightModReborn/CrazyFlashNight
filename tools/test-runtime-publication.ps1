# Publication transport and ordering integration test. All Git processes use
# temporary local repositories. No GitHub workflow, signing key or deployed game
# is used. Only the two expensive producer-proof / byte-install operations are
# substituted; the orchestrator, queue loader, classifier and admission are real.
param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
. (Join-Path $ProjectRoot 'tools/runtime-build-queue-common.ps1')
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('cf7-publication-' + [guid]::NewGuid().ToString('N'))
$repo = Join-Path $fixture 'publisher'
$origin = Join-Path $fixture 'origin.git'
$racer = Join-Path $fixture 'collaborator'
$queue = Join-Path $fixture 'queue'
$candidate = Join-Path $fixture 'candidate'
$receipt = Join-Path $fixture 'policy.txt'
$utf8 = New-Object Text.UTF8Encoding($false)

function Write-Text([string]$Path, [string]$Text) {
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    [IO.File]::WriteAllText($Path, $Text, $utf8)
}
function Invoke-Git([string]$Location, [string[]]$Arguments) {
    $result = @(& git -C $Location @Arguments)
    if ($LASTEXITCODE -ne 0) { throw "Fixture git $($Arguments[0]) failed in $Location." }
    return $result
}
function Assert-Expected([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Get-Record([string]$Source, [string]$Identity, [string]$Closure) {
    [ordered]@{
        schema='cf7-runtime-release-consensus.v2'; sourceCommitOid=$Source
        releaseTreeOid=(Invoke-Git $repo @('rev-parse',"$Source^{tree}"))
        buildIdentityHash=$Identity; payloadClosureHash=$Closure; attestations=@()
    }
}
function New-Request([string]$Source, [string]$Identity) {
    $tree = Invoke-Git $repo @('rev-parse',"$Source^{tree}")
    $policy = Get-Cf7QueueFileSha256 -Path $receipt
    $id = Get-Cf7RuntimeRequestId -ReleaseTreeOid $tree -PolicyHash $policy
    $directory = Get-Cf7RuntimeRequestDirectory -QueueRoot $queue -RequestId $id
    [void][IO.Directory]::CreateDirectory($directory)
    $bundle = Join-Path $directory 'source.bundle'
    # A real Git bundle with exact S as its single advertised tip.
    $ref = 'refs/cf7/publication-test/' + $Source
    Invoke-Git $repo @('update-ref',$ref,$Source) | Out-Null
    Invoke-Git $repo @('bundle','create',$bundle,$ref) | Out-Null
    $request = [ordered]@{
        schema='cf7-runtime-build-request.v2';requestId=$id;sourceKind='Treeish'
        releaseTreeOid=$tree;sourceCommitOid=$Source;requestCommitOid=$Source;bundleTreeOid=$tree
        artifactSourceHash=('1' * 64);producerRecipeHash=('2' * 64);toolchainLockHash=('3' * 64)
        policyHash=$policy;buildIdentityHash=$Identity;bundleFile='source.bundle'
        bundleSha256=(Get-Cf7QueueFileSha256 $bundle);requiredQuorum=2;createdAtUtc='2026-01-01T00:00:00Z'
    }
    Write-Text (Join-Path $directory 'request.json') ($request | ConvertTo-Json)
    return $id
}
function Invoke-Publication([string]$Run, [string]$Id) {
    $states = @(& (Join-Path $repo 'tools/invoke-runtime-publication.ps1') -ProjectRoot $repo -PublicationRoot (Join-Path $fixture $Run) -QueueRoot $queue -RequestId $Id -PolicyReceiptPath $receipt -CandidateRoot $candidate | ForEach-Object {
        if ($null -ne $_.PSObject.Properties['state']) { $_ } else { Write-Host $_ }
    })
    Assert-Expected ($states.Count -eq 1) 'Publication must return exactly one terminal state.'
    return $states[0]
}
try {
    [void][IO.Directory]::CreateDirectory($repo)
    Invoke-Git $fixture @('init','--quiet','--template=','--bare','--initial-branch=main',$origin) | Out-Null
    Invoke-Git $repo @('init','--quiet','--template=','--initial-branch=main') | Out-Null
    Invoke-Git $origin @('config','core.hooksPath',(Join-Path $origin 'hooks')) | Out-Null
    Invoke-Git $repo @('config','core.hooksPath',(Join-Path $repo '.git/hooks')) | Out-Null
    foreach ($location in @($origin,$repo)) {
        Invoke-Git $location @('config','user.name','Publication fixture') | Out-Null
        Invoke-Git $location @('config','user.email','publication@example.invalid') | Out-Null
        Invoke-Git $location @('config','core.autocrlf','false') | Out-Null
    }
    # Plain filesystem paths prevent credentials or network access.
    Invoke-Git $repo @('remote','add','origin',$origin) | Out-Null
    [void][IO.Directory]::CreateDirectory((Join-Path $repo 'tools'))
    foreach ($tool in @('invoke-runtime-publication','runtime-release-admission','runtime-build-queue-common',
            'runtime-build-v2-common','runtime-build-attestation-v2-common','classify-runtime-release-state')) {
        Copy-Item -LiteralPath (Join-Path $ProjectRoot "tools/$tool.ps1") -Destination (Join-Path $repo "tools/$tool.ps1")
    }
    Write-Text (Join-Path $repo 'tools/promote-runtime-bundle.ps1') @'
param($ProjectRoot,$QueueRoot,$RequestId,$PolicyReceiptPath,$CandidateRoot)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'runtime-build-queue-common.ps1')
. (Join-Path $PSScriptRoot 'runtime-release-admission.ps1')
. (Join-Path $PSScriptRoot 'runtime-build-attestation-v2-common.ps1')
$request = Read-Cf7RuntimeBuildRequest $QueueRoot $RequestId
if ((Get-Cf7QueueFileSha256 $PolicyReceiptPath) -cne $request.policyHash) { throw 'Unexpected fixture receipt.' }
$path = Join-Path $ProjectRoot 'config/build/runtime-release-consensus.json'
$previous = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
$payload = Join-Path $CandidateRoot 'payload.txt'
$closure = Get-Cf7QueueFileSha256 $payload
try { Assert-Cf7RuntimeReleaseSuccessor $ProjectRoot $previous $request.sourceCommitOid $request.buildIdentityHash $closure }
catch {
    [IO.File]::WriteAllText((Join-Path $QueueRoot 'fixture-rejection.txt'), $_.Exception.Message)
    throw
}
$head = [string](& git -C $ProjectRoot rev-parse HEAD)
Add-Content -LiteralPath (Join-Path $QueueRoot 'fixture-install.log') -Encoding UTF8 -Value "$head $RequestId $closure"
if ($previous.sourceCommitOid -ceq $request.sourceCommitOid) { exit 0 }
Copy-Item -LiteralPath $payload -Destination (Join-Path $ProjectRoot 'runtime/payload.txt') -Force
$next = [ordered]@{
    schema='cf7-runtime-release-consensus.v2';sourceCommitOid=$request.sourceCommitOid;releaseTreeOid=$request.releaseTreeOid
    buildIdentityHash=$request.buildIdentityHash;payloadClosureHash=$closure;attestations=@()
}
[IO.File]::WriteAllText($path, ($next | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
'@
    # Producer cryptography has dedicated suites. Even in this substitute, verify
    # the selected index bytes, source tree and exact tag, for both parent and P.
    Write-Text (Join-Path $repo 'tools/verify-runtime-consensus.ps1') @'
param($ProjectRoot,[switch]$Staged,[switch]$HistoricalSource)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'runtime-release-admission.ps1')
. (Join-Path $PSScriptRoot 'runtime-build-attestation-v2-common.ps1')
. (Join-Path $PSScriptRoot 'runtime-build-queue-common.ps1')
if (-not $Staged -or -not $env:GIT_INDEX_FILE) { throw 'Fixture requires a revision-specific index.' }
$recordBytes = Invoke-Cf7GitBinary @('cat-file','blob',':config/build/runtime-release-consensus.json')
$record = [Text.Encoding]::UTF8.GetString($recordBytes) | ConvertFrom-Json
$null = Resolve-Cf7RuntimeRecordSource $ProjectRoot $record
if ((Get-Cf7QueueSha256Bytes (Invoke-Cf7GitBinary @('cat-file','blob',':runtime/payload.txt'))) -cne $record.payloadClosureHash) {
    throw 'Fixture deployed bytes do not match its record.'
}
'@
    Write-Text (Join-Path $repo 'config/build/runtime-github-builder.v2.json') '{"sourceRefNamespace":"refs/tags/runtime-build-v2/"}'
    foreach ($config in @('native-change-gate.v1.json','main-branch-admission.v2.json')) {
        Copy-Item -LiteralPath (Join-Path $ProjectRoot "config/build/$config") -Destination (Join-Path $repo "config/build/$config")
    }
    $domains = [ordered]@{}
    foreach ($name in @('artifactSource','producerRecipe','toolchainLock','policy')) {
        $domains[$name] = @{ fixedFiles=@(); trees=@() }
    }
    $descriptor = [ordered]@{
        schema='cf7-runtime-inputs.v2'; domains=$domains
        payload=@{ fixedRoots=@('CRAZYFLASHER7MercenaryEmpire.exe'); trees=@('runtime'); excludePaths=@(); excludePrefixes=@() }
    }
    Write-Text (Join-Path $repo 'config/build/runtime-inputs.v2.json') ($descriptor | ConvertTo-Json -Depth 8)
    Write-Text (Join-Path $repo 'CRAZYFLASHER7MercenaryEmpire.exe') 'fixture entry'
    Write-Text (Join-Path $repo 'runtime/cf7-runtime-manifest.tsv') "cf7-runtime-manifest-v2`nfixture`n"
    Write-Text (Join-Path $repo 'runtime/payload.txt') 'previous deployment'
    Write-Text $receipt 'test-only policy receipt'
    Write-Text (Join-Path $candidate 'payload.txt') 'the same frozen candidate bytes on both attempts'
    Invoke-Git $repo @('add','--','.') | Out-Null
    Invoke-Git $repo @('commit','--quiet','-m','original source') | Out-Null
    $oldSource = Invoke-Git $repo @('rev-parse','HEAD')
    Invoke-Git $repo @('tag',("runtime-build-v2/$oldSource"),$oldSource) | Out-Null
    $record = Get-Record $oldSource ('5' * 64) (Get-Cf7QueueFileSha256 (Join-Path $repo 'runtime/payload.txt'))
    Write-Text (Join-Path $repo 'config/build/runtime-release-consensus.json') ($record | ConvertTo-Json)
    Write-Text (Join-Path $repo 'docs/reports/source.md') 'new source'
    Invoke-Git $repo @('add','--','.') | Out-Null
    Invoke-Git $repo @('commit','--quiet','-m','candidate source') | Out-Null
    $source = Invoke-Git $repo @('rev-parse','HEAD')
    Invoke-Git $repo @('tag','-a','-m','immutable source',("runtime-build-v2/$source"),$source) | Out-Null
    Invoke-Git $repo @('push','--quiet','--no-follow-tags','origin','main') | Out-Null
    $request = New-Request $source ('6' * 64)
    $oldRequest = New-Request $oldSource ('5' * 64)
    $missingTag = $false
    try { $null = Invoke-Publication 'local-tag-only' $request } catch { $missingTag = $_.Exception.Message -like '*protected remote source tag*' }
    Assert-Expected ($missingTag -and -not (Test-Path (Join-Path $queue 'fixture-install.log'))) 'A tag found only on the publisher must not authorize installation.'
    Invoke-Git $repo @('push','--quiet','--tags','origin') | Out-Null
    # Simulate a separate publisher that has not fetched the previous release tag.
    Invoke-Git $repo @('update-ref','-d',"refs/tags/runtime-build-v2/$oldSource") | Out-Null
    Invoke-Git $fixture @('clone','--quiet','--template=',$origin,$racer) | Out-Null
    Invoke-Git $racer @('config','core.hooksPath',(Join-Path $racer '.git/hooks')) | Out-Null
    Invoke-Git $racer @('config','user.name','Second writer') | Out-Null
    Invoke-Git $racer @('config','user.email','second@example.invalid') | Out-Null
    Write-Text (Join-Path $racer 'docs/reports/parallel.md') 'independent collaborator'
    Invoke-Git $racer @('add','--','docs') | Out-Null
    Invoke-Git $racer @('commit','--quiet','-m','concurrent document') | Out-Null
    $concurrent = Invoke-Git $racer @('rev-parse','HEAD')

    # Race after the first client has observed H, using a second client and a real
    # push. Once P wins, move main one step further before its client re-queries.
    $quoteRacer = $racer.Replace('\','/').Replace("'", "'\''")
    $raceHook = @'
#!/bin/sh
set -eu
unset $(git rev-parse --local-env-vars)
if mkdir 'RACER_PATH/race-started' 2>/dev/null; then
  git -C 'RACER_PATH' push --quiet origin main
fi
'@
    Write-Text (Join-Path $repo '.git/hooks/pre-push') ($raceHook.Replace('RACER_PATH',$quoteRacer).Replace("`r",'') + "`n")
    $advanceHook = @'
#!/bin/sh
set -eu
while read before after ref; do
  test "$ref" = refs/heads/main || continue
  git diff --quiet "$before" "$after" -- config/build/runtime-release-consensus.json && continue
  successor=$(echo 'independent later head' | git commit-tree "$after^{tree}" -p "$after")
  git update-ref refs/heads/main "$successor" "$after"
done
'@
    Write-Text (Join-Path $origin 'hooks/post-receive') ($advanceHook.Replace("`r",'') + "`n")
    $result = Invoke-Publication 'race' $request
    Assert-Expected ($result.state -ceq 'published' -and $result.parent -ceq $concurrent) 'Race loser must re-admit the original candidate on the winning parent.'
    $first = Invoke-Git (Join-Path $fixture 'race/attempt-1') @('rev-parse','HEAD')
    Assert-Expected ((Invoke-Git $repo @('rev-parse',"$first^")) -ceq $source) 'First P and collaborator must have the same observed parent.'
    Assert-Expected ($first -cne $result.commit -and (Invoke-Git $repo @('rev-parse',"$($result.commit)^")) -ceq $concurrent) 'Retry requires a new P with its actual parent.'
    Assert-Expected ($result.head -cne $result.commit -and (Invoke-Git $origin @('rev-parse','refs/heads/main')) -ceq $result.head) 'A later remote head must retain P and succeed.'
    Invoke-Git $repo @('merge-base','--is-ancestor',$result.commit,$result.head) | Out-Null
    $closure = Get-Cf7QueueFileSha256 (Join-Path $candidate 'payload.txt')
    $installs = @(Get-Content -LiteralPath (Join-Path $queue 'fixture-install.log') -Encoding UTF8)
    Assert-Expected ($installs.Count -eq 2 -and $installs[0] -ceq "$source $request $closure" -and $installs[1] -ceq "$concurrent $request $closure") 'Both attempts must reuse the identical request and candidate bytes.'
    $same = Invoke-Publication 'already' $request
    Assert-Expected ($same.state -ceq 'already-deployed' -and $same.head -ceq $result.head) 'Repeated valid candidate must complete without another publication.'
    $blocked = $false
    try { $null = Invoke-Publication 'stale' $oldRequest } catch { $blocked = $_.Exception.Message -like '*Promotion rejected*' }
    $reason = Get-Content -LiteralPath (Join-Path $queue 'fixture-rejection.txt') -Raw
    Assert-Expected ($blocked -and $reason -like '*precedes or diverges from deployed source*' -and
        (Invoke-Git $origin @('rev-parse','refs/heads/main')) -ceq $result.head) 'An older source must not overwrite the verified winner.'
    # A separate local-only ref is correct, but its namesake on the test origin
    # points elsewhere. Reject it before invoking the installer.
    $otherTag = "runtime-build-v2/$concurrent"
    Invoke-Git $repo @('tag',$otherTag,$concurrent) | Out-Null
    Invoke-Git $origin @('tag',$otherTag,$oldSource) | Out-Null
    $otherRequest = New-Request $concurrent ('7' * 64)
    $wrongTag = $false
    try { $null = Invoke-Publication 'different-remote-tag' $otherRequest } catch { $wrongTag = $_.Exception.Message -like '*remote tag does not match*' }
    Assert-Expected ($wrongTag -and (Invoke-Git $origin @('rev-parse','refs/heads/main')) -ceq $result.head) 'Remote tag target must match the request exactly.'
    Write-Host '[RuntimePublicationTest] PASS remote tag binding, annotated tag peeling, same-parent race, original request retry, remote descendant, idempotency, and stale source'
} finally {
    $resolved = [IO.Path]::GetFullPath($fixture)
    $prefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\cf7-publication-'
    if ($resolved.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -and [IO.Directory]::Exists($resolved)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
