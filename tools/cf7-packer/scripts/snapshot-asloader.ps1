# Copy the selected source movies under the publisher's native Windows lock.
# The packer runs on Windows installations that do not have a Python runtime.
[CmdletBinding()]
param([string]$ProjectRoot, [string]$Destination, [string]$Modules)
$ErrorActionPreference = 'Stop'
$files = @{resident='asLoader.swf'; shared='asLoaderShared.swf'; boot='asLoaderLogic.swf'}
$state = Join-Path $ProjectRoot 'tmp\asloader-artifact-set'
if (-not [IO.Directory]::Exists($state)) {
    # Packing a legacy or read-only checkout creates no source files. Every
    # transaction creates its guard directory before the first module write.
    $contents = @{}
    foreach ($name in $Modules.Split(',')) {
        if (-not $files.ContainsKey($name)) { throw "Invalid asLoader module: $name" }
        $contents[$name] = [IO.File]::ReadAllBytes((Join-Path $ProjectRoot ('scripts\' + $files[$name])))
    }
    if (-not [IO.Directory]::Exists($state)) {
        foreach ($name in $contents.Keys) {
            $stream = [IO.File]::Open((Join-Path $Destination $files[$name]), [IO.FileMode]::CreateNew)
            try { $stream.Write($contents[$name], 0, $contents[$name].Length) } finally { $stream.Dispose() }
        }
        return
    }
}
$guard = [IO.File]::Open((Join-Path $state 'guard.lock'),
    [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::Read, [IO.FileShare]::Read)
function Read-PackSha256([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    $hasher = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($hasher.ComputeHash($stream))).Replace('-', '') }
    finally { $stream.Dispose(); $hasher.Dispose() }
}
try {
    if ([IO.File]::Exists((Join-Path $state 'pending.json'))) { throw 'Pending asLoader transaction requires recovery.' }
    $record = $null
    $gitSet = $null
    $index = Join-Path $state 'active.json'
    if ([IO.File]::Exists($index)) {
        $digest = ([IO.File]::ReadAllText($index) | ConvertFrom-Json).receiptSha256
        if ($digest -cnotmatch '^[0-9a-f]{64}$') { throw 'Invalid active asLoader index.' }
        $receipt = Join-Path $state ('receipts\' + $digest)
        if ((Read-PackSha256 $receipt) -ine $digest) { throw 'Damaged active asLoader receipt.' }
        $record = ([IO.File]::ReadAllText($receipt) | ConvertFrom-Json).modules
        if (@($record.PSObject.Properties).Count -ne 3) { throw 'Invalid active asLoader module inventory.' }
        $mismatch = $false
        foreach ($name in $files.Keys) {
            if ($record.$name.sha256 -notmatch '^[0-9a-f]{64}$') { throw 'Invalid asLoader module receipt.' }
            if (-not [IO.File]::Exists((Join-Path $ProjectRoot ('scripts\' + $files[$name]))) -or
                    (Read-PackSha256 (Join-Path $ProjectRoot ('scripts\' + $files[$name]))) -ine $record.$name.sha256) {
                $mismatch = $true
            }
        }
        if ($mismatch) {
            $helper = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'asloader-git-set.ps1'
            $raw = & $helper -ProjectRoot $ProjectRoot
            if (-not $raw) { throw 'asLoader bytes differ from both the active receipt and Git HEAD.' }
            $gitSet = $raw | ConvertFrom-Json
        }
    } elseif ([IO.File]::Exists((Join-Path $state 'last-good.json'))) { throw 'Managed asLoader set lost its active index.' }
    foreach ($name in $Modules.Split(',')) {
        if (-not $files.ContainsKey($name)) { throw "Invalid asLoader module: $name" }
        $target = Join-Path $Destination $files[$name]
        [IO.File]::Copy((Join-Path $ProjectRoot ('scripts\' + $files[$name])), $target, $false)
        if ($record) {
            $expected = if ($gitSet) { $gitSet.installed.$name } else { $record.$name.sha256 }
            if ((Read-PackSha256 $target) -ine $expected) { throw "Copied bytes changed for $name." }
        }
    }
    if ($gitSet -and $raw -cne (& $helper -ProjectRoot $ProjectRoot)) { throw 'Git checkout changed during the asLoader snapshot.' }
} finally {
    $guard.Dispose()
}
