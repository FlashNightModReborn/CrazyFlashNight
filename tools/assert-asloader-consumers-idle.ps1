[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectRoot)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
$portsFile = Join-Path $root 'launcher_ports.json'
if (Test-Path -LiteralPath $portsFile) {
    $owner = (Get-Content -LiteralPath $portsFile -Raw -Encoding UTF8 | ConvertFrom-Json).pid
    if (-not $owner -or [int]$owner -le 0) { throw 'Cannot establish Guardian ownership from launcher_ports.json.' }
    if (Get-Process -Id ([int]$owner) -ErrorAction SilentlyContinue) { throw "Guardian $owner can still read the asLoader set." }
}

# The launch guard covers process creation. A surviving Guardian can start another
# Player even after its original launcher and current Player have both exited.
$names = @('CRAZYFLASHER7MercenaryEmpire.Core.exe','Adobe Flash Player 20.exe')
$config = Join-Path $root 'config.toml'
if (Test-Path -LiteralPath $config) {
    foreach ($line in Get-Content -LiteralPath $config -Encoding UTF8) {
        if ($line -match '^\s*flashPlayerPath\s*=\s*"([^"]+)"') {
            $names += [IO.Path]::GetFileName($Matches[1])
        }
    }
}
# Use the framework WMI provider to avoid relying on module auto-loading in
# Windows PowerShell started from an environment with a custom PSModulePath.
$filters = $names | Select-Object -Unique | ForEach-Object {
    "Name='" + $_.Replace("\", "\\").Replace("'", "\'") + "'"
}
$query = 'SELECT Name,ProcessId,ExecutablePath,CommandLine FROM Win32_Process WHERE ' + ($filters -join ' OR ')
$searcher = [System.Management.ManagementObjectSearcher]::new($query)
try {
$processes = $searcher.Get()
foreach ($process in $processes) {
    $exe = [string]$process.ExecutablePath
    $argsText = [string]$process.CommandLine
    if (-not $exe -or -not $argsText) { throw "Cannot establish consumer identity for PID $($process.ProcessId)." }
    $inRoot = $exe.StartsWith(($root + '\'), [StringComparison]::OrdinalIgnoreCase)
    $usesRoot = $argsText.IndexOf(($root + '\'), [StringComparison]::OrdinalIgnoreCase) -ge 0
    if ($argsText -match '(?i)(?:^|\s)--project-root\s+(?:"([^"]+)"|(\S+))') {
        $specified = if ($Matches[1]) { $Matches[1] } else { $Matches[2] }
        $usesRoot = ([IO.Path]::GetFullPath($specified).TrimEnd('\') -ieq $root)
    }
    if ($inRoot -or $usesRoot) { throw "PID $($process.ProcessId) can still read the asLoader set." }
}
} finally {
    $searcher.Dispose()
}
