# CF7 runtime v2 X509 builder registry, attestation, and consensus helpers.
# Dot-source runtime-build-v2-common.ps1 before this file.

function ConvertTo-Cf7RuntimeV2JsonString {
    param([AllowEmptyString()][string]$Value)
    if ($null -eq $Value) { return 'null' }
    $builder = New-Object Text.StringBuilder
    [void]$builder.Append('"')
    foreach ($character in $Value.ToCharArray()) {
        $code = [int][char]$character
        switch ($code) {
            8  { [void]$builder.Append('\b'); continue }
            9  { [void]$builder.Append('\t'); continue }
            10 { [void]$builder.Append('\n'); continue }
            12 { [void]$builder.Append('\f'); continue }
            13 { [void]$builder.Append('\r'); continue }
            34 { [void]$builder.Append('\"'); continue }
            92 { [void]$builder.Append('\\'); continue }
        }
        if ($code -lt 0x20) { [void]$builder.Append(('\u{0:x4}' -f $code)) }
        else { [void]$builder.Append($character) }
    }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function ConvertTo-Cf7RuntimeV2CanonicalPayloadBytes {
    param([Parameter(Mandatory=$true)][object]$Payload)
    $fields = @('builderKeyId','faultDomain','artifactSourceHash','producerRecipeHash','toolchainLockHash','buildIdentityHash','payloadClosureHash','createdAtUtc')
    foreach ($field in $fields) {
        if ($null -eq $Payload.PSObject.Properties[$field]) { throw "Attestation payload lacks field: $field" }
    }
    if ([string]$Payload.schema -ne 'cf7-runtime-build-attestation-payload.v2') { throw 'Unsupported attestation payload schema.' }
    foreach ($field in @('builderKeyId','artifactSourceHash','producerRecipeHash','toolchainLockHash','buildIdentityHash','payloadClosureHash')) {
        if ([string]$Payload.$field -notmatch '^[0-9A-Fa-f]{64}$') { throw "Invalid attestation payload field: $field" }
    }
    if ([string]$Payload.faultDomain -notmatch '^[a-z0-9][a-z0-9._-]{1,63}$') { throw 'Invalid attestation faultDomain.' }
    $epoch = [Int64]$Payload.builderEpoch
    if ($epoch -lt 1 -or [string]$Payload.builderEpoch -notmatch '^\d+$') { throw 'Invalid attestation builderEpoch.' }
    $created = [DateTime]::MinValue
    if (-not [DateTime]::TryParse([string]$Payload.createdAtUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$created)) {
        throw 'Invalid attestation createdAtUtc.'
    }
    $files = @($Payload.files)
    $sorted = @($files)
    [Array]::Sort($sorted, [Comparison[object]]{
        param($left, $right)
        return [StringComparer]::Ordinal.Compare([string]$left.path, [string]$right.path)
    })
    $expectedClosure = Get-Cf7RuntimeV2CanonicalClosureHash -Files $sorted
    if ($expectedClosure -ne ([string]$Payload.payloadClosureHash).ToUpperInvariant()) { throw 'Attestation file inventory does not match payloadClosureHash.' }
    $expectedBuild = Get-Cf7RuntimeV2BuildIdentityHash -ArtifactSourceHash ([string]$Payload.artifactSourceHash) -ProducerRecipeHash ([string]$Payload.producerRecipeHash) -ToolchainLockHash ([string]$Payload.toolchainLockHash)
    if ($expectedBuild -ne ([string]$Payload.buildIdentityHash).ToUpperInvariant()) { throw 'Attestation identity fields do not match buildIdentityHash.' }

    $parts = New-Object 'System.Collections.Generic.List[string]'
    $parts.Add('{"schema":"cf7-runtime-build-attestation-payload.v2"')
    $parts.Add(',"builderKeyId":' + (ConvertTo-Cf7RuntimeV2JsonString ([string]$Payload.builderKeyId).ToUpperInvariant()))
    $parts.Add(',"builderEpoch":' + $epoch.ToString([Globalization.CultureInfo]::InvariantCulture))
    $parts.Add(',"faultDomain":' + (ConvertTo-Cf7RuntimeV2JsonString ([string]$Payload.faultDomain)))
    foreach ($field in @('artifactSourceHash','producerRecipeHash','toolchainLockHash','buildIdentityHash','payloadClosureHash')) {
        $parts.Add(',"' + $field + '":' + (ConvertTo-Cf7RuntimeV2JsonString ([string]$Payload.$field).ToUpperInvariant()))
    }
    $parts.Add(',"createdAtUtc":' + (ConvertTo-Cf7RuntimeV2JsonString ([string]$Payload.createdAtUtc)))
    $parts.Add(',"files":[')
    for ($index = 0; $index -lt $sorted.Count; $index++) {
        $row = $sorted[$index]
        if ($index -gt 0) { $parts.Add(',') }
        $parts.Add('{"path":' + (ConvertTo-Cf7RuntimeV2JsonString ([string]$row.path)) +
            ',"size":' + ([Int64]$row.size).ToString([Globalization.CultureInfo]::InvariantCulture) +
            ',"sha256":' + (ConvertTo-Cf7RuntimeV2JsonString ([string]$row.sha256).ToUpperInvariant()) + '}')
    }
    $parts.Add(']}')
    return [Text.Encoding]::UTF8.GetBytes([string]::Join('', $parts.ToArray()))
}

function Get-Cf7RuntimeV2BuilderKeyId {
    param([Parameter(Mandatory=$true)][System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate)
    return Get-Cf7RuntimeV2BytesSha256 -Bytes $Certificate.GetPublicKey()
}

function Read-Cf7RuntimeV2BuilderRegistry {
    param([Parameter(Mandatory=$true)][string]$RegistryPath)
    if (-not (Test-Path -LiteralPath $RegistryPath -PathType Leaf)) { throw "Runtime builder registry missing: $RegistryPath" }
    $registry = Get-Content -LiteralPath $RegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -eq $registry -or [string]$registry.schema -ne 'cf7-runtime-builders.v2') { throw 'Unsupported runtime builder registry schema.' }
    $minimum = [Int64]$registry.minimumConsensus
    if ($minimum -lt 2 -or [string]$registry.minimumConsensus -notmatch '^\d+$') { throw 'Builder registry minimumConsensus must be at least 2.' }
    $keys = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $thumbprints = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in @($registry.builders)) {
        $keyId = ([string]$entry.keyId).ToUpperInvariant()
        if ($keyId -notmatch '^[0-9A-F]{64}$') { throw 'Builder registry contains an invalid keyId.' }
        if (-not $keys.Add($keyId)) { throw "Builder registry contains duplicate keyId: $keyId" }
        if ($entry.enabled -isnot [bool]) { throw "Builder registry enabled must be Boolean: $keyId" }
        $epoch = [Int64]$entry.epoch
        if ($epoch -lt 1 -or [string]$entry.epoch -notmatch '^\d+$') { throw "Builder registry contains an invalid epoch: $keyId" }
        if ([string]$entry.faultDomain -notmatch '^[a-z0-9][a-z0-9._-]{1,63}$') { throw "Builder registry contains an invalid faultDomain: $keyId" }
        try { $raw = [Convert]::FromBase64String([string]$entry.certificateBase64) }
        catch { throw "Builder registry contains invalid certificateBase64: $keyId" }
        $certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList @(,$raw)
        try {
            if ((Get-Cf7RuntimeV2BuilderKeyId -Certificate $certificate) -ne $keyId) { throw "Builder registry certificate does not match keyId: $keyId" }
            $thumbprint = $certificate.Thumbprint.Replace(' ', '').ToUpperInvariant()
            if ($entry.PSObject.Properties['certificateThumbprint'] -and ([string]$entry.certificateThumbprint).Replace(' ', '').ToUpperInvariant() -ne $thumbprint) {
                throw "Builder registry certificateThumbprint mismatch: $keyId"
            }
            if (-not $thumbprints.Add($thumbprint)) { throw "Builder registry contains duplicate certificate: $thumbprint" }
        } finally { $certificate.Dispose() }
    }
    return $registry
}

function Get-Cf7RuntimeV2RegistryEntry {
    param(
        [Parameter(Mandatory=$true)][object]$Registry,
        [string]$KeyId,
        [string]$CertificateThumbprint
    )
    $normalizedKey = ([string]$KeyId).Replace(' ', '').ToUpperInvariant()
    $normalizedThumb = ([string]$CertificateThumbprint).Replace(' ', '').ToUpperInvariant()
    $matches = @($Registry.builders | Where-Object {
        $entryKey = ([string]$_.keyId).Replace(' ', '').ToUpperInvariant()
        $entryThumb = ([string]$_.certificateThumbprint).Replace(' ', '').ToUpperInvariant()
        (($normalizedKey -and $entryKey -eq $normalizedKey) -or ($normalizedThumb -and $entryThumb -eq $normalizedThumb))
    })
    if ($matches.Count -ne 1) { throw 'Signing certificate is not uniquely registered.' }
    return $matches[0]
}

function Get-Cf7RuntimeV2CurrentUserCertificate {
    param([Parameter(Mandatory=$true)][string]$CertificateThumbprint)
    $thumbprint = $CertificateThumbprint.Replace(' ', '').ToUpperInvariant()
    if ($thumbprint -notmatch '^[0-9A-F]{40,128}$') { throw 'Invalid certificate thumbprint.' }
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store('My', 'CurrentUser')
    $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly)
    try {
        $matches = @($store.Certificates | Where-Object { $_.Thumbprint.Replace(' ', '').ToUpperInvariant() -eq $thumbprint })
        if ($matches.Count -ne 1) { throw "CurrentUser signing certificate not found: $thumbprint" }
        return New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList $matches[0]
    } finally { $store.Close() }
}

function New-Cf7RuntimeBuildAttestationV2 {
    param(
        [Parameter(Mandatory=$true)][string]$ProjectRoot,
        [Parameter(Mandatory=$true)][string]$DeploymentRoot,
        [Parameter(Mandatory=$true)][string]$CertificateThumbprint,
        [string]$RegistryPath,
        [ValidateSet('Worktree','Index')][string]$Mode = 'Worktree',
        [string]$ConfigPath,
        [object]$ExpectedIdentity,
        [DateTime]$CreatedAtUtc = ([DateTime]::UtcNow)
    )
    $root = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
    if (-not $RegistryPath) { $RegistryPath = Join-Path $root 'config\build\runtime-builders.v2.json' }
    $registry = Read-Cf7RuntimeV2BuilderRegistry -RegistryPath $RegistryPath
    $certificate = Get-Cf7RuntimeV2CurrentUserCertificate -CertificateThumbprint $CertificateThumbprint
    try {
        if (-not $certificate.HasPrivateKey) { throw 'Runtime builder certificate has no private key.' }
        $keyId = Get-Cf7RuntimeV2BuilderKeyId -Certificate $certificate
        $entry = Get-Cf7RuntimeV2RegistryEntry -Registry $registry -KeyId $keyId -CertificateThumbprint $certificate.Thumbprint
        if (-not [bool]$entry.enabled) { throw "Runtime builder is disabled: $keyId" }
        $registeredBase64 = [string]$entry.certificateBase64
        if ([Convert]::ToBase64String($certificate.RawData) -ne $registeredBase64) { throw 'CurrentUser certificate does not byte-match the registered certificate.' }
        $now = [DateTime]::UtcNow
        if ($now -lt $certificate.NotBefore.ToUniversalTime() -or $now -gt $certificate.NotAfter.ToUniversalTime()) { throw 'Runtime builder certificate is outside its validity period.' }

        if ($null -ne $ExpectedIdentity) {
            # The caller (queue worker) passes the request-pinned identity it already proved
            # against the frozen checkout. This is a comparison anchor, not blind trust: field
            # shape is validated here and buildIdentityHash is re-derived from the three domain
            # hashes; a mismatch fails closed before signing.
            foreach ($field in @('artifactSourceHash','producerRecipeHash','toolchainLockHash','policyHash','buildIdentityHash')) {
                if ($null -eq $ExpectedIdentity.PSObject.Properties[$field] -or
                        [string]$ExpectedIdentity.$field -notmatch '^[0-9A-Fa-f]{64}$') {
                    throw "Expected identity has a missing or invalid field: $field"
                }
            }
            $expectedBuildIdentity = Get-Cf7RuntimeV2BuildIdentityHash `
                -ArtifactSourceHash ([string]$ExpectedIdentity.artifactSourceHash) `
                -ProducerRecipeHash ([string]$ExpectedIdentity.producerRecipeHash) `
                -ToolchainLockHash ([string]$ExpectedIdentity.toolchainLockHash)
            if ($expectedBuildIdentity -ne ([string]$ExpectedIdentity.buildIdentityHash).ToUpperInvariant()) {
                throw 'Expected identity domain hashes do not reproduce buildIdentityHash.'
            }
            $identity = [pscustomobject]@{
                artifactSourceHash = ([string]$ExpectedIdentity.artifactSourceHash).ToUpperInvariant()
                producerRecipeHash = ([string]$ExpectedIdentity.producerRecipeHash).ToUpperInvariant()
                toolchainLockHash = ([string]$ExpectedIdentity.toolchainLockHash).ToUpperInvariant()
                policyHash = ([string]$ExpectedIdentity.policyHash).ToUpperInvariant()
                buildIdentityHash = ([string]$ExpectedIdentity.buildIdentityHash).ToUpperInvariant()
            }
        } else {
            $identity = Get-Cf7RuntimeV2Identity -ProjectRoot $root -Mode $Mode -ConfigPath $ConfigPath
        }
        $closure = Get-Cf7RuntimePayloadClosureV2 -ProjectRoot $root -DeploymentRoot $DeploymentRoot -Mode $Mode -ConfigPath $ConfigPath
        $payload = [pscustomobject][ordered]@{
            schema = 'cf7-runtime-build-attestation-payload.v2'
            builderKeyId = $keyId
            builderEpoch = [Int64]$entry.epoch
            faultDomain = [string]$entry.faultDomain
            artifactSourceHash = $identity.artifactSourceHash
            producerRecipeHash = $identity.producerRecipeHash
            toolchainLockHash = $identity.toolchainLockHash
            buildIdentityHash = $identity.buildIdentityHash
            payloadClosureHash = $closure.payloadClosureHash
            createdAtUtc = $CreatedAtUtc.ToUniversalTime().ToString('o')
            files = $closure.files
        }
        $canonical = ConvertTo-Cf7RuntimeV2CanonicalPayloadBytes -Payload $payload
        $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($certificate)
        if ($null -eq $rsa) { throw 'Runtime builder certificate private key is not RSA.' }
        try {
            $signatureBytes = $rsa.SignData($canonical, [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
        } finally { $rsa.Dispose() }
        return [pscustomobject][ordered]@{
            schema = 'cf7-runtime-build-attestation.v2'
            payload = $payload
            signature = [pscustomobject][ordered]@{
                algorithm = 'RS256'
                keyId = $keyId
                certificateThumbprint = $certificate.Thumbprint.Replace(' ', '').ToUpperInvariant()
                canonicalPayloadSha256 = Get-Cf7RuntimeV2BytesSha256 -Bytes $canonical
                valueBase64 = [Convert]::ToBase64String($signatureBytes)
            }
        }
    } finally { $certificate.Dispose() }
}

function Test-Cf7RuntimeBuildAttestationV2 {
    param(
        [Parameter(Mandatory=$true)][object]$Attestation,
        [Parameter(Mandatory=$true)][string]$RegistryPath
    )
    if ($null -eq $Attestation -or [string]$Attestation.schema -ne 'cf7-runtime-build-attestation.v2') { throw 'Unsupported runtime build attestation schema.' }
    if ([string]$Attestation.signature.algorithm -ne 'RS256') { throw 'Unsupported runtime build attestation signature algorithm.' }
    $registry = Read-Cf7RuntimeV2BuilderRegistry -RegistryPath $RegistryPath
    $payload = $Attestation.payload
    $canonical = ConvertTo-Cf7RuntimeV2CanonicalPayloadBytes -Payload $payload
    $canonicalHash = Get-Cf7RuntimeV2BytesSha256 -Bytes $canonical
    if ($canonicalHash -ne ([string]$Attestation.signature.canonicalPayloadSha256).ToUpperInvariant()) { throw 'Attestation canonical payload hash mismatch.' }
    $keyId = ([string]$payload.builderKeyId).ToUpperInvariant()
    if ($keyId -ne ([string]$Attestation.signature.keyId).ToUpperInvariant()) { throw 'Attestation signature keyId does not match payload.' }
    $entry = Get-Cf7RuntimeV2RegistryEntry -Registry $registry -KeyId $keyId -CertificateThumbprint ([string]$Attestation.signature.certificateThumbprint)
    if (-not [bool]$entry.enabled) { throw "Runtime builder is disabled: $keyId" }
    if ([Int64]$entry.epoch -ne [Int64]$payload.builderEpoch) { throw "Runtime builder epoch mismatch: $keyId" }
    if ([string]$entry.faultDomain -ne [string]$payload.faultDomain) { throw "Runtime builder faultDomain mismatch: $keyId" }
    $raw = [Convert]::FromBase64String([string]$entry.certificateBase64)
    $certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList @(,$raw)
    try {
        $thumbprint = $certificate.Thumbprint.Replace(' ', '').ToUpperInvariant()
        if ($thumbprint -ne ([string]$Attestation.signature.certificateThumbprint).Replace(' ', '').ToUpperInvariant()) { throw 'Attestation certificateThumbprint mismatch.' }
        if ((Get-Cf7RuntimeV2BuilderKeyId -Certificate $certificate) -ne $keyId) { throw 'Attestation certificate public key mismatch.' }
        try { $signatureBytes = [Convert]::FromBase64String([string]$Attestation.signature.valueBase64) }
        catch { throw 'Attestation signature is not valid Base64.' }
        $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($certificate)
        if ($null -eq $rsa) { throw 'Registered runtime builder certificate public key is not RSA.' }
        try {
            $valid = $rsa.VerifyData($canonical, $signatureBytes, [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
        } finally { $rsa.Dispose() }
        if (-not $valid) { throw "Runtime build attestation signature verification failed: $keyId" }
    } finally { $certificate.Dispose() }
    return $payload
}

function Test-Cf7RuntimeBuildConsensusV2 {
    param(
        [Parameter(Mandatory=$true)][object[]]$Attestations,
        [Parameter(Mandatory=$true)][string]$RegistryPath,
        [int]$MinimumConsensus = 0
    )
    $registry = Read-Cf7RuntimeV2BuilderRegistry -RegistryPath $RegistryPath
    if ($MinimumConsensus -eq 0) { $MinimumConsensus = [int]$registry.minimumConsensus }
    if ($MinimumConsensus -lt 2) { throw 'Runtime v2 consensus requires at least two builders.' }
    if ($Attestations.Count -lt $MinimumConsensus) { throw "Runtime v2 consensus requires at least $MinimumConsensus attestations." }
    $payloads = New-Object 'System.Collections.Generic.List[object]'
    foreach ($attestation in $Attestations) {
        $payload = Test-Cf7RuntimeBuildAttestationV2 -Attestation $attestation -RegistryPath $RegistryPath
        $payloads.Add($payload)
    }
    return Test-Cf7RuntimeVerifiedPayloadConsensusV2 -Payloads $payloads.ToArray() -MinimumConsensus $MinimumConsensus
}

function Assert-Cf7RuntimeGitHubProofEquivalentV2 {
    param(
        [Parameter(Mandatory=$true)][object]$Expected,
        [Parameter(Mandatory=$true)][object]$Actual
    )
    $topLevelFields = @('schema','payload','canonicalPayloadSha256','envelopeBase64','bundleBase64')
    foreach ($proof in @($Expected,$Actual)) {
        if ([string]$proof.schema -ne 'cf7-runtime-github-build-attestation.v2') {
            throw 'GitHub runtime proof has an unsupported schema.'
        }
        foreach ($property in @($proof.PSObject.Properties.Name)) {
            if ($topLevelFields -notcontains $property) { throw "Unexpected GitHub runtime proof field: $property" }
        }
        foreach ($field in $topLevelFields) {
            if ($null -eq $proof.PSObject.Properties[$field]) { throw "GitHub runtime proof lacks field: $field" }
        }
    }
    foreach ($field in @('schema','canonicalPayloadSha256','envelopeBase64','bundleBase64')) {
        if ([string]$Expected.$field -cne [string]$Actual.$field) {
            throw "GitHub runtime proof differs from fresh verification: $field"
        }
    }

    $payloadFields = @(
        'schema','builderKind','builderIdentityHash','faultDomain','repository','signerWorkflow',
        'sourceRef','runnerClass','sourceCommitOid','releaseTreeOid','artifactSourceHash',
        'producerRecipeHash','toolchainLockHash','buildIdentityHash','payloadClosureHash',
        'envelopeSha256','bundleSha256','files'
    )
    foreach ($payload in @($Expected.payload,$Actual.payload)) {
        foreach ($property in @($payload.PSObject.Properties.Name)) {
            if ($payloadFields -notcontains $property) { throw "Unexpected GitHub runtime proof payload field: $property" }
        }
        foreach ($field in $payloadFields) {
            if ($null -eq $payload.PSObject.Properties[$field]) { throw "GitHub runtime proof payload lacks field: $field" }
        }
    }
    foreach ($field in $payloadFields | Where-Object { $_ -ne 'files' }) {
        if ([string]$Expected.payload.$field -cne [string]$Actual.payload.$field) {
            throw "GitHub runtime proof payload differs from fresh verification: $field"
        }
    }

    $expectedFiles = @($Expected.payload.files)
    $actualFiles = @($Actual.payload.files)
    foreach ($file in @($expectedFiles) + @($actualFiles)) {
        foreach ($property in @($file.PSObject.Properties.Name)) {
            if (@('path','size','sha256') -notcontains $property) { throw "Unexpected GitHub runtime proof file field: $property" }
        }
        foreach ($field in @('path','size','sha256')) {
            if ($null -eq $file.PSObject.Properties[$field]) { throw "GitHub runtime proof file lacks field: $field" }
        }
    }
    [Array]::Sort($expectedFiles, [Comparison[object]]{
        param($left,$right)
        return [StringComparer]::Ordinal.Compare([string]$left.path,[string]$right.path)
    })
    [Array]::Sort($actualFiles, [Comparison[object]]{
        param($left,$right)
        return [StringComparer]::Ordinal.Compare([string]$left.path,[string]$right.path)
    })
    if ($expectedFiles.Count -ne $actualFiles.Count) { throw 'GitHub runtime proof file inventory count differs from fresh verification.' }
    for ($index = 0; $index -lt $expectedFiles.Count; $index++) {
        foreach ($field in @('path','size','sha256')) {
            if ([string]$expectedFiles[$index].$field -cne [string]$actualFiles[$index].$field) {
                throw "GitHub runtime proof file inventory differs from fresh verification: $field row=$index"
            }
        }
    }
    return $true
}

function Test-Cf7RuntimeVerifiedPayloadConsensusV2 {
    param(
        [Parameter(Mandatory=$true)][object[]]$Payloads,
        [ValidateRange(2,32)][int]$MinimumConsensus = 2
    )
    if ($Payloads.Count -lt $MinimumConsensus) {
        throw "Runtime v2 consensus requires at least $MinimumConsensus verified producer proofs."
    }
    $signerIdentities = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $rawSignerIds = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $faultDomains = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($payload in $Payloads) {
        $schema = [string]$payload.schema
        if ($schema -eq 'cf7-runtime-build-attestation-payload.v2') {
            $rawSignerId = ([string]$payload.builderKeyId).ToUpperInvariant()
            $signerIdentity = 'x509:' + $rawSignerId
        } elseif ($schema -eq 'cf7-runtime-github-build-attestation-payload.v2') {
            if ([string]$payload.builderKind -ne 'github-oidc') { throw 'Unsupported GitHub runtime builder kind.' }
            $rawSignerId = ([string]$payload.builderIdentityHash).ToUpperInvariant()
            $signerIdentity = 'github-oidc:' + $rawSignerId
        } else {
            throw "Unsupported verified producer payload schema: $schema"
        }
        if ($rawSignerId -notmatch '^[0-9A-F]{64}$') { throw 'Verified producer proof has an invalid signer identity.' }
        if ([string]$payload.faultDomain -notmatch '^[a-z0-9][a-z0-9._-]{1,63}$') { throw 'Verified producer proof has an invalid faultDomain.' }
        foreach ($field in @('artifactSourceHash','producerRecipeHash','toolchainLockHash','buildIdentityHash','payloadClosureHash')) {
            if ([string]$payload.$field -notmatch '^[0-9A-Fa-f]{64}$') { throw "Verified producer proof has an invalid field: $field" }
        }
        $expectedBuildIdentity = Get-Cf7RuntimeV2BuildIdentityHash `
            -ArtifactSourceHash ([string]$payload.artifactSourceHash) `
            -ProducerRecipeHash ([string]$payload.producerRecipeHash) `
            -ToolchainLockHash ([string]$payload.toolchainLockHash)
        if ($expectedBuildIdentity -ne ([string]$payload.buildIdentityHash).ToUpperInvariant()) {
            throw 'Verified producer proof has an inconsistent buildIdentityHash.'
        }
        $expectedClosure = Get-Cf7RuntimeV2CanonicalClosureHash -Files @($payload.files)
        if ($expectedClosure -ne ([string]$payload.payloadClosureHash).ToUpperInvariant()) {
            throw 'Verified producer proof has an inconsistent payloadClosureHash.'
        }
        if (-not $signerIdentities.Add($signerIdentity)) { throw "Duplicate runtime builder identity: $signerIdentity" }
        [void]$rawSignerIds.Add($rawSignerId)
        if (-not $faultDomains.Add([string]$payload.faultDomain)) { throw "Duplicate runtime builder faultDomain: $($payload.faultDomain)" }
    }
    if ($signerIdentities.Count -lt $MinimumConsensus -or $faultDomains.Count -lt $MinimumConsensus) {
        throw 'Runtime v2 consensus lacks independent builder identities or fault domains.'
    }
    $reference = $payloads[0]
    foreach ($payload in $Payloads | Select-Object -Skip 1) {
        foreach ($field in @('artifactSourceHash','producerRecipeHash','toolchainLockHash','buildIdentityHash','payloadClosureHash')) {
            if (([string]$payload.$field).ToUpperInvariant() -ne ([string]$reference.$field).ToUpperInvariant()) {
                throw "Runtime v2 consensus mismatch: $field"
            }
        }
    }
    return [pscustomobject][ordered]@{
        schema = 'cf7-runtime-build-consensus-result.v2'
        artifactSourceHash = $reference.artifactSourceHash
        producerRecipeHash = $reference.producerRecipeHash
        toolchainLockHash = $reference.toolchainLockHash
        buildIdentityHash = $reference.buildIdentityHash
        payloadClosureHash = $reference.payloadClosureHash
        signerIdentities = @($signerIdentities)
        builderKeyIds = @($rawSignerIds)
        faultDomains = @($faultDomains)
        files = $reference.files
    }
}
