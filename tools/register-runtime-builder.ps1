param(
    [Parameter(Mandatory=$true)][ValidatePattern('^[a-z0-9][a-z0-9._-]{1,63}$')][string]$BuilderId,
    [Parameter(Mandatory=$true)][ValidatePattern('^[a-z0-9][a-z0-9._-]{1,63}$')][string]$FaultDomain,
    [ValidateRange(1,2147483647)][int]$Epoch = 1,
    [ValidateRange(1,10)][int]$ValidYears = 3,
    [string]$ProjectRoot,
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
if (-not $ProjectRoot) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
. (Join-Path $ProjectRoot 'tools\runtime-build-v2-common.ps1')
. (Join-Path $ProjectRoot 'tools\runtime-build-attestation-v2-common.ps1')

if (-not (Get-Command New-SelfSignedCertificate -ErrorAction SilentlyContinue)) {
    throw 'New-SelfSignedCertificate is unavailable; enroll builders on Windows with the PKI module installed.'
}

$subject = "CN=CF7 Runtime Builder $BuilderId"
$certificate = New-SelfSignedCertificate `
    -Type Custom `
    -Subject $subject `
    -FriendlyName "CF7 runtime builder $BuilderId" `
    -CertStoreLocation 'Cert:\CurrentUser\My' `
    -KeyAlgorithm RSA `
    -KeyLength 3072 `
    -HashAlgorithm SHA256 `
    -KeyExportPolicy NonExportable `
    -KeyUsage DigitalSignature `
    -NotBefore ([DateTime]::UtcNow.AddMinutes(-5)) `
    -NotAfter ([DateTime]::UtcNow.AddYears($ValidYears)) `
    -TextExtension @('2.5.29.19={critical}{text}ca=false', '2.5.29.37={text}1.3.6.1.5.5.7.3.3')

try {
    if (-not $certificate.HasPrivateKey) { throw 'Enrollment produced a certificate without a private key.' }
    $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($certificate)
    if ($null -eq $rsa) { throw 'Enrollment produced a non-RSA private key.' }
    try {
        if ($rsa -is [System.Security.Cryptography.RSACryptoServiceProvider] -and $rsa.CspKeyContainerInfo.Exportable) {
            throw 'Enrollment provider ignored the non-exportable key requirement.'
        }
        if ($rsa.GetType().FullName -eq 'System.Security.Cryptography.RSACng') {
            $exportPolicy = [string]$rsa.Key.ExportPolicy
            if ($exportPolicy -match 'AllowExport') { throw 'Enrollment provider created an exportable CNG key.' }
        }
    } finally { $rsa.Dispose() }

    $entry = [pscustomobject][ordered]@{
        builderId = $BuilderId
        keyId = Get-Cf7RuntimeV2BuilderKeyId -Certificate $certificate
        certificateThumbprint = $certificate.Thumbprint.Replace(' ', '').ToUpperInvariant()
        certificateBase64 = [Convert]::ToBase64String($certificate.RawData)
        enabled = $true
        epoch = $Epoch
        faultDomain = $FaultDomain
        subject = $certificate.Subject
        notBeforeUtc = $certificate.NotBefore.ToUniversalTime().ToString('o')
        notAfterUtc = $certificate.NotAfter.ToUniversalTime().ToString('o')
    }
    if (-not $OutputPath) {
        $outputDirectory = Join-Path $ProjectRoot 'tmp\runtime-builder-enrollment'
        if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) { New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null }
        $OutputPath = Join-Path $outputDirectory ("$BuilderId-$($entry.keyId.Substring(0, 16)).json")
    } elseif (-not [IO.Path]::IsPathRooted($OutputPath)) {
        $OutputPath = Join-Path $ProjectRoot $OutputPath
    }
    $parent = Split-Path -Parent $OutputPath
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $utf8NoBom = New-Object Text.UTF8Encoding($false)
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath), ($entry | ConvertTo-Json -Depth 5) + "`n", $utf8NoBom)
    Write-Host "[RuntimeBuilderEnrollment] Created non-exportable CurrentUser certificate: $($entry.certificateThumbprint)" -ForegroundColor Green
    Write-Host "[RuntimeBuilderEnrollment] Registry entry written (registry was not modified): $([IO.Path]::GetFullPath($OutputPath))" -ForegroundColor Green
    return $entry
} catch {
    if ($certificate -and $certificate.Thumbprint) {
        $failedThumbprint = $certificate.Thumbprint.Replace(' ', '')
        $failedPath = "Cert:\CurrentUser\My\$failedThumbprint"
        if (Test-Path -LiteralPath $failedPath) { Remove-Item -LiteralPath $failedPath -Force }
    }
    throw
} finally {
    if ($certificate) { $certificate.Dispose() }
}
