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
        'tools/bootstrap-runtime-build-env.ps1',
        'tools/check-runtime-build-env.ps1',
        'tools/promote-runtime-bundle.ps1',
        'tools/runtime-build-common.ps1',
        'tools/test-runtime-build-consensus.ps1',
        'tools/verify-runtime-bundle.ps1',
        'tools/verify-runtime-consensus.ps1'
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

function Get-Cf7RuntimeBuildRecipeHash {
    param(
        [Parameter(Mandatory=$true)][string]$ProjectRoot,
        [ValidateSet('Worktree','Index')][string]$Mode = 'Worktree'
    )

    $root = (Resolve-Path -LiteralPath $ProjectRoot).Path
    $recipeFiles = @(
        'config/build/runtime-toolchain.lock.json',
        'launcher/CRAZYFLASHER7MercenaryEmpire.csproj',
        'launcher/build.ps1',
        'launcher/native/build.bat',
        'launcher/native/assert-pinned-tools.bat',
        'launcher/native/bootstrap/build.bat',
        'launcher/native/sol_parser/build.bat',
        'tools/check-runtime-build-env.ps1',
        'tools/promote-runtime-bundle.ps1',
        'tools/runtime-build-common.ps1',
        'tools/test-runtime-build-consensus.ps1',
        'tools/verify-runtime-bundle.ps1',
        'tools/verify-runtime-consensus.ps1'
    )
    $lines = @()
    $indexBlobs = @{}
    if ($Mode -eq 'Index') {
        foreach ($row in @(& git -C $root ls-files -s -- $recipeFiles)) {
            if ($row -match '^[0-9]+\s+([0-9a-f]+)\s+[0-9]+\t(.+)$') { $indexBlobs[$Matches[2].Replace('\', '/')] = $Matches[1] }
        }
        if ($LASTEXITCODE -ne 0) { throw 'Cannot read build recipe identities from Git index.' }
    }
    foreach ($relative in $recipeFiles) {
        if ($Mode -eq 'Index') {
            $hash = $indexBlobs[$relative]
            if (-not $hash) { throw "Build recipe input is absent from Git index: $relative" }
        } else {
            $full = Join-Path $root ($relative -replace '/', '\')
            if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "Build recipe input missing: $relative" }
            $hash = & git -C $root hash-object "--path=$relative" -- $full
            if ($LASTEXITCODE -ne 0 -or -not $hash) { throw "Cannot hash build recipe input: $relative" }
            $hash = ($hash | Select-Object -First 1).Trim()
        }
        $lines += "$relative`t$hash"
    }
    $payload = [string]::Join("`n", [string[]]$lines) + "`n"
    return Get-Cf7BytesSha256 -Bytes ([Text.Encoding]::UTF8.GetBytes($payload))
}

function Get-Cf7RuntimeArtifactClosure {
    param(
        [Parameter(Mandatory=$true)][string]$DeploymentRoot,
        [ValidateSet('Worktree','Index')][string]$Mode = 'Worktree',
        [string]$ProjectRoot
    )

    if ($Mode -eq 'Index') {
        if (-not $ProjectRoot) { throw 'ProjectRoot is required for index artifact closure.' }
        $root = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
        $paths = @(& git -C $root ls-files -- 'CRAZYFLASHER7MercenaryEmpire.exe' 'runtime')
        if ($LASTEXITCODE -ne 0) { throw 'Cannot enumerate runtime artifact closure from Git index.' }
        $paths = @($paths | ForEach-Object { $_.Replace('\', '/') } | Sort-Object -Unique)
    } else {
        $root = (Resolve-Path -LiteralPath $DeploymentRoot).Path.TrimEnd('\')
        $paths = @()
        $rootExe = Join-Path $root 'CRAZYFLASHER7MercenaryEmpire.exe'
        if (-not (Test-Path -LiteralPath $rootExe -PathType Leaf)) { throw "Runtime candidate lacks root bootstrap: $rootExe" }
        $paths += 'CRAZYFLASHER7MercenaryEmpire.exe'
        $runtimeDir = Join-Path $root 'runtime'
        if (-not (Test-Path -LiteralPath $runtimeDir -PathType Container)) { throw "Runtime candidate lacks runtime directory: $runtimeDir" }
        Get-ChildItem -LiteralPath $runtimeDir -Recurse -File | ForEach-Object {
            $paths += $_.FullName.Substring($root.Length + 1).Replace('\', '/')
        }
        $paths = @($paths | Sort-Object -Unique)
    }
    $rows = @()
    $lines = @()
    foreach ($relative in $paths) {
        if ($Mode -eq 'Index') {
            $bytes = Get-Cf7GitBlobBytes -ProjectRoot $root -RelativePath $relative
            $size = [Int64]$bytes.LongLength
            $hash = Get-Cf7BytesSha256 -Bytes $bytes
        } else {
            $full = Join-Path $root ($relative -replace '/', '\')
            $item = Get-Item -LiteralPath $full
            $size = [Int64]$item.Length
            $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $full).Hash.ToUpperInvariant()
        }
        $rows += [pscustomobject]@{ path = $relative; size = $size; sha256 = $hash }
        $lines += "$relative`t$size`t$hash"
    }
    $payload = [string]::Join("`n", [string[]]$lines) + "`n"
    return [pscustomobject]@{
        artifactClosureHash = Get-Cf7BytesSha256 -Bytes ([Text.Encoding]::UTF8.GetBytes($payload))
        files = $rows
    }
}

function New-Cf7RuntimeBuildAttestation {
    param(
        [Parameter(Mandatory=$true)][string]$ProjectRoot,
        [Parameter(Mandatory=$true)][string]$DeploymentRoot,
        [Parameter(Mandatory=$true)][string]$BuilderId
    )
    if ($BuilderId -notmatch '^[a-z0-9][a-z0-9._-]{1,63}$') {
        throw 'BuilderId must be 2-64 lowercase ASCII letters, digits, dot, underscore, or hyphen.'
    }
    $closure = Get-Cf7RuntimeArtifactClosure -DeploymentRoot $DeploymentRoot
    return [pscustomobject]@{
        schema = 'cf7-runtime-build-attestation.v1'
        builderId = $BuilderId
        sourceTreeHash = Get-Cf7RuntimeSourceTreeHash -ProjectRoot $ProjectRoot -Mode Worktree
        toolchainLockHash = Get-Cf7ToolchainLockHash -ProjectRoot $ProjectRoot -Mode Worktree
        buildRecipeHash = Get-Cf7RuntimeBuildRecipeHash -ProjectRoot $ProjectRoot -Mode Worktree
        artifactClosureHash = $closure.artifactClosureHash
        createdAtUtc = [DateTime]::UtcNow.ToString('o')
        files = $closure.files
    }
}

function Test-Cf7RuntimeBuildAttestationConsensus {
    param([Parameter(Mandatory=$true)][object[]]$Attestations)

    if ($Attestations.Count -lt 2) { throw 'At least two runtime build attestations are required.' }
    $builders = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $reference = $null
    foreach ($attestation in $Attestations) {
        if ($null -eq $attestation -or $attestation.schema -ne 'cf7-runtime-build-attestation.v1') {
            throw 'Unsupported or missing runtime build attestation schema.'
        }
        if ([string]$attestation.builderId -notmatch '^[a-z0-9][a-z0-9._-]{1,63}$') { throw 'Invalid attestation builderId.' }
        if (-not $builders.Add([string]$attestation.builderId)) { throw "Duplicate runtime builderId: $($attestation.builderId)" }
        foreach ($field in @('sourceTreeHash','toolchainLockHash','buildRecipeHash','artifactClosureHash')) {
            if ([string]$attestation.$field -notmatch '^[0-9A-Fa-f]{64}$') { throw "Invalid attestation field: $field" }
        }
        if ($null -eq $reference) { $reference = $attestation; continue }
        foreach ($field in @('sourceTreeHash','toolchainLockHash','buildRecipeHash','artifactClosureHash')) {
            if ([string]$reference.$field -ne [string]$attestation.$field) {
                throw "Runtime build consensus mismatch: $field builder=$($attestation.builderId)"
            }
        }
    }
    return $reference
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
