# CF7 runtime v2 input identity, build identity, release tree, and payload closure helpers.
# This file is dot-sourced by build/release scripts and supports Windows PowerShell 5.1 and PowerShell 7.

function Get-Cf7RuntimeV2BytesSha256 {
    param([Parameter(Mandatory=$true)][byte[]]$Bytes)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '') }
    finally { $sha.Dispose() }
}

function Get-Cf7RuntimeV2TextSha256 {
    param([Parameter(Mandatory=$true)][string]$Text)
    return Get-Cf7RuntimeV2BytesSha256 -Bytes ([Text.Encoding]::UTF8.GetBytes($Text))
}

function New-Cf7RuntimeV2CandidateLeafName {
    param(
        [Parameter(Mandatory=$true)][string]$BuildIdentityHash,
        [Parameter(Mandatory=$true)][string]$BuilderId,
        [string]$RunToken
    )
    if ($BuildIdentityHash -cnotmatch '^[0-9A-F]{64}$') {
        throw 'BuildIdentityHash must be an uppercase SHA-256 value.'
    }
    if ([string]::IsNullOrWhiteSpace($BuilderId)) { throw 'BuilderId is required for a candidate path.' }
    if (-not $RunToken) {
        $RunToken = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ').ToLowerInvariant() + '-' +
            [Guid]::NewGuid().ToString('N').Substring(0, 8)
    }
    if ($RunToken.Length -gt 32 -or $RunToken -cnotmatch '^[a-z0-9][a-z0-9-]*$') {
        throw 'Runtime candidate RunToken must be 1-32 lowercase ASCII letters, digits, or hyphens.'
    }
    $builderHash = Get-Cf7RuntimeV2TextSha256 -Text $BuilderId
    # The complete identity and builder label live in metadata/attestations. The directory
    # carries only collision-resistant prefixes so the legacy MAX_PATH bootstrap can verify it.
    return ('c-{0}-{1}-{2}' -f `
        $BuildIdentityHash.Substring(0, 12).ToLowerInvariant(),
        $builderHash.Substring(0, 10).ToLowerInvariant(),
        $RunToken)
}

function Get-Cf7RuntimeV2RelativePath {
    param(
        [Parameter(Mandatory=$true)][string]$ProjectRoot,
        [Parameter(Mandatory=$true)][string]$Path
    )
    $root = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
    $full = [IO.Path]::GetFullPath($Path)
    $prefix = $root + '\'
    if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside ProjectRoot: $full"
    }
    return $full.Substring($prefix.Length).Replace('\', '/')
}

function Get-Cf7RuntimeV2GitIndexBlobBytes {
    param(
        [Parameter(Mandatory=$true)][string]$ProjectRoot,
        [Parameter(Mandatory=$true)][string]$RelativePath
    )
    if ($RelativePath -match '(^|/)\.\.(/|$)' -or $RelativePath.IndexOf([char]0) -ge 0) {
        throw "Unsafe Git path: $RelativePath"
    }
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

function Read-Cf7RuntimeV2Config {
    param(
        [Parameter(Mandatory=$true)][string]$ProjectRoot,
        [ValidateSet('Worktree','Index')][string]$Mode = 'Worktree',
        [string]$ConfigPath
    )
    $root = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
    if (-not $ConfigPath) { $ConfigPath = Join-Path $root 'config\build\runtime-inputs.v2.json' }
    if (-not [IO.Path]::IsPathRooted($ConfigPath)) { $ConfigPath = Join-Path $root $ConfigPath }
    $relative = Get-Cf7RuntimeV2RelativePath -ProjectRoot $root -Path $ConfigPath
    if ($Mode -eq 'Index') {
        $bytes = Get-Cf7RuntimeV2GitIndexBlobBytes -ProjectRoot $root -RelativePath $relative
        $json = [Text.Encoding]::UTF8.GetString($bytes)
    } else {
        if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { throw "Runtime v2 input config missing: $ConfigPath" }
        $json = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $ConfigPath).Path, [Text.Encoding]::UTF8)
    }
    $json = $json.TrimStart([char]0xFEFF)
    $config = $json | ConvertFrom-Json
    if ($null -eq $config -or [string]$config.schema -ne 'cf7-runtime-inputs.v2') {
        throw 'Unsupported or missing runtime v2 input config schema.'
    }
    foreach ($domain in @('artifactSource','producerRecipe','toolchainLock','policy')) {
        if ($null -eq $config.domains.PSObject.Properties[$domain]) { throw "Runtime v2 input config lacks domain: $domain" }
    }
    return $config
}

function Test-Cf7RuntimeV2PathExcluded {
    param(
        [Parameter(Mandatory=$true)][string]$RelativePath,
        [object[]]$ExcludePaths,
        [object[]]$ExcludePrefixes
    )
    $path = $RelativePath.Replace('\', '/')
    foreach ($excluded in @($ExcludePaths)) {
        if ($path.Equals(([string]$excluded).Replace('\', '/'), [StringComparison]::Ordinal)) { return $true }
    }
    foreach ($prefix in @($ExcludePrefixes)) {
        if ($path.StartsWith(([string]$prefix).Replace('\', '/'), [StringComparison]::Ordinal)) { return $true }
    }
    return $false
}

function Get-Cf7RuntimeV2DomainFiles {
    param(
        [Parameter(Mandatory=$true)][string]$ProjectRoot,
        [Parameter(Mandatory=$true)][ValidateSet('artifactSource','producerRecipe','toolchainLock','policy')][string]$Domain,
        [ValidateSet('Worktree','Index')][string]$Mode = 'Worktree',
        [string]$ConfigPath
    )
    $root = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
    $config = Read-Cf7RuntimeV2Config -ProjectRoot $root -Mode $Mode -ConfigPath $ConfigPath
    $domainConfig = $config.domains.PSObject.Properties[$Domain].Value
    $files = New-Object 'System.Collections.Generic.List[string]'

    foreach ($fixedValue in @($domainConfig.fixedFiles)) {
        $fixed = ([string]$fixedValue).Replace('\', '/')
        if ($fixed -match '(^|/)\.\.(/|$)' -or [IO.Path]::IsPathRooted($fixed)) { throw "Unsafe runtime input path: $fixed" }
        if ($Mode -eq 'Index') {
            # Do not compare `git ls-files` display text with the logical path. On a clean
            # hosted runner core.quotepath defaults to true, so non-ASCII names are emitted
            # as quoted octal escapes even though the index entry exists. cat-file checks
            # the exact stage-0 index object without depending on terminal/output encoding.
            & git -C $root cat-file -e (':' + $fixed) 2>$null
            if ($LASTEXITCODE -ne 0) { throw "Required $Domain input is absent from Git index: $fixed" }
        } else {
            $full = Join-Path $root ($fixed -replace '/', '\')
            if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "Required $Domain input missing: $fixed" }
        }
        $files.Add($fixed)
    }

    foreach ($tree in @($domainConfig.trees)) {
        $base = ([string]$tree.path).Replace('\', '/').TrimEnd('/')
        if (-not $base -or $base -match '(^|/)\.\.(/|$)' -or [IO.Path]::IsPathRooted($base)) { throw "Unsafe runtime input tree: $base" }
        $extensions = @($tree.includeExtensions | ForEach-Object { ([string]$_).ToLowerInvariant() })
        if ($Mode -eq 'Index') {
            $candidates = @(& git -c core.quotepath=false -C $root ls-files -- $base)
            if ($LASTEXITCODE -ne 0) { throw "Cannot enumerate runtime input tree from Git index: $base" }
        } else {
            $baseFull = Join-Path $root ($base -replace '/', '\')
            if (-not (Test-Path -LiteralPath $baseFull -PathType Container)) { throw "Required $Domain input tree missing: $base" }
            $candidates = @(Get-ChildItem -LiteralPath $baseFull -Recurse -File | ForEach-Object {
                $_.FullName.Substring($root.Length + 1).Replace('\', '/')
            })
        }
        foreach ($candidateValue in $candidates) {
            $candidate = ([string]$candidateValue).Replace('\', '/')
            $extension = [IO.Path]::GetExtension($candidate).ToLowerInvariant()
            if ($extensions.Count -gt 0 -and -not ($extensions -contains $extension)) { continue }
            if (Test-Cf7RuntimeV2PathExcluded -RelativePath $candidate -ExcludePaths @($tree.excludePaths) -ExcludePrefixes @($tree.excludePrefixes)) { continue }
            $files.Add($candidate)
        }
    }

    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($file in $files) { [void]$set.Add($file) }
    $result = [string[]]$set
    [Array]::Sort($result, [StringComparer]::Ordinal)
    return @($result)
}

function Get-Cf7RuntimeV2GitObjectId {
    param(
        [Parameter(Mandatory=$true)][string]$ProjectRoot,
        [Parameter(Mandatory=$true)][string]$RelativePath,
        [ValidateSet('Worktree','Index')][string]$Mode = 'Worktree'
    )
    $root = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
    if ($Mode -eq 'Index') {
        $rows = @(& git -C $root ls-files -s -- $RelativePath)
        if ($LASTEXITCODE -ne 0) { throw "Cannot read Git index identity: $RelativePath" }
        $stageZero = @($rows | Where-Object { $_ -match '^[0-9]+\s+([0-9a-fA-F]+)\s+0\t' })
        if ($stageZero.Count -ne 1) { throw "Runtime input has no unique stage-0 Git index entry: $RelativePath" }
        if ($stageZero[0] -notmatch '^[0-9]+\s+([0-9a-fA-F]+)\s+0\t') { throw "Invalid Git index row: $RelativePath" }
        return $Matches[1].ToLowerInvariant()
    }
    $full = Join-Path $root ($RelativePath -replace '/', '\')
    $oid = @(& git -C $root hash-object "--path=$RelativePath" -- $full)
    if ($LASTEXITCODE -ne 0 -or $oid.Count -ne 1 -or [string]$oid[0] -notmatch '^[0-9a-fA-F]{40,64}$') {
        throw "Cannot hash runtime input: $RelativePath"
    }
    return ([string]$oid[0]).Trim().ToLowerInvariant()
}

function Get-Cf7RuntimeV2DomainHash {
    param(
        [Parameter(Mandatory=$true)][string]$ProjectRoot,
        [Parameter(Mandatory=$true)][ValidateSet('artifactSource','producerRecipe','toolchainLock','policy')][string]$Domain,
        [ValidateSet('Worktree','Index')][string]$Mode = 'Worktree',
        [string]$ConfigPath
    )
    $root = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
    $lines = New-Object 'System.Collections.Generic.List[string]'
    foreach ($relative in Get-Cf7RuntimeV2DomainFiles -ProjectRoot $root -Domain $Domain -Mode $Mode -ConfigPath $ConfigPath) {
        $oid = Get-Cf7RuntimeV2GitObjectId -ProjectRoot $root -RelativePath $relative -Mode $Mode
        $lines.Add("$relative`t$oid")
    }
    $payload = [string]::Join("`n", $lines.ToArray()) + "`n"
    return Get-Cf7RuntimeV2BytesSha256 -Bytes ([Text.Encoding]::UTF8.GetBytes($payload))
}

function Get-Cf7RuntimeArtifactSourceHash {
    param([Parameter(Mandatory=$true)][string]$ProjectRoot, [ValidateSet('Worktree','Index')][string]$Mode = 'Worktree', [string]$ConfigPath)
    return Get-Cf7RuntimeV2DomainHash -ProjectRoot $ProjectRoot -Domain artifactSource -Mode $Mode -ConfigPath $ConfigPath
}

function Get-Cf7RuntimeProducerRecipeHash {
    param([Parameter(Mandatory=$true)][string]$ProjectRoot, [ValidateSet('Worktree','Index')][string]$Mode = 'Worktree', [string]$ConfigPath)
    return Get-Cf7RuntimeV2DomainHash -ProjectRoot $ProjectRoot -Domain producerRecipe -Mode $Mode -ConfigPath $ConfigPath
}

function Get-Cf7RuntimeToolchainLockHashV2 {
    param([Parameter(Mandatory=$true)][string]$ProjectRoot, [ValidateSet('Worktree','Index')][string]$Mode = 'Worktree', [string]$ConfigPath)
    return Get-Cf7RuntimeV2DomainHash -ProjectRoot $ProjectRoot -Domain toolchainLock -Mode $Mode -ConfigPath $ConfigPath
}

function Get-Cf7RuntimePolicyHash {
    param([Parameter(Mandatory=$true)][string]$ProjectRoot, [ValidateSet('Worktree','Index')][string]$Mode = 'Worktree', [string]$ConfigPath)
    return Get-Cf7RuntimeV2DomainHash -ProjectRoot $ProjectRoot -Domain policy -Mode $Mode -ConfigPath $ConfigPath
}

function Get-Cf7RuntimeV2BuildIdentityHash {
    param(
        [Parameter(Mandatory=$true)][string]$ArtifactSourceHash,
        [Parameter(Mandatory=$true)][string]$ProducerRecipeHash,
        [Parameter(Mandatory=$true)][string]$ToolchainLockHash
    )
    foreach ($value in @($ArtifactSourceHash,$ProducerRecipeHash,$ToolchainLockHash)) {
        if ([string]$value -notmatch '^[0-9A-Fa-f]{64}$') { throw 'Build identity components must be SHA-256 hex strings.' }
    }
    $canonical = "artifactSourceHash`t$($ArtifactSourceHash.ToUpperInvariant())`n" +
        "producerRecipeHash`t$($ProducerRecipeHash.ToUpperInvariant())`n" +
        "toolchainLockHash`t$($ToolchainLockHash.ToUpperInvariant())`n"
    return Get-Cf7RuntimeV2BytesSha256 -Bytes ([Text.Encoding]::UTF8.GetBytes($canonical))
}

function Get-Cf7RuntimeV2Identity {
    param(
        [Parameter(Mandatory=$true)][string]$ProjectRoot,
        [ValidateSet('Worktree','Index')][string]$Mode = 'Worktree',
        [string]$ConfigPath
    )
    $owners = @{}
    foreach ($domain in @('artifactSource','producerRecipe','toolchainLock','policy')) {
        foreach ($path in Get-Cf7RuntimeV2DomainFiles -ProjectRoot $ProjectRoot -Domain $domain -Mode $Mode -ConfigPath $ConfigPath) {
            if ($owners.ContainsKey($path)) { throw "Runtime v2 input domains overlap: $path ($($owners[$path]),$domain)" }
            $owners[$path] = $domain
        }
    }
    $artifact = Get-Cf7RuntimeArtifactSourceHash -ProjectRoot $ProjectRoot -Mode $Mode -ConfigPath $ConfigPath
    $producer = Get-Cf7RuntimeProducerRecipeHash -ProjectRoot $ProjectRoot -Mode $Mode -ConfigPath $ConfigPath
    $toolchain = Get-Cf7RuntimeToolchainLockHashV2 -ProjectRoot $ProjectRoot -Mode $Mode -ConfigPath $ConfigPath
    $policy = Get-Cf7RuntimePolicyHash -ProjectRoot $ProjectRoot -Mode $Mode -ConfigPath $ConfigPath
    return [pscustomobject][ordered]@{
        schema = 'cf7-runtime-build-identity.v2'
        artifactSourceHash = $artifact
        producerRecipeHash = $producer
        toolchainLockHash = $toolchain
        policyHash = $policy
        buildIdentityHash = Get-Cf7RuntimeV2BuildIdentityHash -ArtifactSourceHash $artifact -ProducerRecipeHash $producer -ToolchainLockHash $toolchain
    }
}

function Get-Cf7RuntimeBuildIdentityV2 {
    param([Parameter(Mandatory=$true)][string]$ProjectRoot, [ValidateSet('Worktree','Index')][string]$Mode = 'Worktree', [string]$ConfigPath)
    return Get-Cf7RuntimeV2Identity -ProjectRoot $ProjectRoot -Mode $Mode -ConfigPath $ConfigPath
}

function Get-Cf7RuntimeV2ReleaseTreeOid {
    param([Parameter(Mandatory=$true)][string]$ProjectRoot, [ValidateSet('Worktree','Index')][string]$Mode = 'Index')
    $root = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
    if ($Mode -eq 'Index') {
        $oid = @(& git -C $root write-tree)
    } else {
        $dirty = @(& git -C $root status --porcelain --untracked-files=normal)
        if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect Git worktree for release tree identity.' }
        if ($dirty.Count -gt 0) { throw 'A dirty worktree has no immutable releaseTreeOid; stage it and use Mode Index.' }
        $oid = @(& git -C $root rev-parse 'HEAD^{tree}')
    }
    if ($LASTEXITCODE -ne 0 -or $oid.Count -ne 1 -or [string]$oid[0] -notmatch '^[0-9a-fA-F]{40,64}$') { throw 'Cannot resolve releaseTreeOid.' }
    return ([string]$oid[0]).Trim().ToLowerInvariant()
}

function Get-Cf7RuntimeV2CanonicalClosureHash {
    param([Parameter(Mandatory=$true)][object[]]$Files)
    $rows = @($Files)
    [Array]::Sort($rows, [Comparison[object]]{
        param($left, $right)
        return [StringComparer]::Ordinal.Compare([string]$left.path, [string]$right.path)
    })
    $lines = New-Object 'System.Collections.Generic.List[string]'
    foreach ($row in $rows) {
        $path = ([string]$row.path).Replace('\', '/')
        if (-not $path -or $path.StartsWith('/', [StringComparison]::Ordinal) -or $path -match '(^|/)\.\.(/|$)' -or $path.Contains("`t") -or $path.Contains("`n") -or $path.Contains("`r")) {
            throw "Invalid payload path: $path"
        }
        $size = [Int64]$row.size
        if ($size -lt 0 -or [string]$row.size -notmatch '^\d+$') { throw "Invalid payload size: $path" }
        $hash = ([string]$row.sha256).ToUpperInvariant()
        if ($hash -notmatch '^[0-9A-F]{64}$') { throw "Invalid payload SHA-256: $path" }
        $lines.Add("$path`t$size`t$hash")
    }
    $canonical = [string]::Join("`n", $lines.ToArray()) + "`n"
    return Get-Cf7RuntimeV2BytesSha256 -Bytes ([Text.Encoding]::UTF8.GetBytes($canonical))
}

function Get-Cf7RuntimePayloadClosureV2 {
    param(
        [Parameter(Mandatory=$true)][string]$ProjectRoot,
        [Parameter(Mandatory=$true)][string]$DeploymentRoot,
        [ValidateSet('Worktree','Index')][string]$Mode = 'Worktree',
        [string]$ConfigPath
    )
    $project = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
    $config = Read-Cf7RuntimeV2Config -ProjectRoot $project -Mode $Mode -ConfigPath $ConfigPath
    $payloadConfig = $config.payload
    $paths = New-Object 'System.Collections.Generic.List[string]'

    if ($Mode -eq 'Index') {
        foreach ($fixedValue in @($payloadConfig.fixedRoots)) {
            $fixed = ([string]$fixedValue).Replace('\', '/')
            & git -C $project cat-file -e (':' + $fixed) 2>$null
            if ($LASTEXITCODE -ne 0) { throw "Required payload is absent from Git index: $fixed" }
            $paths.Add($fixed)
        }
        foreach ($treeValue in @($payloadConfig.trees)) {
            $tree = ([string]$treeValue).Replace('\', '/').TrimEnd('/')
            $found = @(& git -c core.quotepath=false -C $project ls-files -- $tree)
            if ($LASTEXITCODE -ne 0) { throw "Cannot enumerate payload tree from Git index: $tree" }
            foreach ($pathValue in $found) { $paths.Add(([string]$pathValue).Replace('\', '/')) }
        }
        $root = $project
    } else {
        $root = (Resolve-Path -LiteralPath $DeploymentRoot).Path.TrimEnd('\')
        foreach ($fixedValue in @($payloadConfig.fixedRoots)) {
            $fixed = ([string]$fixedValue).Replace('\', '/')
            $full = Join-Path $root ($fixed -replace '/', '\')
            if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "Runtime candidate lacks required payload: $fixed" }
            $paths.Add($fixed)
        }
        foreach ($treeValue in @($payloadConfig.trees)) {
            $tree = ([string]$treeValue).Replace('\', '/').TrimEnd('/')
            $treeFull = Join-Path $root ($tree -replace '/', '\')
            if (-not (Test-Path -LiteralPath $treeFull -PathType Container)) { throw "Runtime candidate lacks payload tree: $tree" }
            Get-ChildItem -LiteralPath $treeFull -Recurse -File | ForEach-Object {
                $paths.Add($_.FullName.Substring($root.Length + 1).Replace('\', '/'))
            }
        }
    }

    $pathSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($pathValue in $paths) {
        $path = ([string]$pathValue).Replace('\', '/')
        if (Test-Cf7RuntimeV2PathExcluded -RelativePath $path -ExcludePaths @($payloadConfig.excludePaths) -ExcludePrefixes @($payloadConfig.excludePrefixes)) { continue }
        [void]$pathSet.Add($path)
    }
    $sortedPaths = [string[]]$pathSet
    [Array]::Sort($sortedPaths, [StringComparer]::Ordinal)
    $files = New-Object 'System.Collections.Generic.List[object]'
    foreach ($relative in $sortedPaths) {
        if ($Mode -eq 'Index') {
            $bytes = Get-Cf7RuntimeV2GitIndexBlobBytes -ProjectRoot $project -RelativePath $relative
            $size = [Int64]$bytes.LongLength
            $hash = Get-Cf7RuntimeV2BytesSha256 -Bytes $bytes
        } else {
            $full = Join-Path $root ($relative -replace '/', '\')
            $item = Get-Item -LiteralPath $full
            $size = [Int64]$item.Length
            $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $full).Hash.ToUpperInvariant()
        }
        $files.Add([pscustomobject][ordered]@{ path = $relative; size = $size; sha256 = $hash })
    }
    $fileArray = $files.ToArray()
    return [pscustomobject][ordered]@{
        schema = 'cf7-runtime-payload-closure.v2'
        payloadClosureHash = Get-Cf7RuntimeV2CanonicalClosureHash -Files $fileArray
        files = $fileArray
    }
}

function Get-Cf7RuntimeV2PayloadClosure {
    param([Parameter(Mandatory=$true)][string]$ProjectRoot, [Parameter(Mandatory=$true)][string]$DeploymentRoot, [ValidateSet('Worktree','Index')][string]$Mode = 'Worktree', [string]$ConfigPath)
    return Get-Cf7RuntimePayloadClosureV2 -ProjectRoot $ProjectRoot -DeploymentRoot $DeploymentRoot -Mode $Mode -ConfigPath $ConfigPath
}
