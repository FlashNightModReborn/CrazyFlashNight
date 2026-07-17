# CF7 Runtime 构建输入与哈希公共函数。PowerShell 5.1 / 7 均可用。

function Get-Cf7RuntimeInputFiles {
    param(
        [Parameter(Mandatory=$true)][string]$ProjectRoot,
        [ValidateSet('Worktree','Index')][string]$Mode = 'Worktree'
    )

    $root = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
    $files = @()
    $fixed = @(
        '.gitattributes',
        'global.json',
        'config/build/runtime-toolchain.lock.json',
        'launcher/CRAZYFLASHER7MercenaryEmpire.csproj',
        'launcher/Directory.Packages.props',
        'launcher/packages.lock.json',
        'launcher/app.ico',
        'launcher/app.manifest',
        'launcher/build.ps1',
        'tools/assert-optimized.cs',
        'tools/check-runtime-build-env.ps1',
        'tools/runtime-build-common.ps1',
        'tools/verify-runtime-bundle.ps1'
    )
    if ($Mode -eq 'Index') {
        $tracked = @(& git -C $root ls-files -- @($fixed + @('launcher/src', 'launcher/native')))
        if ($LASTEXITCODE -ne 0) { throw 'Cannot enumerate runtime inputs from the Git index.' }
        $trackedSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        foreach ($path in $tracked) { [void]$trackedSet.Add($path.Replace('\', '/')) }
        foreach ($required in $fixed) {
            if (-not $trackedSet.Contains($required)) { throw "Required runtime input is absent from Git index: $required" }
        }
        foreach ($relative in $tracked) {
            $relative = $relative.Replace('\', '/')
            $extension = [IO.Path]::GetExtension($relative).ToLowerInvariant()
            $underSourceTree = $relative.StartsWith('launcher/src/', [StringComparison]::Ordinal) -and $extension -eq '.cs'
            $underNativeTree = $relative.StartsWith('launcher/native/', [StringComparison]::Ordinal) -and @('.bat', '.c', '.cpp', '.h', '.rc', '.rs', '.toml', '.lock') -contains $extension
            $fixedInput = $fixed -contains $relative
            if (($fixedInput -or $underSourceTree -or $underNativeTree) -and $relative -notmatch '(^|/)(target|bin|obj)/') {
                $files += $relative
            }
        }
    } else {
        foreach ($relative in $fixed) {
            $full = Join-Path $root ($relative -replace '/', '\')
            if (Test-Path -LiteralPath $full -PathType Leaf) { $files += $relative }
        }

    $trees = @(
        @{ Path = 'launcher/src'; Extensions = @('.cs') },
        @{ Path = 'launcher/native'; Extensions = @('.bat', '.c', '.cpp', '.h', '.rc', '.rs', '.toml', '.lock') }
    )
        foreach ($tree in $trees) {
            $base = Join-Path $root ($tree.Path -replace '/', '\')
            if (-not (Test-Path -LiteralPath $base)) { continue }
            Get-ChildItem -LiteralPath $base -Recurse -File | Where-Object {
                $tree.Extensions -contains $_.Extension.ToLowerInvariant() -and
                $_.FullName -notmatch '[\\/](target|bin|obj)[\\/]'
            } | ForEach-Object {
                $relative = $_.FullName.Substring($root.Length + 1).Replace('\', '/')
                $files += $relative
            }
        }
    }

    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($file in $files) { [void]$set.Add($file) }
    $result = [string[]]$set
    [Array]::Sort($result, [StringComparer]::Ordinal)
    return @($result)
}

function Get-Cf7RuntimeSourceTreeHash {
    param(
        [Parameter(Mandatory=$true)][string]$ProjectRoot,
        [ValidateSet('Worktree','Index')][string]$Mode = 'Worktree'
    )

    $root = (Resolve-Path -LiteralPath $ProjectRoot).Path
    $lines = @()
    $indexBlobs = @{}
    if ($Mode -eq 'Index') {
        foreach ($row in @(& git -C $root ls-files -s)) {
            if ($row -match '^[0-9]+\s+([0-9a-f]+)\s+[0-9]+\t(.+)$') { $indexBlobs[$Matches[2].Replace('\', '/')] = $Matches[1] }
        }
        if ($LASTEXITCODE -ne 0) { throw 'Cannot read Git index identities.' }
    }
    foreach ($relative in Get-Cf7RuntimeInputFiles -ProjectRoot $root -Mode $Mode) {
        if ($Mode -eq 'Index') {
            $blob = $indexBlobs[$relative]
            if (-not $blob) { throw "Runtime input is absent from Git index: $relative" }
        } else {
            $full = Join-Path $root ($relative -replace '/', '\')
            $blob = & git -C $root hash-object "--path=$relative" -- $full
            if ($LASTEXITCODE -ne 0 -or -not $blob) { throw "Cannot hash runtime input: $relative" }
            $blob = ($blob | Select-Object -First 1).Trim()
        }
        $lines += "$relative`t$blob"
    }
    $payload = [string]::Join("`n", [string[]]$lines) + "`n"
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($payload)))).Replace('-', '')
    } finally { $sha.Dispose() }
}

function Get-Cf7ToolchainLockHash {
    param(
        [Parameter(Mandatory=$true)][string]$ProjectRoot,
        [ValidateSet('Worktree','Index')][string]$Mode = 'Worktree'
    )
    if ($Mode -eq 'Index') {
        return Get-Cf7BytesSha256 -Bytes (Get-Cf7GitBlobBytes -ProjectRoot $ProjectRoot -RelativePath 'config/build/runtime-toolchain.lock.json')
    }
    $path = Join-Path $ProjectRoot 'config\build\runtime-toolchain.lock.json'
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToUpperInvariant()
}

function Get-Cf7GitBlobBytes {
    param(
        [Parameter(Mandatory=$true)][string]$ProjectRoot,
        [Parameter(Mandatory=$true)][string]$RelativePath
    )
    if ($RelativePath -notmatch '^[A-Za-z0-9_./-]+$') { throw "Unsafe Git path: $RelativePath" }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'git.exe'
    $psi.Arguments = "-C `"$ProjectRoot`" cat-file blob `":$RelativePath`""
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $process = [System.Diagnostics.Process]::Start($psi)
    $memory = New-Object System.IO.MemoryStream
    try {
        $process.StandardOutput.BaseStream.CopyTo($memory)
        $errorText = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) { throw "Cannot read Git index blob $RelativePath`: $errorText" }
        return $memory.ToArray()
    } finally {
        $memory.Dispose()
        $process.Dispose()
    }
}

function Get-Cf7BytesSha256 {
    param([Parameter(Mandatory=$true)][byte[]]$Bytes)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '') }
    finally { $sha.Dispose() }
}
