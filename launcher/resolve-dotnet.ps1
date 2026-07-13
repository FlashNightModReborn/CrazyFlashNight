# Shared .NET SDK host resolver for Launcher build/test entrypoints.
# Selects a host that can satisfy the repo-root global.json feature band without
# changing machine/user PATH, so side-by-side legacy SDK consumers remain safe.

function Resolve-Cf7Dotnet {
    param([Parameter(Mandatory=$true)][string]$ProjectRoot)

    $globalJsonPath = Join-Path $ProjectRoot 'global.json'
    if (-not (Test-Path -LiteralPath $globalJsonPath)) {
        throw "global.json missing: $globalJsonPath"
    }
    $globalJson = Get-Content -Raw -Encoding UTF8 -LiteralPath $globalJsonPath | ConvertFrom-Json
    $requiredText = [string]$globalJson.sdk.version
    $required = [Version]$requiredText
    $requiredFeatureBand = [Math]::Floor($required.Build / 100) * 100

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
            $compatible = $versions | Where-Object {
                ($_.Major -eq $required.Major -and
                    $_.Minor -eq $required.Minor -and
                    ([Math]::Floor($_.Build / 100) * 100) -eq $requiredFeatureBand -and
                    $_ -ge $required)
            } | Sort-Object -Descending | Select-Object -First 1
            if ($compatible) { return $fullPath }
        } catch {
            $probed += "$fullPath => probe failed: $($_.Exception.Message)"
        }
    }
    throw "No dotnet host can satisfy global.json SDK $requiredText. Probed: $($probed -join '; ')"
}
