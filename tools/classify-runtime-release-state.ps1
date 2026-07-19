param(
    [string]$ProjectRoot,
    [ValidateSet('Development', 'Protected')]
    [string]$Mode = 'Development',
    [string]$BaseRevision,
    [string]$TrustedBaseRevision,
    [switch]$DisableFastPath,
    [string]$HeadRevision = 'HEAD'
)

$ErrorActionPreference = 'Stop'

function Write-Cf7Failure([string]$Message) {
    Write-Host "[RuntimeReleaseState] FAIL $Message" -ForegroundColor Red
}

function Test-Cf7SafeRevision([string]$Revision) {
    if ([string]::IsNullOrWhiteSpace($Revision)) { return $false }
    if ($Revision -match '^0+$') { return $false }
    if ($Revision.StartsWith('-') -or $Revision.Contains('..') -or $Revision.Contains(':') -or
        $Revision.Contains('\\') -or $Revision.Contains('@{')) { return $false }
    return $Revision -match '^[A-Za-z0-9][A-Za-z0-9._/^-]*$'
}

function Resolve-Cf7Commit([string]$Revision, [switch]$Optional) {
    if (-not (Test-Cf7SafeRevision $Revision)) {
        if ($Optional -and ([string]::IsNullOrWhiteSpace($Revision) -or $Revision -match '^0+$')) { return $null }
        throw "Unsafe or invalid Git revision: $Revision"
    }
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $resolved = @(& git -C $ProjectRoot rev-parse --verify "$Revision^{commit}" 2>$null)
        $gitExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorAction
    }
    if ($gitExitCode -ne 0 -or $resolved.Count -ne 1 -or $resolved[0] -notmatch '^[0-9a-fA-F]{40,64}$') {
        if ($Optional) { return $null }
        throw "Cannot resolve Git commit: $Revision"
    }
    return ([string]$resolved[0]).Trim().ToLowerInvariant()
}

function Get-Cf7IndexedText([string]$RelativePath) {
    $output = @(& git -C $ProjectRoot show --no-textconv ":$RelativePath" 2>$null)
    if ($LASTEXITCODE -ne 0) { throw "Required indexed file is missing: $RelativePath" }
    return ($output -join "`n")
}

function Get-Cf7RevisionText([string]$Revision, [string]$RelativePath, [switch]$Optional) {
    $output = @(& git -C $ProjectRoot show --no-textconv "${Revision}:$RelativePath" 2>$null)
    if ($LASTEXITCODE -ne 0) {
        if ($Optional) { return $null }
        throw "Required file is missing at revision $Revision`: $RelativePath"
    }
    return ($output -join "`n")
}

function Get-Cf7GitBlobBytes([string]$ObjectSpec) {
    $gitCommand = Get-Command git -ErrorAction Stop
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $gitCommand.Source
    $psi.Arguments = "-C `"$ProjectRoot`" cat-file blob `"$ObjectSpec`""
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($psi)
    $memory = New-Object IO.MemoryStream
    try {
        $process.StandardOutput.BaseStream.CopyTo($memory)
        $errorText = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) { throw "Cannot read Git blob $ObjectSpec`: $errorText" }
        return $memory.ToArray()
    } finally {
        $memory.Dispose()
        $process.Dispose()
    }
}

function Get-Cf7BytesSha256([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '') }
    finally { $sha.Dispose() }
}

function Invoke-Cf7GitBinary([string[]]$Arguments) {
    $gitCommand = Get-Command git -ErrorAction Stop
    $quoted = New-Object 'Collections.Generic.List[string]'
    foreach ($argumentValue in $Arguments) {
        $argument = [string]$argumentValue
        if ($argument.IndexOfAny([char[]]@([char]0, [char]10, [char]13, [char]34)) -ge 0) {
            throw 'Unsafe character in binary Git command argument.'
        }
        # All dynamic repository paths are normalized to forward slashes and cannot end in a
        # backslash, so ordinary Windows command-line quoting is unambiguous here.
        [void]$quoted.Add('"' + $argument + '"')
    }
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $gitCommand.Source
    $psi.WorkingDirectory = $ProjectRoot
    $psi.Arguments = [string]::Join(' ', $quoted.ToArray())
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($psi)
    $memory = New-Object IO.MemoryStream
    try {
        $process.StandardOutput.BaseStream.CopyTo($memory)
        $errorText = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) {
            throw "Binary Git command failed (git $($Arguments -join ' ')): $errorText"
        }
        return ,$memory.ToArray()
    } finally {
        $memory.Dispose()
        $process.Dispose()
    }
}

function ConvertFrom-Cf7NulDelimitedUtf8([byte[]]$Bytes, [string]$Label) {
    if ($Bytes.Length -eq 0) { return @() }
    $utf8 = New-Object Text.UTF8Encoding($false, $true)
    try { $text = $utf8.GetString($Bytes) }
    catch { throw "$Label is not strict UTF-8." }
    if ($text[$text.Length - 1] -ne [char]0) { throw "$Label lacks its final NUL delimiter." }
    $tokens = @($text.Split([char]0))
    if ($tokens[$tokens.Count - 1] -ne '') { throw "$Label has an invalid NUL-delimited tail." }
    if ($tokens.Count -eq 1) { return @() }
    return @($tokens[0..($tokens.Count - 2)])
}

function ConvertTo-Cf7SafeRepoPath([AllowNull()][string]$Value, [string]$Label, [switch]$AllowTrailingSlash) {
    if ([string]::IsNullOrWhiteSpace($Value)) { throw "$Label is empty." }
    $path = [string]$Value
    if ($path.Contains('\') -or $path.Contains(':') -or $path.StartsWith('/') -or $path.Contains('//') -or
            $path.IndexOfAny([char[]]@([char]0, [char]10, [char]13, [char]34, [char]42, [char]60, [char]62, [char]63, [char]124, [char]127)) -ge 0) {
        throw "$Label is not a safe repository-relative path: $path"
    }
    foreach ($character in $path.ToCharArray()) {
        if ([int]$character -lt 32) { throw "$Label contains a control character." }
    }
    if ($path.EndsWith('/') -and -not $AllowTrailingSlash) { throw "$Label cannot end with '/': $path" }
    $segments = @($path.TrimEnd('/').Split('/'))
    if ($segments.Count -eq 0 -or @($segments | Where-Object { $_ -eq '' -or $_ -eq '.' -or $_ -eq '..' }).Count -gt 0) {
        throw "$Label contains an unsafe path segment: $path"
    }
    foreach ($segment in $segments) {
        if ($segment.Length -gt 255) {
            throw "$Label contains a path segment longer than 255 UTF-16 code units: $path"
        }
        if ($segment.EndsWith('.') -or $segment.EndsWith(' ')) {
            throw "$Label contains a Windows-ambiguous trailing character: $path"
        }
        $deviceStem = ([string]$segment.Split('.')[0]).TrimEnd(' ', '.')
        if ($deviceStem -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$') {
            throw "$Label contains a reserved Windows device name: $path"
        }
    }
    if ($path.Normalize([Text.NormalizationForm]::FormC) -cne $path) {
        throw "$Label is not Unicode NFC: $path"
    }
    return $path
}

function Add-Cf7ProtectedPath($Dictionary, [string]$Path, [string]$Origin) {
    $safe = ConvertTo-Cf7SafeRepoPath -Value $Path -Label $Origin
    if ($Dictionary.ContainsKey($safe)) {
        if ([string]$Dictionary[$safe] -cne $safe) {
            throw "Protected paths have a case collision: $($Dictionary[$safe]) and $safe"
        }
        return
    }
    $Dictionary.Add($safe, $safe)
}

function New-Cf7InputTreeRule($Tree, [string]$Domain) {
    if ($null -eq $Tree) { throw "Runtime input domain $Domain has a null tree rule." }
    $base = (ConvertTo-Cf7SafeRepoPath -Value ([string]$Tree.path) -Label "$Domain tree path").TrimEnd('/')
    $extensions = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($extensionValue in @($Tree.includeExtensions)) {
        $extension = [string]$extensionValue
        if ($extension -notmatch '^\.[A-Za-z0-9]+$') { throw "Invalid $Domain tree extension: $extension" }
        [void]$extensions.Add($extension)
    }
    $excludePaths = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($excludeValue in @($Tree.excludePaths)) {
        [void]$excludePaths.Add((ConvertTo-Cf7SafeRepoPath -Value ([string]$excludeValue) -Label "$Domain excluded path"))
    }
    $excludePrefixes = New-Object 'Collections.Generic.List[string]'
    foreach ($prefixValue in @($Tree.excludePrefixes)) {
        $prefix = ConvertTo-Cf7SafeRepoPath -Value ([string]$prefixValue) -Label "$Domain excluded prefix" -AllowTrailingSlash
        [void]$excludePrefixes.Add($prefix)
    }
    return [pscustomobject]@{
        Domain = $Domain
        Base = $base
        Extensions = $extensions
        ExcludePaths = $excludePaths
        ExcludePrefixes = $excludePrefixes.ToArray()
    }
}

function Test-Cf7InputTreeRule([string]$Path, $Rule) {
    if (-not $Path.StartsWith(([string]$Rule.Base + '/'), [StringComparison]::OrdinalIgnoreCase)) { return $false }
    if ($Rule.Extensions.Count -gt 0 -and -not $Rule.Extensions.Contains([IO.Path]::GetExtension($Path))) { return $false }
    if ($Rule.ExcludePaths.Contains($Path)) { return $false }
    foreach ($prefix in @($Rule.ExcludePrefixes)) {
        if ($Path.StartsWith([string]$prefix, [StringComparison]::Ordinal)) { return $false }
    }
    return $true
}

function Get-Cf7NativeChangeGate([string]$BaseCommit) {
    $relativePath = 'config/build/native-change-gate.v1.json'
    $blobOid = Get-Cf7RevisionBlobOid -Revision $BaseCommit -RelativePath $relativePath -Optional
    if (-not $blobOid) { return $null }
    $bytes = Get-Cf7GitBlobBytes -ObjectSpec "${BaseCommit}:$relativePath"
    $utf8 = New-Object Text.UTF8Encoding($false, $true)
    try { $text = $utf8.GetString($bytes).TrimStart([char]0xFEFF) }
    catch { throw 'Base native change gate is not strict UTF-8.' }
    try { $config = $text | ConvertFrom-Json }
    catch { throw "Base native change gate is invalid JSON: $($_.Exception.Message)" }

    $expectedFields = @('schema','protectedExtensions','protectedBasenames','protectedFiles','protectedPrefixes')
    $actualFields = @($config.PSObject.Properties.Name)
    if ($null -eq $config -or $actualFields.Count -ne $expectedFields.Count -or
            @($actualFields | Where-Object { $expectedFields -notcontains $_ }).Count -gt 0 -or
            [string]$config.schema -cne 'cf7-native-change-gate.v1') {
        throw 'Base native change gate does not have the exact cf7-native-change-gate.v1 shape.'
    }
    foreach ($arrayField in @('protectedExtensions','protectedBasenames','protectedFiles','protectedPrefixes')) {
        if ($config.$arrayField -isnot [Array]) { throw "Base native change gate $arrayField must be a JSON array." }
    }

    $extensions = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($value in @($config.protectedExtensions)) {
        if ($value -isnot [string] -or [string]$value -cnotmatch '^\.[a-z0-9]+$') {
            throw "Native change gate has an invalid lowercase extension: $value"
        }
        if (-not $extensions.Add([string]$value)) { throw "Native change gate has a duplicate extension: $value" }
    }
    if ($extensions.Count -eq 0) { throw 'Native change gate must protect at least one extension.' }

    $basenames = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($value in @($config.protectedBasenames)) {
        if ($value -isnot [string]) { throw 'Native change gate basenames must be strings.' }
        $basename = ConvertTo-Cf7SafeRepoPath -Value ([string]$value) -Label 'native protected basename'
        if ($basename.Contains('/')) { throw "Native protected basename cannot contain '/': $basename" }
        if (-not $basenames.Add($basename)) { throw "Native change gate has a duplicate basename: $basename" }
    }
    if ($basenames.Count -eq 0) { throw 'Native change gate must protect at least one basename.' }

    $files = New-Object 'Collections.Generic.Dictionary[string,string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($value in @($config.protectedFiles)) {
        if ($value -isnot [string]) { throw 'Native change gate files must be strings.' }
        Add-Cf7ProtectedPath -Dictionary $files -Path ([string]$value) -Origin 'native protected file'
    }
    if ($files.Count -eq 0) { throw 'Native change gate must protect at least one fixed file.' }

    $prefixes = New-Object 'Collections.Generic.List[string]'
    $seenPrefixes = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($value in @($config.protectedPrefixes)) {
        if ($value -isnot [string]) { throw 'Native change gate prefixes must be strings.' }
        $prefix = ConvertTo-Cf7SafeRepoPath -Value ([string]$value) -Label 'native protected prefix' -AllowTrailingSlash
        if (-not $seenPrefixes.Add($prefix)) { throw "Native change gate has a duplicate prefix: $prefix" }
        [void]$prefixes.Add($prefix)
    }
    if ($prefixes.Count -eq 0) { throw 'Native change gate must protect at least one prefix.' }

    foreach ($required in @('.c','.cpp','.cs','.csproj','.dll','.exe','.h','.hpp','.rs','.sln','.so','.dylib','.vcxproj','.wasm')) {
        if (-not $extensions.Contains($required)) { throw "Native change gate is missing mandatory extension: $required" }
    }
    foreach ($required in @('Cargo.lock','Cargo.toml','CMakeLists.txt','Directory.Build.props','Directory.Build.targets','global.json','packages.lock.json','rust-toolchain.toml')) {
        if (-not $basenames.Contains($required)) { throw "Native change gate is missing mandatory basename: $required" }
    }
    foreach ($required in @(
        '.github/CODEOWNERS',
        '.github/workflows/runtime-bundle-integrity.yml',
        'config/build/main-branch-admission.v1.json',
        'config/build/native-change-gate.v1.json',
        'config/build/runtime-inputs.v2.json',
        'tools/audit-main-branch-admission.ps1',
        'tools/classify-runtime-release-state.ps1',
        'tools/resolve-runtime-trusted-base.ps1'
    )) {
        if (-not $files.ContainsKey($required)) { throw "Native change gate is missing mandatory fixed file: $required" }
    }
    foreach ($required in @(
        '.github/actions/', '.github/workflows/', 'config/build/', 'launcher/build',
        'launcher/native/', 'launcher/src/', 'runtime/', 'tools/promote-runtime-',
        'tools/resolve-runtime-', 'tools/runtime-', 'tools/verify-runtime-'
    )) {
        if (-not $seenPrefixes.Contains($required)) { throw "Native change gate is missing mandatory prefix: $required" }
    }

    return [pscustomobject]@{
        BlobOid = $blobOid
        Extensions = $extensions
        Basenames = $basenames
        Files = $files
        Prefixes = $prefixes.ToArray()
    }
}

function Get-Cf7FastPathProtection([string]$BaseCommit) {
    $descriptorPath = 'config/build/runtime-inputs.v2.json'
    $descriptorOid = Get-Cf7RevisionBlobOid -Revision $BaseCommit -RelativePath $descriptorPath -Optional
    if (-not $descriptorOid) { return $null }
    $descriptorBytes = Get-Cf7GitBlobBytes -ObjectSpec "${BaseCommit}:$descriptorPath"
    $utf8 = New-Object Text.UTF8Encoding($false, $true)
    try { $descriptorText = $utf8.GetString($descriptorBytes).TrimStart([char]0xFEFF) }
    catch { throw 'Base runtime input descriptor is not strict UTF-8.' }
    try { $descriptor = $descriptorText | ConvertFrom-Json }
    catch { throw "Base runtime input descriptor is invalid JSON: $($_.Exception.Message)" }
    if ($null -eq $descriptor -or [string]$descriptor.schema -cne 'cf7-runtime-inputs.v2') {
        throw 'Base runtime input descriptor has an unsupported schema.'
    }
    foreach ($requiredDomain in @('artifactSource','producerRecipe','toolchainLock','policy')) {
        $requiredProperty = $descriptor.domains.PSObject.Properties[$requiredDomain]
        if ($null -eq $requiredProperty -or $requiredProperty.Value.fixedFiles -isnot [Array] -or
                $requiredProperty.Value.trees -isnot [Array]) {
            throw "Base runtime input descriptor lacks a well-formed domain: $requiredDomain"
        }
    }
    $nativeGate = Get-Cf7NativeChangeGate -BaseCommit $BaseCommit
    if ($null -eq $nativeGate) { return $null }

    $fixed = New-Object 'Collections.Generic.Dictionary[string,string]' ([StringComparer]::OrdinalIgnoreCase)
    $treeRules = New-Object 'Collections.Generic.List[object]'
    $fullPrefixes = New-Object 'Collections.Generic.List[string]'
    # The formal release policy remains deliberately broad, but direct-push admission is
    # native-only. Content generators and derived catalogs stay bound to the next policy
    # receipt without forcing an unrelated content push to republish the runtime bundle.
    foreach ($domain in @('artifactSource','producerRecipe','toolchainLock')) {
        $domainProperty = $descriptor.domains.PSObject.Properties[$domain]
        if ($null -eq $domainProperty) { throw "Base runtime input descriptor lacks domain: $domain" }
        $domainConfig = $domainProperty.Value
        foreach ($fixedValue in @($domainConfig.fixedFiles)) {
            Add-Cf7ProtectedPath -Dictionary $fixed -Path ([string]$fixedValue) -Origin "$domain fixed input"
        }
        foreach ($tree in @($domainConfig.trees)) {
            $rule = New-Cf7InputTreeRule -Tree $tree -Domain $domain
            [void]$treeRules.Add($rule)
            $treeBytes = Invoke-Cf7GitBinary @('ls-tree','-r','-z','--full-tree',$BaseCommit,'--',[string]$rule.Base)
            $treeRows = @(ConvertFrom-Cf7NulDelimitedUtf8 -Bytes $treeBytes -Label "$domain base tree listing")
            foreach ($row in $treeRows) {
                if ([string]$row -notmatch '^([0-7]{6}) (blob|commit) ([0-9a-fA-F]{40,64})\t(.+)$') {
                    throw "Invalid Git tree row while expanding $domain inputs."
                }
                $mode = [string]$Matches[1]
                $candidate = ConvertTo-Cf7SafeRepoPath -Value ([string]$Matches[4]) -Label "$domain tree entry"
                if (-not (Test-Cf7InputTreeRule -Path $candidate -Rule $rule)) { continue }
                if ($mode -notin @('100644','100755')) {
                    throw "Runtime input tree contains a non-regular entry: $candidate mode=$mode"
                }
                Add-Cf7ProtectedPath -Dictionary $fixed -Path $candidate -Origin "$domain expanded tree input"
            }
        }
    }

    if ($null -eq $descriptor.payload) { throw 'Base runtime input descriptor lacks payload protection.' }
    foreach ($fixedRootValue in @($descriptor.payload.fixedRoots)) {
        Add-Cf7ProtectedPath -Dictionary $fixed -Path ([string]$fixedRootValue) -Origin 'payload fixed root'
    }
    foreach ($payloadTreeValue in @($descriptor.payload.trees)) {
        $payloadTree = ConvertTo-Cf7SafeRepoPath -Value ([string]$payloadTreeValue) -Label 'payload tree'
        [void]$fullPrefixes.Add($payloadTree + '/')
        $payloadBytes = Invoke-Cf7GitBinary @('ls-tree','-r','-z','--full-tree',$BaseCommit,'--',$payloadTree)
        foreach ($row in @(ConvertFrom-Cf7NulDelimitedUtf8 -Bytes $payloadBytes -Label 'payload base tree listing')) {
            if ([string]$row -notmatch '^([0-7]{6}) (blob|commit) ([0-9a-fA-F]{40,64})\t(.+)$') {
                throw 'Invalid Git tree row while expanding payload protection.'
            }
            $mode = [string]$Matches[1]
            $candidate = ConvertTo-Cf7SafeRepoPath -Value ([string]$Matches[4]) -Label 'payload tree entry'
            if (-not $candidate.StartsWith(($payloadTree + '/'), [StringComparison]::Ordinal)) { continue }
            if ($mode -ne '100644') { throw "Payload tree contains a non-canonical entry: $candidate mode=$mode" }
            Add-Cf7ProtectedPath -Dictionary $fixed -Path $candidate -Origin 'expanded payload tree entry'
        }
    }

    foreach ($nativeFile in @($nativeGate.Files.Keys)) {
        Add-Cf7ProtectedPath -Dictionary $fixed -Path ([string]$nativeFile) -Origin 'native gate fixed file'
    }
    foreach ($nativePrefix in @($nativeGate.Prefixes)) { [void]$fullPrefixes.Add([string]$nativePrefix) }

    foreach ($sentinel in @(
        'CRAZYFLASHER7MercenaryEmpire.exe',
        'config/build/main-branch-admission.v1.json',
        'config/build/native-change-gate.v1.json',
        'config/build/runtime-release-consensus.json',
        'config/build/runtime-builders.v2.json',
        'config/build/runtime-v2-migration-bootstrap.json',
        'config/build/runtime-inputs.v2.json',
        '.github/workflows/runtime-bundle-integrity.yml',
        'tools/classify-runtime-release-state.ps1',
        'tools/runtime-build-common.ps1',
        'tools/runtime-build-v2-common.ps1',
        'tools/runtime-build-attestation-v2-common.ps1',
        'tools/runtime-build-queue-common.ps1',
        'tools/verify-runtime-bundle.ps1',
        'tools/verify-runtime-bundle-v2.ps1',
        'tools/verify-runtime-consensus.ps1',
        'tools/verify-runtime-github-attestation.ps1'
    )) {
        Add-Cf7ProtectedPath -Dictionary $fixed -Path $sentinel -Origin 'hard-coded runtime integrity sentinel'
    }
    return [pscustomobject]@{
        Fixed = $fixed
        TreeRules = $treeRules.ToArray()
        FullPrefixes = $fullPrefixes.ToArray()
        GlobalExtensions = $nativeGate.Extensions
        ProtectedBasenames = $nativeGate.Basenames
        GateFiles = $nativeGate.Files
        GatePrefixes = $nativeGate.Prefixes
        DescriptorOid = $descriptorOid
        GateBlobOid = $nativeGate.BlobOid
    }
}

function Get-Cf7RequiredBaseSentinels([string]$BaseCommit) {
    $result = [ordered]@{}
    foreach ($relativePath in @(
        'config/build/runtime-inputs.v2.json',
        'config/build/main-branch-admission.v1.json',
        'config/build/native-change-gate.v1.json',
        'runtime/cf7-runtime-manifest.tsv',
        'config/build/runtime-release-consensus.json',
        'config/build/runtime-builders.v2.json',
        'config/build/runtime-v2-migration-bootstrap.json',
        'CRAZYFLASHER7MercenaryEmpire.exe'
    )) {
        $bytes = Invoke-Cf7GitBinary @('ls-tree','-z',$BaseCommit,'--',$relativePath)
        $rows = @(ConvertFrom-Cf7NulDelimitedUtf8 -Bytes $bytes -Label "base sentinel $relativePath")
        if ($rows.Count -eq 0) { return $null }
        if ($rows.Count -ne 1 -or [string]$rows[0] -notmatch '^100644 blob ([0-9a-fA-F]{40,64})\t(.+)$' -or [string]$Matches[2] -cne $relativePath) {
            throw "Trusted base lacks the required regular-file sentinel: $relativePath"
        }
        $result[$relativePath] = ([string]$Matches[1]).ToLowerInvariant()
    }
    return $result
}

function Assert-Cf7HeadTreePathSafety([string]$BaseCommit, [string]$HeadCommit) {
    $baseBytes = Invoke-Cf7GitBinary @('ls-tree','-r','-z','--full-tree',$BaseCommit)
    $baseRows = @(ConvertFrom-Cf7NulDelimitedUtf8 -Bytes $baseBytes -Label 'base tree listing')
    $baseEntries = New-Object 'Collections.Generic.Dictionary[string,string]' ([StringComparer]::Ordinal)
    $baseCaseVariants = New-Object 'Collections.Generic.Dictionary[string,object]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($row in $baseRows) {
        if ([string]$row -notmatch '^([0-7]{6}) (blob|commit) ([0-9a-fA-F]{40,64})\t(.+)$') { throw 'Base tree contains an invalid row.' }
        $mode = [string]$Matches[1]
        $oid = ([string]$Matches[3]).ToLowerInvariant()
        $path = [string]$Matches[4]
        if ($baseEntries.ContainsKey($path)) { throw "Base tree contains a duplicate path: $path" }
        $baseEntries.Add($path, "$mode`t$oid")
        $prefix = ''
        foreach ($segment in $path.Split('/')) {
            $prefix = if ($prefix) { $prefix + '/' + $segment } else { $segment }
            if (-not $baseCaseVariants.ContainsKey($prefix)) {
                $baseCaseVariants.Add($prefix, (New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)))
            }
            [void]$baseCaseVariants[$prefix].Add($prefix)
        }
    }

    $headBytes = Invoke-Cf7GitBinary @('ls-tree','-r','-z','--full-tree',$HeadCommit)
    $headRows = @(ConvertFrom-Cf7NulDelimitedUtf8 -Bytes $headBytes -Label 'head tree listing')
    $headCaseMap = New-Object 'Collections.Generic.Dictionary[string,string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($row in $headRows) {
        if ([string]$row -notmatch '^([0-7]{6}) (blob|commit) ([0-9a-fA-F]{40,64})\t(.+)$') { throw 'Head tree contains an invalid row.' }
        $mode = [string]$Matches[1]
        $oid = ([string]$Matches[3]).ToLowerInvariant()
        $rawPath = [string]$Matches[4]
        $unchangedLegacyPath = $baseEntries.ContainsKey($rawPath) -and [string]$baseEntries[$rawPath] -ceq "$mode`t$oid"
        $path = if ($unchangedLegacyPath) {
            # Historical trees contain a small number of paths that modern Windows path rules
            # would reject (including U+FFFF). They may survive byte-for-byte, but any touch,
            # rename, mode change, or new unsafe path must pass the strict validator below.
            $rawPath
        } else {
            try {
                ConvertTo-Cf7SafeRepoPath -Value $rawPath -Label 'changed head tree path'
            } catch {
                $baseIdentity = if ($baseEntries.ContainsKey($rawPath)) { [string]$baseEntries[$rawPath] } else { 'absent' }
                throw "Changed or newly introduced head path is unsafe: path=$rawPath baseIdentity=$baseIdentity headIdentity=$mode`t$oid detail=$($_.Exception.Message)"
            }
        }
        if (-not $unchangedLegacyPath -and $mode -ne '100644') {
            throw "Head tree contains a symlink, gitlink, executable, or non-regular entry: $path mode=$mode"
        }
        $prefix = ''
        foreach ($segment in $path.Split('/')) {
            $prefix = if ($prefix) { $prefix + '/' + $segment } else { $segment }
            if ($headCaseMap.ContainsKey($prefix) -and [string]$headCaseMap[$prefix] -cne $prefix) {
                $existing = [string]$headCaseMap[$prefix]
                $grandfathered = $baseCaseVariants.ContainsKey($prefix) -and
                    $baseCaseVariants[$prefix].Contains($existing) -and $baseCaseVariants[$prefix].Contains($prefix)
                if (-not $grandfathered) {
                    throw "Head tree contains a case-colliding path component: $existing and $prefix"
                }
            } elseif (-not $headCaseMap.ContainsKey($prefix)) {
                $headCaseMap.Add($prefix, $prefix)
            }
        }
    }
}

function Get-Cf7RawChangedEntries([string]$BaseCommit, [string]$HeadCommit) {
    $rawBytes = Invoke-Cf7GitBinary @('diff','--raw','-z','--full-index','--no-renames',$BaseCommit,$HeadCommit,'--')
    $tokens = @(ConvertFrom-Cf7NulDelimitedUtf8 -Bytes $rawBytes -Label 'raw base/head diff')
    if (($tokens.Count % 2) -ne 0) { throw 'Raw base/head diff has an invalid token count.' }
    $entries = New-Object 'Collections.Generic.List[object]'
    $caseMap = New-Object 'Collections.Generic.Dictionary[string,string]' ([StringComparer]::OrdinalIgnoreCase)
    for ($index = 0; $index -lt $tokens.Count; $index += 2) {
        $header = [string]$tokens[$index]
        if ($header -notmatch '^:([0-7]{6}) ([0-7]{6}) ([0-9a-fA-F]{7,64}) ([0-9a-fA-F]{7,64}) ([A-Z])$') {
            throw "Unsupported raw Git diff record: $header"
        }
        $oldMode = [string]$Matches[1]
        $newMode = [string]$Matches[2]
        $oldOid = ([string]$Matches[3]).ToLowerInvariant()
        $newOid = ([string]$Matches[4]).ToLowerInvariant()
        $status = [string]$Matches[5]
        $validModeShape = switch ($status) {
            'A' { $oldMode -eq '000000' -and $newMode -eq '100644' -and $oldOid -match '^0+$' -and $newOid -notmatch '^0+$' }
            'D' { $oldMode -eq '100644' -and $newMode -eq '000000' -and $oldOid -notmatch '^0+$' -and $newOid -match '^0+$' }
            'M' { $oldMode -eq '100644' -and $newMode -eq '100644' -and $oldOid -notmatch '^0+$' -and $newOid -notmatch '^0+$' }
            default { $false }
        }
        if (-not $validModeShape) {
            throw "Content fast path rejects inconsistent, executable, symlink, gitlink, or non-regular changes: status=$status old=$oldMode new=$newMode"
        }
        $path = ConvertTo-Cf7SafeRepoPath -Value ([string]$tokens[$index + 1]) -Label 'changed path'
        if ($caseMap.ContainsKey($path)) {
            throw "Changed paths have a duplicate or case collision: $($caseMap[$path]) and $path"
        }
        $caseMap.Add($path, $path)
        $entries.Add([pscustomobject]@{ Path=$path; Status=$status; OldMode=$oldMode; NewMode=$newMode; OldOid=$oldOid; NewOid=$newOid })
    }
    return @($entries.ToArray())
}

function Test-Cf7ProtectedFastPath([string]$Path, $Protection) {
    if ($Protection.Fixed.ContainsKey($Path)) { return $true }
    if ($Protection.GlobalExtensions.Contains([IO.Path]::GetExtension($Path))) { return $true }
    if ($Protection.ProtectedBasenames.Contains([IO.Path]::GetFileName($Path))) { return $true }
    foreach ($prefix in @($Protection.FullPrefixes)) {
        if ($Path.StartsWith([string]$prefix, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    foreach ($rule in @($Protection.TreeRules)) {
        if (Test-Cf7InputTreeRule -Path $Path -Rule $rule) { return $true }
    }
    return $false
}

function Test-Cf7NativeGatePath([string]$Path, $Protection) {
    if ($null -eq $Protection) { return $false }
    if ($Protection.GateFiles.ContainsKey($Path)) { return $true }
    if ($Protection.GlobalExtensions.Contains([IO.Path]::GetExtension($Path))) { return $true }
    if ($Protection.ProtectedBasenames.Contains([IO.Path]::GetFileName($Path))) { return $true }
    foreach ($prefix in @($Protection.GatePrefixes)) {
        if ($Path.StartsWith([string]$prefix, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Get-Cf7IndexedReleaseBoundPaths {
    $commonPath = Join-Path $ProjectRoot 'tools\runtime-build-v2-common.ps1'
    if (-not (Test-Path -LiteralPath $commonPath -PathType Leaf)) { throw 'Runtime v2 binding helper is missing.' }
    . $commonPath

    $bound = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($domain in @('artifactSource','producerRecipe','toolchainLock','policy')) {
        foreach ($value in Get-Cf7RuntimeV2DomainFiles -ProjectRoot $ProjectRoot -Domain $domain -Mode Index) {
            $path = ConvertTo-Cf7SafeRepoPath -Value ([string]$value) -Label "$domain indexed release binding"
            [void]$bound.Add($path)
        }
    }
    $descriptor = Read-Cf7RuntimeV2Config -ProjectRoot $ProjectRoot -Mode Index
    if ($null -eq $descriptor.payload -or $descriptor.payload.fixedRoots -isnot [Array] -or
            $descriptor.payload.trees -isnot [Array]) {
        throw 'Indexed runtime descriptor lacks well-formed payload binding.'
    }
    foreach ($fixedValue in @($descriptor.payload.fixedRoots)) {
        $fixed = ConvertTo-Cf7SafeRepoPath -Value ([string]$fixedValue) -Label 'indexed payload fixed root'
        $oid = Get-Cf7RevisionBlobOid -Revision ':' -RelativePath $fixed -Optional
        if (-not $oid) { throw "Indexed payload fixed root is absent: $fixed" }
        [void]$bound.Add($fixed)
    }
    foreach ($treeValue in @($descriptor.payload.trees)) {
        $tree = ConvertTo-Cf7SafeRepoPath -Value ([string]$treeValue) -Label 'indexed payload tree'
        $bytes = Invoke-Cf7GitBinary @('ls-files','-z','--',$tree)
        foreach ($value in @(ConvertFrom-Cf7NulDelimitedUtf8 -Bytes $bytes -Label "indexed payload tree $tree")) {
            $path = ConvertTo-Cf7SafeRepoPath -Value ([string]$value) -Label 'indexed payload entry'
            if ($path.StartsWith(($tree + '/'), [StringComparison]::Ordinal) -or $path -ceq $tree) {
                [void]$bound.Add($path)
            }
        }
    }
    # These are canonical release outputs/bootstrap controls. The consensus record cannot
    # be an input to its own build identity, while the registry and fuse must remain
    # available to the separately validated one-time v1 -> v2 migration path.
    foreach ($releaseControlPath in @(
        'config/build/runtime-release-consensus.json',
        'config/build/runtime-builders.v2.json',
        'config/build/runtime-v2-migration-bootstrap.json'
    )) {
        [void]$bound.Add($releaseControlPath)
    }
    return ,$bound
}

function Assert-Cf7NativeChangesReleaseBound([object[]]$Entries, $BaseProtection, $HeadProtection) {
    if ($null -eq $HeadProtection) { throw 'Protected head must retain a valid native change gate and runtime input descriptor.' }
    $gatedWrites = @($Entries | Where-Object {
        [string]$_.Status -ne 'D' -and (
            (Test-Cf7NativeGatePath -Path ([string]$_.Path) -Protection $BaseProtection) -or
            (Test-Cf7NativeGatePath -Path ([string]$_.Path) -Protection $HeadProtection)
        )
    })
    if ($gatedWrites.Count -eq 0) { return }
    $bound = Get-Cf7IndexedReleaseBoundPaths
    $unbound = @($gatedWrites | Where-Object { -not $bound.Contains([string]$_.Path) } | ForEach-Object { [string]$_.Path } | Sort-Object -Unique)
    if ($unbound.Count -gt 0) {
        throw "Native/runtime changes are not bound by the indexed release descriptor and cannot become green: $($unbound -join ',')"
    }
}

function Get-Cf7RevisionBlobOid([string]$Revision, [string]$RelativePath, [switch]$Optional) {
    $spec = if ($Revision -eq ':') { ":$RelativePath" } else { "${Revision}:$RelativePath" }
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& git -C $ProjectRoot rev-parse --verify $spec 2>$null)
        $gitExitCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousErrorAction }
    if ($gitExitCode -ne 0 -or $output.Count -ne 1 -or [string]$output[0] -notmatch '^[0-9a-fA-F]{40,64}$') {
        if ($Optional) { return $null }
        throw "Required Git blob is missing: $spec"
    }
    return ([string]$output[0]).Trim().ToLowerInvariant()
}

function Read-Cf7MigrationMarker([byte[]]$Bytes) {
    $utf8 = New-Object Text.UTF8Encoding($false, $true)
    try { $text = $utf8.GetString($Bytes) }
    catch { throw 'Runtime v2 migration marker is not strict UTF-8.' }
    try { $marker = $text | ConvertFrom-Json }
    catch { throw "Runtime v2 migration marker is invalid JSON: $($_.Exception.Message)" }
    if ($null -eq $marker) { throw 'Runtime v2 migration marker is empty.' }
    $fields = @('schema','migrationId','baseCommitOid','fromManifest','toManifest','legacyArtifactClosureHash','targetBuilderRegistrySha256')
    $properties = @($marker.PSObject.Properties.Name)
    if ($properties.Count -ne $fields.Count -or @($properties | Where-Object { $fields -notcontains $_ }).Count -gt 0) {
        throw 'Runtime v2 migration marker fields are not the exact allowed set.'
    }
    if ([string]$marker.schema -cne 'cf7-runtime-v2-migration-bootstrap.v1' -or
            [string]$marker.migrationId -cne 'runtime-release-v2-bootstrap-2026-07' -or
            [string]$marker.fromManifest -cne 'cf7-runtime-manifest-v1' -or
            [string]$marker.toManifest -cne 'cf7-runtime-manifest-v2') {
        throw 'Runtime v2 migration marker has an unsupported fixed transition.'
    }
    if ([string]$marker.baseCommitOid -cnotmatch '^(?:[0-9a-f]{40}|[0-9a-f]{64})$') { throw 'Migration marker baseCommitOid must be a lowercase full Git OID.' }
    foreach ($field in @('legacyArtifactClosureHash','targetBuilderRegistrySha256')) {
        if ([string]$marker.$field -cnotmatch '^[0-9A-F]{64}$') { throw "Migration marker $field must be uppercase SHA-256." }
    }
    $canonical = '{"schema":"cf7-runtime-v2-migration-bootstrap.v1","migrationId":"runtime-release-v2-bootstrap-2026-07","baseCommitOid":"' +
        [string]$marker.baseCommitOid + '","fromManifest":"cf7-runtime-manifest-v1","toManifest":"cf7-runtime-manifest-v2","legacyArtifactClosureHash":"' +
        [string]$marker.legacyArtifactClosureHash + '","targetBuilderRegistrySha256":"' + [string]$marker.targetBuilderRegistrySha256 + '"}' + "`n"
    $canonicalBytes = [Text.Encoding]::UTF8.GetBytes($canonical)
    if ($Bytes.Length -ne $canonicalBytes.Length) { throw 'Runtime v2 migration marker is not in canonical byte form.' }
    for ($index = 0; $index -lt $Bytes.Length; $index++) {
        if ($Bytes[$index] -ne $canonicalBytes[$index]) { throw 'Runtime v2 migration marker is not in canonical byte form.' }
    }
    return $marker
}

function Assert-Cf7BootstrapBuilderRegistry([byte[]]$RegistryBytes, [string]$ExpectedSha256) {
    $actualHash = Get-Cf7BytesSha256 -Bytes $RegistryBytes
    if ($actualHash -cne $ExpectedSha256) { throw "Migration builder registry SHA-256 mismatch: expected=$ExpectedSha256 actual=$actualHash" }
    $temporaryPath = Join-Path ([IO.Path]::GetTempPath()) ('cf7-runtime-builders-' + [Guid]::NewGuid().ToString('N') + '.json')
    try {
        [IO.File]::WriteAllBytes($temporaryPath, $RegistryBytes)
        . (Join-Path $ProjectRoot 'tools\runtime-build-v2-common.ps1')
        . (Join-Path $ProjectRoot 'tools\runtime-build-attestation-v2-common.ps1')
        $registry = Read-Cf7RuntimeV2BuilderRegistry -RegistryPath $temporaryPath
        $enabled = @($registry.builders | Where-Object { $_.enabled -eq $true })
        if ($enabled.Count -lt 1) { throw 'Migration builder registry requires at least one enabled public-key identity.' }
        $builderIds = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        $faultDomains = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        foreach ($entry in @($registry.builders)) {
            if ([string]$entry.builderId -notmatch '^[a-z0-9][a-z0-9._-]{1,63}$' -or -not $builderIds.Add([string]$entry.builderId)) {
                throw 'Migration builder registry has an invalid or duplicate builderId.'
            }
        }
        foreach ($entry in $enabled) {
            if (-not $faultDomains.Add([string]$entry.faultDomain)) { throw 'Enabled migration builders must have unique faultDomain values.' }
            $raw = [Convert]::FromBase64String([string]$entry.certificateBase64)
            $certificate = New-Object Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList @(,$raw)
            try {
                if ($certificate.HasPrivateKey) { throw 'Builder registry must contain only public certificate bytes, never private key material.' }
                $rsa = [Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($certificate)
                if ($null -eq $rsa) { throw 'Enabled migration builder certificate does not contain an RSA public key.' }
                $rsa.Dispose()
            } finally { $certificate.Dispose() }
        }
    } finally {
        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
    }
    return $actualHash
}

function Get-Cf7ManifestHeader([AllowNull()][string]$Text, [switch]$Optional) {
    if ($null -eq $Text) {
        if ($Optional) { return $null }
        throw 'Runtime manifest text is missing.'
    }
    $lines = @($Text -split "`r?`n" | Where-Object { $_ -ne '' })
    if ($lines.Count -eq 0) {
        if ($Optional) { return $null }
        throw 'Runtime manifest is empty.'
    }
    $header = ([string]$lines[0]).TrimStart([char]0xFEFF)
    if ($header -notin @('cf7-runtime-manifest-v1', 'cf7-runtime-manifest-v2')) {
        if ($Optional) { return $null }
        throw "Unsupported runtime manifest header: $header"
    }
    return $header
}

function Get-Cf7PowerShellExecutable {
    try {
        $current = (Get-Process -Id $PID -ErrorAction Stop).Path
        if ($current -and (Test-Path -LiteralPath $current -PathType Leaf)) { return $current }
    } catch {}
    foreach ($name in @('powershell.exe', 'pwsh.exe', 'pwsh')) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command) { return $command.Source }
    }
    throw 'Cannot locate a PowerShell executable for isolated verification.'
}

function Invoke-Cf7Verifier(
    [string]$Label,
    [string]$Path,
    [string[]]$Arguments,
    [bool]$EchoOutput = $true
) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Label script is missing: $Path" }
    $commandArguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Path) + $Arguments
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& $script:PowerShellExecutable @commandArguments 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorAction
    }
    if ($EchoOutput) {
        foreach ($line in $output) { Write-Host ([string]$line) }
    }
    return [pscustomobject]@{
        Label = $Label
        ExitCode = [int]$exitCode
        Output = @($output | ForEach-Object { [string]$_ })
    }
}

function Assert-Cf7Passed($Result) {
    if ($Result.ExitCode -ne 0) { throw "$($Result.Label) failed with exit code $($Result.ExitCode)." }
}

try {
    if (-not $ProjectRoot) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }
    $ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\\')
    & git -C $ProjectRoot rev-parse --is-inside-work-tree *> $null
    if ($LASTEXITCODE -ne 0) { throw "ProjectRoot is not a Git worktree: $ProjectRoot" }
    if ($Mode -ne 'Protected') {
        throw 'Runtime integrity required context is reserved for Protected target refs; Development mode is forbidden.'
    }

    $headCommit = Resolve-Cf7Commit -Revision $HeadRevision
    $baseWasAbsent = [string]::IsNullOrWhiteSpace($BaseRevision) -or $BaseRevision -match '^0+$'
    $baseCommit = if ($baseWasAbsent) { $null } else { Resolve-Cf7Commit -Revision $BaseRevision }
    $baseOrigin = 'provided'
    if (-not $baseCommit) {
        $baseCommit = Resolve-Cf7Commit -Revision "$headCommit^" -Optional
        $baseOrigin = if ($baseCommit) { 'head-parent-fallback' } else { 'initial-commit' }
    }
    if (-not $baseWasAbsent) {
        & git -C $ProjectRoot merge-base --is-ancestor $baseCommit $headCommit *> $null
        if ($LASTEXITCODE -ne 0) { throw 'Explicit protected base must be an ancestor of the classified head.' }
    }
    if ($DisableFastPath -and -not [string]::IsNullOrWhiteSpace($TrustedBaseRevision)) {
        throw '-DisableFastPath and -TrustedBaseRevision are mutually exclusive.'
    }
    $trustedBaseCommit = if ([string]::IsNullOrWhiteSpace($TrustedBaseRevision)) {
        $null
    } else { Resolve-Cf7Commit -Revision $TrustedBaseRevision }
    if ($trustedBaseCommit) {
        & git -C $ProjectRoot merge-base --is-ancestor $trustedBaseCommit $headCommit *> $null
        if ($LASTEXITCODE -ne 0) { throw 'Trusted fast-path base must be an ancestor of the classified head.' }
        if ($baseCommit) {
            & git -C $ProjectRoot merge-base --is-ancestor $trustedBaseCommit $baseCommit *> $null
            if ($LASTEXITCODE -ne 0) { throw 'Trusted fast-path base must be an ancestor of the explicit event base.' }
        }
    }
    if ($DisableFastPath -or -not $trustedBaseCommit) {
        throw 'No externally verified green main anchor is available; refusing to emit a reusable required-check success.'
    }

    # -Staged verifiers read the Git index. Refuse an ambiguous head/index pairing.
    $indexTree = (@(& git -C $ProjectRoot write-tree 2>$null) -join '').Trim()
    $headTree = (@(& git -C $ProjectRoot rev-parse "$headCommit^{tree}" 2>$null) -join '').Trim()
    if ($LASTEXITCODE -ne 0 -or -not $indexTree -or $indexTree -ne $headTree) {
        throw "Git index does not match HeadRevision $headCommit; staged verification would classify different content."
    }
    if ($baseCommit) { Assert-Cf7HeadTreePathSafety -BaseCommit $baseCommit -HeadCommit $headCommit }
    $admissionBaseCommit = if ($trustedBaseCommit) { $trustedBaseCommit } else { $baseCommit }
    if ($admissionBaseCommit -and $admissionBaseCommit -cne $baseCommit) {
        Assert-Cf7HeadTreePathSafety -BaseCommit $admissionBaseCommit -HeadCommit $headCommit
    }
    # Wrap the complete if expression: Windows PowerShell 5.1 unwraps a one-element array
    # emitted inside an if branch, which would make PSCustomObject.Count null.
    [object[]]$admissionChangedEntries = @(if ($admissionBaseCommit) {
        Get-Cf7RawChangedEntries -BaseCommit $admissionBaseCommit -HeadCommit $headCommit
    })
    $admissionBaseProtection = if ($admissionBaseCommit) {
        Get-Cf7FastPathProtection -BaseCommit $admissionBaseCommit
    } else { $null }
    $headProtection = Get-Cf7FastPathProtection -BaseCommit $headCommit
    Assert-Cf7NativeChangesReleaseBound -Entries $admissionChangedEntries `
        -BaseProtection $admissionBaseProtection -HeadProtection $headProtection

    # A protected non-native change inherits deployment consensus only from the external
    # green-check anchor. Event base remains separate for strict deployment/migration semantics.
    # The formal policy domain can accumulate content/tooling changes;
    # it is rebound by the next native promotion, not used as a direct-push admission list.
    # With an external anchor present, an older/missing trusted descriptor falls through to
    # the complete strict chain. Missing anchors and ambiguous/unsafe Git records fail closed.
    if (-not $DisableFastPath -and -not $baseWasAbsent -and $baseCommit -and $trustedBaseCommit) {
        $protection = $admissionBaseProtection
        $baseSentinels = Get-Cf7RequiredBaseSentinels -BaseCommit $trustedBaseCommit
        if ($null -ne $protection -and $null -ne $baseSentinels) {
            $changedEntries = $admissionChangedEntries
            $protectedIntersection = @($changedEntries | Where-Object {
                Test-Cf7ProtectedFastPath -Path ([string]$_.Path) -Protection $protection
            })
            if ($changedEntries.Count -gt 0 -and $protectedIntersection.Count -eq 0) {
                $changedPaths = [string[]]@($changedEntries | ForEach-Object { [string]$_.Path })
                [Array]::Sort($changedPaths, [StringComparer]::Ordinal)
                $changedPathBytes = [Text.Encoding]::UTF8.GetBytes(([string]::Join("`n", $changedPaths) + "`n"))
                $changedPathsSha256 = Get-Cf7BytesSha256 -Bytes $changedPathBytes
                $entryLines = [string[]]@($changedEntries | ForEach-Object {
                    "$($_.Status)`t$($_.OldMode)`t$($_.NewMode)`t$($_.OldOid)`t$($_.NewOid)`t$($_.Path)"
                })
                [Array]::Sort($entryLines, [StringComparer]::Ordinal)
                $changedEntriesSha256 = Get-Cf7BytesSha256 -Bytes ([Text.Encoding]::UTF8.GetBytes(([string]::Join("`n", $entryLines) + "`n")))
                $protectedLines = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
                foreach ($fixedPath in @($protection.Fixed.Keys)) { [void]$protectedLines.Add("fixed`t$fixedPath") }
                foreach ($prefix in @($protection.FullPrefixes)) { [void]$protectedLines.Add("prefix`t$prefix") }
                foreach ($extension in @($protection.GlobalExtensions)) { [void]$protectedLines.Add("global-extension`t$(([string]$extension).ToLowerInvariant())") }
                foreach ($basename in @($protection.ProtectedBasenames)) { [void]$protectedLines.Add("basename`t$basename") }
                foreach ($rule in @($protection.TreeRules)) {
                    $extensions = New-Object 'Collections.Generic.List[string]'
                    foreach ($extension in $rule.Extensions) { [void]$extensions.Add(([string]$extension).ToLowerInvariant()) }
                    $extensionArray = [string[]]$extensions.ToArray()
                    [Array]::Sort($extensionArray, [StringComparer]::Ordinal)

                    $excludePaths = [string[]]@($rule.ExcludePaths)
                    [Array]::Sort($excludePaths, [StringComparer]::Ordinal)
                    $excludePrefixes = [string[]]@($rule.ExcludePrefixes)
                    [Array]::Sort($excludePrefixes, [StringComparer]::Ordinal)

                    $ruleKey = "tree`t$($rule.Domain)`t$($rule.Base)"
                    [void]$protectedLines.Add("$ruleKey`tincludeExtensions=$($extensionArray.Count)`texcludePaths=$($excludePaths.Count)`texcludePrefixes=$($excludePrefixes.Count)")
                    foreach ($extension in $extensionArray) { [void]$protectedLines.Add("tree-include-extension`t$($rule.Domain)`t$($rule.Base)`t$extension") }
                    foreach ($excludePath in $excludePaths) { [void]$protectedLines.Add("tree-exclude-path`t$($rule.Domain)`t$($rule.Base)`t$excludePath") }
                    foreach ($excludePrefix in $excludePrefixes) { [void]$protectedLines.Add("tree-exclude-prefix`t$($rule.Domain)`t$($rule.Base)`t$excludePrefix") }
                }
                $protectedArray = [string[]]@($protectedLines)
                [Array]::Sort($protectedArray, [StringComparer]::Ordinal)
                $protectedSetSha256 = Get-Cf7BytesSha256 -Bytes ([Text.Encoding]::UTF8.GetBytes(([string]::Join("`n", $protectedArray) + "`n")))

                $sentinelLines = [string[]]@($baseSentinels.Keys | ForEach-Object { "$_`t$($baseSentinels[$_])" })
                [Array]::Sort($sentinelLines, [StringComparer]::Ordinal)
                $baseSentinelsSha256 = Get-Cf7BytesSha256 -Bytes ([Text.Encoding]::UTF8.GetBytes(([string]::Join("`n", $sentinelLines) + "`n")))
                Write-Host "[RuntimeReleaseState] OK state=protected-nonnative-fastpath mode=Protected consensus=inherited-from-trusted-base changedCount=$($changedPaths.Count) changedPathsSha256=$changedPathsSha256 changedEntriesSha256=$changedEntriesSha256 protectedSetCount=$($protectedArray.Count) protectedSetSha256=$protectedSetSha256 descriptorBlobOid=$($protection.DescriptorOid) nativeGateBlobOid=$($protection.GateBlobOid) baseSentinelCount=$($sentinelLines.Count) baseSentinelsSha256=$baseSentinelsSha256 baseManifestBlobOid=$($baseSentinels['runtime/cf7-runtime-manifest.tsv']) baseConsensusBlobOid=$($baseSentinels['config/build/runtime-release-consensus.json']) eventBase=$baseCommit trustedBase=$trustedBaseCommit head=$headCommit" -ForegroundColor Green
                exit 0
            }
        }
    }

    $manifestPath = 'runtime/cf7-runtime-manifest.tsv'
    $migrationMarkerPath = 'config/build/runtime-v2-migration-bootstrap.json'
    $builderRegistryPath = 'config/build/runtime-builders.v2.json'
    $consensusRecordPath = 'config/build/runtime-release-consensus.json'
    $headHeader = Get-Cf7ManifestHeader (Get-Cf7IndexedText $manifestPath)
    $baseHeader = $null
    if ($baseCommit) {
        $baseHeader = Get-Cf7ManifestHeader (Get-Cf7RevisionText -Revision $baseCommit -RelativePath $manifestPath -Optional) -Optional
    }

    $script:PowerShellExecutable = Get-Cf7PowerShellExecutable
    $toolsRoot = Join-Path $ProjectRoot 'tools'
    $bundleVerifier = if ($headHeader -eq 'cf7-runtime-manifest-v2') {
        Join-Path $toolsRoot 'verify-runtime-bundle-v2.ps1'
    } else {
        Join-Path $toolsRoot 'verify-runtime-bundle.ps1'
    }
    $commonArguments = @('-ProjectRoot', $ProjectRoot, '-Staged')

    # Byte closure is non-negotiable in every state, including source-ahead.
    $integrity = Invoke-Cf7Verifier -Label 'runtime byte-integrity verification' -Path $bundleVerifier `
        -Arguments ($commonArguments + @('-IntegrityOnly'))
    Assert-Cf7Passed $integrity

    if ($baseHeader -eq 'cf7-runtime-manifest-v2' -and $headHeader -eq 'cf7-runtime-manifest-v1') {
        throw 'Runtime manifest downgrade from v2 to v1 is forbidden.'
    }

    $baseMarkerBlob = if ($baseCommit) { Get-Cf7RevisionBlobOid -Revision $baseCommit -RelativePath $migrationMarkerPath -Optional } else { $null }
    $headMarkerBlob = Get-Cf7RevisionBlobOid -Revision ':' -RelativePath $migrationMarkerPath -Optional
    if ($baseMarkerBlob) {
        if (-not $headMarkerBlob) { throw 'The permanent runtime v2 migration fuse marker cannot be removed.' }
        if ($baseMarkerBlob -cne $headMarkerBlob) { throw 'The permanent runtime v2 migration fuse marker cannot be modified after bootstrap.' }
        if ($headHeader -ne 'cf7-runtime-manifest-v2') {
            throw 'The one-time runtime v2 migration bootstrap has already been consumed; the next protected state requires a complete v2 promotion.'
        }
    }
    $isMigrationBootstrap = -not $baseMarkerBlob -and [bool]$headMarkerBlob

    $deploymentChanged = $true
    $changedDeploymentPaths = @()
    if ($baseCommit) {
        $pathspecs = @(
            'CRAZYFLASHER7MercenaryEmpire.exe',
            'runtime',
            $consensusRecordPath,
            $builderRegistryPath
        )
        $changedDeploymentPaths = @(& git -C $ProjectRoot diff --name-only --no-renames $baseCommit $headCommit -- @pathspecs)
        if ($LASTEXITCODE -ne 0) { throw 'Cannot compare runtime deployment paths between base and head.' }
        $changedDeploymentPaths = @($changedDeploymentPaths | Where-Object { $_ -ne '' } | Sort-Object -Unique)
        $deploymentChanged = $changedDeploymentPaths.Count -gt 0
    }

    $consensusVerifier = Join-Path $toolsRoot 'verify-runtime-consensus.ps1'
    if ($isMigrationBootstrap) {
        if ($Mode -ne 'Protected') { throw 'The one-time runtime v2 migration bootstrap is allowed only against a protected ref.' }
        if ($baseWasAbsent -or -not $baseCommit) { throw 'Migration bootstrap requires an explicit, non-zero base revision.' }
        if ($baseHeader -ne 'cf7-runtime-manifest-v1' -or $headHeader -ne 'cf7-runtime-manifest-v1') {
            throw 'Migration bootstrap must preserve the legacy v1 manifest until the separately attested v2 promotion.'
        }
        & git -C $ProjectRoot merge-base --is-ancestor $baseCommit $headCommit *> $null
        if ($LASTEXITCODE -ne 0) { throw 'Migration marker base must be an ancestor of the classified head.' }

        $markerStatus = @(& git -C $ProjectRoot diff --name-status --no-renames $baseCommit $headCommit -- $migrationMarkerPath)
        if ($LASTEXITCODE -ne 0 -or $markerStatus.Count -ne 1 -or [string]$markerStatus[0] -cne "A`t$migrationMarkerPath") {
            throw 'Migration marker must be added exactly once between the classified base and head.'
        }
        $legacyDeploymentChanges = @(& git -C $ProjectRoot diff --name-only --no-renames $baseCommit $headCommit -- `
            'CRAZYFLASHER7MercenaryEmpire.exe' 'runtime' $consensusRecordPath)
        if ($LASTEXITCODE -ne 0) { throw 'Cannot compare legacy deployment bytes for migration bootstrap.' }
        $legacyDeploymentChanges = @($legacyDeploymentChanges | Where-Object { $_ -ne '' })
        if ($legacyDeploymentChanges.Count -gt 0) {
            throw "Migration bootstrap cannot alter legacy deployment bytes: $($legacyDeploymentChanges -join ',')"
        }
        $registryStatus = @(& git -C $ProjectRoot diff --name-status --no-renames $baseCommit $headCommit -- $builderRegistryPath)
        if ($LASTEXITCODE -ne 0 -or $registryStatus.Count -ne 1 -or [string]$registryStatus[0] -notmatch "^[AM]`t$([regex]::Escape($builderRegistryPath))$") {
            throw 'Migration bootstrap must add or modify exactly the marker-bound v2 builder registry.'
        }

        $markerBytes = Get-Cf7GitBlobBytes -ObjectSpec ":$migrationMarkerPath"
        $marker = Read-Cf7MigrationMarker -Bytes $markerBytes
        if ([string]$marker.baseCommitOid -cne $baseCommit) { throw 'Migration marker does not bind the exact classified base commit.' }
        $consensusBytes = Get-Cf7GitBlobBytes -ObjectSpec ":$consensusRecordPath"
        try { $legacyConsensus = [Text.Encoding]::UTF8.GetString($consensusBytes).TrimStart([char]0xFEFF) | ConvertFrom-Json }
        catch { throw "Legacy consensus record is invalid JSON: $($_.Exception.Message)" }
        if ([string]$legacyConsensus.schema -cne 'cf7-runtime-release-consensus.v1' -or
                [string]$legacyConsensus.artifactClosureHash -cnotmatch '^[0-9A-F]{64}$') {
            throw 'Migration bootstrap requires a valid v1 legacy consensus record.'
        }
        if ([string]$marker.legacyArtifactClosureHash -cne [string]$legacyConsensus.artifactClosureHash) {
            throw 'Migration marker does not bind the legacy consensus artifact closure.'
        }
        $registryBytes = Get-Cf7GitBlobBytes -ObjectSpec ":$builderRegistryPath"
        $registryHash = Assert-Cf7BootstrapBuilderRegistry -RegistryBytes $registryBytes -ExpectedSha256 ([string]$marker.targetBuilderRegistrySha256)
        $consensusIntegrity = Invoke-Cf7Verifier -Label 'legacy runtime consensus integrity verification' -Path $consensusVerifier `
            -Arguments ($commonArguments + @('-IntegrityOnly'))
        Assert-Cf7Passed $consensusIntegrity
        Write-Host "[RuntimeReleaseState] OK state=migration-bootstrap mode=$Mode manifest=$headHeader deploymentChanged=true base=$baseCommit head=$headCommit registrySha256=$registryHash" -ForegroundColor Yellow
        exit 0
    }

    if ($Mode -eq 'Protected' -and $baseCommit -and $deploymentChanged -and $headHeader -ne 'cf7-runtime-manifest-v2') {
        throw "Protected v1 deployment changes require the exact one-time migration bootstrap or a complete v2 promotion: $($changedDeploymentPaths -join ',')"
    }

    if ($Mode -eq 'Development' -and -not $deploymentChanged) {
        # Exit 2 is the verifier's explicit identity-mismatch result. Infrastructure failures remain fatal.
        $strict = Invoke-Cf7Verifier -Label 'runtime strict identity verification' -Path $bundleVerifier `
            -Arguments $commonArguments -EchoOutput $false
        if ($strict.ExitCode -eq 0) {
            foreach ($line in $strict.Output) { Write-Host $line }
            Write-Host "[RuntimeReleaseState] OK state=coherent mode=$Mode manifest=$headHeader deploymentChanged=false base=$baseCommit head=$headCommit" -ForegroundColor Green
            exit 0
        }
        if ($strict.ExitCode -ne 2) {
            foreach ($line in $strict.Output) { Write-Host $line }
            throw "Runtime strict identity verifier failed unexpectedly with exit code $($strict.ExitCode)."
        }
        Write-Host "[RuntimeReleaseState] OK state=source-ahead mode=$Mode manifest=$headHeader deploymentChanged=false base=$baseCommit head=$headCommit" -ForegroundColor Yellow
        exit 0
    }

    if ($Mode -eq 'Development' -and $deploymentChanged -and $headHeader -ne 'cf7-runtime-manifest-v2') {
        $detail = if ($baseCommit) { $changedDeploymentPaths -join ',' } else { "no comparable base ($baseOrigin)" }
        throw "Development deployment changes require a complete v2 promotion; manifest=$headHeader changes=$detail"
    }

    $strict = Invoke-Cf7Verifier -Label 'runtime strict identity verification' -Path $bundleVerifier -Arguments $commonArguments
    Assert-Cf7Passed $strict
    $consensus = Invoke-Cf7Verifier -Label 'runtime release consensus verification' -Path $consensusVerifier -Arguments $commonArguments
    Assert-Cf7Passed $consensus

    $state = if ($Mode -eq 'Protected') { 'protected-coherent' } else { 'promoted' }
    Write-Host "[RuntimeReleaseState] OK state=$state mode=$Mode manifest=$headHeader deploymentChanged=$($deploymentChanged.ToString().ToLowerInvariant()) base=$(if ($baseCommit) {$baseCommit} else {'none'}) head=$headCommit" -ForegroundColor Green
    exit 0
} catch {
    Write-Cf7Failure $_.Exception.Message
    exit 2
}
