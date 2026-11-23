# Publish an already independently built candidate. Each attempt uses a private H
# checkout. The ordinary fast-forward push chooses the winner; never rebase P.
[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [Parameter(Mandatory=$true)][string]$PublicationRoot,
    [Parameter(Mandatory=$true)][string]$QueueRoot,
    [Parameter(Mandatory=$true)][string]$RequestId,
    [Parameter(Mandatory=$true)][string]$PolicyReceiptPath,
    [string]$CandidateRoot,
    [string]$ExternalAttestationPath
)
$ErrorActionPreference = 'Stop'
# A private worktree must never inherit another checkout's index or object store.
foreach ($key in @('GIT_INDEX_FILE','GIT_DIR','GIT_WORK_TREE','GIT_COMMON_DIR','GIT_OBJECT_DIRECTORY',
        'GIT_ALTERNATE_OBJECT_DIRECTORIES','GIT_NAMESPACE','GIT_REPLACE_REF_BASE','GIT_SHALLOW_FILE',
        'GIT_QUARANTINE_PATH','GIT_PREFIX','GIT_CONFIG_COUNT','GIT_CONFIG_PARAMETERS')) {
    if ([Environment]::GetEnvironmentVariable($key)) { throw "Publication requires the repository's own Git context: $key is set." }
}
. (Join-Path $PSScriptRoot 'runtime-release-admission.ps1')
. (Join-Path $PSScriptRoot 'runtime-build-queue-common.ps1')
. (Join-Path $PSScriptRoot 'runtime-build-attestation-v2-common.ps1')
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$QueueRoot = (Resolve-Path -LiteralPath $QueueRoot).Path
$PolicyReceiptPath = (Resolve-Path -LiteralPath $PolicyReceiptPath).Path
if ($ExternalAttestationPath) { $ExternalAttestationPath = (Resolve-Path -LiteralPath $ExternalAttestationPath).Path }
if ($CandidateRoot) { $CandidateRoot = (Resolve-Path -LiteralPath $CandidateRoot).Path }
if ($RequestId -notmatch '^[0-9a-fA-F]{64}$') { throw 'Invalid immutable request ID.' }
$request = Read-Cf7RuntimeBuildRequest -QueueRoot $QueueRoot -RequestId $RequestId
if ($request.schema -cne 'cf7-runtime-build-request.v2' -or $request.requestId -cne $RequestId.ToUpperInvariant() -or $request.sourceKind -cne 'Treeish') {
    throw 'Main publication requires a committed immutable request.'
}
$PublicationRoot = [IO.Path]::GetFullPath($PublicationRoot)
if ([IO.File]::Exists($PublicationRoot) -or [IO.Directory]::Exists($PublicationRoot)) {
    throw "Choose a fresh publication directory. Existing evidence is preserved at $PublicationRoot."
}
[void][IO.Directory]::CreateDirectory($PublicationRoot)
$remoteRef = 'refs/heads/main'

function Read-RemoteMain {
    foreach ($delay in @(0,2,5)) {
        if ($delay) { Start-Sleep -Seconds $delay }
        $advertised = @(& git -C $ProjectRoot ls-remote --exit-code --refs origin $remoteRef)
        $remoteStatus = $LASTEXITCODE
        if ($remoteStatus -eq 0) { break }
    }
    if ($remoteStatus -ne 0 -or $advertised.Count -ne 1 -or
        $advertised[0] -cnotmatch '^(?<oid>[0-9a-f]{40}|[0-9a-f]{64})\trefs/heads/main$') {
        throw 'Remote main could not be established. Query the remote before retrying publication.'
    }
    $oid = $Matches.oid
    $local = @(& git -C $ProjectRoot rev-parse --quiet --verify "$oid^{commit}")
    if ($LASTEXITCODE -ne 0 -or $local.Count -ne 1) {
        & git -C $ProjectRoot fetch --quiet --no-tags --no-write-fetch-head origin $oid
        if ($LASTEXITCODE -ne 0) { throw "Cannot fetch observed main commit $oid." }
    }
    return Get-Cf7ReleaseGitOid $ProjectRoot "$oid^{commit}"
}

# A local tag alone cannot establish the protected remote source of a two-X509
# release. Accept the advertised peeled commit for annotated tags as well.
$configBytes = Get-Cf7RuntimeFrozenBlobBytes $ProjectRoot $request.sourceCommitOid 'config/build/runtime-github-builder.v2.json'
$config = [Text.Encoding]::UTF8.GetString($configBytes).TrimStart([char]0xFEFF) | ConvertFrom-Json
$sourceRef = Resolve-Cf7RuntimeGitHubSourceRef -Config $config -SourceCommitOid $request.sourceCommitOid
function Sync-ProtectedSourceTag([string]$sourceRef, [string]$ExpectedSource) {
    $tagRows = @(& git -C $ProjectRoot ls-remote --exit-code origin $sourceRef "$sourceRef^{}")
    if ($LASTEXITCODE -ne 0 -or $tagRows.Count -lt 1 -or $tagRows.Count -gt 2) {
        throw "Cannot establish the protected remote source tag $sourceRef."
    }
    $refs = @{}
    foreach ($row in $tagRows) {
        $parts = $row.Split([char]9)
        if ($parts.Count -ne 2 -or $parts[1] -cnotin @($sourceRef,"$sourceRef^{}") -or $refs.ContainsKey($parts[1])) {
            throw "Unexpected remote tag advertisement for $sourceRef."
        }
        $refs.Add($parts[1],$parts[0])
    }
    $sourceTarget = if ($refs.ContainsKey("$sourceRef^{}")) { $refs["$sourceRef^{}"] } else { $refs[$sourceRef] }
    if (!$refs.ContainsKey($sourceRef) -or ($ExpectedSource -and $sourceTarget -cne $ExpectedSource)) {
        throw "Protected remote tag does not match immutable request source $($ExpectedSource)."
    }
    $localTag = @(& git -C $ProjectRoot rev-parse --quiet --verify $sourceRef)
    if ($LASTEXITCODE -ne 0) {
        & git -C $ProjectRoot fetch --quiet --no-tags --no-write-fetch-head origin "${sourceRef}:$sourceRef"
        if ($LASTEXITCODE -ne 0) { throw "Cannot fetch protected tag $sourceRef." }
    } elseif ($localTag.Count -ne 1 -or $localTag[0] -cne $refs[$sourceRef]) {
        throw "Local and remote protected tag objects disagree: $sourceRef"
    }
    if ((Get-Cf7ReleaseGitOid $ProjectRoot "$sourceRef^{commit}") -cne $sourceTarget) { throw "Protected tag moved: $sourceRef" }
}

Sync-ProtectedSourceTag $sourceRef $request.sourceCommitOid

for ($attempt = 1; $attempt -le 3; $attempt++) {
    $parent = Read-RemoteMain
    # Another publisher may have introduced a source tag absent in this clone.
    $previousBytes = Get-Cf7RuntimeFrozenBlobBytes $ProjectRoot $parent 'config/build/runtime-release-consensus.json'
    $previous = [Text.Encoding]::UTF8.GetString($previousBytes).TrimStart([char]0xFEFF) | ConvertFrom-Json
    if ($previous.schema -cne 'cf7-runtime-release-consensus.v2' -or $previous.releaseTreeOid -cnotmatch '\A(?:[0-9a-f]{40}|[0-9a-f]{64})\z') {
        throw 'Publication parent lacks a frozen v2 consensus.'
    }
    $configBytes = Get-Cf7RuntimeFrozenBlobBytes $ProjectRoot $previous.releaseTreeOid 'config/build/runtime-github-builder.v2.json'
    $previousConfig = [Text.Encoding]::UTF8.GetString($configBytes).TrimStart([char]0xFEFF) | ConvertFrom-Json
    $previousSource = [string]$previous.sourceCommitOid
    $previousRef = if ($previousSource) {
        Resolve-Cf7RuntimeGitHubSourceRef -Config $previousConfig -SourceCommitOid $previousSource
    } else {
        Resolve-Cf7RuntimeGitHubSourceRef -Config $previousConfig -ValidateOnly
    }
    if (-not $previousRef) { throw 'Deployment parent lacks a resolvable protected source tag.' }
    if ($previousRef -cne $sourceRef) { Sync-ProtectedSourceTag $previousRef $previousSource }
    # Read the proposed source with the reviewed implementation first. The deployed
    # directory may vary; its old proofs and actual bytes are checked by promotion.
    $admission = @{ ProjectRoot=$ProjectRoot; SourceCommitOid=$request.sourceCommitOid
        ReleaseTreeOid=$request.releaseTreeOid; HeadCommitOid=$parent; AllowVerifiedDeploymentChanges=$true }
    Assert-Cf7RuntimeReleaseAdmission @admission
    $checkout = Join-Path $PublicationRoot "attempt-$attempt"
    & git -C $ProjectRoot worktree add --quiet --detach $checkout $parent
    if ($LASTEXITCODE -ne 0) { throw "Failed to create private publication checkout for $parent." }
    $run = @('-NoProfile','-InputFormat','None','-ExecutionPolicy','Bypass','-File',(Join-Path $checkout 'tools/promote-runtime-bundle.ps1'),
        '-ProjectRoot',$checkout,'-QueueRoot',$QueueRoot,'-RequestId',$RequestId,'-PolicyReceiptPath',$PolicyReceiptPath)
    if ($CandidateRoot) { $run += @('-CandidateRoot',$CandidateRoot) }
    if ($ExternalAttestationPath) { $run += @('-ExternalAttestationPath',$ExternalAttestationPath) }
    & powershell.exe @run | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Promotion rejected the candidate at $parent. Evidence: $checkout" }
    if ((Get-Cf7ReleaseGitOid $checkout 'HEAD^{commit}') -cne $parent) { throw 'Publication checkout moved during installation.' }
    & git -C $checkout add -A -- CRAZYFLASHER7MercenaryEmpire.exe runtime config/build/runtime-release-consensus.json
    if ($LASTEXITCODE -ne 0) { throw 'Cannot stage the verified deployment.' }
    & git -C $checkout diff --cached --quiet
    $stageStatus = $LASTEXITCODE
    if ($stageStatus -eq 0) {
        # Existing deployment was validated under the promotion lock. Ensure the
        # observed main still contains H before reporting idempotent completion.
        $now = Read-RemoteMain
        if ($now -cne $parent) { continue }
        return [pscustomobject]@{ state='already-deployed'; source=$request.sourceCommitOid; head=$parent; worktree=$checkout }
    }
    if ($stageStatus -ne 1) { throw 'Cannot inspect staged deployment.' }
    & git -C $checkout commit --quiet -m "晋升 Runtime v2 双签候选 $($request.sourceCommitOid.Substring(0,12))，回归标准启动与完整闭包"
    if ($LASTEXITCODE -ne 0) { throw 'Cannot construct the publication commit.' }
    $publication = Get-Cf7ReleaseGitOid $checkout 'HEAD^{commit}'
    $verified = @('-NoProfile','-InputFormat','None','-ExecutionPolicy','Bypass','-File',(Join-Path $checkout 'tools/classify-runtime-release-state.ps1'),
        '-ProjectRoot',$checkout,'-Mode','Audit','-BaseRevision',$parent,'-HeadRevision',$publication)
    & powershell.exe @verified | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Private publication commit failed independent audit: $publication" }
    Write-Host "[RuntimePublication] attempt=$attempt source=$($request.sourceCommitOid) parent=$parent commit=$publication"
    $preference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & git -C $checkout push --porcelain origin "$($publication):$remoteRef" | Out-Host
        $pushStatus = $LASTEXITCODE
    } finally { $ErrorActionPreference = $preference }
    # Even a failed transport may already have advanced the remote. Query before
    # classifying the result. A new attempt always begins with admission at fresh H.
    $now = Read-RemoteMain
    & git -C $ProjectRoot merge-base --is-ancestor $publication $now
    $contains = $LASTEXITCODE
    if ($contains -eq 0) {
        return [pscustomobject]@{ state='published'; source=$request.sourceCommitOid; parent=$parent; commit=$publication; head=$now; worktree=$checkout }
    }
    & git -C $ProjectRoot merge-base --is-ancestor $parent $now
    if ($LASTEXITCODE -ne 0 -or $contains -ne 1 -or $pushStatus -eq 0 -or $now -ceq $parent) {
        throw "Remote publication not confirmed. Local commit $publication and evidence $checkout retained. Observed main: $now."
    }
}
throw 'Remote main changed in every publication window. Keep the original candidate and retry admission on the latest main.'
