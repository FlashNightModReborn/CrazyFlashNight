param(
    [int]$Runs = 5,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$ScriptDir = Split-Path -Parent $PSCommandPath
$CycleScript = Join-Path $ScriptDir 'protocol_latency_cycle.ps1'

function Get-PercentileValue {
    param(
        [double[]]$SortedValues,
        [double]$Percentile
    )

    if ($null -eq $SortedValues -or $SortedValues.Length -eq 0) {
        return $null
    }
    if ($SortedValues.Length -eq 1) {
        return [double]$SortedValues[0]
    }

    $rank = ($Percentile / 100.0) * ($SortedValues.Length - 1)
    $lower = [int][Math]::Floor($rank)
    $upper = [int][Math]::Ceiling($rank)
    if ($lower -eq $upper) {
        return [double]$SortedValues[$lower]
    }
    $weight = $rank - $lower
    return [double]($SortedValues[$lower] + (($SortedValues[$upper] - $SortedValues[$lower]) * $weight))
}

function Add-NumberSample {
    param(
        [hashtable]$Store,
        [string]$Name,
        [AllowNull()]$Value
    )

    if ($null -eq $Value) {
        throw "Protocol latency sample '$Name' is null; refusing to coerce it to zero."
    }
    try {
        $number = [System.Convert]::ToDouble(
            $Value, [System.Globalization.CultureInfo]::InvariantCulture)
    } catch {
        throw "Protocol latency sample '$Name' is not numeric."
    }
    if ([double]::IsNaN($number) -or [double]::IsInfinity($number) -or
        $number -lt 0) {
        throw "Protocol latency sample '$Name' is negative or non-finite."
    }
    if (-not $Store.ContainsKey($Name)) {
        $Store[$Name] = New-Object System.Collections.ArrayList
    }
    [void]$Store[$Name].Add($number)
}

function Build-Stats {
    param([System.Collections.IList]$Values)

    if ($null -eq $Values -or $Values.Count -eq 0) {
        return [ordered]@{
            count = 0
            min = $null
            p50 = $null
            p90 = $null
            p95 = $null
            avg = $null
            max = $null
            span = $null
        }
    }

    $sorted = @($Values | ForEach-Object { [double]$_ } | Sort-Object)
    $sum = 0.0
    foreach ($v in $sorted) { $sum += $v }
    $min = [double]$sorted[0]
    $max = [double]$sorted[$sorted.Length - 1]

    return [ordered]@{
        count = $sorted.Length
        min = [Math]::Round($min, 2)
        p50 = [Math]::Round((Get-PercentileValue -SortedValues $sorted -Percentile 50), 2)
        p90 = [Math]::Round((Get-PercentileValue -SortedValues $sorted -Percentile 90), 2)
        p95 = [Math]::Round((Get-PercentileValue -SortedValues $sorted -Percentile 95), 2)
        avg = [Math]::Round(($sum / $sorted.Length), 2)
        max = [Math]::Round($max, 2)
        span = [Math]::Round(($max - $min), 2)
    }
}

if ($Runs -lt 1) {
    throw "Runs must be >= 1."
}

$runResults = New-Object System.Collections.ArrayList
$connectSamples = @{
    ports_file_ms = New-Object System.Collections.ArrayList
    socket_port_ms = New-Object System.Collections.ArrayList
    socket_connected_ms = New-Object System.Collections.ArrayList
}
$metricSamples = @{}

for ($runIndex = 1; $runIndex -le $Runs; $runIndex++) {
    Write-Host ("[sweep] run {0}/{1}" -f $runIndex, $Runs)
    $jsonText = & $CycleScript -StopBusAfter -Json | Out-String
    $cycleExitCode = $LASTEXITCODE
    if ($cycleExitCode -ne 0) {
        throw "Protocol latency cycle failed with exit code $cycleExitCode; refusing to include its JSON in sweep statistics."
    }
    if ([string]::IsNullOrWhiteSpace($jsonText)) {
        throw 'Protocol latency cycle returned no JSON; refusing to record a zero-valued sample.'
    }
    $run = $jsonText | ConvertFrom-Json
    if ($null -eq $run.connect -or $null -eq $run.metrics -or
        $null -eq $run.raw_samples) {
        throw 'Protocol latency cycle JSON is missing connect, metrics, or raw_samples.'
    }
    if ($null -ne $run.failures -and @($run.failures).Count -gt 0) {
        throw 'Protocol latency cycle returned failure records with exit code zero.'
    }
    [void]$runResults.Add($run)

    Add-NumberSample -Store $connectSamples -Name 'ports_file_ms' -Value $run.connect.ports_file_ms
    Add-NumberSample -Store $connectSamples -Name 'socket_port_ms' -Value $run.connect.socket_port_ms
    Add-NumberSample -Store $connectSamples -Name 'socket_connected_ms' -Value $run.connect.socket_connected_ms

    foreach ($metricProp in $run.metrics.PSObject.Properties) {
        $rawProp = $run.raw_samples.PSObject.Properties[$metricProp.Name]
        if ($null -eq $rawProp) {
            throw "Protocol latency JSON is missing raw samples for '$($metricProp.Name)'."
        }
        $declaredCount = $metricProp.Value.count
        if ($null -eq $declaredCount -or
            [int]$declaredCount -ne @($rawProp.Value).Count) {
            throw "Protocol latency metric '$($metricProp.Name)' count does not match its raw samples."
        }
        foreach ($sample in @($rawProp.Value)) {
            Add-NumberSample -Store $metricSamples `
                -Name $metricProp.Name -Value $sample
        }
    }
    foreach ($rawProp in $run.raw_samples.PSObject.Properties) {
        if ($null -eq $run.metrics.PSObject.Properties[$rawProp.Name]) {
            throw "Protocol latency JSON has unexpected raw metric '$($rawProp.Name)'."
        }
    }

}

$connectStats = [ordered]@{}
foreach ($name in @('ports_file_ms', 'socket_port_ms', 'socket_connected_ms')) {
    $connectStats[$name] = Build-Stats -Values $connectSamples[$name]
}

$metricStats = [ordered]@{}
foreach ($name in ($metricSamples.Keys | Sort-Object)) {
    $metricStats[$name] = Build-Stats -Values $metricSamples[$name]
}

$result = [ordered]@{
    runs = $Runs
    connect = $connectStats
    metrics = $metricStats
    failures = @()
}

if ($Json) {
    $result | ConvertTo-Json -Depth 8
    exit 0
}

Write-Host ("[sweep] completed runs={0}" -f $Runs)
Write-Host 'connect:'
foreach ($entry in $connectStats.GetEnumerator()) {
    $v = $entry.Value
    Write-Host ("  {0}: count={1} min={2} p50={3} p95={4} avg={5} max={6} span={7}" -f `
        $entry.Key, $v.count, $v.min, $v.p50, $v.p95, $v.avg, $v.max, $v.span)
}
Write-Host 'metrics:'
foreach ($entry in $metricStats.GetEnumerator()) {
    $v = $entry.Value
    Write-Host ("  {0}: count={1} min={2} p50={3} p95={4} avg={5} max={6} span={7}" -f `
        $entry.Key, $v.count, $v.min, $v.p50, $v.p95, $v.avg, $v.max, $v.span)
}
