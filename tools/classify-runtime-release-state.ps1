param(
    [string]$ProjectRoot,
    [ValidateSet('Development', 'Protected')]
    [string]$Mode = 'Development',
    [string]$BaseRevision,
    [string]$HeadRevision = 'HEAD'
)

$ErrorActionPreference = 'Stop'

function Write-Cf7Failure([string]$Message) {
    Write-Host "[RuntimeReleaseState] FAIL $Message" -ForegroundColor Red
}

function Test-Cf7SafeRevision([string]$Revision) {
    if ([string]::IsNullOrWhiteSpace($Revision)) { return $false }
    if ($Revision -match '^0+$') { return $false }
    if ($Revision.StartsWith('-') -or $Revision.Contains('..') -or $Revision.Contains(':') -or
        $Revision.Contains('\\') -or $Revision.Contains('@{')) { return $false }
    return $Revision -match '^[A-Za-z0-9][A-Za-z0-9._/^-]*$'
}

function Resolve-Cf7Commit([string]$Revision, [switch]$Optional) {
    if (-not (Test-Cf7SafeRevision $Revision)) {
        if ($Optional -and ([string]::IsNullOrWhiteSpace($Revision) -or $Revision -match '^0+$')) { return $null }
        throw "Unsafe or invalid Git revision: $Revision"
    }
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $resolved = @(& git -C $ProjectRoot rev-parse --verify "$Revision^{commit}" 2>$null)
        $gitExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorAction
    }
    if ($gitExitCode -ne 0 -or $resolved.Count -ne 1 -or $resolved[0] -notmatch '^[0-9a-fA-F]{40,64}$') {
        if ($Optional) { return $null }
        throw "Cannot resolve Git commit: $Revision"
    }
    return ([string]$resolved[0]).Trim().ToLowerInvariant()
}

function Get-Cf7IndexedText([string]$RelativePath) {
    $output = @(& git -C $ProjectRoot show --no-textconv ":$RelativePath" 2>$null)
    if ($LASTEXITCODE -ne 0) { throw "Required indexed file is missing: $RelativePath" }
    return ($output -join "`n")
}

function Get-Cf7RevisionText([string]$Revision, [string]$RelativePath, [switch]$Optional) {
    $output = @(& git -C $ProjectRoot show --no-textconv "${Revision}:$RelativePath" 2>$null)
    if ($LASTEXITCODE -ne 0) {
        if ($Optional) { return $null }
        throw "Required file is missing at revision $Revision`: $RelativePath"
    }
    return ($output -join "`n")
}

function Get-Cf7GitBlobBytes([string]$ObjectSpec) {
    $gitCommand = Get-Command git -ErrorAction Stop
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $gitCommand.Source
    $psi.Arguments = "-C `"$ProjectRoot`" cat-file blob `"$ObjectSpec`""
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($psi)
    $memory = New-Object IO.MemoryStream
    try {
        $process.StandardOutput.BaseStream.CopyTo($memory)
        $errorText = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) { throw "Cannot read Git blob $ObjectSpec`: $errorText" }
        return $memory.ToArray()
    } finally {
        $memory.Dispose()
        $process.Dispose()
    }
}

function Get-Cf7BytesSha256([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '') }
    finally { $sha.Dispose() }
}

function Get-Cf7RevisionBlobOid([string]$Revision, [string]$RelativePath, [switch]$Optional) {
    $spec = if ($Revision -eq ':') { ":$RelativePath" } else { "${Revision}:$RelativePath" }
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& git -C $ProjectRoot rev-parse --verify $spec 2>$null)
        $gitExitCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousErrorAction }
    if ($gitExitCode -ne 0 -or $output.Count -ne 1 -or [string]$output[0] -notmatch '^[0-9a-fA-F]{40,64}$') {
        if ($Optional) { return $null }
        throw "Required Git blob is missing: $spec"
    }
    return ([string]$output[0]).Trim().ToLowerInvariant()
}

function Read-Cf7MigrationMarker([byte[]]$Bytes) {
    $utf8 = New-Object Text.UTF8Encoding($false, $true)
    try { $text = $utf8.GetString($Bytes) }
    catch { throw 'Runtime v2 migration marker is not strict UTF-8.' }
    try { $marker = $text | ConvertFrom-Json }
    catch { throw "Runtime v2 migration marker is invalid JSON: $($_.Exception.Message)" }
    if ($null -eq $marker) { throw 'Runtime v2 migration marker is empty.' }
    $fields = @('schema','migrationId','baseCommitOid','fromManifest','toManifest','legacyArtifactClosureHash','targetBuilderRegistrySha256')
    $properties = @($marker.PSObject.Properties.Name)
    if ($properties.Count -ne $fields.Count -or @($properties | Where-Object { $fields -notcontains $_ }).Count -gt 0) {
        throw 'Runtime v2 migration marker fields are not the exact allowed set.'
    }
    if ([string]$marker.schema -cne 'cf7-runtime-v2-migration-bootstrap.v1' -or
            [string]$marker.migrationId -cne 'runtime-release-v2-bootstrap-2026-07' -or
            [string]$marker.fromManifest -cne 'cf7-runtime-manifest-v1' -or
            [string]$marker.toManifest -cne 'cf7-runtime-manifest-v2') {
        throw 'Runtime v2 migration marker has an unsupported fixed transition.'
    }
    if ([string]$marker.baseCommitOid -cnotmatch '^(?:[0-9a-f]{40}|[0-9a-f]{64})$') { throw 'Migration marker baseCommitOid must be a lowercase full Git OID.' }
    foreach ($field in @('legacyArtifactClosureHash','targetBuilderRegistrySha256')) {
        if ([string]$marker.$field -cnotmatch '^[0-9A-F]{64}$') { throw "Migration marker $field must be uppercase SHA-256." }
    }
    $canonical = '{"schema":"cf7-runtime-v2-migration-bootstrap.v1","migrationId":"runtime-release-v2-bootstrap-2026-07","baseCommitOid":"' +
        [string]$marker.baseCommitOid + '","fromManifest":"cf7-runtime-manifest-v1","toManifest":"cf7-runtime-manifest-v2","legacyArtifactClosureHash":"' +
        [string]$marker.legacyArtifactClosureHash + '","targetBuilderRegistrySha256":"' + [string]$marker.targetBuilderRegistrySha256 + '"}' + "`n"
    $canonicalBytes = [Text.Encoding]::UTF8.GetBytes($canonical)
    if ($Bytes.Length -ne $canonicalBytes.Length) { throw 'Runtime v2 migration marker is not in canonical byte form.' }
    for ($index = 0; $index -lt $Bytes.Length; $index++) {
        if ($Bytes[$index] -ne $canonicalBytes[$index]) { throw 'Runtime v2 migration marker is not in canonical byte form.' }
    }
    return $marker
}

function Assert-Cf7BootstrapBuilderRegistry([byte[]]$RegistryBytes, [string]$ExpectedSha256) {
    $actualHash = Get-Cf7BytesSha256 -Bytes $RegistryBytes
    if ($actualHash -cne $ExpectedSha256) { throw "Migration builder registry SHA-256 mismatch: expected=$ExpectedSha256 actual=$actualHash" }
    $temporaryPath = Join-Path ([IO.Path]::GetTempPath()) ('cf7-runtime-builders-' + [Guid]::NewGuid().ToString('N') + '.json')
    try {
        [IO.File]::WriteAllBytes($temporaryPath, $RegistryBytes)
        . (Join-Path $ProjectRoot 'tools\runtime-build-v2-common.ps1')
        . (Join-Path $ProjectRoot 'tools\runtime-build-attestation-v2-common.ps1')
        $registry = Read-Cf7RuntimeV2BuilderRegistry -RegistryPath $temporaryPath
        $enabled = @($registry.builders | Where-Object { $_.enabled -eq $true })
        if ($enabled.Count -lt 1) { throw 'Migration builder registry requires at least one enabled public-key identity.' }
        $builderIds = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        $faultDomains = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        foreach ($entry in @($registry.builders)) {
            if ([string]$entry.builderId -notmatch '^[a-z0-9][a-z0-9._-]{1,63}$' -or -not $builderIds.Add([string]$entry.builderId)) {
                throw 'Migration builder registry has an invalid or duplicate builderId.'
            }
        }
        foreach ($entry in $enabled) {
            if (-not $faultDomains.Add([string]$entry.faultDomain)) { throw 'Enabled migration builders must have unique faultDomain values.' }
            $raw = [Convert]::FromBase64String([string]$entry.certificateBase64)
            $certificate = New-Object Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList @(,$raw)
            try {
                if ($certificate.HasPrivateKey) { throw 'Builder registry must contain only public certificate bytes, never private key material.' }
                $rsa = [Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($certificate)
                if ($null -eq $rsa) { throw 'Enabled migration builder certificate does not contain an RSA public key.' }
                $rsa.Dispose()
            } finally { $certificate.Dispose() }
        }
    } finally {
        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
    }
    return $actualHash
}

function Get-Cf7ManifestHeader([AllowNull()][string]$Text, [switch]$Optional) {
    if ($null -eq $Text) {
        if ($Optional) { return $null }
        throw 'Runtime manifest text is missing.'
    }
    $lines = @($Text -split "`r?`n" | Where-Object { $_ -ne '' })
    if ($lines.Count -eq 0) {
        if ($Optional) { return $null }
        throw 'Runtime manifest is empty.'
    }
    $header = ([string]$lines[0]).TrimStart([char]0xFEFF)
    if ($header -notin @('cf7-runtime-manifest-v1', 'cf7-runtime-manifest-v2')) {
        if ($Optional) { return $null }
        throw "Unsupported runtime manifest header: $header"
    }
    return $header
}

function Get-Cf7PowerShellExecutable {
    try {
        $current = (Get-Process -Id $PID -ErrorAction Stop).Path
        if ($current -and (Test-Path -LiteralPath $current -PathType Leaf)) { return $current }
    } catch {}
    foreach ($name in @('powershell.exe', 'pwsh.exe', 'pwsh')) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command) { return $command.Source }
    }
    throw 'Cannot locate a PowerShell executable for isolated verification.'
}

function Invoke-Cf7Verifier(
    [string]$Label,
    [string]$Path,
    [string[]]$Arguments,
    [bool]$EchoOutput = $true
) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Label script is missing: $Path" }
    $commandArguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Path) + $Arguments
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& $script:PowerShellExecutable @commandArguments 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorAction
    }
    if ($EchoOutput) {
        foreach ($line in $output) { Write-Host ([string]$line) }
    }
    return [pscustomobject]@{
        Label = $Label
        ExitCode = [int]$exitCode
        Output = @($output | ForEach-Object { [string]$_ })
    }
}

function Assert-Cf7Passed($Result) {
    if ($Result.ExitCode -ne 0) { throw "$($Result.Label) failed with exit code $($Result.ExitCode)." }
}

try {
    if (-not $ProjectRoot) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }
    $ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\\')
    & git -C $ProjectRoot rev-parse --is-inside-work-tree *> $null
    if ($LASTEXITCODE -ne 0) { throw "ProjectRoot is not a Git worktree: $ProjectRoot" }

    $headCommit = Resolve-Cf7Commit -Revision $HeadRevision
    $baseWasAbsent = [string]::IsNullOrWhiteSpace($BaseRevision) -or $BaseRevision -match '^0+$'
    $baseCommit = if ($baseWasAbsent) { $null } else { Resolve-Cf7Commit -Revision $BaseRevision }
    $baseOrigin = 'provided'
    if (-not $baseCommit) {
        $baseCommit = Resolve-Cf7Commit -Revision "$headCommit^" -Optional
        $baseOrigin = if ($baseCommit) { 'head-parent-fallback' } else { 'initial-commit' }
    }

    # -Staged verifiers read the Git index. Refuse an ambiguous head/index pairing.
    $indexTree = (@(& git -C $ProjectRoot write-tree 2>$null) -join '').Trim()
    $headTree = (@(& git -C $ProjectRoot rev-parse "$headCommit^{tree}" 2>$null) -join '').Trim()
    if ($LASTEXITCODE -ne 0 -or -not $indexTree -or $indexTree -ne $headTree) {
        throw "Git index does not match HeadRevision $headCommit; staged verification would classify different content."
    }

    $manifestPath = 'runtime/cf7-runtime-manifest.tsv'
    $migrationMarkerPath = 'config/build/runtime-v2-migration-bootstrap.json'
    $builderRegistryPath = 'config/build/runtime-builders.v2.json'
    $consensusRecordPath = 'config/build/runtime-release-consensus.json'
    $headHeader = Get-Cf7ManifestHeader (Get-Cf7IndexedText $manifestPath)
    $baseHeader = $null
    if ($baseCommit) {
        $baseHeader = Get-Cf7ManifestHeader (Get-Cf7RevisionText -Revision $baseCommit -RelativePath $manifestPath -Optional) -Optional
    }

    $script:PowerShellExecutable = Get-Cf7PowerShellExecutable
    $toolsRoot = Join-Path $ProjectRoot 'tools'
    $bundleVerifier = if ($headHeader -eq 'cf7-runtime-manifest-v2') {
        Join-Path $toolsRoot 'verify-runtime-bundle-v2.ps1'
    } else {
        Join-Path $toolsRoot 'verify-runtime-bundle.ps1'
    }
    $commonArguments = @('-ProjectRoot', $ProjectRoot, '-Staged')

    # Byte closure is non-negotiable in every state, including source-ahead.
    $integrity = Invoke-Cf7Verifier -Label 'runtime byte-integrity verification' -Path $bundleVerifier `
        -Arguments ($commonArguments + @('-IntegrityOnly'))
    Assert-Cf7Passed $integrity

    if ($baseHeader -eq 'cf7-runtime-manifest-v2' -and $headHeader -eq 'cf7-runtime-manifest-v1') {
        throw 'Runtime manifest downgrade from v2 to v1 is forbidden.'
    }

    $baseMarkerBlob = if ($baseCommit) { Get-Cf7RevisionBlobOid -Revision $baseCommit -RelativePath $migrationMarkerPath -Optional } else { $null }
    $headMarkerBlob = Get-Cf7RevisionBlobOid -Revision ':' -RelativePath $migrationMarkerPath -Optional
    if ($baseMarkerBlob) {
        if (-not $headMarkerBlob) { throw 'The permanent runtime v2 migration fuse marker cannot be removed.' }
        if ($baseMarkerBlob -cne $headMarkerBlob) { throw 'The permanent runtime v2 migration fuse marker cannot be modified after bootstrap.' }
        if ($headHeader -ne 'cf7-runtime-manifest-v2') {
            throw 'The one-time runtime v2 migration bootstrap has already been consumed; the next protected state requires a complete v2 promotion.'
        }
    }
    $isMigrationBootstrap = -not $baseMarkerBlob -and [bool]$headMarkerBlob

    $deploymentChanged = $true
    $changedDeploymentPaths = @()
    if ($baseCommit) {
        $pathspecs = @(
            'CRAZYFLASHER7MercenaryEmpire.exe',
            'runtime',
            $consensusRecordPath,
            $builderRegistryPath
        )
        $changedDeploymentPaths = @(& git -C $ProjectRoot diff --name-only --no-renames $baseCommit $headCommit -- @pathspecs)
        if ($LASTEXITCODE -ne 0) { throw 'Cannot compare runtime deployment paths between base and head.' }
        $changedDeploymentPaths = @($changedDeploymentPaths | Where-Object { $_ -ne '' } | Sort-Object -Unique)
        $deploymentChanged = $changedDeploymentPaths.Count -gt 0
    }

    $consensusVerifier = Join-Path $toolsRoot 'verify-runtime-consensus.ps1'
    if ($isMigrationBootstrap) {
        if ($Mode -ne 'Protected') { throw 'The one-time runtime v2 migration bootstrap is allowed only against a protected ref.' }
        if ($baseWasAbsent -or -not $baseCommit) { throw 'Migration bootstrap requires an explicit, non-zero base revision.' }
        if ($baseHeader -ne 'cf7-runtime-manifest-v1' -or $headHeader -ne 'cf7-runtime-manifest-v1') {
            throw 'Migration bootstrap must preserve the legacy v1 manifest until the separately attested v2 promotion.'
        }
        & git -C $ProjectRoot merge-base --is-ancestor $baseCommit $headCommit *> $null
        if ($LASTEXITCODE -ne 0) { throw 'Migration marker base must be an ancestor of the classified head.' }

        $markerStatus = @(& git -C $ProjectRoot diff --name-status --no-renames $baseCommit $headCommit -- $migrationMarkerPath)
        if ($LASTEXITCODE -ne 0 -or $markerStatus.Count -ne 1 -or [string]$markerStatus[0] -cne "A`t$migrationMarkerPath") {
            throw 'Migration marker must be added exactly once between the classified base and head.'
        }
        $legacyDeploymentChanges = @(& git -C $ProjectRoot diff --name-only --no-renames $baseCommit $headCommit -- `
            'CRAZYFLASHER7MercenaryEmpire.exe' 'runtime' $consensusRecordPath)
        if ($LASTEXITCODE -ne 0) { throw 'Cannot compare legacy deployment bytes for migration bootstrap.' }
        $legacyDeploymentChanges = @($legacyDeploymentChanges | Where-Object { $_ -ne '' })
        if ($legacyDeploymentChanges.Count -gt 0) {
            throw "Migration bootstrap cannot alter legacy deployment bytes: $($legacyDeploymentChanges -join ',')"
        }
        $registryStatus = @(& git -C $ProjectRoot diff --name-status --no-renames $baseCommit $headCommit -- $builderRegistryPath)
        if ($LASTEXITCODE -ne 0 -or $registryStatus.Count -ne 1 -or [string]$registryStatus[0] -notmatch "^[AM]`t$([regex]::Escape($builderRegistryPath))$") {
            throw 'Migration bootstrap must add or modify exactly the marker-bound v2 builder registry.'
        }

        $markerBytes = Get-Cf7GitBlobBytes -ObjectSpec ":$migrationMarkerPath"
        $marker = Read-Cf7MigrationMarker -Bytes $markerBytes
        if ([string]$marker.baseCommitOid -cne $baseCommit) { throw 'Migration marker does not bind the exact classified base commit.' }
        $consensusBytes = Get-Cf7GitBlobBytes -ObjectSpec ":$consensusRecordPath"
        try { $legacyConsensus = [Text.Encoding]::UTF8.GetString($consensusBytes).TrimStart([char]0xFEFF) | ConvertFrom-Json }
        catch { throw "Legacy consensus record is invalid JSON: $($_.Exception.Message)" }
        if ([string]$legacyConsensus.schema -cne 'cf7-runtime-release-consensus.v1' -or
                [string]$legacyConsensus.artifactClosureHash -cnotmatch '^[0-9A-F]{64}$') {
            throw 'Migration bootstrap requires a valid v1 legacy consensus record.'
        }
        if ([string]$marker.legacyArtifactClosureHash -cne [string]$legacyConsensus.artifactClosureHash) {
            throw 'Migration marker does not bind the legacy consensus artifact closure.'
        }
        $registryBytes = Get-Cf7GitBlobBytes -ObjectSpec ":$builderRegistryPath"
        $registryHash = Assert-Cf7BootstrapBuilderRegistry -RegistryBytes $registryBytes -ExpectedSha256 ([string]$marker.targetBuilderRegistrySha256)
        $consensusIntegrity = Invoke-Cf7Verifier -Label 'legacy runtime consensus integrity verification' -Path $consensusVerifier `
            -Arguments ($commonArguments + @('-IntegrityOnly'))
        Assert-Cf7Passed $consensusIntegrity
        Write-Host "[RuntimeReleaseState] OK state=migration-bootstrap mode=$Mode manifest=$headHeader deploymentChanged=true base=$baseCommit head=$headCommit registrySha256=$registryHash" -ForegroundColor Yellow
        exit 0
    }

    if ($Mode -eq 'Protected' -and $baseCommit -and $deploymentChanged -and $headHeader -ne 'cf7-runtime-manifest-v2') {
        throw "Protected v1 deployment changes require the exact one-time migration bootstrap or a complete v2 promotion: $($changedDeploymentPaths -join ',')"
    }

    if ($Mode -eq 'Development' -and -not $deploymentChanged) {
        # Exit 2 is the verifier's explicit identity-mismatch result. Infrastructure failures remain fatal.
        $strict = Invoke-Cf7Verifier -Label 'runtime strict identity verification' -Path $bundleVerifier `
            -Arguments $commonArguments -EchoOutput $false
        if ($strict.ExitCode -eq 0) {
            foreach ($line in $strict.Output) { Write-Host $line }
            Write-Host "[RuntimeReleaseState] OK state=coherent mode=$Mode manifest=$headHeader deploymentChanged=false base=$baseCommit head=$headCommit" -ForegroundColor Green
            exit 0
        }
        if ($strict.ExitCode -ne 2) {
            foreach ($line in $strict.Output) { Write-Host $line }
            throw "Runtime strict identity verifier failed unexpectedly with exit code $($strict.ExitCode)."
        }
        Write-Host "[RuntimeReleaseState] OK state=source-ahead mode=$Mode manifest=$headHeader deploymentChanged=false base=$baseCommit head=$headCommit" -ForegroundColor Yellow
        exit 0
    }

    if ($Mode -eq 'Development' -and $deploymentChanged -and $headHeader -ne 'cf7-runtime-manifest-v2') {
        $detail = if ($baseCommit) { $changedDeploymentPaths -join ',' } else { "no comparable base ($baseOrigin)" }
        throw "Development deployment changes require a complete v2 promotion; manifest=$headHeader changes=$detail"
    }

    $strict = Invoke-Cf7Verifier -Label 'runtime strict identity verification' -Path $bundleVerifier -Arguments $commonArguments
    Assert-Cf7Passed $strict
    $consensus = Invoke-Cf7Verifier -Label 'runtime release consensus verification' -Path $consensusVerifier -Arguments $commonArguments
    Assert-Cf7Passed $consensus

    $state = if ($Mode -eq 'Protected') { 'protected-coherent' } else { 'promoted' }
    Write-Host "[RuntimeReleaseState] OK state=$state mode=$Mode manifest=$headHeader deploymentChanged=$($deploymentChanged.ToString().ToLowerInvariant()) base=$(if ($baseCommit) {$baseCommit} else {'none'}) head=$headCommit" -ForegroundColor Green
    exit 0
} catch {
    Write-Cf7Failure $_.Exception.Message
    exit 2
}
