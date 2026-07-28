[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\..'))
$ClosurePath = Join-Path $PSScriptRoot 'closure.json'
$ChainPath = Join-Path $PSScriptRoot 'source-binary-chain.json'
$ExpectedRevision = 'b0-01a-r3'
$ExpectedDigest = '6f4bf9f36563c1bd16993c7472c4ebf49321852ab19eebb0bdf6b58df9264368'
$ExpectedAnchor = '9845dd9084f7b285dbbf1ed603dad7b201a6a324'
$XflRoot = 'flashswf/UI/玩家信息界面'
$DocumentPath = "$XflRoot/DOMDocument.xml"
$XflProxyPath = "$XflRoot/玩家信息界面.xfl"
$PlayerInfoSymbol = '玩家信息界面'
$HpRoot = 'sprite/主角hp显示界面'
$MpRoot = 'sprite/主角mp显示界面'

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if (-not $Condition) {
        throw "B0-01A verification failed: $Message"
    }
}

function Quote-ProcessArgument {
    param([Parameter(Mandatory = $true)][string]$Value)
    if ($Value -notmatch '[\s"]') {
        return $Value
    }
    return '"' + $Value.Replace('"', '\"') + '"'
}

function Invoke-GitBytes {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = 'git.exe'
    $startInfo.WorkingDirectory = $RepoRoot
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.Arguments = (($Arguments | ForEach-Object { Quote-ProcessArgument $_ }) -join ' ')

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    [void]$process.Start()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $output = New-Object System.IO.MemoryStream
    try {
        $process.StandardOutput.BaseStream.CopyTo($output)
        $process.WaitForExit()
        $stderr = $stderrTask.Result
        if ($process.ExitCode -ne 0) {
            throw "git $($Arguments -join ' ') failed with exit $($process.ExitCode): $stderr"
        }
        return $output.ToArray()
    }
    finally {
        $output.Dispose()
        $process.Dispose()
    }
}

function Invoke-GitText {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    return ([System.Text.Encoding]::UTF8.GetString(
        (Invoke-GitBytes -Arguments $Arguments)
    )).Trim()
}

function Get-GitBlobBytes {
    param(
        [Parameter(Mandatory = $true)][string]$Revision,
        [Parameter(Mandatory = $true)][string]$Path
    )
    return Invoke-GitBytes -Arguments @('cat-file', 'blob', "${Revision}:$Path")
}

function Get-GitBlobOid {
    param(
        [Parameter(Mandatory = $true)][string]$Revision,
        [Parameter(Mandatory = $true)][string]$Path
    )
    return Invoke-GitText -Arguments @('rev-parse', "${Revision}:$Path")
}

function Get-IndexBlobOid {
    param([Parameter(Mandatory = $true)][string]$Path)
    return Invoke-GitText -Arguments @('rev-parse', ":$Path")
}

function Get-CleanFilteredWorktreeOid {
    param([Parameter(Mandatory = $true)][string]$Path)
    return Invoke-GitText -Arguments @('hash-object', "--path=$Path", $Path)
}

function Get-Sha256Hex {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Read-WorktreeXml {
    param([Parameter(Mandatory = $true)][string]$Path)
    return [xml](Get-Content -LiteralPath (Join-Path $RepoRoot $Path) -Raw -Encoding UTF8)
}

function Convert-BytesToXml {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)
    $stream = New-Object System.IO.MemoryStream(, $Bytes)
    $reader = New-Object System.IO.StreamReader(
        $stream,
        (New-Object System.Text.UTF8Encoding($false, $true)),
        $true
    )
    try {
        return [xml]$reader.ReadToEnd()
    }
    finally {
        $reader.Dispose()
        $stream.Dispose()
    }
}

function Get-OptionalProperty {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        $Default = $null
    )
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $Default
    }
    return $property.Value
}

function Assert-StringSetEqual {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Actual,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Expected,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $actualSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    $expectedSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($value in @($Actual)) {
        Assert-True ($null -ne $value) "$Label actual set contains null"
        [void]$actualSet.Add([string]$value)
    }
    foreach ($value in @($Expected)) {
        Assert-True ($null -ne $value) "$Label expected set contains null"
        [void]$expectedSet.Add([string]$value)
    }
    Assert-True ($actualSet.Count -eq @($Actual).Count) "$Label actual set contains duplicates"
    Assert-True ($expectedSet.Count -eq @($Expected).Count) "$Label expected set contains duplicates"
    Assert-True ($actualSet.SetEquals($expectedSet)) (
        "$Label differs; actual=[$(($actualSet | Sort-Object) -join ', ')]; " +
        "expected=[$(($expectedSet | Sort-Object) -join ', ')]"
    )
}

function Get-LibraryMap {
    $map = @{}
    $libraryRoot = Join-Path $RepoRoot "$XflRoot/LIBRARY"
    foreach ($file in Get-ChildItem -LiteralPath $libraryRoot -Recurse -Filter '*.xml' -File) {
        $document = [xml](Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8)
        if ($document.DocumentElement.LocalName -ne 'DOMSymbolItem') {
            continue
        }
        $name = $document.DocumentElement.GetAttribute('name')
        Assert-True (-not [string]::IsNullOrWhiteSpace($name)) "unnamed library symbol: $($file.FullName)"
        Assert-True (-not $map.ContainsKey($name)) "duplicate library symbol name: $name"
        $relativePath = $file.FullName.Substring($RepoRoot.Length + 1).Replace('\', '/')
        $map[$name] = [pscustomobject]@{
            Name = $name
            Path = $relativePath
            Document = $document
        }
    }
    return $map
}

function Get-RecursiveSymbols {
    param(
        [Parameter(Mandatory = $true)][string]$RootName,
        [Parameter(Mandatory = $true)][hashtable]$LibraryMap
    )
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    $queue = New-Object 'System.Collections.Generic.Queue[string]'
    $queue.Enqueue($RootName)
    while ($queue.Count -gt 0) {
        $name = $queue.Dequeue()
        if (-not $seen.Add($name)) {
            continue
        }
        Assert-True ($LibraryMap.ContainsKey($name)) "unresolved library reference: $name"
        foreach ($instance in @($LibraryMap[$name].Document.SelectNodes(
            '//*[local-name()="DOMSymbolInstance"]'
        ))) {
            $target = $instance.GetAttribute('libraryItemName')
            Assert-True (-not [string]::IsNullOrWhiteSpace($target)) "empty DOMSymbolInstance target in $name"
            if (-not $seen.Contains($target)) {
                $queue.Enqueue($target)
            }
        }
    }
    return @($seen)
}

function Get-AncestorNode {
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlNode]$Node,
        [Parameter(Mandatory = $true)][string]$LocalName
    )
    $current = $Node.ParentNode
    while ($null -ne $current -and $current.LocalName -ne $LocalName) {
        $current = $current.ParentNode
    }
    Assert-True ($null -ne $current) "missing $LocalName ancestor for $($Node.OuterXml)"
    return $current
}

function Get-DoubleAttribute {
    param(
        [System.Xml.XmlNode]$Node,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][double]$Default
    )
    if ($null -eq $Node -or -not $Node.HasAttribute($Name)) {
        return $Default
    }
    return [double]::Parse(
        $Node.GetAttribute($Name),
        [System.Globalization.CultureInfo]::InvariantCulture
    )
}

function Get-BoolAttribute {
    param(
        [System.Xml.XmlNode]$Node,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][bool]$Default
    )
    if ($null -eq $Node -or -not $Node.HasAttribute($Name)) {
        return $Default
    }
    return [string]::Equals($Node.GetAttribute($Name), 'true', [System.StringComparison]::OrdinalIgnoreCase)
}

function New-PlacementFact {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][System.Xml.XmlNode]$Instance
    )
    $frame = Get-AncestorNode -Node $Instance -LocalName 'DOMFrame'
    $layer = Get-AncestorNode -Node $Instance -LocalName 'DOMLayer'
    $matrix = $Instance.SelectSingleNode('./*[local-name()="matrix"]/*[local-name()="Matrix"]')
    $point = $Instance.SelectSingleNode(
        './*[local-name()="transformationPoint"]/*[local-name()="Point"]'
    )
    $frameIndex = [int]$frame.GetAttribute('index')
    $duration = if ($frame.HasAttribute('duration')) { [int]$frame.GetAttribute('duration') } else { 1 }
    $instanceName = if ($Instance.HasAttribute('name')) { $Instance.GetAttribute('name') } else { $null }
    $symbolType = if ($Instance.HasAttribute('symbolType')) { $Instance.GetAttribute('symbolType') } else { $null }
    $loop = if ($Instance.HasAttribute('loop')) { $Instance.GetAttribute('loop') } else { $null }
    $blendMode = if ($Instance.HasAttribute('blendMode')) { $Instance.GetAttribute('blendMode') } else { $null }
    $filterSignatures = New-Object 'System.Collections.Generic.List[string]'
    foreach ($filter in @($Instance.SelectNodes('./*[local-name()="filters"]/*'))) {
        $attributes = @(
            $filter.Attributes |
                Sort-Object Name |
                ForEach-Object { "$($_.Name)=$($_.Value)" }
        )
        $filterSignatures.Add("$($filter.LocalName)|$($attributes -join ';')")
    }
    return [pscustomobject]@{
        Source = $Source
        Layer = $layer.GetAttribute('name')
        FrameIndex = $frameIndex
        Duration = $duration
        Target = $Instance.GetAttribute('libraryItemName')
        InstanceName = $instanceName
        Matrix = @(
            (Get-DoubleAttribute $matrix 'a' 1),
            (Get-DoubleAttribute $matrix 'b' 0),
            (Get-DoubleAttribute $matrix 'c' 0),
            (Get-DoubleAttribute $matrix 'd' 1),
            (Get-DoubleAttribute $matrix 'tx' 0),
            (Get-DoubleAttribute $matrix 'ty' 0)
        )
        TransformationPoint = @(
            (Get-DoubleAttribute $point 'x' 0),
            (Get-DoubleAttribute $point 'y' 0)
        )
        CenterPoint3D = @(
            (Get-DoubleAttribute $Instance 'centerPoint3DX' 0),
            (Get-DoubleAttribute $Instance 'centerPoint3DY' 0)
        )
        FilterSignatures = @($filterSignatures)
        Visible = Get-BoolAttribute $Instance 'isVisible' $true
        SymbolType = $symbolType
        Loop = $loop
        BlendMode = $blendMode
        ExportAsBitmap = Get-BoolAttribute $Instance 'exportAsBitmap' $false
        Node = $Instance
    }
}

function Get-PlacementKey {
    param([Parameter(Mandatory = $true)]$Fact)
    $instanceName = if ($null -eq $Fact.InstanceName) { '<null>' } else { [string]$Fact.InstanceName }
    return @(
        [string]$Fact.Source,
        [string]$Fact.Layer,
        [string]$Fact.FrameIndex,
        [string]$Fact.Duration,
        [string]$Fact.Target,
        $instanceName
    ) -join ([char]0x1f)
}

function Assert-NumberArrayEqual {
    param(
        [Parameter(Mandatory = $true)][object[]]$Actual,
        [Parameter(Mandatory = $true)][object[]]$Expected,
        [Parameter(Mandatory = $true)][string]$Label
    )
    Assert-True ($Actual.Count -eq $Expected.Count) "$Label length mismatch"
    for ($index = 0; $index -lt $Actual.Count; $index++) {
        $delta = [math]::Abs(([double]$Actual[$index]) - ([double]$Expected[$index]))
        Assert-True ($delta -le 0.000000000001) "$Label[$index] mismatch: $($Actual[$index]) != $($Expected[$index])"
    }
}

function Get-TimelineStats {
    param([Parameter(Mandatory = $true)][xml]$Document)
    $frames = @($Document.SelectNodes('//*[local-name()="DOMFrame"]'))
    $maxIndex = -1
    $span = 0
    foreach ($frame in $frames) {
        $index = [int]$frame.GetAttribute('index')
        $duration = if ($frame.HasAttribute('duration')) { [int]$frame.GetAttribute('duration') } else { 1 }
        $maxIndex = [math]::Max($maxIndex, $index)
        $span = [math]::Max($span, $index + $duration)
    }
    return [pscustomobject]@{
        DomFrameCount = $frames.Count
        DomMaxFrameIndex = $maxIndex
        TimelineSpan = $span
        DomShapeCount = @($Document.SelectNodes('//*[local-name()="DOMShape"]')).Count
        DomSymbolInstanceCount = @($Document.SelectNodes('//*[local-name()="DOMSymbolInstance"]')).Count
        ShapeTweenFrameCount = @($frames | Where-Object { $_.GetAttribute('tweenType') -eq 'shape' }).Count
        MotionTweenFrameCount = @($frames | Where-Object { $_.GetAttribute('tweenType') -eq 'motion' }).Count
        ShapeTweenFrameIndices = @(
            $frames |
                Where-Object { $_.GetAttribute('tweenType') -eq 'shape' } |
                ForEach-Object { [int]$_.GetAttribute('index') }
        )
    }
}

function Assert-GitIdentity {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Expected,
        [Parameter(Mandatory = $true)][string]$Anchor
    )
    $headOid = Get-GitBlobOid 'HEAD' $Path
    $indexOid = Get-IndexBlobOid $Path
    $filteredOid = Get-CleanFilteredWorktreeOid $Path
    $anchorOid = Get-GitBlobOid $Anchor $Path
    Assert-True ($headOid -eq $Expected.gitBlobOid) "HEAD blob OID mismatch: $Path"
    Assert-True ($indexOid -eq $headOid) "index blob does not match HEAD: $Path"
    Assert-True ($filteredOid -eq $headOid) "clean-filtered worktree does not bind to HEAD: $Path"
    Assert-True ($anchorOid -eq $Expected.gitBlobOid) "anchor blob OID mismatch: $Path"
    $bytes = Get-GitBlobBytes 'HEAD' $Path
    Assert-True ($bytes.Length -eq [int64]$Expected.gitBlobBytes) "canonical blob length mismatch: $Path"
    Assert-True ((Get-Sha256Hex $bytes) -eq $Expected.gitBlobSha256) "canonical blob SHA-256 mismatch: $Path"
    return $Expected.gitBlobSha256
}

function Assert-CanonicalSourceLink {
    param(
        [Parameter(Mandatory = $true)]$Entry,
        [Parameter(Mandatory = $true)][string]$Anchor
    )
    $headBytes = Get-GitBlobBytes 'HEAD' $Entry.path
    $anchorBytes = Get-GitBlobBytes $Anchor $Entry.path
    $headOid = Get-GitBlobOid 'HEAD' $Entry.path
    $indexOid = Get-IndexBlobOid $Entry.path
    $anchorOid = Get-GitBlobOid $Anchor $Entry.path
    $filteredOid = Get-CleanFilteredWorktreeOid $Entry.path
    $headExpectedSha = [string]$Entry.reviewBaseline.gitBlobSha256
    $anchorExpectedSha = [string]$Entry.sourceBinaryAnchor.gitBlobSha256
    Assert-True ($headOid -eq $Entry.reviewBaseline.gitBlobOid) "source-link HEAD OID mismatch: $($Entry.path)"
    Assert-True ($indexOid -eq $headOid) "source-link index mismatch: $($Entry.path)"
    Assert-True ($filteredOid -eq $headOid) "source-link worktree binding mismatch: $($Entry.path)"
    Assert-True ($anchorOid -eq $Entry.sourceBinaryAnchor.gitBlobOid) "source-link anchor OID mismatch: $($Entry.path)"
    Assert-True ((Get-Sha256Hex $headBytes) -eq $headExpectedSha) "source-link HEAD SHA mismatch: $($Entry.path)"
    Assert-True ((Get-Sha256Hex $anchorBytes) -eq $anchorExpectedSha) "source-link anchor SHA mismatch: $($Entry.path)"
    Assert-True ([bool]$Entry.identical -eq ($headOid -eq $anchorOid)) (
        "source-link identical conclusion mismatch: $($Entry.path)"
    )
}

Push-Location $RepoRoot
try {
    Assert-True (Test-Path -LiteralPath $ClosurePath -PathType Leaf) 'closure.json missing'
    Assert-True (Test-Path -LiteralPath $ChainPath -PathType Leaf) 'source-binary-chain.json missing'
    $closure = Get-Content -LiteralPath $ClosurePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $chain = Get-Content -LiteralPath $ChainPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($closure.evidenceRevision -eq $ExpectedRevision) 'closure evidence revision mismatch'
    Assert-True ($chain.evidenceRevision -eq $ExpectedRevision) 'chain evidence revision mismatch'
    Assert-True ($closure.status -eq 'placement_closure_frozen') 'closure status mismatch'
    Assert-True (-not [bool]$closure.assertions.oracleFrozen) 'closure must not claim oracle_frozen'
    Assert-True (-not [bool]$chain.conclusions.oracleFrozen) 'chain must not claim oracle_frozen'
    foreach ($assertionName in @(
        'all16FilesExist',
        'all16WorktreeFilesNormalizeToReviewBaselineGitBlobs',
        'all16IndexBlobsMatchReviewBaselineGitBlobs',
        'all16GitBlobsEqualSourceBinaryAnchorCommit',
        'wholeXflTreeEqualsSourceBinaryAnchorCommit',
        'allReferencedHpMpSymbolsResolved',
        'includedClosureBitmapFillCountIsZero',
        'scriptReachableStoppedDescendantsRetained',
        'placementClosureFrozen'
    )) {
        Assert-True ([bool]$closure.assertions.$assertionName) (
            "declared closure assertion must be true: $assertionName"
        )
    }

    # Regenerate the graph from authored XFL content. Evidence paths do not seed this traversal.
    $libraryMap = Get-LibraryMap
    $document = Read-WorktreeXml $DocumentPath
    Assert-True ($document.DocumentElement.LocalName -eq 'DOMDocument') 'document root is not DOMDocument'
    Assert-True ([int]$document.DocumentElement.GetAttribute('width') -eq 1024) 'document width mismatch'
    Assert-True ([int]$document.DocumentElement.GetAttribute('height') -eq 64) 'document height mismatch'
    Assert-True ([int]$document.DocumentElement.GetAttribute('frameRate') -eq 30) 'document frameRate mismatch'
    & git.exe diff --cached --quiet --exit-code HEAD -- $XflRoot
    $xflIndexDiffExit = $LASTEXITCODE
    Assert-True ($xflIndexDiffExit -eq 0) 'player-info XFL root has staged index drift from HEAD'

    $stageRoots = @($document.SelectNodes(
        '//*[local-name()="DOMSymbolInstance" and @libraryItemName="玩家信息界面"]'
    ))
    Assert-True ($stageRoots.Count -eq 1) "expected one placed 玩家信息界面 stage root, got $($stageRoots.Count)"
    Assert-True ($libraryMap.ContainsKey($PlayerInfoSymbol)) '玩家信息界面 library symbol missing'
    $playerInfoDocument = $libraryMap[$PlayerInfoSymbol].Document
    $hpPlacements = @($playerInfoDocument.SelectNodes(
        '//*[local-name()="DOMSymbolInstance" and @libraryItemName="sprite/主角hp显示界面"]'
    ))
    $mpPlacements = @($playerInfoDocument.SelectNodes(
        '//*[local-name()="DOMSymbolInstance" and @libraryItemName="sprite/主角mp显示界面"]'
    ))
    Assert-True ($hpPlacements.Count -eq 1) "expected one placed HP root, got $($hpPlacements.Count)"
    Assert-True ($mpPlacements.Count -eq 1) "expected one placed MP root, got $($mpPlacements.Count)"
    $anchorTargets = @(
        $playerInfoDocument.SelectNodes('//*[local-name()="DOMSymbolInstance"]') |
            ForEach-Object { $_.GetAttribute('libraryItemName') }
    )
    $excludedAnchorTargets = @($anchorTargets | Where-Object { $_ -ne $HpRoot -and $_ -ne $MpRoot })
    Assert-StringSetEqual $excludedAnchorTargets @($closure.excludedSiblingEdgesAtPlayerInfoAnchor) (
        'excluded sibling edges at 玩家信息界面'
    )

    $hpSymbols = @(Get-RecursiveSymbols -RootName $HpRoot -LibraryMap $libraryMap)
    $mpSymbols = @(Get-RecursiveSymbols -RootName $MpRoot -LibraryMap $libraryMap)
    $union = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($symbol in @($hpSymbols) + @($mpSymbols)) {
        [void]$union.Add($symbol)
    }
    $shared = @($hpSymbols | Where-Object { $mpSymbols -contains $_ })
    Assert-True ($hpSymbols.Count -eq 10) "regenerated HP symbol count is $($hpSymbols.Count), expected 10"
    Assert-True ($mpSymbols.Count -eq 5) "regenerated MP symbol count is $($mpSymbols.Count), expected 5"
    Assert-True ($shared.Count -eq 2) "regenerated shared symbol count is $($shared.Count), expected 2"
    Assert-StringSetEqual $hpSymbols @($closure.symbolSets.hp) 'HP symbol set'
    Assert-StringSetEqual $mpSymbols @($closure.symbolSets.mp) 'MP symbol set'
    Assert-StringSetEqual $shared @($closure.symbolSets.shared) 'shared symbol set'

    $regeneratedFiles = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    [void]$regeneratedFiles.Add($DocumentPath)
    [void]$regeneratedFiles.Add($XflProxyPath)
    [void]$regeneratedFiles.Add($libraryMap[$PlayerInfoSymbol].Path)
    foreach ($symbol in $union) {
        [void]$regeneratedFiles.Add($libraryMap[$symbol].Path)
    }
    Assert-True ($regeneratedFiles.Count -eq 16) "regenerated file count is $($regeneratedFiles.Count), expected 16"
    Assert-StringSetEqual @($regeneratedFiles) @($closure.files.path) 'closure file set'
    Assert-True (
        (Get-Content -LiteralPath (Join-Path $RepoRoot $XflProxyPath) -Raw -Encoding UTF8).Trim() -eq 'PROXY-CS5'
    ) 'XFL proxy marker mismatch'

    $fileEvidence = @{}
    foreach ($entry in @($closure.files)) {
        Assert-True (-not $fileEvidence.ContainsKey($entry.path)) "duplicate file evidence: $($entry.path)"
        $fileEvidence[$entry.path] = $entry
    }
    $digestRows = New-Object 'System.Collections.Generic.List[object]'
    $rawDiagnosticDrift = 0
    foreach ($path in $regeneratedFiles) {
        $canonicalSha = Assert-GitIdentity -Path $path -Expected $fileEvidence[$path] -Anchor $ExpectedAnchor
        $rawBytes = [System.IO.File]::ReadAllBytes((Join-Path $RepoRoot $path))
        $rawSha = Get-Sha256Hex $rawBytes
        $expectedRawBytes = Get-OptionalProperty $fileEvidence[$path] 'rawWorktreeBytes'
        $expectedRawSha = Get-OptionalProperty $fileEvidence[$path] 'rawWorktreeSha256'
        if ($null -ne $expectedRawBytes -or $null -ne $expectedRawSha) {
            Assert-True ($null -ne $expectedRawBytes -and $null -ne $expectedRawSha) (
                "partial raw worktree diagnostic: $path"
            )
            if ($rawBytes.Length -ne [int64]$expectedRawBytes -or $rawSha -ne $expectedRawSha) {
                $rawDiagnosticDrift++
            }
        }
        $sortKey = ([System.BitConverter]::ToString(
            [System.Text.Encoding]::UTF8.GetBytes($path)
        )).Replace('-', '')
        $digestRows.Add([pscustomobject]@{
            Path = $path
            Sha = $canonicalSha
            SortKey = $sortKey
        })
    }
    $digestText = New-Object System.Text.StringBuilder
    foreach ($row in @($digestRows | Sort-Object SortKey)) {
        [void]$digestText.Append($row.Path)
        [void]$digestText.Append("`t")
        [void]$digestText.Append($row.Sha.ToLowerInvariant())
        [void]$digestText.Append("`n")
    }
    $actualDigest = Get-Sha256Hex ([System.Text.Encoding]::UTF8.GetBytes($digestText.ToString()))
    Assert-True ($actualDigest -eq $ExpectedDigest) "canonical closure digest mismatch: $actualDigest"
    Assert-True ($closure.closureDigest.value -eq $ExpectedDigest) 'declared closure digest mismatch'

    # Regenerate all 17 selected placement facts and compare facts/matrices to JSON.
    $actualPlacements = New-Object 'System.Collections.Generic.List[object]'
    $actualPlacements.Add((New-PlacementFact -Source '_stage' -Instance $stageRoots[0]))
    $actualPlacements.Add((New-PlacementFact -Source $PlayerInfoSymbol -Instance $hpPlacements[0]))
    $actualPlacements.Add((New-PlacementFact -Source $PlayerInfoSymbol -Instance $mpPlacements[0]))
    foreach ($symbol in $union) {
        foreach ($instance in @($libraryMap[$symbol].Document.SelectNodes(
            '//*[local-name()="DOMSymbolInstance"]'
        ))) {
            $actualPlacements.Add((New-PlacementFact -Source $symbol -Instance $instance))
        }
    }
    Assert-True ($actualPlacements.Count -eq 17) "regenerated placement count is $($actualPlacements.Count), expected 17"
    Assert-True (@($closure.placements).Count -eq 17) 'evidence placement count is not 17'
    $hpBranchEdges = 1 + @($actualPlacements | Where-Object {
        $hpSymbols -contains $_.Source
    }).Count
    $mpBranchEdges = 1 + @($actualPlacements | Where-Object {
        $mpSymbols -contains $_.Source
    }).Count
    $pathExpandedRuntimeEdges = 1 + $hpBranchEdges + $mpBranchEdges
    Assert-True ($hpBranchEdges -eq 12) "HP path-expanded branch edge count is $hpBranchEdges"
    Assert-True ($mpBranchEdges -eq 5) "MP path-expanded branch edge count is $mpBranchEdges"
    Assert-True ($pathExpandedRuntimeEdges -eq 18) (
        "path-expanded runtime edge count is $pathExpandedRuntimeEdges"
    )
    $cardinality = $closure.scope.placementCardinality
    Assert-True ([int]$cardinality.authoredDefinitionEdges -eq 17) (
        'declared authored definition edge count mismatch'
    )
    Assert-True ([int]$cardinality.pathExpandedRuntimeEdges -eq 18) (
        'declared path-expanded runtime edge count mismatch'
    )
    Assert-True ([int]$cardinality.stageEdges -eq 1) 'declared stage edge count mismatch'
    Assert-True ([int]$cardinality.hpBranchEdges -eq $hpBranchEdges) (
        'declared HP branch edge count mismatch'
    )
    Assert-True ([int]$cardinality.mpBranchEdges -eq $mpBranchEdges) (
        'declared MP branch edge count mismatch'
    )
    Assert-True ([int]$cardinality.sharedDefinitionEdgesExpandedTwice -eq 1) (
        'declared shared-edge expansion count mismatch'
    )
    $evidencePlacements = @{}
    foreach ($entry in @($closure.placements)) {
        $entryFact = [pscustomobject]@{
            Source = $entry.source
            Layer = $entry.layer
            FrameIndex = $entry.frameIndex
            Duration = $entry.duration
            Target = $entry.target
            InstanceName = $entry.instanceName
        }
        $key = Get-PlacementKey $entryFact
        Assert-True (-not $evidencePlacements.ContainsKey($key)) "duplicate evidence placement key: $key"
        $evidencePlacements[$key] = $entry
    }
    foreach ($fact in $actualPlacements) {
        $key = Get-PlacementKey $fact
        Assert-True ($evidencePlacements.ContainsKey($key)) "missing evidence placement: $key"
        $expected = $evidencePlacements[$key]
        $expectedScope = if ($fact.Source -eq '_stage') {
            @('hp', 'mp')
        }
        elseif ($fact.Source -eq $PlayerInfoSymbol -and $fact.Target -eq $HpRoot) {
            @('hp')
        }
        elseif ($fact.Source -eq $PlayerInfoSymbol -and $fact.Target -eq $MpRoot) {
            @('mp')
        }
        else {
            @(
                if ($hpSymbols -contains $fact.Source) { 'hp' }
                if ($mpSymbols -contains $fact.Source) { 'mp' }
            )
        }
        Assert-True (@($expectedScope).Count -gt 0) "placement has no regenerated scope: $key"
        Assert-StringSetEqual @($expected.scope) @($expectedScope) "scope $($expected.id)"
        Assert-NumberArrayEqual @($fact.Matrix) @($expected.matrix) "matrix $($expected.id)"
        Assert-NumberArrayEqual @($fact.TransformationPoint) @($expected.transformationPoint) (
            "transformationPoint $($expected.id)"
        )
        Assert-NumberArrayEqual @($fact.CenterPoint3D) @($expected.centerPoint3D) (
            "centerPoint3D $($expected.id)"
        )
        Assert-StringSetEqual @($fact.FilterSignatures) @($expected.xflFilterSignatures) (
            "filter signatures $($expected.id)"
        )
        Assert-True ($fact.Visible -eq [bool]$expected.visible) "visible mismatch: $($expected.id)"
        Assert-True ($fact.SymbolType -eq (Get-OptionalProperty $expected 'symbolType')) (
            "symbolType mismatch: $($expected.id)"
        )
        Assert-True ($fact.Loop -eq (Get-OptionalProperty $expected 'loop')) "loop mismatch: $($expected.id)"
        Assert-True ($fact.BlendMode -eq (Get-OptionalProperty $expected 'blendMode')) (
            "blendMode mismatch: $($expected.id)"
        )
        Assert-True ($fact.ExportAsBitmap -eq [bool](Get-OptionalProperty $expected 'exportAsBitmap' $false)) (
            "exportAsBitmap mismatch: $($expected.id)"
        )
    }
    $hpLoadScript = @(@($hpPlacements[0].SelectNodes(
        './*[local-name()="Actionscript"]/*[local-name()="script"]'
    )) | ForEach-Object { $_.InnerText })
    $mpLoadScript = @(@($mpPlacements[0].SelectNodes(
        './*[local-name()="Actionscript"]/*[local-name()="script"]'
    )) | ForEach-Object { $_.InnerText })
    Assert-True ($hpLoadScript.Count -eq 1) 'HP root load action count mismatch'
    Assert-True ($mpLoadScript.Count -eq 1) 'MP root load action count mismatch'
    Assert-True ($hpLoadScript[0].Contains('this.刷新显示 = _root.UI系统.血条刷新显示;')) (
        'HP root load binding mismatch'
    )
    Assert-True ($mpLoadScript[0].Contains('this.刷新显示 = _root.UI系统.蓝条刷新显示;')) (
        'MP root load binding mismatch'
    )
    Assert-True ($hpLoadScript[0].Contains('stop();')) 'HP root load action does not stop'
    Assert-True ($mpLoadScript[0].Contains('stop();')) 'MP root load action does not stop'
    Assert-True (
        ($closure.placements | Where-Object { $_.id -eq 'p01-hp-root' }).loadBinding -eq
            '_root.UI系统.血条刷新显示'
    ) 'declared HP load binding mismatch'
    Assert-True (
        ($closure.placements | Where-Object { $_.id -eq 'p02-mp-root' }).loadBinding -eq
            '_root.UI系统.蓝条刷新显示'
    ) 'declared MP load binding mismatch'

    # Timeline facts are regenerated from every selected symbol, not trusted as an inventory.
    $expectedTimelineSymbols = @($union) + @($PlayerInfoSymbol)
    Assert-True ($expectedTimelineSymbols.Count -eq 14) 'regenerated timeline inventory is not 14'
    Assert-True (@($closure.timelineFacts).Count -eq 14) 'evidence timeline inventory is not 14'
    $timelineEvidence = @{}
    foreach ($entry in @($closure.timelineFacts)) {
        Assert-True (-not $timelineEvidence.ContainsKey($entry.symbol)) "duplicate timeline fact: $($entry.symbol)"
        $timelineEvidence[$entry.symbol] = $entry
    }
    Assert-StringSetEqual $expectedTimelineSymbols @($closure.timelineFacts.symbol) 'timeline symbol inventory'
    foreach ($symbol in $expectedTimelineSymbols) {
        $documentForSymbol = $libraryMap[$symbol].Document
        $stats = Get-TimelineStats $documentForSymbol
        $expected = $timelineEvidence[$symbol]
        Assert-True ($stats.DomFrameCount -eq [int]$expected.domFrameCount) "DOMFrame count mismatch: $symbol"
        Assert-True ($stats.DomMaxFrameIndex -eq [int]$expected.domMaxFrameIndex) "max frame mismatch: $symbol"
        Assert-True ($stats.TimelineSpan -eq [int]$expected.timelineSpan) "timeline span mismatch: $symbol"
        Assert-True ($stats.DomShapeCount -eq [int]$expected.domShapeCount) "DOMShape count mismatch: $symbol"
        Assert-True (
            $stats.DomSymbolInstanceCount -eq [int]$expected.domSymbolInstanceCount
        ) "DOMSymbolInstance count mismatch: $symbol"
        $shapeTweenExpected = Get-OptionalProperty $expected 'shapeTweenFrameCount'
        if ($null -ne $shapeTweenExpected) {
            Assert-True ($stats.ShapeTweenFrameCount -eq [int]$shapeTweenExpected) (
                "shape tween count mismatch: $symbol"
            )
        }
        $shapeTweenFrameIndices = Get-OptionalProperty $expected 'shapeTweenFrameIndices'
        if ($null -ne $shapeTweenFrameIndices) {
            Assert-NumberArrayEqual @($stats.ShapeTweenFrameIndices) @($shapeTweenFrameIndices) (
                "shape tween frame indices: $symbol"
            )
        }
        $motionTweenExpected = Get-OptionalProperty $expected 'motionTweenFrameCount'
        if ($null -ne $motionTweenExpected) {
            Assert-True ($stats.MotionTweenFrameCount -eq [int]$motionTweenExpected) (
                "motion tween count mismatch: $symbol"
            )
        }
    }

    $closureBitmapFillCount = 0
    $closureDomBitmapInstanceCount = 0
    foreach ($path in $regeneratedFiles) {
        if ($path.EndsWith('.xml', [System.StringComparison]::OrdinalIgnoreCase)) {
            $selectedDocument = Read-WorktreeXml $path
            $closureBitmapFillCount += @($selectedDocument.SelectNodes(
                '//*[local-name()="BitmapFill"]'
            )).Count
            $closureDomBitmapInstanceCount += @($selectedDocument.SelectNodes(
                '//*[local-name()="DOMBitmapInstance"]'
            )).Count
        }
    }
    Assert-True ($closureBitmapFillCount -eq 0) "regenerated closure BitmapFill count is $closureBitmapFillCount"
    Assert-True ($closureDomBitmapInstanceCount -eq 0) (
        "regenerated closure DOMBitmapInstance count is $closureDomBitmapInstanceCount"
    )
    Assert-True (
        [int]$closure.bitmapBoundary.includedClosureBitmapFillCount -eq $closureBitmapFillCount
    ) 'declared closure BitmapFill count mismatch'
    Assert-True (
        [int]$closure.bitmapBoundary.includedClosureDomBitmapInstanceCount -eq
            $closureDomBitmapInstanceCount
    ) 'declared closure DOMBitmapInstance count mismatch'
    Assert-True (
        -not [bool]$closure.bitmapBoundary.documentBitmapItemsReferencedBySelectedHpMpGraph
    ) 'document bitmap items must remain outside the selected HP/MP graph'

    # Independently regenerate the excluded sibling boundary.
    $siblingRoot = 'sprite/玩家必要信息界面'
    $siblingSymbols = @(Get-RecursiveSymbols -RootName $siblingRoot -LibraryMap $libraryMap)
    $siblingBitmapFillCount = 0
    $siblingBitmapPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($symbol in $siblingSymbols) {
        foreach ($fill in @($libraryMap[$symbol].Document.SelectNodes('//*[local-name()="BitmapFill"]'))) {
            $siblingBitmapFillCount++
            [void]$siblingBitmapPaths.Add($fill.GetAttribute('bitmapPath'))
        }
    }
    Assert-True ($siblingSymbols.Count -eq 13) "sibling closure symbol count is $($siblingSymbols.Count)"
    Assert-True ($siblingBitmapFillCount -eq 4) "sibling closure BitmapFill count is $siblingBitmapFillCount"
    Assert-StringSetEqual @($siblingBitmapPaths) @('image/bitmap1804.png', 'image/bitmap1805.png') (
        'sibling bitmap paths'
    )
    Assert-True (
        [int]$closure.bitmapBoundary.excludedPlacedSibling.closureSymbolCountIncludingRoot -eq
            $siblingSymbols.Count
    ) 'declared sibling symbol count mismatch'
    Assert-True (
        [int]$closure.bitmapBoundary.excludedPlacedSibling.bitmapFillCount -eq $siblingBitmapFillCount
    ) 'declared sibling BitmapFill count mismatch'
    $illustration = $libraryMap['玩家信息界面示意图'].Document
    Assert-True (
        @($illustration.SelectNodes('//*[local-name()="BitmapFill"]')).Count -eq 2
    ) 'unused illustration BitmapFill count mismatch'

    # Verify the actual source scripts and their Git anchors.
    $displayEnginePath = 'scripts/展现/视觉系统/视觉系统_fs_显示列表引擎.as'
    $displayEngineText = Get-Content -LiteralPath (Join-Path $RepoRoot $displayEnginePath) -Raw -Encoding UTF8
    foreach ($runtimePath in @(
        '_root.玩家信息界面.主角hp显示界面.血槽内动画',
        '_root.玩家信息界面.主角hp显示界面.网格动画',
        '_root.玩家信息界面.主角hp显示界面.血槽光效'
    )) {
        Assert-True ($displayEngineText.Contains("默认播放动画($runtimePath);")) (
            "missing display-engine reachability edge: $runtimePath"
        )
    }
    $formulaPath = 'scripts/展现/UI交互/UI交互_fs_玩家信息界面.as'
    $formulaText = Get-Content -LiteralPath (Join-Path $RepoRoot $formulaPath) -Raw -Encoding UTF8
    foreach ($snippet in @(
        '_root.UI系统.血条刷新显示 = function()',
        'var 血条格数 = 128;',
        '_root.UI系统.蓝条刷新显示 = function()',
        'var 蓝条格数 = 100;'
    )) {
        Assert-True ($formulaText.Contains($snippet)) "missing player-info formula anchor: $snippet"
    }
    $sharedAction = @($libraryMap['sprite/Symbol 1785'].Document.SelectNodes(
        '//*[local-name()="Actionscript"]/*[local-name()="script"]'
    )) | ForEach-Object { $_.InnerText.Trim() }
    Assert-True ($sharedAction -contains '_parent.刷新显示();') 'shared refresh marker action missing'
    foreach ($stoppedSymbol in @(
        'UI重构/血槽相关/血槽光效',
        'UI重构/血槽相关/血槽内动画',
        'UI重构/血槽相关/血槽内动画-网格背景'
    )) {
        $actions = @($libraryMap[$stoppedSymbol].Document.SelectNodes(
            '//*[local-name()="Actionscript"]/*[local-name()="script"]'
        )) | ForEach-Object { $_.InnerText.Trim() }
        Assert-True ($actions -contains 'stop();') "first-frame stop anchor missing: $stoppedSymbol"
    }

    # Source-link entries are verified from canonical HEAD/anchor blobs.
    foreach ($entry in @($chain.sourceLinkEvidence)) {
        Assert-CanonicalSourceLink -Entry $entry -Anchor $ExpectedAnchor
    }
    $frame41Text = Get-Content -LiteralPath (Join-Path $RepoRoot 'scripts/asLoaderManifest/frame41.as') -Raw -Encoding UTF8
    $frame42Text = Get-Content -LiteralPath (Join-Path $RepoRoot 'scripts/asLoaderManifest/frame42.as') -Raw -Encoding UTF8
    Assert-True (
        $frame41Text.Contains('#include "../展现/UI交互/UI交互_fs_玩家信息界面.as"')
    ) 'frame41 player-info include missing'
    Assert-True (
        $frame42Text.Contains('#include "../展现/视觉系统/视觉系统_fs_显示列表引擎.as"')
    ) 'frame42 display-engine include missing'

    # Main RSL import and main placement are checked in both HEAD and anchor blobs.
    $mainImportPath = 'CRAZYFLASHER7MercenaryEmpire/LIBRARY/import/UI组件/玩家信息界面.xml'
    foreach ($revision in @('HEAD', $ExpectedAnchor)) {
        $importDocument = Convert-BytesToXml (Get-GitBlobBytes $revision $mainImportPath)
        $importRoot = $importDocument.DocumentElement
        Assert-True ($importRoot.GetAttribute('linkageImportForRS') -eq 'true') (
            "main import linkageImportForRS mismatch at $revision"
        )
        Assert-True ($importRoot.GetAttribute('linkageExportInFirstFrame') -eq 'false') (
            "main import linkageExportInFirstFrame mismatch at $revision"
        )
        Assert-True ($importRoot.GetAttribute('linkageIdentifier') -eq '玩家信息界面') (
            "main import linkageIdentifier mismatch at $revision"
        )
        Assert-True ($importRoot.GetAttribute('linkageURL') -eq 'flashswf/UI/玩家信息界面.swf') (
            "main import linkageURL mismatch at $revision"
        )

        $mainDocument = Convert-BytesToXml (
            Get-GitBlobBytes $revision 'CRAZYFLASHER7MercenaryEmpire/DOMDocument.xml'
        )
        $mainPlacements = @($mainDocument.SelectNodes(
            '//*[local-name()="DOMSymbolInstance" and @libraryItemName="import/UI组件/玩家信息界面"]'
        ))
        Assert-True ($mainPlacements.Count -eq 1) "main placement count mismatch at $revision"
        $mainFact = New-PlacementFact -Source '_main' -Instance $mainPlacements[0]
        $declaredMain = $chain.runtimeRelationship.main.placement
        Assert-True ($mainFact.Layer -eq $declaredMain.layer) "main layer mismatch at $revision"
        Assert-True ($mainFact.FrameIndex -eq [int]$declaredMain.frameIndex) (
            "main frame mismatch at $revision"
        )
        Assert-True ($mainFact.Duration -eq [int]$declaredMain.duration) (
            "main duration mismatch at $revision"
        )
        Assert-True ($mainFact.InstanceName -eq $declaredMain.instanceName) (
            "main instance name mismatch at $revision"
        )
        Assert-NumberArrayEqual @($mainFact.Matrix) @($declaredMain.matrix) "main matrix at $revision"
        Assert-NumberArrayEqual @($mainFact.TransformationPoint) @($declaredMain.transformationPoint) (
            "main transformation point at $revision"
        )
    }

    # Anchor commit metadata and binary identities are regenerated from Git.
    Assert-True ($chain.sourceBinaryAnchorCommit.commit -eq $ExpectedAnchor) 'chain anchor commit mismatch'
    Assert-True (
        $closure.sourceAnchor.reviewBaselineCommit -eq $chain.reviewBaseline.commit
    ) 'closure/chain review baseline commit mismatch'
    $reviewBaselineTree = Invoke-GitText -Arguments @(
        'rev-parse', "$($chain.reviewBaseline.commit)^{tree}"
    )
    $reviewBaselineXflTree = Invoke-GitText -Arguments @(
        'rev-parse', "$($chain.reviewBaseline.commit):$XflRoot"
    )
    Assert-True ($reviewBaselineTree -eq $chain.reviewBaseline.tree) 'review baseline tree mismatch'
    Assert-True ($reviewBaselineXflTree -eq $chain.reviewBaseline.xflTreeOid) (
        'review baseline XFL tree mismatch'
    )
    Assert-True ($reviewBaselineXflTree -eq $closure.sourceAnchor.xflTreeOidAtReviewBaseline) (
        'closure review-baseline XFL tree mismatch'
    )
    $anchorTree = Invoke-GitText -Arguments @('rev-parse', "${ExpectedAnchor}^{tree}")
    $anchorParents = Invoke-GitText -Arguments @('show', '-s', '--format=%P', $ExpectedAnchor)
    $anchorDate = Invoke-GitText -Arguments @('show', '-s', '--format=%cI', $ExpectedAnchor)
    $anchorSubject = Invoke-GitText -Arguments @('show', '-s', '--format=%s', $ExpectedAnchor)
    Assert-True ($anchorTree -eq $chain.sourceBinaryAnchorCommit.tree) 'anchor tree mismatch'
    Assert-True ($anchorParents -eq $chain.sourceBinaryAnchorCommit.parent) 'anchor parent mismatch'
    Assert-True ($anchorDate -eq $chain.sourceBinaryAnchorCommit.commitDate) 'anchor date mismatch'
    Assert-True ($anchorSubject -eq $chain.sourceBinaryAnchorCommit.subject) 'anchor subject mismatch'
    $anchorChangedPaths = @(
        ((Invoke-GitText -Arguments @(
            'diff-tree', '--no-commit-id', '--name-only', '-r', $ExpectedAnchor
        )) -split "`r?`n") | Where-Object { $_ }
    )
    foreach ($path in @(
        'flashswf/UI/玩家信息界面.swf',
        'CRAZYFLASHER7MercenaryEmpire.swf',
        'scripts/asLoader.swf'
    )) {
        Assert-True ($anchorChangedPaths -contains $path) "anchor did not modify expected binary: $path"
    }
    Assert-StringSetEqual @($chain.sourceBinaryAnchorCommit.relevantBinaryPathsModifiedTogetherByCommit) @(
        'flashswf/UI/玩家信息界面.swf',
        'CRAZYFLASHER7MercenaryEmpire.swf',
        'scripts/asLoader.swf'
    ) 'relevant binary paths modified together at anchor'

    $headXflTree = Invoke-GitText -Arguments @('rev-parse', "HEAD:$XflRoot")
    $anchorXflTree = Invoke-GitText -Arguments @('rev-parse', "${ExpectedAnchor}:$XflRoot")
    Assert-True ($headXflTree -eq $anchorXflTree) 'HEAD and anchor player-info XFL trees differ'
    Assert-True ($headXflTree -eq $closure.sourceAnchor.xflTreeOidAtReviewBaseline) (
        'closure review XFL tree mismatch'
    )
    Assert-True ($anchorXflTree -eq $closure.sourceAnchor.xflTreeOidAtSourceBinaryAnchor) (
        'closure anchor XFL tree mismatch'
    )

    $binarySameness = @{}
    foreach ($binary in @($chain.binaries)) {
        $headBytes = Get-GitBlobBytes 'HEAD' $binary.path
        $anchorBytes = Get-GitBlobBytes $ExpectedAnchor $binary.path
        $headOid = Get-GitBlobOid 'HEAD' $binary.path
        $indexOid = Get-IndexBlobOid $binary.path
        $anchorOid = Get-GitBlobOid $ExpectedAnchor $binary.path
        $filteredOid = Get-CleanFilteredWorktreeOid $binary.path
        Assert-True ($headOid -eq $binary.reviewBaseline.gitBlobOid) (
            "binary HEAD OID mismatch: $($binary.path)"
        )
        Assert-True ($indexOid -eq $headOid) "binary index mismatch: $($binary.path)"
        Assert-True ($filteredOid -eq $headOid) "binary worktree binding mismatch: $($binary.path)"
        Assert-True ($anchorOid -eq $binary.sourceBinaryAnchor.gitBlobOid) (
            "binary anchor OID mismatch: $($binary.path)"
        )
        Assert-True ($headBytes.Length -eq [int64]$binary.reviewBaseline.bytes) (
            "binary HEAD length mismatch: $($binary.path)"
        )
        Assert-True ((Get-Sha256Hex $headBytes) -eq $binary.reviewBaseline.sha256) (
            "binary HEAD SHA mismatch: $($binary.path)"
        )
        Assert-True ($anchorBytes.Length -eq [int64]$binary.sourceBinaryAnchor.bytes) (
            "binary anchor length mismatch: $($binary.path)"
        )
        Assert-True ((Get-Sha256Hex $anchorBytes) -eq $binary.sourceBinaryAnchor.sha256) (
            "binary anchor SHA mismatch: $($binary.path)"
        )
        $actualIdentical = $headOid -eq $anchorOid
        Assert-True ([bool]$binary.identical -eq $actualIdentical) (
            "binary identical conclusion mismatch: $($binary.path)"
        )
        Assert-True (-not $binarySameness.ContainsKey([string]$binary.role)) (
            "duplicate binary role: $($binary.role)"
        )
        $binarySameness[[string]$binary.role] = $actualIdentical
    }

    Assert-True ($binarySameness.Count -eq 3) 'binary role inventory mismatch'
    Assert-True ([bool]$binarySameness['child']) 'child must equal source-binary anchor'
    Assert-True (-not [bool]$binarySameness['main']) 'current main must differ from source-binary anchor'
    Assert-True (-not [bool]$binarySameness['asLoader']) (
        'current asLoader must differ from source-binary anchor'
    )
    $conclusions = $chain.conclusions
    Assert-True ([bool]$conclusions.exact16ClosureBlobsEqualAnchor) (
        'closure equality conclusion must be true'
    )
    Assert-True ([bool]$conclusions.wholePlayerInfoXflTreeEqualsAnchor) (
        'whole-XFL equality conclusion must be true'
    )
    Assert-True ([bool]$conclusions.childBlobEqualsAnchor -eq [bool]$binarySameness['child']) (
        'child equality conclusion mismatch'
    )
    Assert-True ([bool]$conclusions.anchorCommitTouchedChildMainAndAsLoader) (
        'anchor relevant-binary conclusion must be true'
    )
    Assert-True ([bool]$conclusions.currentMainEqualsAnchor -eq [bool]$binarySameness['main']) (
        'current-main conclusion mismatch'
    )
    Assert-True (
        [bool]$conclusions.currentAsLoaderEqualsAnchor -eq [bool]$binarySameness['asLoader']
    ) 'current-asLoader conclusion mismatch'
    Assert-True ([bool]$conclusions.repositoryAncestryVerified) (
        'repository ancestry conclusion must be true'
    )
    Assert-True (-not [bool]$conclusions.reproducibleBuildReceiptPresent) (
        'B0-01A must not claim a reproducible Flash build receipt'
    )
    Assert-True (-not [bool]$conclusions.actualCaptureProcessLoadVerified) (
        'B0-01A must not claim actual capture process-load verification'
    )
    Assert-True (-not [bool]$conclusions.oracleFrozen) 'B0-01A must not claim oracle_frozen'
    Assert-True ([string]$conclusions.allowedStatus -eq 'placement_closure_frozen') (
        'allowed status conclusion mismatch'
    )

    $captureLoader = $chain.runtimeRelationship.captureLoaderContract
    Assert-True ([string]$captureLoader.plannedLoaderPath -eq 'scripts/TestLoader.swf') (
        'planned capture loader must be scripts/TestLoader.swf'
    )
    Assert-True (-not [bool]$captureLoader.actualCaptureLoaderVerified) (
        'B0-01A must not claim its planned capture loader was observed'
    )
    Assert-True (-not [bool]$captureLoader.mainParticipatesInCapture) (
        'main must not be represented as a B0-01A capture participant'
    )
    Assert-True (-not [bool]$captureLoader.asLoaderParticipatesInCapture) (
        'asLoader must not be represented as a B0-01A capture participant'
    )
    Assert-True (
        [string]$captureLoader.childPathToVerify -eq 'flashswf/UI/玩家信息界面.swf'
    ) 'capture child path contract mismatch'
    Assert-True (
        [bool]$chain.reviewBaseline.relevantTrackedPathsMatchHeadInIndexAndAfterCleanFilter
    ) 'tracked-path clean binding conclusion must be true'

    Write-Output 'B0-01A verifier OK'
    Write-Output (
        "revision=$ExpectedRevision; files=16; hp=10; mp=5; shared=2; " +
        "placements=17/18; timelines=14; BitmapFill=0; DOMBitmapInstance=0"
    )
    Write-Output "canonicalDigest=$actualDigest; cleanFilterBindings=16/16; anchorBlobMatches=16/16"
    Write-Output (
        "indexBindings=closure16+source6+binaries3; " +
        "sourceBinary=childSame:true,mainSame:false,asLoaderSame:false; " +
        "mainImport=head+anchor; sourceLinks=6/6; scriptSemantics=5/5; " +
        "rawDiagnosticDrift=$rawDiagnosticDrift"
    )
    Write-Output 'status=placement_closure_frozen; oracleFrozen=false'
}
finally {
    Pop-Location
}
