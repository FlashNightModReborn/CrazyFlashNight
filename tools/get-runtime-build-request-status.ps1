param(
    [string]$ProjectRoot,
    [string]$QueueRoot,
    [string]$RequestId,
    [string]$RegistryPath,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
if (-not $ProjectRoot) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
. (Join-Path $ProjectRoot 'tools\runtime-build-common.ps1')
. (Join-Path $ProjectRoot 'tools\runtime-build-v2-common.ps1')
. (Join-Path $ProjectRoot 'tools\runtime-build-attestation-v2-common.ps1')
. (Join-Path $ProjectRoot 'tools\runtime-build-queue-common.ps1')

$QueueRoot = Get-Cf7RuntimeQueueRoot -ProjectRoot $ProjectRoot -QueueRoot $QueueRoot
if (-not $RegistryPath) { $RegistryPath = Join-Path $ProjectRoot 'config\build\runtime-builders.v2.json' }
Initialize-Cf7RuntimeQueue -QueueRoot $QueueRoot

$ids = @()
if ($RequestId) {
    Assert-Cf7QueueHash -Name requestId -Value $RequestId
    $ids = @($RequestId.ToUpperInvariant())
} else {
    $ids = @(Get-ChildItem -LiteralPath (Join-Path $QueueRoot 'requests') -Directory |
        Where-Object { -not $_.Name.StartsWith('.') } | Select-Object -ExpandProperty Name | Sort-Object)
}

$rows = @()
foreach ($id in $ids) {
    try {
        $request = Read-Cf7RuntimeBuildRequest -QueueRoot $QueueRoot -RequestId $id
        $state = Get-Cf7RuntimeBuildRequestState -QueueRoot $QueueRoot -Request $request -RegistryPath $RegistryPath
        $rows += [pscustomobject]@{
            requestId=[string]$request.requestId; status=[string]$state.status; quorum=[string]$state.quorum
            buildIdentityHash=[string]$request.buildIdentityHash; releaseTreeOid=[string]$request.releaseTreeOid
            faultDomains=@($state.faultDomains); failures=[int]$state.failures; supersededBy=$state.supersededBy
        }
    } catch {
        $rows += [pscustomobject]@{
            requestId=$id; status='failed'; quorum='0/2'; buildIdentityHash=$null; releaseTreeOid=$null
            faultDomains=@(); failures=1; supersededBy=$null; error=$_.Exception.Message
        }
    }
}

if ($Json) { $rows | ConvertTo-Json -Depth 8 }
else { $rows }

# Stable automation contract: 0=all active requests ready, 10=pending or empty,
# 20=failed/invalid, 30=only superseded requests. Superseded history does not
# poison an otherwise ready active release train.
$activeRows = @($rows | Where-Object { $_.status -ne 'superseded' })
if (@($activeRows | Where-Object { $_.status -eq 'failed' }).Count -gt 0) { exit 20 }
if ($activeRows.Count -eq 0) {
    if ($rows.Count -gt 0) { exit 30 }
    exit 10
}
if (@($activeRows | Where-Object { $_.status -ne 'ready' }).Count -gt 0) { exit 10 }
exit 0
