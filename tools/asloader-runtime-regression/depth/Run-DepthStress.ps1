[CmdletBinding()]
param(
    [string]$Resources,
    [string]$ModuleDirectory,
    [string]$EvidenceDirectory = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'CF7DepthProbeEvidence'),
    [ValidateRange(30, 1800)]
    [int]$TimeoutSeconds = 240
)
$ErrorActionPreference = 'Stop'
$utf8 = [Text.UTF8Encoding]::new($false)
$runId = 'CF7DepthProbe-' + [Guid]::NewGuid().ToString('N')
$temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$work = [IO.Path]::GetFullPath((Join-Path $temp $runId))
if ((Split-Path -Parent $work) -ine $temp -or (Split-Path -Leaf $work) -cne $runId -or
    (Test-Path -LiteralPath $work)) { throw 'Unexpected temporary directory.' }
$evidence = [IO.Path]::GetFullPath((Join-Path $EvidenceDirectory $runId))
[IO.Directory]::CreateDirectory($evidence) | Out-Null
$movie = Join-Path $work 'candidate/DepthProbe.swf'
$slot = 'cf7_depth_stress_v1'
$state = [ordered]@{ id=$runId; status='environment-failure'; inputs=[ordered]@{}; checks=@(); utc=[DateTime]::UtcNow.ToString('o') }
$result = 1
$ownedProcess = $null
$receiptPath = $null

function Copy-VerifiedInput([string]$name, [string]$source, [string]$destination) {
    $before = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    [IO.Directory]::CreateDirectory((Split-Path -Parent $destination)) | Out-Null
    [IO.File]::Copy($source, $destination)
    $actual = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
    if ($before -cne $actual) { throw "Input changed while being copied: $name" }
    $state.inputs[$name] = $actual.ToLowerInvariant()
}

function Read-Report([string]$path) {
    $bytes = [IO.File]::ReadAllBytes($path)
    if ($bytes.Length -lt 48 -or $bytes.Length -gt 65536 -or $bytes[0] -ne 0 -or
        $bytes[1] -ne 191 -or $utf8.GetString($bytes, 6, 4) -cne 'TCSO') { throw 'Invalid receipt header.' }
    $nameLength = $bytes[16]*256 + $bytes[17]
    if ($nameLength -ne $slot.Length -or $utf8.GetString($bytes, 18, $nameLength) -cne $slot) { throw 'Unexpected receipt slot.' }
    $p = 18 + $nameLength + 4
    if ($p + 11 -gt $bytes.Length -or $bytes[$p] -ne 0 -or $bytes[$p+1] -ne 6 -or
        $utf8.GetString($bytes, $p+2, 6) -cne 'result' -or $bytes[$p+8] -ne 2) { throw 'Invalid receipt field.' }
    $length = $bytes[$p+9]*256 + $bytes[$p+10]
    if ($p + 11 + $length -gt $bytes.Length) { throw 'Invalid receipt length.' }
    return $utf8.GetString($bytes, $p+11, $length)
}

try {
    if (-not $Resources) { $Resources = Join-Path $PSScriptRoot '../../..' }
    $root = (Get-Item -LiteralPath $Resources).FullName
    if (-not $ModuleDirectory) { $ModuleDirectory = Join-Path $root 'scripts' }
    $projector = Join-Path $work 'DepthProbePlayer.exe'
    Copy-VerifiedInput 'fixture' (Join-Path $PSScriptRoot 'DepthProbe.swf') $movie
    Copy-VerifiedInput 'player' (Join-Path $root 'Adobe Flash Player 20.exe') $projector
    $movieDirectory = Split-Path -Parent $movie
    $tooltip = 'flashswf/UI/注释框.swf'
    Copy-VerifiedInput 'tooltip' (Join-Path $root $tooltip) (Join-Path $movieDirectory $tooltip)
    foreach ($name in @('asLoader.swf', 'asLoaderShared.swf', 'asLoaderLogic.swf')) {
        Copy-VerifiedInput $name (Join-Path $ModuleDirectory $name) (Join-Path $movieDirectory "scripts/$name")
    }

    $started = [DateTime]::UtcNow
    $launch = [Diagnostics.ProcessStartInfo]::new()
    $launch.FileName = $projector
    $launch.Arguments = '"' + $movie + '"'
    $launch.WorkingDirectory = $movieDirectory
    $launch.UseShellExecute = $false
    $launch.CreateNoWindow = $true
    $launch.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $ownedProcess = [Diagnostics.Process]::Start($launch)
    $exited = $ownedProcess.WaitForExit(1000*$TimeoutSeconds)
    if (-not $exited) { $ownedProcess.Kill(); [void]$ownedProcess.WaitForExit(5000) }

    $buckets = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'Macromedia/Flash Player/#SharedObjects'
    $relativeMovie = $movie.Substring([IO.Path]::GetPathRoot($movie).Length)
    $found = @(foreach ($bucket in (Get-ChildItem -LiteralPath $buckets -Directory)) {
        $candidate = Join-Path $bucket.FullName ("localhost\" + $relativeMovie + "\" + $slot + '.sol')
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { Get-Item -LiteralPath $candidate }
    })
    if ($found.Count -ne 1 -or $found[0].LastWriteTimeUtc -lt $started.AddSeconds(-1)) { throw 'Fresh isolated receipt unavailable.' }
    $receiptPath = $found[0].FullName
    $trace = Read-Report $receiptPath
    [IO.File]::WriteAllText((Join-Path $evidence 'trace.txt'), $trace + [Environment]::NewLine, $utf8)
    if (-not $exited) { throw "Projector exceeded $TimeoutSeconds seconds. The partial trace is retained." }
    $state.projectorExit = $ownedProcess.ExitCode
    if ($state.projectorExit -ne 0) { throw "Projector exited with code $($state.projectorExit)." }

    $rows = @($trace -split '\r?\n')
    if ($rows[0] -cne 'DEPTH_STRESS begin' -or $rows[-1] -cnotmatch '^DEPTH_STRESS complete passed=(\d+) total=(\d+)$') {
        throw 'Incomplete fixture run. See trace.txt for the last completed check.'
    }
    $passCount = [int]$matches[1]
    $total = [int]$matches[2]
    $state.checks = @(foreach ($row in $rows) {
        if ($row -cmatch '^check (\w+) (true|false) (.*)$') {
            [ordered]@{ name=$matches[1]; passed=($matches[2] -ceq 'true'); details=$matches[3] }
        }
    })
    $passed = @($state.checks | Where-Object { $_.passed })
    $distinct = @($state.checks | ForEach-Object { $_.name } | Sort-Object -Unique)
    if ($state.checks.Count -ne $total -or $passed.Count -ne $passCount -or $distinct.Count -ne $total) { throw 'Inconsistent fixture counters.' }
    if ($total -eq 19 -and $passCount -eq $total) { $result=0; $state.status='passed' }
    else { $result=2; $state.status='regression' }
} catch {
    $state.error = $_.Exception.Message
} finally {
    if ($ownedProcess) {
        if (-not $ownedProcess.HasExited) { $ownedProcess.Kill(); [void]$ownedProcess.WaitForExit(5000) }
        $ownedProcess.Dispose()
    }
    if ($receiptPath -and $receiptPath.EndsWith(("\$runId\candidate\DepthProbe.swf\$slot.sol"), [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $receiptPath -Force -ErrorAction SilentlyContinue
        $dir = [IO.DirectoryInfo]::new((Split-Path -Parent $receiptPath))
        while ($dir -and $dir.Name -cin @('DepthProbe.swf', 'candidate', $runId)) {
            $parent = $dir.Parent
            try { $dir.Delete($false) } catch { break }
            if ($dir.Name -ceq $runId) { break }
            $dir = $parent
        }
    }
    if (Test-Path -LiteralPath $work) {
        $resolved = (Resolve-Path -LiteralPath $work).Path
        if ($resolved -ieq $work -and (Split-Path -Parent $resolved) -ieq $temp -and (Split-Path -Leaf $resolved) -ceq $runId) {
            Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    [IO.File]::WriteAllText((Join-Path $evidence 'checks.json'), ($state | ConvertTo-Json -Depth 5), $utf8)
}
Write-Host "$($state.status)  $evidence"
if ($state.error) { Write-Host $state.error }
exit $result
