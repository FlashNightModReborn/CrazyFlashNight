[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath,

    [Alias('Validate')]
    [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Cf7NoReparseComponents {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $root = [IO.Path]::GetPathRoot($Path)
    if ([string]::IsNullOrWhiteSpace($root)) {
        throw "$Label must have a filesystem root."
    }

    $cursor = $root
    $remainder = $Path.Substring($root.Length)
    foreach ($part in @($remainder -split '[\\/]' | Where-Object { $_ })) {
        $cursor = Join-Path $cursor $part
        if (-not (Test-Path -LiteralPath $cursor)) {
            throw "$Label contains a missing path component: $cursor"
        }
        $item = Get-Item -LiteralPath $cursor -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "$Label traverses a reparse point: $cursor"
        }
    }
}

function Resolve-Cf7CanonicalDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if (-not [IO.Path]::IsPathRooted($Path)) {
        throw "$Label must be an absolute path."
    }
    $full = [IO.Path]::GetFullPath($Path)
    if (-not [string]::Equals($Path, $full, [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label must use its canonical absolute path."
    }
    if (-not (Test-Path -LiteralPath $full -PathType Container)) {
        throw "$Label does not name a directory: $full"
    }
    $resolved = (Resolve-Path -LiteralPath $full).ProviderPath
    if (-not [string]::Equals($full, $resolved, [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label must use its canonical real path."
    }
    Assert-Cf7NoReparseComponents -Path $resolved -Label $Label
    return $resolved
}

function Resolve-Cf7CanonicalFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label,
        [string]$ExpectedLeafName
    )

    if (-not [IO.Path]::IsPathRooted($Path)) {
        throw "$Label must be an absolute path."
    }
    $full = [IO.Path]::GetFullPath($Path)
    if (-not [string]::Equals($Path, $full, [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label must use its canonical absolute path."
    }
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
        throw "$Label does not name a file: $full"
    }
    $resolved = (Resolve-Path -LiteralPath $full).ProviderPath
    if (-not [string]::Equals($full, $resolved, [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label must use its canonical real path."
    }
    Assert-Cf7NoReparseComponents -Path $resolved -Label $Label
    $item = Get-Item -LiteralPath $resolved -Force
    if ($item.PSIsContainer -or
        ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "$Label must be a regular non-reparse file."
    }
    if ($item.Length -le 0 -or $item.Length -gt (512MB)) {
        throw "$Label size is outside the assembler bound."
    }
    if ($ExpectedLeafName -and
        -not [string]::Equals($item.Name, $ExpectedLeafName, [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label must name $ExpectedLeafName."
    }
    return $resolved
}

function Resolve-Cf7SafeOutputPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ($Path.Length -gt 4096 -or -not [IO.Path]::IsPathRooted($Path)) {
        throw 'OutputPath must be a bounded absolute path.'
    }
    $full = [IO.Path]::GetFullPath($Path)
    if (-not [string]::Equals($Path, $full, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'OutputPath must use its canonical absolute path.'
    }
    $leaf = Split-Path -Leaf $full
    if ([string]::IsNullOrWhiteSpace($leaf) -or $leaf.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) {
        throw 'OutputPath has an unsafe file name.'
    }
    $parent = Resolve-Cf7CanonicalDirectory -Path (Split-Path -Parent $full) -Label 'OutputPath parent'
    $candidate = Join-Path $parent $leaf
    if (-not [string]::Equals($candidate, $full, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'OutputPath does not bind directly to its canonical parent.'
    }
    if (Test-Path -LiteralPath $full) {
        [void](Resolve-Cf7CanonicalFile -Path $full -Label 'OutputPath')
    }
    return $full
}

function Get-Cf7RequiredEnvironmentValue {
    param([Parameter(Mandatory = $true)][string]$Name)

    $value = [Environment]::GetEnvironmentVariable($Name, [EnvironmentVariableTarget]::Process)
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Pinned runtime environment did not set $Name."
    }
    return $value
}

function Get-Cf7Descriptor {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label,
        [string]$ExpectedLeafName
    )

    $resolved = Resolve-Cf7CanonicalFile -Path $Path -Label $Label -ExpectedLeafName $ExpectedLeafName
    $before = Get-Item -LiteralPath $resolved -Force
    $hash = (Get-FileHash -LiteralPath $resolved -Algorithm SHA256).Hash.ToUpperInvariant()
    $after = Get-Item -LiteralPath $resolved -Force
    if ($before.Length -ne $after.Length -or $before.LastWriteTimeUtc.Ticks -ne $after.LastWriteTimeUtc.Ticks) {
        throw "$Label changed while it was hashed."
    }
    if ($hash -notmatch '^[A-F0-9]{64}$') {
        throw "$Label did not produce an uppercase SHA-256 digest."
    }
    return [ordered]@{ path = $resolved; sha256 = $hash }
}

function Get-Cf7NodeVersion {
    param([Parameter(Mandatory = $true)][string]$NodePath)

    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $NodePath
    $start.Arguments = '--version'
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.EnvironmentVariables.Clear()
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    try {
        if (-not $process.Start()) { throw 'Node version probe did not start.' }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(15000)) {
            try { $process.Kill() } catch {}
            throw 'Node version probe timed out.'
        }
        $stdout = $stdoutTask.Result.Trim()
        $stderr = $stderrTask.Result.Trim()
        if ($process.ExitCode -ne 0 -or $stderr.Length -ne 0) {
            throw "Node version probe failed with exit code $($process.ExitCode)."
        }
        if ($stdout -notmatch '^v(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)(?:[-+][0-9A-Za-z.-]+)?$') {
            throw "Node version output is invalid: $stdout"
        }
        return $stdout
    } finally {
        $process.Dispose()
    }
}

function ConvertTo-Cf7JsonString {
    param([Parameter(Mandatory = $true)][string]$Value)
    return (ConvertTo-Json -InputObject $Value -Compress)
}

function ConvertTo-Cf7ToolchainBytes {
    param([Parameter(Mandatory = $true)][System.Collections.IDictionary]$Toolchain)

    $lines = New-Object Collections.Generic.List[string]
    [void]$lines.Add('{')
    $keys = @('cl', 'cmd', 'dotnet', 'msvcToolsVersion', 'node', 'nodeVersion', 'powershell', 'schema', 'vcvars64', 'windowsSdkVersion')
    for ($index = 0; $index -lt $keys.Count; $index++) {
        $key = $keys[$index]
        $comma = if ($index -lt ($keys.Count - 1)) { ',' } else { '' }
        $value = $Toolchain[$key]
        if ($value -is [System.Collections.IDictionary]) {
            $pathJson = ConvertTo-Cf7JsonString -Value ([string]$value.path)
            $shaJson = ConvertTo-Cf7JsonString -Value ([string]$value.sha256)
            [void]$lines.Add(('  "{0}": {{' -f $key))
            [void]$lines.Add(('    "path": {0},' -f $pathJson))
            [void]$lines.Add(('    "sha256": {0}' -f $shaJson))
            [void]$lines.Add(('  }}{0}' -f $comma))
        } else {
            $valueJson = ConvertTo-Cf7JsonString -Value ([string]$value)
            [void]$lines.Add(('  "{0}": {1}{2}' -f $key, $valueJson, $comma))
        }
    }
    [void]$lines.Add('}')
    $text = ([string]::Join("`n", $lines.ToArray())) + "`n"
    return ([Text.UTF8Encoding]::new($false, $true)).GetBytes($text)
}

function Test-Cf7BytesEqual {
    param([byte[]]$Left, [byte[]]$Right)
    if ($Left.Length -ne $Right.Length) { return $false }
    for ($index = 0; $index -lt $Left.Length; $index++) {
        if ($Left[$index] -ne $Right[$index]) { return $false }
    }
    return $true
}

function Write-Cf7AtomicCreateNew {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][byte[]]$Bytes
    )

    $parent = Split-Path -Parent $Path
    $temporary = Join-Path $parent ('.' + (Split-Path -Leaf $Path) + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        $stream = New-Object IO.FileStream(
            $temporary,
            [IO.FileMode]::CreateNew,
            [IO.FileAccess]::Write,
            [IO.FileShare]::None)
        try {
            $stream.Write($Bytes, 0, $Bytes.Length)
            $stream.Flush($true)
        } finally {
            $stream.Dispose()
        }
        [IO.File]::Move($temporary, $Path)
    } catch {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) {
            Remove-Item -LiteralPath $temporary -Force
        }
        throw
    }
}

$resolvedOutput = Resolve-Cf7SafeOutputPath -Path $OutputPath
$projectRoot = Resolve-Cf7CanonicalDirectory -Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))) -Label 'Project root'
$environmentCheck = Resolve-Cf7CanonicalFile `
    -Path (Join-Path $projectRoot 'tools\check-runtime-build-env.ps1') `
    -Label 'Runtime build environment check' `
    -ExpectedLeafName 'check-runtime-build-env.ps1'

foreach ($name in @(
    'CF7_DOTNET_EXE',
    'CF7_CL_EXE',
    'CF7_VCVARS64',
    'CF7_MSVC_TOOLS_VERSION',
    'CF7_WINDOWS_SDK_VERSION'
)) {
    [Environment]::SetEnvironmentVariable($name, $null, [EnvironmentVariableTarget]::Process)
}

# Dot-source the production gate so that its byte-pinned selections remain in
# this process. RuntimePublish is intentional: validation-only warnings are not
# sufficient authority for a qualification toolchain binding.
. $environmentCheck -ProjectRoot $projectRoot -Mode RuntimePublish

$nodeBinding = [Environment]::GetEnvironmentVariable('CF7_NODE_EXE', [EnvironmentVariableTarget]::Process)
if ([string]::IsNullOrWhiteSpace($nodeBinding)) {
    # Ordinary source use may discover Node exactly once. An explicit binding is
    # authority-bearing; Resolve-Cf7CanonicalFile rejects it instead of falling
    # back when it is present but invalid.
    $nodeCommand = Get-Command node.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $nodeCommand) {
        throw 'Node.js is required to write the Audio v2 qualification toolchain.'
    }
    $nodeBinding = $nodeCommand.Source
}
$nodePath = Resolve-Cf7CanonicalFile -Path $nodeBinding -Label 'CF7_NODE_EXE' -ExpectedLeafName 'node.exe'
$env:CF7_NODE_EXE = $nodePath

$systemRoot = [Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)
if ([string]::IsNullOrWhiteSpace($systemRoot)) {
    throw 'The canonical Windows directory is unavailable.'
}
$systemRoot = Resolve-Cf7CanonicalDirectory -Path $systemRoot -Label 'Windows directory'

$msvcToolsVersion = Get-Cf7RequiredEnvironmentValue -Name 'CF7_MSVC_TOOLS_VERSION'
$windowsSdkVersion = Get-Cf7RequiredEnvironmentValue -Name 'CF7_WINDOWS_SDK_VERSION'
foreach ($binding in @(
    @{ name = 'CF7_MSVC_TOOLS_VERSION'; value = $msvcToolsVersion },
    @{ name = 'CF7_WINDOWS_SDK_VERSION'; value = $windowsSdkVersion }
)) {
    if ($binding.value.Length -gt 256 -or $binding.value -match '[\x00-\x1F]') {
        throw "$($binding.name) is not a bounded single-line value."
    }
}

$toolchain = [ordered]@{
    cl = Get-Cf7Descriptor -Path (Get-Cf7RequiredEnvironmentValue -Name 'CF7_CL_EXE') -Label 'CF7_CL_EXE' -ExpectedLeafName 'cl.exe'
    cmd = Get-Cf7Descriptor -Path (Join-Path $systemRoot 'System32\cmd.exe') -Label 'cmd.exe' -ExpectedLeafName 'cmd.exe'
    dotnet = Get-Cf7Descriptor -Path (Get-Cf7RequiredEnvironmentValue -Name 'CF7_DOTNET_EXE') -Label 'CF7_DOTNET_EXE' -ExpectedLeafName 'dotnet.exe'
    msvcToolsVersion = $msvcToolsVersion
    node = Get-Cf7Descriptor -Path $nodePath -Label 'node.exe' -ExpectedLeafName 'node.exe'
    nodeVersion = Get-Cf7NodeVersion -NodePath $nodePath
    powershell = Get-Cf7Descriptor -Path (Join-Path $systemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -Label 'powershell.exe' -ExpectedLeafName 'powershell.exe'
    schema = 'cf7.audio-v2.qualification-toolchain.v1'
    vcvars64 = Get-Cf7Descriptor -Path (Get-Cf7RequiredEnvironmentValue -Name 'CF7_VCVARS64') -Label 'CF7_VCVARS64' -ExpectedLeafName 'vcvars64.bat'
    windowsSdkVersion = $windowsSdkVersion
}
$expectedBytes = ConvertTo-Cf7ToolchainBytes -Toolchain $toolchain

if ($Check) {
    if (-not (Test-Path -LiteralPath $resolvedOutput -PathType Leaf)) {
        throw "Qualification toolchain JSON is missing: $resolvedOutput"
    }
    $actualBytes = [IO.File]::ReadAllBytes($resolvedOutput)
    if (-not (Test-Cf7BytesEqual -Left $actualBytes -Right $expectedBytes)) {
        throw "Qualification toolchain JSON differs from the exact current toolchain: $resolvedOutput"
    }
    Write-Host "[AudioV2Toolchain] OK $resolvedOutput" -ForegroundColor Green
    return
}

Write-Cf7AtomicCreateNew -Path $resolvedOutput -Bytes $expectedBytes
Write-Host "[AudioV2Toolchain] WROTE $resolvedOutput" -ForegroundColor Green
