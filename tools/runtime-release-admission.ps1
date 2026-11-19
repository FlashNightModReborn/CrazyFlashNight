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
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($psi)
    $memory = New-Object IO.MemoryStream
    try {
        $stderr = $process.StandardError.ReadToEndAsync()
        $process.StandardOutput.BaseStream.CopyTo($memory)
        $errorText = $stderr.GetAwaiter().GetResult()
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
    for ($index = 0; $index -lt $path.Length; $index++) {
        $character = $path[$index]
        $codeUnit = [int]$character
        if ($codeUnit -lt 32) { throw "$Label contains a control character." }
        if ([char]::IsHighSurrogate($character)) {
            if ($index + 1 -ge $path.Length -or -not [char]::IsLowSurrogate($path[$index + 1])) {
                throw "$Label contains an unpaired Unicode surrogate."
            }
            $scalar = [char]::ConvertToUtf32($character, $path[$index + 1])
            $index++
        } elseif ([char]::IsLowSurrogate($character)) {
            throw "$Label contains an unpaired Unicode surrogate."
        } else {
            $scalar = $codeUnit
        }
        if (($scalar -ge 0xFDD0 -and $scalar -le 0xFDEF) -or (($scalar -band 0xFFFF) -ge 0xFFFE)) {
            throw "$Label contains a Unicode noncharacter."
        }
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

# Use immutable Git objects for source identity. All verifier code is loaded from
# the reviewed checkout. The temporary index also isolates historical payload reads.
function Invoke-Cf7RuntimeRevisionIndex {
    param([string]$ProjectRoot, [string]$CommitOid, [scriptblock]$Action)
    if ($CommitOid -cnotmatch '\A(?:[a-f0-9]{40}|[a-f0-9]{64})\z') { throw 'Expected a full source commit OID.' }
    $previous = $env:GIT_INDEX_FILE
    $indexPath = Join-Path ([IO.Path]::GetTempPath()) ('cf7-release-' + [guid]::NewGuid().ToString('N') + '.index')
    try {
        $env:GIT_INDEX_FILE = $indexPath
        & git -C $ProjectRoot -c core.splitIndex=false read-tree --no-sparse-checkout "$CommitOid^{commit}"
        if ($LASTEXITCODE -ne 0) { throw "Cannot read committed tree at $CommitOid." }
        & $Action
    } finally {
        $env:GIT_INDEX_FILE = $previous
        foreach ($ownedPath in @($indexPath, "$indexPath.lock")) {
            if ([IO.File]::Exists($ownedPath)) { [IO.File]::Delete($ownedPath) }
        }
    }
}

function Get-Cf7RuntimeFrozenIdentity {
    param([string]$ProjectRoot, [string]$SourceCommitOid)
    Invoke-Cf7RuntimeRevisionIndex $ProjectRoot $SourceCommitOid {
        Get-Cf7RuntimeBuildIdentityV2 -ProjectRoot $ProjectRoot -Mode Index
    }
}

function Get-Cf7RuntimeFrozenBlobBytes {
    param(
        [string]$ProjectRoot, [string]$SourceCommitOid,
        [ValidateSet('config/build/runtime-inputs.v2.json','config/build/runtime-github-builder.v2.json',
            'config/build/runtime-builders.v2.json','config/build/runtime-release-consensus.json','tools/asloader-modules.json')][string]$RelativePath
    )
    if ($SourceCommitOid -cnotmatch '\A(?:[a-f0-9]{40}|[a-f0-9]{64})\z') { throw 'Expected a full Git object ID.' }
    return ,(Invoke-Cf7GitBinary @('cat-file','blob',"$($SourceCommitOid):$RelativePath"))
}

function Get-Cf7ReleaseGitOid([string]$ProjectRoot, [string]$Revision) {
    $result = @(& git -C $ProjectRoot rev-parse --verify --end-of-options $Revision)
    if ($LASTEXITCODE -ne 0 -or $result.Count -ne 1 -or $result[0] -cnotmatch '\A(?:[a-f0-9]{40}|[a-f0-9]{64})\z') {
        throw "Cannot resolve release object $Revision."
    }
    return [string]$result[0]
}

function Resolve-Cf7RuntimeRecordSource {
    param([string]$ProjectRoot, $Record)
    if ($Record.schema -cne 'cf7-runtime-release-consensus.v2' -or $Record.releaseTreeOid -cnotmatch '\A(?:[a-f0-9]{40}|[a-f0-9]{64})\z') {
        throw 'Cannot identify the frozen v2 release tree.'
    }
    $cloud = @($Record.attestations | Where-Object { $_.schema -ceq 'cf7-runtime-github-build-attestation.v2' })
    $source = [string]$Record.sourceCommitOid
    if ($Record.PSObject.Properties['sourceCommitOid'] -and $source -cnotmatch '\A(?:[a-f0-9]{40}|[a-f0-9]{64})\z') {
        throw 'Invalid consensus sourceCommitOid.'
    }
    if ($cloud.Count -gt 1) { throw 'Ambiguous hosted release source.' }
    if ($cloud.Count -eq 1) {
        $hosted = [string]$cloud[0].payload.sourceCommitOid
        if ($hosted -cnotmatch '\A(?:[a-f0-9]{40}|[a-f0-9]{64})\z' -or ($source -and $hosted -cne $source)) {
            throw 'Consensus and hosted proof disagree on the source commit.'
        }
        $source = $hosted
    }
    # Resolve the exact protected tag using the config from the recorded tree.
    # For old, two-X509 records this is the only unambiguous history anchor.
    $bytes = Get-Cf7RuntimeFrozenBlobBytes $ProjectRoot $Record.releaseTreeOid 'config/build/runtime-github-builder.v2.json'
    $config = [Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xFEFF) | ConvertFrom-Json
    if (-not $source) {
        if ([string]$config.sourceRef -cnotmatch '^refs/tags/runtime-build-v2/[A-Za-z0-9][A-Za-z0-9._-]*$') {
            throw 'Legacy release source cannot be uniquely resolved from its frozen tag.'
        }
        $source = Get-Cf7ReleaseGitOid $ProjectRoot "$($config.sourceRef)^{commit}"
    }
    $tag = Resolve-Cf7RuntimeGitHubSourceRef -Config $config -SourceCommitOid $source
    if ((Get-Cf7ReleaseGitOid $ProjectRoot "$tag^{commit}") -cne $source -or
        (Get-Cf7ReleaseGitOid $ProjectRoot "$source^{tree}") -cne $Record.releaseTreeOid) {
        throw 'Protected tag, source commit and frozen tree disagree.'
    }
    return $source
}

function Test-Cf7RuntimeDeploymentPath([string]$Path) {
    return $Path -ceq 'CRAZYFLASHER7MercenaryEmpire.exe' -or
        $Path -ceq 'config/build/runtime-release-consensus.json' -or
        $Path.StartsWith('runtime/', [StringComparison]::Ordinal)
}

function Assert-Cf7RuntimeReleaseAdmission {
    param([string]$ProjectRoot, [string]$SourceCommitOid, [string]$ReleaseTreeOid,
        [string]$HeadCommitOid, [switch]$AllowVerifiedDeploymentChanges)
    foreach ($oid in @($SourceCommitOid,$ReleaseTreeOid,$HeadCommitOid)) {
        if ($oid -cnotmatch '\A(?:[a-f0-9]{40}|[a-f0-9]{64})\z') { throw 'Admission requires full immutable Git object IDs.' }
    }
    if ((Get-Cf7ReleaseGitOid $ProjectRoot "$SourceCommitOid^{tree}") -cne $ReleaseTreeOid) {
        throw 'Candidate source tree differs from the frozen request.'
    }
    & git -C $ProjectRoot merge-base --is-ancestor $SourceCommitOid $HeadCommitOid
    if ($LASTEXITCODE -ne 0) { throw 'Candidate source is outside the publication parent history.' }
    if ($SourceCommitOid -ceq $HeadCommitOid) { return }
    $compiledClasses = $null
    foreach ($entry in @(Get-Cf7RawChangedEntries $SourceCommitOid $HeadCommitOid)) {
        if ($AllowVerifiedDeploymentChanges -and (Test-Cf7RuntimeDeploymentPath $entry.Path)) { continue }
        # These human-readable retrospective reports are never loaded by the runtime.
        # New application data, control files and unknown consumers require a new source.
        if ($entry.Path -cmatch '^docs/reports/[^/]+\.md$') { continue }
        # Flash loads the built module SWFs. A change to the text of an existing
        # owned combat class alone has no standard-entry bytes to deploy.
        if ($entry.Status -ceq 'M' -and $entry.Path -cmatch '^scripts/类定义/(org/flashNight/arki/bullet/[A-Za-z0-9_/]+)\.as$') {
            $className = $Matches[1].Replace('/','.')
            if ($null -eq $compiledClasses) {
                $bytes = Get-Cf7RuntimeFrozenBlobBytes $ProjectRoot $SourceCommitOid 'tools/asloader-modules.json'
                $modules = [Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xFEFF) | ConvertFrom-Json
                if ($modules.schema -cne 'cf7-asloader-modules.v1') { throw 'Unknown AS2 build ownership descriptor.' }
                $compiledClasses = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
                foreach ($lane in @('resident','shared','logic')) {
                    foreach ($name in @($modules.$lane.classes)) { if ($name) { [void]$compiledClasses.Add($name) } }
                }
            }
            if ($compiledClasses.Contains($className)) { continue }
        }
        throw "Candidate compatibility has not been established for $($entry.Path) at $HeadCommitOid."
    }
}

function Assert-Cf7RuntimeReleaseSuccessor {
    param([string]$ProjectRoot, $PreviousRecord, [string]$SourceCommitOid,
        [string]$BuildIdentityHash, [string]$PayloadClosureHash)
    $previous = Resolve-Cf7RuntimeRecordSource -ProjectRoot $ProjectRoot -Record $PreviousRecord
    if ($SourceCommitOid -cnotmatch '\A(?:[a-f0-9]{40}|[a-f0-9]{64})\z') { throw 'Invalid successor source commit.' }
    & git -C $ProjectRoot merge-base --is-ancestor $previous $SourceCommitOid
    if ($LASTEXITCODE -ne 0) { throw "Candidate source precedes or diverges from deployed source $previous." }
    if ($BuildIdentityHash -ceq $PreviousRecord.buildIdentityHash -and $PayloadClosureHash -cne $PreviousRecord.payloadClosureHash) {
        throw 'The deployed build identity has a different payload closure.'
    }
    if ($previous -ceq $SourceCommitOid -and
        ($BuildIdentityHash -cne $PreviousRecord.buildIdentityHash -or $PayloadClosureHash -cne $PreviousRecord.payloadClosureHash)) {
        throw 'The same source already has a different deployed build identity or payload closure.'
    }
}
