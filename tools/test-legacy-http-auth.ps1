$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'lib\LegacyHttpAuth.ps1')

$scratch = Join-Path ([IO.Path]::GetTempPath()) (
    'cf7-legacy-http-auth-ps-' + [Guid]::NewGuid().ToString('N'))
$projectRoot = Join-Path $scratch 'Project'
$localAppData = Join-Path $scratch 'LocalAppData'
$checks = 0

function Assert-Cf7 {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Condition,
        [Parameter(Mandatory = $true)]
        [string]$Message
    )
    if (-not $Condition) { throw $Message }
    $script:checks++
}

try {
    New-Item -ItemType Directory -Path $projectRoot -Force | Out-Null
    $credentialPath = Get-Cf7LegacyHttpExpectedCredentialPath `
        -ProjectRoot $projectRoot -LocalAppData $localAppData
    New-Item -ItemType Directory -Path (
        Split-Path -Parent $credentialPath) -Force | Out-Null
    $process = Get-Process -Id $PID
    $tokenBytes = New-Object byte[] 32
    $random = [Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $random.GetBytes($tokenBytes)
    } finally {
        $random.Dispose()
    }
    $token = [Convert]::ToBase64String($tokenBytes).
        TrimEnd('=').Replace('+', '-').Replace('/', '_')
    $ports = [ordered]@{
        pid = $PID
        httpPort = 1192
        socketPort = 1193
        legacyHttpAuthFile = $credentialPath
    }
    $credential = [ordered]@{
        v = 1
        kind = 'legacy_http_automation'
        pid = $PID
        processStartUtcTicks = [string](
            $process.StartTime.ToUniversalTime().Ticks)
        lifecycleId = 'test-lifecycle'
        header = 'X-CF7-Automation-Token'
        token = $token
        capabilities = @('legacy.task')
    }
    [IO.File]::WriteAllText(
        (Join-Path $projectRoot 'launcher_ports.json'),
        ($ports | ConvertTo-Json -Compress),
        [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText(
        $credentialPath,
        ($credential | ConvertTo-Json -Compress),
        [Text.UTF8Encoding]::new($false))

    $context = Get-Cf7LegacyHttpContext `
        -ProjectRoot $projectRoot -LocalAppData $localAppData
    Assert-Cf7 ($context.Pid -eq $PID) 'PID binding failed'
    Assert-Cf7 ($context.Token -ceq $token) 'token binding failed'
    Assert-Cf7 (
        $context.CredentialFile.Equals(
            $credentialPath, [StringComparison]::OrdinalIgnoreCase)
    ) 'credential path binding failed'

    $ports.legacyHttpAuthFile = Join-Path $scratch 'attacker.json'
    [IO.File]::WriteAllText(
        (Join-Path $projectRoot 'launcher_ports.json'),
        ($ports | ConvertTo-Json -Compress),
        [Text.UTF8Encoding]::new($false))
    $rejected = $false
    try {
        Get-Cf7LegacyHttpContext `
            -ProjectRoot $projectRoot -LocalAppData $localAppData | Out-Null
    } catch {
        $rejected = $_.Exception.Message -eq (
            'legacy_http_credential_path_mismatch')
    }
    Assert-Cf7 $rejected 'mismatched credential path was accepted'

    Write-Host "legacy-http-auth PowerShell tests: $checks/4 passed"
} finally {
    if (Test-Path -LiteralPath $scratch) {
        Remove-Item -LiteralPath $scratch -Recurse -Force
    }
}
