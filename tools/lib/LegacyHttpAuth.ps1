Set-StrictMode -Version 2.0

$script:Cf7LegacyHttpHeaderName = 'X-CF7-Automation-Token'
$script:Cf7LegacyHttpTokenPattern = '^[A-Za-z0-9_-]{43}$'

function Get-Cf7LegacyHttpProjectRootHash {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    $canonical = [IO.Path]::GetFullPath($ProjectRoot).
        TrimEnd([char[]]@('\', '/')).ToUpperInvariant()
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $digest = $sha.ComputeHash(
            [Text.Encoding]::UTF8.GetBytes($canonical))
        return (($digest | Select-Object -First 16 | ForEach-Object {
            $_.ToString('x2')
        }) -join '')
    } finally {
        $sha.Dispose()
    }
}

function Get-Cf7LegacyHttpExpectedCredentialPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot,
        [string]$LocalAppData = [Environment]::GetFolderPath(
            [Environment+SpecialFolder]::LocalApplicationData)
    )

    if ([string]::IsNullOrWhiteSpace($LocalAppData)) {
        throw 'legacy_http_localappdata_unavailable'
    }
    return [IO.Path]::GetFullPath((Join-Path $LocalAppData (
        'CF7FlashNight\agent-runtime\v1\' +
        (Get-Cf7LegacyHttpProjectRootHash -ProjectRoot $ProjectRoot) +
        '\legacy-http-credential.json')))
}

function Assert-Cf7RegularFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LiteralPath,
        [Parameter(Mandatory = $true)]
        [string]$ErrorCode
    )

    $item = Get-Item -LiteralPath $LiteralPath -Force -ErrorAction Stop
    if ($item.PSIsContainer -or
        (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
        throw $ErrorCode
    }
    return $item
}

function Get-Cf7LauncherPortsRecord {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot,
        [switch]$SkipProcessCheck
    )

    $root = [IO.Path]::GetFullPath($ProjectRoot)
    $portsFile = Join-Path $root 'launcher_ports.json'
    try {
        Assert-Cf7RegularFile -LiteralPath $portsFile `
            -ErrorCode 'legacy_http_ports_file_invalid' | Out-Null
        $ports = [IO.File]::ReadAllText(
            $portsFile, [Text.Encoding]::UTF8) | ConvertFrom-Json
    } catch {
        if ($_.Exception.Message -like 'legacy_http_*') { throw }
        throw 'legacy_http_ports_json_invalid'
    }

    $pidValue = 0
    $httpPort = 0
    $socketPort = 0
    if ($null -eq $ports -or
        -not [int]::TryParse([string]$ports.pid, [ref]$pidValue) -or
        $pidValue -le 0 -or
        -not [int]::TryParse([string]$ports.httpPort, [ref]$httpPort) -or
        $httpPort -lt 1 -or $httpPort -gt 65535 -or
        -not [int]::TryParse([string]$ports.socketPort, [ref]$socketPort) -or
        $socketPort -lt 1 -or $socketPort -gt 65535 -or
        $httpPort -eq $socketPort) {
        throw 'legacy_http_ports_shape_invalid'
    }

    if (-not $SkipProcessCheck) {
        if ($null -eq (Get-Process -Id $pidValue -ErrorAction SilentlyContinue)) {
            throw 'legacy_http_ports_pid_not_running'
        }
    }

    $authFile = if ($ports.PSObject.Properties.Name -contains (
            'legacyHttpAuthFile')) {
        [string]$ports.legacyHttpAuthFile
    } else {
        ''
    }
    return [pscustomobject]@{
        ProjectRoot = $root
        PortsFile = $portsFile
        Pid = $pidValue
        HttpPort = $httpPort
        SocketPort = $socketPort
        LegacyHttpAuthFile = $authFile
    }
}

function Get-Cf7LegacyHttpContext {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot,
        [string]$LocalAppData = [Environment]::GetFolderPath(
            [Environment+SpecialFolder]::LocalApplicationData)
    )

    $ports = Get-Cf7LauncherPortsRecord -ProjectRoot $ProjectRoot
    $expectedPath = Get-Cf7LegacyHttpExpectedCredentialPath `
        -ProjectRoot $ports.ProjectRoot -LocalAppData $LocalAppData
    if ([string]::IsNullOrWhiteSpace($ports.LegacyHttpAuthFile)) {
        throw 'legacy_http_credential_path_missing'
    }
    $advertisedPath = [IO.Path]::GetFullPath($ports.LegacyHttpAuthFile)
    if (-not $advertisedPath.Equals(
            $expectedPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'legacy_http_credential_path_mismatch'
    }

    try {
        Assert-Cf7RegularFile -LiteralPath $expectedPath `
            -ErrorCode 'legacy_http_credential_not_regular_file' | Out-Null
        $credential = [IO.File]::ReadAllText(
            $expectedPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    } catch {
        if ($_.Exception.Message -like 'legacy_http_*') { throw }
        throw 'legacy_http_credential_invalid'
    }

    $credentialPid = 0
    $startTicks = 0L
    $capabilities = @($credential.capabilities)
    if ($null -eq $credential -or
        [int]$credential.v -ne 1 -or
        [string]$credential.kind -cne 'legacy_http_automation' -or
        -not [int]::TryParse([string]$credential.pid, [ref]$credentialPid) -or
        $credentialPid -ne $ports.Pid -or
        [string]$credential.header -cne $script:Cf7LegacyHttpHeaderName -or
        [string]::IsNullOrWhiteSpace([string]$credential.lifecycleId) -or
        -not [long]::TryParse(
            [string]$credential.processStartUtcTicks, [ref]$startTicks) -or
        $startTicks -le 0 -or
        [string]$credential.token -cnotmatch $script:Cf7LegacyHttpTokenPattern -or
        $capabilities.Count -eq 0) {
        throw 'legacy_http_credential_invalid'
    }

    try {
        $process = Get-Process -Id $ports.Pid -ErrorAction Stop
        $actualStartTicks = $process.StartTime.ToUniversalTime().Ticks
        $process.Dispose()
    } catch {
        throw 'legacy_http_credential_process_identity_unavailable'
    }
    if ($actualStartTicks -ne $startTicks) {
        throw 'legacy_http_credential_process_identity_mismatch'
    }

    return [pscustomobject]@{
        ProjectRoot = $ports.ProjectRoot
        PortsFile = $ports.PortsFile
        Pid = $ports.Pid
        HttpPort = $ports.HttpPort
        SocketPort = $ports.SocketPort
        CredentialFile = $expectedPath
        HeaderName = $script:Cf7LegacyHttpHeaderName
        Token = [string]$credential.token
        Headers = @{
            $script:Cf7LegacyHttpHeaderName = [string]$credential.token
        }
    }
}
