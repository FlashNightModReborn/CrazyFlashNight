function Get-PlayerInfoOracleExpectedCases {
    $rows = @(
        [pscustomobject]@{ caseId = 'empty'; hp = 0; mp = 0 },
        [pscustomobject]@{ caseId = 'min_step'; hp = 100; mp = 100 },
        [pscustomobject]@{ caseId = 'p25'; hp = 3200; mp = 2500 },
        [pscustomobject]@{ caseId = 'p50'; hp = 6400; mp = 5000 },
        [pscustomobject]@{ caseId = 'p75'; hp = 9600; mp = 7500 },
        [pscustomobject]@{ caseId = 'p99'; hp = 12672; mp = 9900 },
        [pscustomobject]@{ caseId = 'full'; hp = 12800; mp = 10000 },
        [pscustomobject]@{ caseId = 'mp_vf34'; hp = 8576; mp = 6700 },
        [pscustomobject]@{ caseId = 'mp_vf35'; hp = 8448; mp = 6600 },
        [pscustomobject]@{ caseId = 'mp_vf70'; hp = 3968; mp = 3100 },
        [pscustomobject]@{ caseId = 'mp_vf91'; hp = 1280; mp = 1000 }
    )
    foreach ($row in $rows) {
        $hpFrame = [Math]::Max(
            1, 129 - [Math]::Floor(([double]$row.hp / 12800) * 128))
        $mpFrame = [Math]::Max(
            1, 101 - [Math]::Floor(([double]$row.mp / 10000) * 100))
        [pscustomobject]@{
            caseId = $row.caseId
            hp = [int]$row.hp
            hpMax = 12800
            hpFrame = [int]$hpFrame
            hpPercent = [string][Math]::Floor(([double]$row.hp / 12800) * 100)
            mp = [int]$row.mp
            mpMax = 10000
            mpFrame = [int]$mpFrame
            mpPercent = (
                [string][Math]::Floor(([double]$row.mp / 10000) * 100) + '%')
            mpCombined = ('{0:D5}/{1:D5}' -f [int]$row.mp, 10000)
            lightPresent = if ($row.caseId -ceq 'empty') { '0' } else { '1' }
        }
    }
}

function Get-PlayerInfoOracleExpectedStateFields {
    param([Parameter(Mandatory = $true)]$Expected)

    return [ordered]@{
        caseId = [string]$Expected.caseId
        quality = 'MEDIUM'
        width = '1024'
        height = '64'
        rowCount = '64'
        partChars = '720'
        partsPerRow = '8'
        partRecordMaxChars = '1000'
        pixelFormat = 'ARGB32'
        childUrlReported = '1'
        hpRaw = [string]$Expected.hp
        hpMax = '12800'
        hpRatioNumerator = [string]$Expected.hp
        hpRatioDenominator = '12800'
        hpTargetFrame = [string]$Expected.hpFrame
        hpCurrentFrame = [string]$Expected.hpFrame
        hpCurrentText = [string]$Expected.hp
        hpMaxText = '12800'
        hpPercentText = [string]$Expected.hpPercent
        hpVisible = '1'
        mpRaw = [string]$Expected.mp
        mpMax = '10000'
        mpRatioNumerator = [string]$Expected.mp
        mpRatioDenominator = '10000'
        mpTargetFrame = [string]$Expected.mpFrame
        mpCurrentFrame = [string]$Expected.mpFrame
        mpCurrentText = [string]$Expected.mp
        mpMaxText = '10000'
        mpPercentText = [string]$Expected.mpPercent
        mpCombinedExists = '0'
        mpCombinedText = ''
        mpVisible = '1'
        gridPresent = '1'
        gridPhase = '1'
        gridVisible = '1'
        innerPresent = '1'
        innerPhase = '1'
        innerVisible = '1'
        lightPresent = [string]$Expected.lightPresent
        lightPhase = if ($Expected.lightPresent -ceq '1') { '1' } else { '0' }
        lightVisible = '0'
        lightHidden = '1'
        outOfScopeHidden = '1'
    }
}

function Get-PlayerInfoOracleTypedState {
    param([Parameter(Mandatory = $true)]$Expected)

    return [ordered]@{
        hpRaw = [int]$Expected.hp
        hpMax = 12800
        hpRatioNumerator = [int]$Expected.hp
        hpRatioDenominator = 12800
        hpTargetFrame = [int]$Expected.hpFrame
        hpCurrentFrame = [int]$Expected.hpFrame
        hpCurrentText = [string]$Expected.hp
        hpMaxText = '12800'
        hpPercentText = [string]$Expected.hpPercent
        mpRaw = [int]$Expected.mp
        mpMax = 10000
        mpRatioNumerator = [int]$Expected.mp
        mpRatioDenominator = 10000
        mpTargetFrame = [int]$Expected.mpFrame
        mpCurrentFrame = [int]$Expected.mpFrame
        mpCurrentText = [string]$Expected.mp
        mpMaxText = '10000'
        mpPercentText = [string]$Expected.mpPercent
        mpCombinedExists = $false
        mpCombinedText = $null
        gridPhase = 1
        innerPhase = 1
        lightPresent = $Expected.lightPresent -ceq '1'
        lightPhase = if ($Expected.lightPresent -ceq '1') { 1 } else { 0 }
        lightHidden = $true
        outOfScopeHidden = $true
    }
}

function Get-PlayerInfoOracleBytesSha256 {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [byte[]]$Bytes
    )

    $hasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString(
            $hasher.ComputeHash($Bytes))).Replace('-', '')
    } finally {
        $hasher.Dispose()
    }
}

function ConvertFrom-Avm1EscapedString {
    param([Parameter(Mandatory = $true)][string]$Value)

    if ($Value -match '[^\x00-\x7F]') {
        throw 'AVM1 escaped protocol value must be ASCII before decoding.'
    }
    $unicodeDecoded = [regex]::Replace(
        $Value,
        '(?i)%u([0-9a-f]{4})',
        [System.Text.RegularExpressions.MatchEvaluator]{
            param($match)
            return [string][char][System.Convert]::ToInt32(
                $match.Groups[1].Value, 16)
        }
    )
    try {
        return [System.Uri]::UnescapeDataString($unicodeDecoded)
    } catch {
        throw "Invalid AVM1 escaped protocol value: $($_.Exception.Message)"
    }
}

function ConvertTo-SyntheticAvm1EscapedString {
    param([Parameter(Mandatory = $true)][string]$Value)

    $safe = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789@*_+-./'
    $builder = [System.Text.StringBuilder]::new()
    foreach ($character in $Value.ToCharArray()) {
        $code = [int]$character
        if ($safe.IndexOf($character) -ge 0) {
            [void]$builder.Append($character)
        } elseif ($code -le 0xFF) {
            [void]$builder.Append('%')
            [void]$builder.Append($code.ToString('X2'))
        } else {
            [void]$builder.Append('%u')
            [void]$builder.Append($code.ToString('X4'))
        }
    }
    return $builder.ToString()
}

function Resolve-PlayerInfoOracleChildBinding {
    param(
        [Parameter(Mandatory = $true)][string]$EscapedUrl,
        [Parameter(Mandatory = $true)][string]$ExpectedChildPath
    )

    $reported = ConvertFrom-Avm1EscapedString -Value $EscapedUrl
    $decoded = $reported
    for ($round = 0; $round -lt 3; $round++) {
        try {
            $next = [System.Uri]::UnescapeDataString($decoded)
        } catch {
            throw "Reported child URL has invalid percent encoding: $($_.Exception.Message)"
        }
        if ($next -ceq $decoded) {
            break
        }
        $decoded = $next
    }
    $decoded = $decoded.Replace('\', '/')
    $decoded = [regex]::Replace(
        $decoded,
        '^(?i)file:///([a-z])\|/',
        'file:///$1:/'
    )

    if (-not $decoded.StartsWith(
            'file:///',
            [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Reported child URL must be an absolute hostless file:/// URI.'
    }
    $uri = $null
    if (-not [System.Uri]::TryCreate(
            $decoded,
            [System.UriKind]::Absolute,
            [ref]$uri) -or
        -not $uri.IsFile -or
        -not [string]::IsNullOrEmpty($uri.Host) -or
        -not [string]::IsNullOrEmpty($uri.Query) -or
        -not [string]::IsNullOrEmpty($uri.Fragment)) {
        throw 'Reported child URL is not an absolute hostless file URI without query/fragment.'
    }

    try {
        $canonicalCandidate = [System.IO.Path]::GetFullPath(
            $uri.LocalPath).TrimEnd('\', '/')
        $canonicalExpected = [System.IO.Path]::GetFullPath(
            $ExpectedChildPath).TrimEnd('\', '/')
    } catch {
        throw "Reported child URL cannot be canonicalized: $($_.Exception.Message)"
    }
    if (-not $canonicalCandidate.Equals(
            $canonicalExpected,
            [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Reported child URL does not resolve to the exact expected child SWF.'
    }
    $escapedBytes = [System.Text.Encoding]::ASCII.GetBytes($EscapedUrl)
    $reportedBytes = [System.Text.Encoding]::UTF8.GetBytes($reported)
    $canonicalBytes = [System.Text.Encoding]::UTF8.GetBytes(
        $canonicalCandidate.ToUpperInvariant())
    return [pscustomobject]@{
        matched = $true
        escapedUrlSha256 = Get-PlayerInfoOracleBytesSha256 -Bytes $escapedBytes
        reportedUrlSha256 = Get-PlayerInfoOracleBytesSha256 -Bytes $reportedBytes
        canonicalPathSha256 = Get-PlayerInfoOracleBytesSha256 -Bytes $canonicalBytes
    }
}

function ConvertFrom-PlayerInfoOracleLine {
    param(
        [Parameter(Mandatory = $true)][string]$Line,
        [Parameter(Mandatory = $true)][int]$LineNumber
    )

    for ($index = 0; $index -lt $Line.Length; $index++) {
        if ([int]$Line[$index] -gt 127) {
            throw "Oracle physical record at line $LineNumber is not ASCII."
        }
    }
    if ($Line.Length -gt 1000) {
        throw ("Oracle physical record at line {0} is {1} characters; " +
            'the hard maximum is 1000.' -f $LineNumber, $Line.Length)
    }
    $parts = $Line.Split('|')
    if ($parts.Count -lt 3 -or
        $parts[0] -cne 'PLAYER_INFO_ORACLE' -or
        [string]::IsNullOrWhiteSpace($parts[1])) {
        throw "Malformed player-info oracle line at fresh line $LineNumber."
    }
    $fields = @{}
    for ($index = 2; $index -lt $parts.Count; $index++) {
        $part = $parts[$index]
        $equals = $part.IndexOf('=')
        if ($equals -le 0) {
            throw "Malformed oracle field at fresh line $LineNumber."
        }
        $key = $part.Substring(0, $equals)
        $value = $part.Substring($equals + 1)
        if ($fields.ContainsKey($key)) {
            throw "Duplicate oracle field '$key' at fresh line $LineNumber."
        }
        $fields[$key] = $value
    }
    if (-not $fields.ContainsKey('runId')) {
        throw "Oracle line has no runId at fresh line $LineNumber."
    }
    return [pscustomobject]@{
        type = $parts[1]
        fields = $fields
        line = $Line
        lineNumber = $LineNumber
    }
}

function Get-PlayerInfoOracleRequiredField {
    param(
        [Parameter(Mandatory = $true)]$Record,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if (-not $Record.fields.ContainsKey($Name)) {
        throw "Oracle $($Record.type) record is missing field '$Name'."
    }
    return [string]$Record.fields[$Name]
}

function Assert-PlayerInfoOracleField {
    param(
        [Parameter(Mandatory = $true)]$Record,
        [Parameter(Mandatory = $true)][string]$Name,
        [AllowEmptyString()]
        [Parameter(Mandatory = $true)][string]$Expected
    )

    $actual = Get-PlayerInfoOracleRequiredField -Record $Record -Name $Name
    if ($actual -cne $Expected) {
        throw ("Oracle field mismatch for {0}/{1}: expected '{2}', got '{3}'." -f
            $Record.type, $Name, $Expected, $actual)
    }
}

function Assert-PlayerInfoOracleExactFields {
    param(
        [Parameter(Mandatory = $true)]$Record,
        [Parameter(Mandatory = $true)][string[]]$Names
    )

    $expected = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal)
    foreach ($name in $Names) {
        if (-not $expected.Add($name)) {
            throw "Duplicate expected-field declaration for '$name'."
        }
    }
    if ($Record.fields.Count -ne $expected.Count) {
        throw ("Oracle {0} field count mismatch: expected {1}, got {2}." -f
            $Record.type, $expected.Count, $Record.fields.Count)
    }
    foreach ($name in $Record.fields.Keys) {
        if (-not $expected.Contains([string]$name)) {
            throw "Oracle $($Record.type) has unknown field '$name'."
        }
    }
}

function Test-PlayerInfoOracleTrace {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$FreshText,
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][string]$ExpectedChildPath
    )

    if ($RunId -notmatch '^[0-9a-f]{32}$') {
        throw 'Requested oracle runId must be exactly 32 lowercase hexadecimal chars.'
    }
    $allLines = [regex]::Split($FreshText, '\r?\n')
    $records = [System.Collections.Generic.List[object]]::new()
    for ($lineIndex = 0; $lineIndex -lt $allLines.Count; $lineIndex++) {
        $line = $allLines[$lineIndex]
        if ($line.StartsWith(
                'PLAYER_INFO_ORACLE|',
                [System.StringComparison]::Ordinal)) {
            $records.Add((ConvertFrom-PlayerInfoOracleLine `
                -Line $line -LineNumber ($lineIndex + 1)))
        }
    }
    $matching = @($records | Where-Object {
        $_.fields['runId'] -ceq $RunId
    })
    $knownTypes = @('START', 'CHILD', 'STATE', 'PART', 'COMPLETE', 'FAILURE')
    foreach ($record in $matching) {
        if ($knownTypes -cnotcontains [string]$record.type) {
            throw "Oracle lifecycle contains unknown record type '$($record.type)'."
        }
    }
    $starts = @($matching | Where-Object { $_.type -ceq 'START' })
    $completes = @($matching | Where-Object { $_.type -ceq 'COMPLETE' })
    $failures = @($matching | Where-Object { $_.type -ceq 'FAILURE' })
    if ($failures.Count -ne 0) {
        throw 'Oracle lifecycle contains a same-runId FAILURE record.'
    }
    if ($starts.Count -ne 1 -or $completes.Count -ne 1) {
        throw ("Oracle lifecycle is not exactly one start/complete: " +
            "starts={0}, completes={1}." -f $starts.Count, $completes.Count)
    }
    $startLine = [int]$starts[0].lineNumber
    $completeLine = [int]$completes[0].lineNumber
    if ($startLine -ge $completeLine) {
        throw 'Oracle complete marker does not follow its start marker.'
    }
    foreach ($record in $matching) {
        if ($record.lineNumber -lt $startLine -or
            $record.lineNumber -gt $completeLine) {
            throw 'Same-runId oracle output exists outside the closed lifecycle block.'
        }
    }
    $foreignInside = @($records | Where-Object {
        $_.lineNumber -ge $startLine -and
        $_.lineNumber -le $completeLine -and
        $_.fields['runId'] -cne $RunId
    })
    if ($foreignInside.Count -ne 0) {
        throw 'A foreign-run oracle record interleaves the physical lifecycle block.'
    }
    $rawBlockText = @(
        $allLines[($startLine - 1)..($completeLine - 1)]
    ) -join "`n"
    if ($rawBlockText -match '\[TEST_FAIL\]' -or
        $rawBlockText -match '(^|[\r\n])\s*\[FAIL\]') {
        throw 'Oracle lifecycle block contains a failure sentinel.'
    }

    $cursor = 0
    $expectRecord = {
        param([string]$Type)
        if ($cursor -ge $matching.Count) {
            throw "Oracle protocol ended before required record type '$Type'."
        }
        $record = $matching[$cursor]
        if ($record.type -cne $Type) {
            throw ("Oracle physical order mismatch at same-run record {0}: " +
                "expected {1}, got {2}." -f $cursor, $Type, $record.type)
        }
        return $record
    }

    $start = & $expectRecord 'START'
    $cursor++
    Assert-PlayerInfoOracleExactFields $start @(
        'runId', 'schema', 'quality', 'stageScaleMode', 'stageAlign',
        'stageWidth', 'stageHeight', 'runtimeUrlEscaped', 'caseCount')
    Assert-PlayerInfoOracleField $start 'schema' 'cf7.player_info.flash_oracle.v1'
    Assert-PlayerInfoOracleField $start 'quality' 'MEDIUM'
    Assert-PlayerInfoOracleField $start 'stageScaleMode' 'noScale'
    Assert-PlayerInfoOracleField $start 'stageAlign' 'LT'
    Assert-PlayerInfoOracleField $start 'stageWidth' '500'
    Assert-PlayerInfoOracleField $start 'stageHeight' '500'
    $runtimeUrl = ConvertFrom-Avm1EscapedString -Value (
        Get-PlayerInfoOracleRequiredField $start 'runtimeUrlEscaped')
    if ($runtimeUrl -cne '../flashswf/UI/玩家信息界面.swf') {
        throw 'Oracle START runtime URL is not the fixed child-relative URL.'
    }
    Assert-PlayerInfoOracleField $start 'caseCount' '11'

    $child = & $expectRecord 'CHILD'
    $cursor++
    Assert-PlayerInfoOracleExactFields $child @(
        'runId', 'urlReported', 'escapedUrl')
    Assert-PlayerInfoOracleField $child 'urlReported' '1'
    $childBinding = Resolve-PlayerInfoOracleChildBinding `
        -EscapedUrl (Get-PlayerInfoOracleRequiredField $child 'escapedUrl') `
        -ExpectedChildPath $ExpectedChildPath

    $expectedCases = @(Get-PlayerInfoOracleExpectedCases)
    $caseResults = [System.Collections.Generic.List[object]]::new()
    foreach ($expected in $expectedCases) {
        $state = & $expectRecord 'STATE'
        $cursor++
        $expectedFields = Get-PlayerInfoOracleExpectedStateFields -Expected $expected
        Assert-PlayerInfoOracleExactFields $state (
            @('runId') + [string[]]@($expectedFields.Keys))
        foreach ($entry in $expectedFields.GetEnumerator()) {
            Assert-PlayerInfoOracleField $state $entry.Key ([string]$entry.Value)
        }

        $argb = [byte[]]::new(1024 * 64 * 4)
        for ($row = 0; $row -lt 64; $row++) {
            $encodedBuilder = [System.Text.StringBuilder]::new(5464)
            for ($part = 0; $part -lt 8; $part++) {
                $record = & $expectRecord 'PART'
                $cursor++
                Assert-PlayerInfoOracleExactFields $record @(
                    'runId', 'caseId', 'row', 'part', 'partCount', 'b64')
                Assert-PlayerInfoOracleField $record 'caseId' $expected.caseId
                Assert-PlayerInfoOracleField $record 'row' ([string]$row)
                Assert-PlayerInfoOracleField $record 'part' ([string]$part)
                Assert-PlayerInfoOracleField $record 'partCount' '8'
                $payload = Get-PlayerInfoOracleRequiredField $record 'b64'
                $expectedLength = if ($part -lt 7) { 720 } else { 424 }
                if ($payload.Length -ne $expectedLength -or
                    $payload -notmatch '^[A-Za-z0-9+/=]+$') {
                    throw ("Oracle PART payload shape mismatch for {0}, row {1}, " +
                        "part {2}." -f $expected.caseId, $row, $part)
                }
                [void]$encodedBuilder.Append($payload)
            }
            $encodedRow = $encodedBuilder.ToString()
            if ($encodedRow.Length -ne 5464) {
                throw "Oracle base64 row length mismatch for $($expected.caseId), row $row."
            }
            try {
                $decodedRow = [System.Convert]::FromBase64String($encodedRow)
            } catch {
                throw ("Oracle base64 row is invalid for {0}, row {1}: {2}" -f
                    $expected.caseId, $row, $_.Exception.Message)
            }
            if ($decodedRow.Length -ne 4096) {
                throw ("Oracle row {0}/{1} decoded to {2} bytes, expected 4096." -f
                    $expected.caseId, $row, $decodedRow.Length)
            }
            $canonicalEncodedRow = [System.Convert]::ToBase64String($decodedRow)
            if (-not $canonicalEncodedRow.Equals(
                    $encodedRow,
                    [System.StringComparison]::Ordinal)) {
                throw ("Oracle base64 row is not canonical for {0}, row {1}." -f
                    $expected.caseId, $row)
            }
            [System.Buffer]::BlockCopy(
                $decodedRow, 0, $argb, $row * 4096, 4096)
        }
        $hasVisiblePixel = $false
        for ($offset = 0; $offset -lt $argb.Length; $offset += 4) {
            if ($argb[$offset] -ne 0) {
                $hasVisiblePixel = $true
                break
            }
        }
        if (-not $hasVisiblePixel) {
            throw "Oracle case '$($expected.caseId)' contains no non-transparent pixel."
        }
        $caseResults.Add([pscustomobject]@{
            expected = $expected
            protocolState = $expectedFields
            state = Get-PlayerInfoOracleTypedState -Expected $expected
            argb = $argb
        })
    }

    $complete = & $expectRecord 'COMPLETE'
    $cursor++
    Assert-PlayerInfoOracleExactFields $complete @('runId', 'caseCount')
    Assert-PlayerInfoOracleField $complete 'caseCount' '11'
    if ($cursor -ne $matching.Count) {
        throw 'Same-runId oracle records remain after the exact COMPLETE record.'
    }
    return [pscustomobject]@{
        childBinding = $childBinding
        cases = @($caseResults)
        rawBlockText = $rawBlockText
        startLineNumber = $startLine
        completeLineNumber = $completeLine
        physicalRecordCount = $matching.Count
        runId = $RunId
        runtimeUrlEscaped = Get-PlayerInfoOracleRequiredField `
            $start 'runtimeUrlEscaped'
    }
}

function ConvertTo-PlayerInfoOracleCanonicalFieldValue {
    param(
        [AllowNull()]
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($Value -is [bool]) {
        $text = if ([bool]$Value) { '1' } else { '0' }
    } elseif ($null -eq $Value) {
        $text = ''
    } else {
        $text = [string]$Value
    }
    if ($text -match '[^\x00-\x7F]' -or $text -match '[|=\r\n]') {
        throw "Canonical summary field '$Name' is not a safe ASCII atom."
    }
    return $text
}

function New-PlayerInfoOracleCanonicalSummary {
    param([Parameter(Mandatory = $true)]$Parsed)

    if ([string]$Parsed.runId -notmatch '^[0-9a-f]{32}$' -or
        @($Parsed.cases).Count -ne 11) {
        throw 'Canonical summary input is not one exact eleven-case parsed run.'
    }
    $lines = [System.Collections.Generic.List[string]]::new()
    $appendRecord = {
        param(
            [Parameter(Mandatory = $true)][string]$Type,
            [Parameter(Mandatory = $true)]
            [System.Collections.Specialized.OrderedDictionary]$Fields
        )
        $parts = [System.Collections.Generic.List[string]]::new()
        $parts.Add('PLAYER_INFO_ORACLE_SUMMARY')
        $parts.Add($Type)
        foreach ($entry in $Fields.GetEnumerator()) {
            $key = [string]$entry.Key
            if ($key -notmatch '^[A-Za-z][A-Za-z0-9]*$') {
                throw "Canonical summary field name is invalid: $key"
            }
            $value = ConvertTo-PlayerInfoOracleCanonicalFieldValue `
                -Value $entry.Value -Name $key
            $parts.Add($key + '=' + $value)
        }
        $line = $parts -join '|'
        if ($line.Length -gt 1000 -or $line -match '[^\x00-\x7F]') {
            throw "Canonical summary $Type record is not <=1000 ASCII characters."
        }
        $lines.Add($line)
    }

    & $appendRecord 'START' ([ordered]@{
        runId = [string]$Parsed.runId
        schema = 'cf7.player_info.flash_oracle_summary.v1'
        sourceSchema = 'cf7.player_info.flash_oracle.v1'
        quality = 'MEDIUM'
        stageScaleMode = 'noScale'
        stageAlign = 'LT'
        stageWidth = '500'
        stageHeight = '500'
        runtimeUrlEscaped = [string]$Parsed.runtimeUrlEscaped
        caseCount = '11'
    })
    & $appendRecord 'CHILD' ([ordered]@{
        runId = [string]$Parsed.runId
        exactCanonicalMatch = '1'
        escapedUrlSha256 = [string]$Parsed.childBinding.escapedUrlSha256
        reportedUrlSha256 = [string]$Parsed.childBinding.reportedUrlSha256
        canonicalPathSha256 = [string]$Parsed.childBinding.canonicalPathSha256
    })

    $expectedCases = @(Get-PlayerInfoOracleExpectedCases)
    for ($index = 0; $index -lt $expectedCases.Count; $index++) {
        $case = @($Parsed.cases)[$index]
        $expectedFields = Get-PlayerInfoOracleExpectedStateFields `
            -Expected $expectedCases[$index]
        if ($case.protocolState.Count -ne $expectedFields.Count) {
            throw 'Canonical summary received a state outside its exact allowlist.'
        }
        $stateFields = [ordered]@{ runId = [string]$Parsed.runId }
        foreach ($entry in $expectedFields.GetEnumerator()) {
            if (-not $case.protocolState.Contains($entry.Key) -or
                [string]$case.protocolState[$entry.Key] -cne
                [string]$entry.Value) {
                throw ("Canonical summary state drifted at {0}/{1}." -f
                    $expectedCases[$index].caseId, $entry.Key)
            }
            $stateFields[$entry.Key] = [string]$entry.Value
        }
        $stateFields['rawArgbSha256'] =
            Get-PlayerInfoOracleBytesSha256 -Bytes $case.argb
        & $appendRecord 'STATE' $stateFields
    }
    & $appendRecord 'COMPLETE' ([ordered]@{
        runId = [string]$Parsed.runId
        caseCount = '11'
    })

    $text = ($lines -join "`n") + "`n"
    if ($text -match '\|PART\|' -or
        $text -match '(?m)\|escapedUrl=' -or
        $text -match '(?i)\bfile:') {
        throw 'Canonical summary leaked PART payload or an absolute child URL.'
    }
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($text)
    return [pscustomobject]@{
        text = $text
        bytes = $bytes
        sha256 = Get-PlayerInfoOracleBytesSha256 -Bytes $bytes
        recordCount = $lines.Count
    }
}

function Get-PlayerInfoOracleAlphaBounds {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Argb,
        [Parameter(Mandatory = $true)][int]$Width,
        [Parameter(Mandatory = $true)][int]$Height
    )

    $minX = $Width
    $minY = $Height
    $maxX = -1
    $maxY = -1
    for ($y = 0; $y -lt $Height; $y++) {
        for ($x = 0; $x -lt $Width; $x++) {
            $alpha = $Argb[(($y * $Width + $x) * 4)]
            if ($alpha -ne 0) {
                if ($x -lt $minX) { $minX = $x }
                if ($x -gt $maxX) { $maxX = $x }
                if ($y -lt $minY) { $minY = $y }
                if ($y -gt $maxY) { $maxY = $y }
            }
        }
    }
    if ($maxX -lt 0 -or $maxY -lt 0) {
        throw 'ARGB image has no non-transparent crop bounds.'
    }
    return [pscustomobject]@{
        x = $minX
        y = $minY
        width = $maxX - $minX + 1
        height = $maxY - $minY + 1
    }
}

function Get-PlayerInfoOracleCroppedArgb {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Argb,
        [Parameter(Mandatory = $true)][int]$SourceWidth,
        [Parameter(Mandatory = $true)]$Bounds
    )

    $cropped = [byte[]]::new([int]$Bounds.width * [int]$Bounds.height * 4)
    $rowBytes = [int]$Bounds.width * 4
    for ($row = 0; $row -lt [int]$Bounds.height; $row++) {
        $sourceOffset = (
            (([int]$Bounds.y + $row) * $SourceWidth + [int]$Bounds.x) * 4)
        [System.Buffer]::BlockCopy(
            $Argb, $sourceOffset, $cropped, $row * $rowBytes, $rowBytes)
    }
    return ,$cropped
}

function Convert-PlayerInfoOracleArgbToPngBytes {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Argb,
        [Parameter(Mandatory = $true)][int]$Width,
        [Parameter(Mandatory = $true)][int]$Height
    )

    if ($Argb.Length -ne $Width * $Height * 4) {
        throw 'ARGB byte length does not match requested PNG dimensions.'
    }
    Add-Type -AssemblyName System.Drawing
    $bitmap = [System.Drawing.Bitmap]::new(
        $Width,
        $Height,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    )
    $rect = [System.Drawing.Rectangle]::new(0, 0, $Width, $Height)
    $locked = $null
    try {
        $locked = $bitmap.LockBits(
            $rect,
            [System.Drawing.Imaging.ImageLockMode]::WriteOnly,
            [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
        )
        if ($locked.Stride -le 0) {
            throw (
                'PNG encoder refuses a non-positive bitmap stride because ' +
                'its native row origin cannot be proven in this capture path.')
        }
        $destination = [byte[]]::new($locked.Stride * $Height)
        for ($y = 0; $y -lt $Height; $y++) {
            for ($x = 0; $x -lt $Width; $x++) {
                $sourceOffset = (($y * $Width + $x) * 4)
                $destinationOffset = ($y * $locked.Stride) + ($x * 4)
                $destination[$destinationOffset] = $Argb[$sourceOffset + 3]
                $destination[$destinationOffset + 1] = $Argb[$sourceOffset + 2]
                $destination[$destinationOffset + 2] = $Argb[$sourceOffset + 1]
                $destination[$destinationOffset + 3] = $Argb[$sourceOffset]
            }
        }
        [System.Runtime.InteropServices.Marshal]::Copy(
            $destination, 0, $locked.Scan0, $destination.Length)
        $bitmap.UnlockBits($locked)
        $locked = $null
        $stream = [System.IO.MemoryStream]::new()
        try {
            $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
            return ,$stream.ToArray()
        } finally {
            $stream.Dispose()
        }
    } finally {
        if ($null -ne $locked) {
            $bitmap.UnlockBits($locked)
        }
        $bitmap.Dispose()
    }
}

function Assert-PlayerInfoOraclePngPixels {
    param(
        [Parameter(Mandatory = $true)][byte[]]$PngBytes,
        [Parameter(Mandatory = $true)][byte[]]$ExpectedArgb,
        [Parameter(Mandatory = $true)][int]$ExpectedWidth,
        [Parameter(Mandatory = $true)][int]$ExpectedHeight,
        [Parameter(Mandatory = $true)][string]$Scenario
    )

    if ($ExpectedArgb.Length -ne $ExpectedWidth * $ExpectedHeight * 4) {
        throw "PNG round-trip expected bytes are malformed for $Scenario."
    }
    Add-Type -AssemblyName System.Drawing
    $stream = [System.IO.MemoryStream]::new($PngBytes, $false)
    $bitmap = $null
    try {
        $bitmap = [System.Drawing.Bitmap]::new($stream)
        if ($bitmap.Width -ne $ExpectedWidth -or
            $bitmap.Height -ne $ExpectedHeight) {
            throw ("PNG round-trip dimensions mismatch for {0}: {1}x{2}." -f
                $Scenario, $bitmap.Width, $bitmap.Height)
        }
        for ($y = 0; $y -lt $ExpectedHeight; $y++) {
            for ($x = 0; $x -lt $ExpectedWidth; $x++) {
                $offset = (($y * $ExpectedWidth + $x) * 4)
                $pixel = $bitmap.GetPixel($x, $y)
                $expectedA = [int]$ExpectedArgb[$offset]
                $expectedR = [int]$ExpectedArgb[$offset + 1]
                $expectedG = [int]$ExpectedArgb[$offset + 2]
                $expectedB = [int]$ExpectedArgb[$offset + 3]
                if ($pixel.A -ne $expectedA -or
                    $pixel.R -ne $expectedR -or
                    $pixel.G -ne $expectedG -or
                    $pixel.B -ne $expectedB) {
                    throw ("PNG round-trip ARGB mismatch for {0} at ({1},{2}): " +
                        'expected {3}/{4}/{5}/{6}, got {7}/{8}/{9}/{10}.' -f
                        $Scenario, $x, $y,
                        $expectedA, $expectedR, $expectedG, $expectedB,
                        $pixel.A, $pixel.R, $pixel.G, $pixel.B)
                }
            }
        }
    } finally {
        if ($null -ne $bitmap) {
            $bitmap.Dispose()
        }
        $stream.Dispose()
    }
}

function New-SyntheticPlayerInfoOracleTrace {
    param(
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][string]$ExpectedChildPath
    )

    $rowBytes = [byte[]]::new(4096)
    $rowBytes[0] = 255
    $rowBytes[1] = 50
    $rowBytes[2] = 100
    $rowBytes[3] = 150
    $visibleRow = [System.Convert]::ToBase64String($rowBytes)
    [System.Array]::Clear($rowBytes, 0, $rowBytes.Length)
    $transparentRow = [System.Convert]::ToBase64String($rowBytes)
    $runtimeEscaped = ConvertTo-SyntheticAvm1EscapedString `
        -Value '../flashswf/UI/玩家信息界面.swf'
    $childUri = [System.Uri]::new(
        [System.IO.Path]::GetFullPath($ExpectedChildPath)).AbsoluteUri
    $childEscaped = ConvertTo-SyntheticAvm1EscapedString -Value $childUri
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add(
        'PLAYER_INFO_ORACLE|START|runId=stale000000000000000000000000000|schema=old')
    $lines.Add(
        'PLAYER_INFO_ORACLE|COMPLETE|runId=stale000000000000000000000000000|caseCount=0')
    $lines.Add(
        "PLAYER_INFO_ORACLE|START|runId=$RunId|" +
        'schema=cf7.player_info.flash_oracle.v1|quality=MEDIUM|' +
        'stageScaleMode=noScale|stageAlign=LT|stageWidth=500|stageHeight=500|' +
        "runtimeUrlEscaped=$runtimeEscaped|caseCount=11")
    $lines.Add(
        "PLAYER_INFO_ORACLE|CHILD|runId=$RunId|urlReported=1|" +
        "escapedUrl=$childEscaped")
    foreach ($expected in @(Get-PlayerInfoOracleExpectedCases)) {
        $state = Get-PlayerInfoOracleExpectedStateFields -Expected $expected
        $stateText = ($state.GetEnumerator() | ForEach-Object {
            $_.Key + '=' + [string]$_.Value
        }) -join '|'
        $lines.Add("PLAYER_INFO_ORACLE|STATE|runId=$RunId|$stateText")
        for ($row = 0; $row -lt 64; $row++) {
            $encoded = if ($row -eq 0) { $visibleRow } else { $transparentRow }
            for ($part = 0; $part -lt 8; $part++) {
                $payload = $encoded.Substring(
                    $part * 720,
                    [Math]::Min(720, $encoded.Length - ($part * 720))
                )
                $lines.Add(
                    "PLAYER_INFO_ORACLE|PART|runId=$RunId|" +
                    "caseId=$($expected.caseId)|row=$row|part=$part|" +
                    "partCount=8|b64=$payload")
            }
        }
    }
    $lines.Add("PLAYER_INFO_ORACLE|COMPLETE|runId=$RunId|caseCount=11")
    return ($lines -join "`n") + "`n"
}

function Assert-PlayerInfoOracleTraceRejected {
    param(
        [Parameter(Mandatory = $true)][string]$FreshText,
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][string]$ExpectedChildPath,
        [Parameter(Mandatory = $true)][string]$Scenario
    )

    try {
        [void](Test-PlayerInfoOracleTrace `
            -FreshText $FreshText `
            -RunId $RunId `
            -ExpectedChildPath $ExpectedChildPath)
    } catch {
        return
    }
    throw "Protocol self-test accepted invalid scenario: $Scenario"
}

function Assert-PlayerInfoOracleChildBindingRejected {
    param(
        [Parameter(Mandatory = $true)][string]$ReportedUrl,
        [Parameter(Mandatory = $true)][string]$ExpectedChildPath,
        [Parameter(Mandatory = $true)][string]$Scenario
    )

    try {
        [void](Resolve-PlayerInfoOracleChildBinding `
            -EscapedUrl (
                ConvertTo-SyntheticAvm1EscapedString -Value $ReportedUrl) `
            -ExpectedChildPath $ExpectedChildPath)
    } catch {
        return
    }
    throw "Child-binding self-test accepted invalid scenario: $Scenario"
}

function Invoke-PlayerInfoOracleProtocolSelfTest {
    param([Parameter(Mandatory = $true)][string]$ExpectedChildPath)

    $runId = [System.Guid]::NewGuid().ToString('N')
    $trace = New-SyntheticPlayerInfoOracleTrace `
        -RunId $runId `
        -ExpectedChildPath $ExpectedChildPath
    $parsed = Test-PlayerInfoOracleTrace `
        -FreshText $trace `
        -RunId $runId `
        -ExpectedChildPath $ExpectedChildPath
    if ($parsed.cases.Count -ne 11) {
        throw 'Protocol self-test parser did not return eleven cases.'
    }
    foreach ($focused in @(
        [pscustomobject]@{
            caseId = 'mp_vf34'; hp = 8576; hpFrame = 44
            mp = 6700; mpFrame = 34
        },
        [pscustomobject]@{
            caseId = 'mp_vf35'; hp = 8448; hpFrame = 45
            mp = 6600; mpFrame = 35
        },
        [pscustomobject]@{
            caseId = 'mp_vf70'; hp = 3968; hpFrame = 90
            mp = 3100; mpFrame = 70
        },
        [pscustomobject]@{
            caseId = 'mp_vf91'; hp = 1280; hpFrame = 117
            mp = 1000; mpFrame = 91
        }
    )) {
        $matchingFocused = @($parsed.cases | Where-Object {
            [string]$_.expected.caseId -ceq [string]$focused.caseId
        })
        if ($matchingFocused.Count -ne 1 -or
            [int]$matchingFocused[0].expected.hp -ne [int]$focused.hp -or
            [int]$matchingFocused[0].state.hpTargetFrame -ne
                [int]$focused.hpFrame -or
            [int]$matchingFocused[0].expected.mp -ne [int]$focused.mp -or
            [int]$matchingFocused[0].state.mpTargetFrame -ne
                [int]$focused.mpFrame) {
            throw (
                'Protocol self-test focused virtual-frame case drifted: ' +
                [string]$focused.caseId)
        }
    }
    $emptyTraceRejected = $false
    try {
        [void](Test-PlayerInfoOracleTrace `
            -FreshText '' `
            -RunId $runId `
            -ExpectedChildPath $ExpectedChildPath)
    } catch {
        $emptyTraceRejected = $true
    }
    if (-not $emptyTraceRejected) {
        throw 'Protocol self-test accepted an empty fresh trace.'
    }
    $expectedUri = [System.Uri]::new(
        [System.IO.Path]::GetFullPath($ExpectedChildPath)).AbsoluteUri
    $flashPipeUri = $expectedUri -replace (
        '^file:///([A-Za-z]):/', 'file:///$1|/')
    $pipeBinding = Resolve-PlayerInfoOracleChildBinding `
        -EscapedUrl (
            ConvertTo-SyntheticAvm1EscapedString -Value $flashPipeUri) `
        -ExpectedChildPath $ExpectedChildPath
    if (-not $pipeBinding.matched) {
        throw 'Protocol self-test rejected the canonical Flash C| file URI form.'
    }
    Assert-PlayerInfoOracleChildBindingRejected `
        -ReportedUrl '../flashswf/UI/玩家信息界面.swf' `
        -ExpectedChildPath $ExpectedChildPath `
        -Scenario 'bare relative path'
    Assert-PlayerInfoOracleChildBindingRejected `
        -ReportedUrl ([System.IO.Path]::GetFullPath($ExpectedChildPath)) `
        -ExpectedChildPath $ExpectedChildPath `
        -Scenario 'bare absolute path'
    Assert-PlayerInfoOracleChildBindingRejected `
        -ReportedUrl 'http://example.invalid/玩家信息界面.swf' `
        -ExpectedChildPath $ExpectedChildPath `
        -Scenario 'remote HTTP URL'
    Assert-PlayerInfoOracleChildBindingRejected `
        -ReportedUrl ($expectedUri + '?cache=1') `
        -ExpectedChildPath $ExpectedChildPath `
        -Scenario 'file URI with query'
    Assert-PlayerInfoOracleChildBindingRejected `
        -ReportedUrl ($expectedUri + '#fragment') `
        -ExpectedChildPath $ExpectedChildPath `
        -Scenario 'file URI with fragment'
    Assert-PlayerInfoOracleChildBindingRejected `
        -ReportedUrl 'file://remote-host/C:/player-info.swf' `
        -ExpectedChildPath $ExpectedChildPath `
        -Scenario 'file URI with remote host'
    Assert-PlayerInfoOracleChildBindingRejected `
        -ReportedUrl 'file://localhost/C:/player-info.swf' `
        -ExpectedChildPath $ExpectedChildPath `
        -Scenario 'file URI with localhost host'
    Assert-PlayerInfoOracleChildBindingRejected `
        -ReportedUrl 'file:C:/player-info.swf' `
        -ExpectedChildPath $ExpectedChildPath `
        -Scenario 'opaque file URI without triple slash'
    $canonicalSummary = New-PlayerInfoOracleCanonicalSummary -Parsed $parsed
    if ($canonicalSummary.recordCount -ne 14 -or
        $canonicalSummary.text -match '\|PART\|' -or
        $canonicalSummary.text -match '(?m)\|escapedUrl=' -or
        $canonicalSummary.text -match [regex]::Escape($expectedUri)) {
        throw 'Protocol self-test canonical summary is not compact/path-free.'
    }
    $partLines = @([regex]::Split($trace, '\r?\n') | Where-Object {
        $_.StartsWith(
            'PLAYER_INFO_ORACLE|PART|',
            [System.StringComparison]::Ordinal)
    })
    if ($partLines.Count -ne 5632) {
        throw "Protocol self-test expected 5632 PART records; got $($partLines.Count)."
    }
    $maxPartLineChars = ($partLines | Measure-Object -Maximum Length).Maximum
    if ($maxPartLineChars -gt 1000) {
        throw "Protocol self-test PART record exceeds 1000 chars: $maxPartLineChars"
    }
    foreach ($line in $partLines) {
        if ($line -match '[^\x00-\x7F]') {
            throw 'Protocol self-test generated a non-ASCII PART record.'
        }
    }
    $boundaryPrefix = (
        "PLAYER_INFO_ORACLE|PART|runId=$RunId|" +
        'caseId=empty|row=0|part=0|partCount=8|b64=')
    $lineAt1000 = $boundaryPrefix + ('A' * (1000 - $boundaryPrefix.Length))
    if ($lineAt1000.Length -ne 1000) {
        throw 'Protocol self-test could not construct the 1000-char boundary.'
    }
    [void](ConvertFrom-PlayerInfoOracleLine -Line $lineAt1000 -LineNumber 1)
    try {
        [void](ConvertFrom-PlayerInfoOracleLine `
            -Line ($lineAt1000 + 'A') -LineNumber 1)
        throw 'Protocol self-test accepted a 1001-char physical record.'
    } catch {
        if ($_.Exception.Message -ceq
            'Protocol self-test accepted a 1001-char physical record.') {
            throw
        }
    }

    $first = $parsed.cases[0]
    $bounds = Get-PlayerInfoOracleAlphaBounds `
        -Argb $first.argb -Width 1024 -Height 64
    if ($bounds.x -ne 0 -or $bounds.y -ne 0 -or
        $bounds.width -ne 1 -or $bounds.height -ne 1) {
        throw 'Protocol self-test alpha crop bounds are incorrect.'
    }
    $png = Convert-PlayerInfoOracleArgbToPngBytes `
        -Argb $first.argb -Width 1024 -Height 64
    if ($png.Length -lt 8 -or
        $png[0] -ne 137 -or $png[1] -ne 80 -or
        $png[2] -ne 78 -or $png[3] -ne 71) {
        throw 'Protocol self-test PNG encoder did not produce a PNG signature.'
    }
    $fixtureWidth = 5
    $fixtureHeight = 4
    $fixtureArgb = [byte[]]::new($fixtureWidth * $fixtureHeight * 4)
    $innerAlpha = @(
        @(1, 128, 255),
        @(255, 0, 1)
    )
    for ($y = 0; $y -lt $fixtureHeight; $y++) {
        for ($x = 0; $x -lt $fixtureWidth; $x++) {
            $offset = (($y * $fixtureWidth + $x) * 4)
            $fixtureArgb[$offset] = if (
                $x -ge 1 -and $x -le 3 -and
                $y -ge 1 -and $y -le 2) {
                [byte]$innerAlpha[$y - 1][$x - 1]
            } else {
                [byte]0
            }
            $fixtureArgb[$offset + 1] = [byte](10 + ($y * 17) + $x)
            $fixtureArgb[$offset + 2] = [byte](70 + ($y * 13) + ($x * 2))
            $fixtureArgb[$offset + 3] = [byte](140 + ($y * 7) + ($x * 3))
        }
    }
    $fixturePng = Convert-PlayerInfoOracleArgbToPngBytes `
        -Argb $fixtureArgb -Width $fixtureWidth -Height $fixtureHeight
    Assert-PlayerInfoOraclePngPixels `
        -PngBytes $fixturePng `
        -ExpectedArgb $fixtureArgb `
        -ExpectedWidth $fixtureWidth `
        -ExpectedHeight $fixtureHeight `
        -Scenario '5x4 alpha/RGB fixture'
    $fixtureBounds = Get-PlayerInfoOracleAlphaBounds `
        -Argb $fixtureArgb -Width $fixtureWidth -Height $fixtureHeight
    if ($fixtureBounds.x -ne 1 -or $fixtureBounds.y -ne 1 -or
        $fixtureBounds.width -ne 3 -or $fixtureBounds.height -ne 2) {
        throw 'Protocol self-test multi-row crop bounds are incorrect.'
    }
    $fixtureCropArgb = Get-PlayerInfoOracleCroppedArgb `
        -Argb $fixtureArgb `
        -SourceWidth $fixtureWidth `
        -Bounds $fixtureBounds
    $fixtureCropPng = Convert-PlayerInfoOracleArgbToPngBytes `
        -Argb $fixtureCropArgb -Width 3 -Height 2
    Assert-PlayerInfoOraclePngPixels `
        -PngBytes $fixtureCropPng `
        -ExpectedArgb $fixtureCropArgb `
        -ExpectedWidth 3 `
        -ExpectedHeight 2 `
        -Scenario '3x2 alpha crop fixture'

    $lines = [regex]::Split($trace, '\r?\n')
    $firstPartIndex = -1
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index].StartsWith(
                "PLAYER_INFO_ORACLE|PART|runId=$runId|",
                [System.StringComparison]::Ordinal)) {
            $firstPartIndex = $index
            break
        }
    }
    if ($firstPartIndex -lt 0) {
        throw 'Protocol self-test could not locate its first PART record.'
    }

    $canonicalRowParts = @($lines | Where-Object {
        $_ -match (
            '^PLAYER_INFO_ORACLE\|PART\|runId=' +
            [regex]::Escape($runId) +
            '\|caseId=empty\|row=0\|part=[0-7]\|partCount=8\|b64=')
    })
    if ($canonicalRowParts.Count -ne 8) {
        throw 'Protocol self-test could not isolate one canonical base64 row.'
    }
    $canonicalRowText = ($canonicalRowParts | ForEach-Object {
        $_.Substring($_.IndexOf('|b64=') + 5)
    }) -join ''
    if (-not $canonicalRowText.EndsWith(
            'AA==',
            [System.StringComparison]::Ordinal)) {
        throw 'Protocol self-test canonical row lacks the expected padded tail.'
    }
    $nonCanonicalRowText = $canonicalRowText.Substring(
        0, $canonicalRowText.Length - 4) + 'AB=='
    $canonicalDecoded = [System.Convert]::FromBase64String($canonicalRowText)
    $nonCanonicalDecoded = [System.Convert]::FromBase64String(
        $nonCanonicalRowText)
    if ((Get-PlayerInfoOracleBytesSha256 -Bytes $canonicalDecoded) -cne
        (Get-PlayerInfoOracleBytesSha256 -Bytes $nonCanonicalDecoded)) {
        throw 'Protocol self-test noncanonical padding did not decode identically.'
    }
    $nonCanonicalLines = [string[]]$lines.Clone()
    for ($index = 0; $index -lt $nonCanonicalLines.Count; $index++) {
        if ($nonCanonicalLines[$index] -match (
                '^PLAYER_INFO_ORACLE\|PART\|runId=' +
                [regex]::Escape($runId) +
                '\|caseId=empty\|row=0\|part=7\|partCount=8\|b64=')) {
            $prefixLength = $nonCanonicalLines[$index].IndexOf('|b64=') + 5
            $payload = $nonCanonicalLines[$index].Substring($prefixLength)
            $nonCanonicalLines[$index] =
                $nonCanonicalLines[$index].Substring(0, $prefixLength) +
                $payload.Substring(0, $payload.Length - 4) + 'AB=='
            break
        }
    }
    Assert-PlayerInfoOracleTraceRejected `
        -FreshText ($nonCanonicalLines -join "`n") `
        -RunId $runId `
        -ExpectedChildPath $ExpectedChildPath `
        -Scenario 'noncanonical base64 padding bits'

    $reorderedLines = [string[]]$lines.Clone()
    $swap = $reorderedLines[$firstPartIndex]
    $reorderedLines[$firstPartIndex] = $reorderedLines[$firstPartIndex + 1]
    $reorderedLines[$firstPartIndex + 1] = $swap
    Assert-PlayerInfoOracleTraceRejected `
        -FreshText ($reorderedLines -join "`n") `
        -RunId $runId `
        -ExpectedChildPath $ExpectedChildPath `
        -Scenario 'out-of-order PART'

    $overlongLines = [string[]]$lines.Clone()
    $overlongLines[$firstPartIndex] = (
        $overlongLines[$firstPartIndex].Substring(
            0, $overlongLines[$firstPartIndex].IndexOf('b64=') + 4) +
        ('A' * 920))
    if ($overlongLines[$firstPartIndex].Length -le 1000) {
        throw 'Protocol self-test did not construct an overlong physical record.'
    }
    Assert-PlayerInfoOracleTraceRejected `
        -FreshText ($overlongLines -join "`n") `
        -RunId $runId `
        -ExpectedChildPath $ExpectedChildPath `
        -Scenario 'over-1000-char PART'

    $badText = [regex]::Replace(
        $trace, 'hpCurrentText=0(?=\|)', 'hpCurrentText=1', 1)
    Assert-PlayerInfoOracleTraceRejected `
        -FreshText $badText `
        -RunId $runId `
        -ExpectedChildPath $ExpectedChildPath `
        -Scenario 'state mismatch'

    $unknownField = [regex]::Replace(
        $trace,
        '(?m)^(PLAYER_INFO_ORACLE\|START\|[^\r\n]+)$',
        '$1|rogue=1',
        1)
    Assert-PlayerInfoOracleTraceRejected `
        -FreshText $unknownField `
        -RunId $runId `
        -ExpectedChildPath $ExpectedChildPath `
        -Scenario 'unknown START field'

    $unknownType = $trace.Replace(
        "PLAYER_INFO_ORACLE|STATE|runId=$runId|caseId=empty",
        "PLAYER_INFO_ORACLE|MYSTERY|runId=$runId|caseId=empty")
    Assert-PlayerInfoOracleTraceRejected `
        -FreshText $unknownType `
        -RunId $runId `
        -ExpectedChildPath $ExpectedChildPath `
        -Scenario 'unknown same-run record type'

    $nonOracleSentinel = 'NON_ORACLE|absolute=file:///must-not-promote'
    $mixedTrace = $trace.Replace(
        "PLAYER_INFO_ORACLE|CHILD|runId=$runId|urlReported=1|",
        $nonOracleSentinel + "`n" +
        "PLAYER_INFO_ORACLE|CHILD|runId=$runId|urlReported=1|")
    $mixedParsed = Test-PlayerInfoOracleTrace `
        -FreshText $mixedTrace `
        -RunId $runId `
        -ExpectedChildPath $ExpectedChildPath
    $mixedSummary = New-PlayerInfoOracleCanonicalSummary -Parsed $mixedParsed
    if ($mixedSummary.text.IndexOf(
            $nonOracleSentinel,
            [System.StringComparison]::Ordinal) -ge 0) {
        throw 'Canonical summary retained a non-oracle interleaved line.'
    }

    $afterComplete = $trace +
        "PLAYER_INFO_ORACLE|STATE|runId=$runId|caseId=late`n"
    Assert-PlayerInfoOracleTraceRejected `
        -FreshText $afterComplete `
        -RunId $runId `
        -ExpectedChildPath $ExpectedChildPath `
        -Scenario 'same-run record after COMPLETE'

    $foreignInterleaved = $trace.Replace(
        "PLAYER_INFO_ORACLE|STATE|runId=$runId|caseId=empty",
        "PLAYER_INFO_ORACLE|STATE|runId=ffffffffffffffffffffffffffffffff|" +
        "caseId=foreign`n" +
        "PLAYER_INFO_ORACLE|STATE|runId=$runId|caseId=empty")
    Assert-PlayerInfoOracleTraceRejected `
        -FreshText $foreignInterleaved `
        -RunId $runId `
        -ExpectedChildPath $ExpectedChildPath `
        -Scenario 'foreign-run record interleaved inside lifecycle'

    $failure = $trace.Replace(
        "PLAYER_INFO_ORACLE|COMPLETE|runId=$runId|caseCount=11",
        "PLAYER_INFO_ORACLE|FAILURE|runId=$runId|code=synthetic`n" +
        "PLAYER_INFO_ORACLE|COMPLETE|runId=$runId|caseCount=11")
    Assert-PlayerInfoOracleTraceRejected `
        -FreshText $failure `
        -RunId $runId `
        -ExpectedChildPath $ExpectedChildPath `
        -Scenario 'FAILURE sentinel'

    $wrongChild = Join-Path (
        Split-Path -Parent $ExpectedChildPath) 'not-the-child.swf'
    Assert-PlayerInfoOracleTraceRejected `
        -FreshText $trace `
        -RunId $runId `
        -ExpectedChildPath $wrongChild `
        -Scenario 'exact child path mismatch'

    return [pscustomobject]@{
        partRecordCount = $partLines.Count
        maxPartLineChars = [int]$maxPartLineChars
        cases = $parsed.cases.Count
        canonicalSummaryRecords = [int]$canonicalSummary.recordCount
        pngRoundTrips = 2
        noncanonicalBase64Rejected = $true
    }
}
