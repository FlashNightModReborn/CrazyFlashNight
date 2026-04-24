param(
    [int]$DurationSeconds = 6,
    [int]$IntervalMs = 500,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
chcp.com 65001 | Out-Null

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$duration = [Math]::Max(1, $DurationSeconds)
$interval = [Math]::Max(100, $IntervalMs)
$sampleCount = [Math]::Max(1, [int][Math]::Ceiling(($duration * 1000.0) / $interval))

function Resolve-Group {
    param($Process)

    if ($Process.Name -eq "CRAZYFLASHER7MercenaryEmpire.exe" -and $Process.ExecutablePath -like "$projectRoot*") {
        return "launcher"
    }
    if ($Process.Name -eq "Adobe Flash Player 20.exe" -and $Process.ExecutablePath -like "$projectRoot*") {
        return "flash"
    }
    if ($Process.Name -eq "msedgewebview2.exe" -and $Process.CommandLine -like "*launcher\webview2_overlay_userdata*") {
        return "web_overlay"
    }
    if ($Process.Name -eq "msedgewebview2.exe" -and $Process.CommandLine -like "*launcher\webview2_userdata*") {
        return "bootstrap"
    }

    return $null
}

$processes = Get-CimInstance Win32_Process |
    Where-Object {
        $_.Name -in @("CRAZYFLASHER7MercenaryEmpire.exe", "Adobe Flash Player 20.exe", "msedgewebview2.exe")
    } |
    ForEach-Object {
        $group = Resolve-Group $_
        if ($group) {
            [pscustomobject]@{
                ProcessId = [int]$_.ProcessId
                ParentProcessId = [int]$_.ParentProcessId
                Name = $_.Name
                Group = $group
                ExecutablePath = $_.ExecutablePath
            }
        }
    }

$pidToGroup = @{}
foreach ($process in $processes) {
    $pidToGroup[$process.ProcessId] = $process.Group
}

if ($pidToGroup.Count -eq 0) {
    $emptyPayload = [pscustomobject]@{
        ProjectRoot = $projectRoot
        DurationSeconds = $duration
        IntervalMs = $interval
        ProcessSnapshot = @()
        Results = @()
    }
    if ($Json) {
        $emptyPayload | ConvertTo-Json -Depth 5
    } else {
        Write-Host "Process snapshot:"
        Write-Host "(no CF7 launcher, Flash, or project WebView2 processes found)"
        Write-Host ""
        Write-Host "GPU engine samples skipped."
    }
    exit 0
}

$buckets = @{}
for ($sample = 0; $sample -lt $sampleCount; $sample++) {
    $engines = Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine |
        Where-Object { $_.UtilizationPercentage -gt 0 }

    foreach ($engine in $engines) {
        if ($engine.Name -notmatch "pid_(\d+)_") { continue }

        $engineProcessId = [int]$Matches[1]
        if (-not $pidToGroup.ContainsKey($engineProcessId)) { continue }

        $engineType = "unknown"
        if ($engine.Name -match "engtype_([^_]+)") {
            $engineType = $Matches[1]
        }

        $adapter = "phys_?"
        if ($engine.Name -match "phys_(\d+)") {
            $adapter = "phys_" + $Matches[1]
        }

        $key = $pidToGroup[$engineProcessId] + "|" + $adapter + "|" + $engineType
        if (-not $buckets.ContainsKey($key)) {
            $buckets[$key] = New-Object "System.Collections.Generic.List[double]"
        }
        [void]$buckets[$key].Add([double]$engine.UtilizationPercentage)
    }

    if ($sample -lt ($sampleCount - 1)) {
        Start-Sleep -Milliseconds $interval
    }
}

$results = foreach ($key in $buckets.Keys) {
    $parts = $key -split "\|"
    $values = $buckets[$key]
    [pscustomobject]@{
        Group = $parts[0]
        Adapter = $parts[1]
        Engine = $parts[2]
        Avg = [Math]::Round(($values | Measure-Object -Average).Average, 2)
        Max = [Math]::Round(($values | Measure-Object -Maximum).Maximum, 2)
        Samples = $values.Count
    }
}

$payload = [pscustomobject]@{
    ProjectRoot = $projectRoot
    DurationSeconds = $duration
    IntervalMs = $interval
    ProcessSnapshot = $processes
    Results = @($results | Sort-Object Avg -Descending)
}

if ($Json) {
    $payload | ConvertTo-Json -Depth 5
    exit 0
}

Write-Host "Process snapshot:"
if ($processes) {
    $processes | Select-Object ProcessId,ParentProcessId,Group,Name | Sort-Object Group,ProcessId | Format-Table -AutoSize
} else {
    Write-Host "(no CF7 launcher, Flash, or project WebView2 processes found)"
}

Write-Host ""
Write-Host ("GPU engine samples ({0}s, {1}ms interval):" -f $duration, $interval)
if ($results) {
    $results | Sort-Object Avg -Descending | Format-Table -AutoSize
} else {
    Write-Host "(no matching GPU engine activity sampled)"
}
