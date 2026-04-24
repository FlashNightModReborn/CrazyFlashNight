param(
    [switch]$Apply,
    [switch]$Revert,
    [switch]$List
)

$ErrorActionPreference = "Stop"
chcp.com 65001 | Out-Null

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$registryPath = "HKCU:\Software\Microsoft\DirectX\UserGpuPreferences"
$highPerformanceValue = "GpuPreference=2;"

function Add-Candidate {
    param(
        [System.Collections.Generic.List[string]]$Candidates,
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    try {
        $resolved = [System.IO.Path]::GetFullPath($Path)
    } catch {
        return
    }
    if ((Test-Path -LiteralPath $resolved) -and -not $Candidates.Contains($resolved)) {
        [void]$Candidates.Add($resolved)
    }
}

function Get-CandidateExecutables {
    $candidates = New-Object "System.Collections.Generic.List[string]"

    Add-Candidate $candidates (Join-Path $projectRoot "CRAZYFLASHER7MercenaryEmpire.exe")
    Add-Candidate $candidates (Join-Path $projectRoot "Adobe Flash Player 20.exe")
    Add-Candidate $candidates (Join-Path $projectRoot "launcher\bin\Release\CRAZYFLASHER7MercenaryEmpire.exe")
    Add-Candidate $candidates (Join-Path $projectRoot "launcher\bin\Debug\CRAZYFLASHER7MercenaryEmpire.exe")
    Add-Candidate $candidates (Join-Path $projectRoot "launcher\bin\CRAZYFLASHER7MercenaryEmpire.exe")

    $edgeBase = Join-Path ${env:ProgramFiles(x86)} "Microsoft\EdgeWebView\Application"
    if (Test-Path -LiteralPath $edgeBase) {
        Get-ChildItem -LiteralPath $edgeBase -Directory -ErrorAction SilentlyContinue |
            ForEach-Object {
                Add-Candidate $candidates (Join-Path $_.FullName "msedgewebview2.exe")
            }
    }

    return $candidates
}

function Get-PreferenceValue {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $registryPath)) { return $null }
    $item = Get-ItemProperty -LiteralPath $registryPath
    $property = $item.PSObject.Properties[$Path]
    if ($null -eq $property) { return $null }
    return $property.Value
}

$candidates = Get-CandidateExecutables

if ($candidates.Count -eq 0) {
    Write-Error "No candidate executables found from project root: $projectRoot"
}

if (-not $Apply -and -not $Revert -and -not $List) {
    $List = $true
}

if ($Apply -and $Revert) {
    Write-Error "Use either -Apply or -Revert, not both."
}

if ($Apply) {
    New-Item -Path $registryPath -Force | Out-Null
    foreach ($path in $candidates) {
        New-ItemProperty -Path $registryPath -Name $path -Value $highPerformanceValue -PropertyType String -Force | Out-Null
        Write-Host "[set] $path -> $highPerformanceValue"
    }
    Write-Host ""
    Write-Host "Applied. Fully close and restart the launcher/game for Windows and WebView2 to pick up the preference."
}

if ($Revert) {
    if (Test-Path -LiteralPath $registryPath) {
        foreach ($path in $candidates) {
            $current = Get-PreferenceValue $path
            if ($null -ne $current) {
                Remove-ItemProperty -Path $registryPath -Name $path -ErrorAction SilentlyContinue
                Write-Host "[removed] $path"
            }
        }
    }
    Write-Host ""
    Write-Host "Reverted known CF7 launcher GPU preference entries. Restart the launcher/game."
}

if ($List) {
    Write-Host "Candidate executables:"
    foreach ($path in $candidates) {
        $value = Get-PreferenceValue $path
        if ($null -eq $value) { $value = "(not set)" }
        Write-Host ("[{0}] {1}" -f $value, $path)
    }
    Write-Host ""
    Write-Host "Use -Apply to set GpuPreference=2; use -Revert to remove these entries."
}
