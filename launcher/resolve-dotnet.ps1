# Shared .NET SDK host resolver for Launcher build/test entrypoints.
# The repository currently uses global.json rollForward=disable, so selection and
# the final repo-root --version probe must both match the pinned SDK exactly.

function Get-Cf7DotnetSdkContract {
    param([Parameter(Mandatory=$true)][string]$ProjectRoot)

    $globalJsonPath = Join-Path $ProjectRoot 'global.json'
    if (-not (Test-Path -LiteralPath $globalJsonPath)) {
        throw "global.json missing: $globalJsonPath"
    }

    try {
        $globalJson = Get-Content -Raw -Encoding UTF8 -LiteralPath $globalJsonPath | ConvertFrom-Json
    } catch {
        throw "global.json is invalid: $globalJsonPath ($($_.Exception.Message))"
    }

    $requiredText = [string]$globalJson.sdk.version
    if ([string]::IsNullOrWhiteSpace($requiredText)) {
        throw "global.json sdk.version missing: $globalJsonPath"
    }
    try {
        $required = [Version]$requiredText
    } catch {
        throw "global.json sdk.version is invalid: $requiredText"
    }

    $rollForward = [string]$globalJson.sdk.rollForward
    if ([string]::IsNullOrWhiteSpace($rollForward)) {
        throw "global.json sdk.rollForward missing; resolver fails closed"
    }
    if (-not [string]::Equals($rollForward, 'disable', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsupported global.json sdk.rollForward '$rollForward'; resolver currently requires 'disable'"
    }

    return [PSCustomObject]@{
        VersionText = $requiredText
        Version = $required
        RollForward = 'disable'
    }
}

function Select-Cf7DotnetSdkVersion {
    param(
        [Parameter(Mandatory=$true)][Version]$RequiredVersion,
        [Parameter(Mandatory=$true)][string]$RollForward,
        [Version[]]$InstalledVersions = @()
    )

    if ([string]::IsNullOrWhiteSpace($RollForward)) {
        throw "SDK rollForward policy missing; selector fails closed"
    }
    if (-not [string]::Equals($RollForward, 'disable', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsupported SDK rollForward '$RollForward'; selector currently requires 'disable'"
    }

    return @($InstalledVersions | Where-Object { $_.Equals($RequiredVersion) }) |
        Select-Object -First 1
}

function Resolve-Cf7Dotnet {
    param([Parameter(Mandatory=$true)][string]$ProjectRoot)

    $contract = Get-Cf7DotnetSdkContract -ProjectRoot $ProjectRoot
    $requiredText = $contract.VersionText
    $required = $contract.Version

    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\dotnet\dotnet.exe'),
        (Join-Path $env:USERPROFILE '.dotnet\dotnet.exe')
    )
    $pathHost = Get-Command dotnet -ErrorAction SilentlyContinue
    if ($pathHost) { $candidates += $pathHost.Source }
    $candidates += @(
        (Join-Path $env:ProgramFiles 'dotnet\dotnet.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'dotnet\dotnet.exe')
    )

    $seen = @{}
    $probed = @()
    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        $fullPath = [IO.Path]::GetFullPath($candidate)
        $key = $fullPath.ToLowerInvariant()
        if ($seen[$key] -or -not (Test-Path -LiteralPath $fullPath)) { continue }
        $seen[$key] = $true
        try {
            $sdkLines = @(& $fullPath --list-sdks 2>$null)
            $versions = @()
            foreach ($line in $sdkLines) {
                $match = [regex]::Match([string]$line, '^(\d+\.\d+\.\d+)\s')
                if ($match.Success) { $versions += [Version]$match.Groups[1].Value }
            }
            $probed += "$fullPath => $($versions -join ', ')"
            $selected = Select-Cf7DotnetSdkVersion `
                -RequiredVersion $required `
                -RollForward $contract.RollForward `
                -InstalledVersions $versions
            if (-not $selected) { continue }

            Push-Location -LiteralPath $ProjectRoot
            try {
                $actualLines = @(& $fullPath --version 2>$null)
                $actualExitCode = $LASTEXITCODE
            } finally {
                Pop-Location
            }
            $actualText = [string](@($actualLines | ForEach-Object { ([string]$_).Trim() } |
                Where-Object { $_ -match '^\d+\.\d+\.\d+$' } |
                Select-Object -First 1))
            if ($actualExitCode -eq 0 -and [string]::Equals($actualText, $requiredText, [StringComparison]::Ordinal)) {
                return $fullPath
            }
            $probed += "$fullPath => repo-root --version '$actualText' (exit=$actualExitCode), expected $requiredText"
        } catch {
            $probed += "$fullPath => probe failed: $($_.Exception.Message)"
        }
    }
    throw "No dotnet host can satisfy global.json SDK $requiredText with rollForward=disable. Probed: $($probed -join '; ')"
}
