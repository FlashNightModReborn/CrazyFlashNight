param(
    [string]$Resources,
    [string]$ModuleDirectory,
    [string]$FixtureFile,
    [string]$EvidenceDirectory
)
$ErrorActionPreference = 'Stop'
$utf8 = [Text.UTF8Encoding]::new($false)
$caseId = 'CF7WheelProbe-' + [Guid]::NewGuid().ToString('N')
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$scratch = [IO.Path]::GetFullPath((Join-Path $tempRoot $caseId))
$prefix = $tempRoot.TrimEnd('\') + '\'
if (-not $scratch.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or
    (Split-Path -Leaf $scratch) -cne $caseId -or (Test-Path -LiteralPath $scratch)) {
    throw 'Temporary case path conflict.'
}
if (-not $EvidenceDirectory) { $EvidenceDirectory = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'CF7WheelProbeEvidence' }
$evidence = [IO.Path]::GetFullPath((Join-Path $EvidenceDirectory $caseId))
if (Test-Path -LiteralPath $evidence) { throw 'Evidence directory already exists.' }
[IO.Directory]::CreateDirectory($evidence) | Out-Null
$manifest = [ordered]@{case=$caseId; utc=[DateTime]::UtcNow.ToString('o'); status='infrastructure-failure'; inputs=[ordered]@{}; checks=[ordered]@{}}
$stateFile = Join-Path $evidence 'checks.json'
$exitCode = 1
$movieDir = Join-Path $scratch 'candidate'
$textSlot = 'cf7_wheel_fixture_9c65e2'
$sharedReport = $null
$process = $null

function Copy-Input([string]$name, [string]$from, [string]$to) {
    $expected = (Get-FileHash -Algorithm SHA256 -LiteralPath $from).Hash
    [IO.Directory]::CreateDirectory((Split-Path -Parent $to)) | Out-Null
    [IO.File]::Copy($from, $to, $false)
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $to).Hash
    if ($expected -cne $actual) { throw "File changed during capture: $name" }
    $manifest.inputs[$name] = $actual.ToLowerInvariant()
}

function Read-Receipt([string]$path) {
    # Parse the one AMF0 string produced by this fixture's own SharedObject.
    $bytes = [IO.File]::ReadAllBytes($path)
    if ($bytes.Length -lt 40 -or $bytes.Length -gt 65536 -or
        $utf8.GetString($bytes,6,4) -cne 'TCSO' -or $bytes[0] -ne 0 -or $bytes[1] -ne 191) {
        throw 'Invalid fixture receipt header.'
    }
    $slotLength = $bytes[16]*256 + $bytes[17]
    if ($slotLength -ne $textSlot.Length -or $utf8.GetString($bytes,18,$slotLength) -cne $textSlot) {
        throw 'Unexpected receipt slot.'
    }
    $p = 18 + $slotLength + 4
    if ($bytes[$p] -ne 0 -or $bytes[$p+1] -ne 6 -or $utf8.GetString($bytes,$p+2,6) -cne 'report' -or $bytes[$p+8] -ne 2) {
        throw 'Unexpected receipt field.'
    }
    $length = $bytes[$p+9]*256 + $bytes[$p+10]
    if ($length -lt 10 -or $p+11+$length -gt $bytes.Length) { throw 'Invalid receipt string bounds.' }
    return $utf8.GetString($bytes,$p+11,$length)
}

function Get-Row([string]$tag) {
    $matches = @($rows | Where-Object { $_.StartsWith("WHEEL_PROBE candidate $tag ", [StringComparison]::Ordinal) })
    if ($matches.Count -ne 1) { throw "Missing or repeated measurement: $tag" }
    return [string]$matches[0]
}

function Has-Tokens([string]$row, [string[]]$expected) {
    $tokens = $row.Split(' ')
    foreach ($token in $expected) { if ($tokens -cnotcontains $token) { return $false } }
    return $true
}

function Get-RebuildDigest([string]$path) {
    # CS6 republishes XMP dates and document IDs. Compare the header, frame
    # information and complete raw tags, excluding only length and XMP metadata.
    $bytes = [IO.File]::ReadAllBytes($path)
    if ($bytes.Length -lt 16 -or $utf8.GetString($bytes,0,3) -cne 'FWS' -or
        [BitConverter]::ToUInt32($bytes,4) -ne $bytes.Length) { throw 'Invalid CS6 FWS fixture.' }
    $p = 8 + [int][Math]::Ceiling((5 + 4*($bytes[8] -shr 3))/8) + 4
    $stream = [IO.MemoryStream]::new()
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $stream.Write($bytes,0,4)
        $stream.Write($bytes,8,$p-8)
        while ($p -lt $bytes.Length) {
            $startTag = $p
            $header = [BitConverter]::ToUInt16($bytes,$p)
            $p += 2
            $length = $header -band 63
            if ($length -eq 63) {
                $length = [BitConverter]::ToUInt32($bytes,$p)
                $p += 4
            }
            $p += $length
            if ($p -gt $bytes.Length) { throw 'SWF tag exceeds file bounds.' }
            if (($header -shr 6) -ne 77) { $stream.Write($bytes,$startTag,$p-$startTag) }
        }
        return [BitConverter]::ToString($sha.ComputeHash($stream.ToArray())).Replace('-','').ToLowerInvariant()
    } finally { $sha.Dispose(); $stream.Dispose() }
}

try {
    if (-not $Resources) {
        $Resources = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
        if (-not (Test-Path -LiteralPath (Join-Path $Resources 'Adobe Flash Player 20.exe') -PathType Leaf)) {
            throw 'Pass -Resources followed by the game resources directory.'
        }
    }
    $base = (Get-Item -LiteralPath $Resources).FullName
    if (-not $ModuleDirectory) { $ModuleDirectory = Join-Path $base 'scripts' }
    $moduleBase = (Get-Item -LiteralPath $ModuleDirectory).FullName
    $fixture = Join-Path $movieDir 'WheelProbe.swf'
    $exe = Join-Path $scratch 'WheelProbePlayer.exe'
    if (-not $FixtureFile) { $FixtureFile = Join-Path $PSScriptRoot 'WheelProbe.swf' }
    Copy-Input 'fixture' $FixtureFile $fixture
    $manifest.fixtureContentSha256 = Get-RebuildDigest $fixture
    if ($manifest.fixtureContentSha256 -cne 'bb35bf33330cb8380402b2348abaf740b3a57df3bfc12be626763e563beb8ff6') {
        throw 'Fixture movie content differs from the qualified build.'
    }
    Copy-Input 'player' (Join-Path $base 'Adobe Flash Player 20.exe') $exe
    $ui = 'flashswf/UI/注释框.swf'
    Copy-Input 'tooltip' (Join-Path $base $ui) (Join-Path $movieDir $ui)
    $names = @('asLoader.swf')
    $shared = Test-Path -LiteralPath (Join-Path $moduleBase 'asLoaderShared.swf') -PathType Leaf
    $logic = Test-Path -LiteralPath (Join-Path $moduleBase 'asLoaderLogic.swf') -PathType Leaf
    if ($shared -ne $logic) { throw 'Incomplete split module set.' }
    if ($shared) { $names += @('asLoaderShared.swf','asLoaderLogic.swf') }
    $manifest.layout = if ($shared) { 'split' } else { 'monolith' }
    foreach ($name in $names) {
        Copy-Input $name (Join-Path $moduleBase $name) (Join-Path $movieDir ('scripts/' + $name))
    }
    $start = [DateTime]::UtcNow
    $launch = [Diagnostics.ProcessStartInfo]::new()
    $launch.FileName = $exe
    $launch.Arguments = '"' + $fixture + '"'
    $launch.WorkingDirectory = $movieDir
    $launch.UseShellExecute = $false
    $launch.CreateNoWindow = $true
    $launch.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $process = [Diagnostics.Process]::Start($launch)
    if (-not $process.WaitForExit(30000)) {
        throw 'Fixture did not exit within 30 seconds.'
    }
    $manifest.projectorExit = $process.ExitCode
    $bucketRoot = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'Macromedia/Flash Player/#SharedObjects'
    $drive = [IO.Path]::GetPathRoot($fixture)
    $relative = $fixture.Substring($drive.Length)
    $found = @(foreach ($bucket in (Get-ChildItem -Directory -LiteralPath $bucketRoot)) {
        $file = Join-Path (Join-Path (Join-Path $bucket.FullName 'localhost') $relative) ($textSlot + '.sol')
        if (Test-Path -LiteralPath $file -PathType Leaf) { Get-Item -LiteralPath $file }
    })
    if ($found.Count -ne 1 -or $found[0].LastWriteTimeUtc -lt $start.AddSeconds(-1)) {
        throw 'Missing fresh receipt in the isolated fixture namespace.'
    }
    $sharedReport = $found[0].FullName
    $report = Read-Receipt $sharedReport
    [IO.File]::WriteAllText((Join-Path $evidence 'trace.txt'),$report + [Environment]::NewLine,$utf8)
    $rows = @($report -split '\r?\n')
    $checks = $manifest.checks
    $checks.complete = ($rows[0] -ceq 'WHEEL_PROBE candidate begin' -and $rows[-1] -ceq 'WHEEL_PROBE candidate complete')
    $checks.clockSurvives = Has-Tokens (Get-Row 'authored-3-tick3') @('clock=_level0._cdWheel','65533=注释框','frameFn=function')
    $canvas = Get-Row initial
    # Two clips created in the same millisecond may share an AVM1 target name.
    # Under the same parent, their numeric depths and distinct blend modes are unambiguous.
    $plane = [regex]::Match($canvas, 'ordinaryDepth=(\d+) additiveDepth=(\d+) ')
    $checks.twoIndependentCanvases = $plane.Success -and $plane.Groups[1].Value -cne $plane.Groups[2].Value -and
        (Has-Tokens $canvas @('ordinaryBlend=normal','addBlend=add'))
    $checks.heldSemiFiresOnce = Has-Tokens (Get-Row semi-held-t5) @('shots=1')
    $checks.firstSemiRepress = Has-Tokens (Get-Row semi-retap-t15) @('shots=2')
    $checks.secondSemiRepress = Has-Tokens (Get-Row semi-retap-t23) @('shots=3')
    $checks.debouncedSaveCallback = (Has-Tokens (Get-Row debounce-start) @('accepted=true')) -and (Has-Tokens (Get-Row semi-retap-t15) @('callback=1')) -and (Has-Tokens (Get-Row semi-retap-t23) @('callback=1'))
    $checks.autoRelease = Has-Tokens (Get-Row 'measure t=16') @('shots=6','lock=false','shooting=false','heldTask=undefined')
    $checks.autoRepress = Has-Tokens (Get-Row 'measure t=24') @('shots=11')
    $checks.trailsHiddenAndCleared = Has-Tokens (Get-Row 'measure t=24') @('normal.visible=false','add.visible=false','normal.bounds=0','add.bounds=0','normal.cycle=5','add.cycle=3')
    $checks.wheelTasks = Has-Tokens (Get-Row 'measure t=24') @('plain=1','repeats=3','sameDriver=true')
    $failed = @($checks.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key })
    $manifest.failed = $failed
    if ($failed.Count) {
        $manifest.status = 'regression'
        $exitCode = 2
    } else {
        $manifest.status = 'passed'
        $exitCode = 0
    }
} catch {
    $manifest.error = $_.Exception.Message
} finally {
    if ($process) {
        if (-not $process.HasExited) { $process.Kill(); [void]$process.WaitForExit(3000) }
        $process.Dispose()
    }
    if ($sharedReport -and $sharedReport -like ("*\" + $caseId + "\candidate\WheelProbe.swf\" + $textSlot + '.sol')) {
        Remove-Item -Force -LiteralPath $sharedReport -ErrorAction SilentlyContinue
        $dir = [IO.DirectoryInfo]::new((Split-Path -Parent $sharedReport))
        while ($dir -and ($dir.Name -ceq 'WheelProbe.swf' -or $dir.Name -ceq 'candidate' -or $dir.Name -ceq $caseId)) {
            $next = $dir.Parent
            try { $dir.Delete($false) } catch { break }
            if ($dir.Name -ceq $caseId) { break }
            $dir = $next
        }
    }
    if (Test-Path -LiteralPath $scratch -PathType Container) {
        $resolved = (Resolve-Path -LiteralPath $scratch).Path
        if ($resolved -ieq $scratch -and $resolved.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolved) -ceq $caseId) {
            Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    [IO.File]::WriteAllText($stateFile,($manifest | ConvertTo-Json -Depth 6),$utf8)
}
Write-Host ($manifest.status + '  ' + $evidence)
if ($manifest.error) { Write-Host $manifest.error }
exit $exitCode
