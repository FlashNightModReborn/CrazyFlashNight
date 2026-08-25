[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Xml.Linq
$projectRoot = Split-Path -Parent $PSScriptRoot
$stageRoot = Join-Path $projectRoot 'data\stages'
$idPattern = '^[a-z][a-z0-9_-]{0,31}$'
$maxPools = 16
$maxActivePools = 4
$maxDurationSeconds = 3600

function Read-XDocument {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $settings = New-Object System.Xml.XmlReaderSettings
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $stringReader = New-Object System.IO.StringReader($Text)
    $reader = $null
    try {
        $reader = [System.Xml.XmlReader]::Create($stringReader, $settings)
        return [System.Xml.Linq.XDocument]::Load(
            $reader,
            [System.Xml.Linq.LoadOptions]::SetLineInfo)
    } catch {
        throw "$Label XML 解析失败: $($_.Exception.Message)"
    } finally {
        if ($null -ne $reader) { $reader.Dispose() }
        $stringReader.Dispose()
    }
}

function Get-Children {
    param($Node, [string]$Name)
    return @($Node.Elements() | Where-Object { $_.Name.LocalName -eq $Name })
}

function Get-LineLabel {
    param($Node, [string]$Fallback)
    $lineInfo = [System.Xml.IXmlLineInfo]$Node
    if ($null -ne $lineInfo -and $lineInfo.HasLineInfo()) {
        return "${Fallback}:$($lineInfo.LineNumber)"
    }
    return $Fallback
}

function Test-StageTimePoolDocument {
    param(
        [Parameter(Mandatory = $true)]$Document,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $errors = New-Object 'System.Collections.Generic.List[string]'
    $root = $Document.Root
    if ($null -eq $root -or $root.Name.LocalName -ne 'GameStage') {
        $errors.Add("${Label}: 根元素必须是 GameStage")
        return @($errors)
    }

    $timePoolContainers = Get-Children $root 'TimePools'
    if ($timePoolContainers.Count -gt 1) {
        $errors.Add("${Label}: TimePools 只能出现一次")
    }
    $container = if ($timePoolContainers.Count -eq 1) { $timePoolContainers[0] } else { $null }
    foreach ($nestedContainer in @($root.Descendants() | Where-Object {
                $_.Name.LocalName -eq 'TimePools' -and $_.Parent -ne $root
            })) {
        $nestedLocation = Get-LineLabel $nestedContainer $Label
        $errors.Add("${nestedLocation}: TimePools 只能是 GameStage 的直接子节点")
    }
    foreach ($strayPool in @($root.Descendants() | Where-Object {
                $_.Name.LocalName -eq 'TimePool' -and $_.Parent -ne $container
            })) {
        $strayLocation = Get-LineLabel $strayPool $Label
        $errors.Add("${strayLocation}: TimePool 只能是 GameStage/TimePools 的直接子节点")
    }

    $definitions = @()
    if ($null -ne $container) {
        foreach ($child in @($container.Elements())) {
            if ($child.Name.LocalName -ne 'TimePool') {
                $childLocation = Get-LineLabel $child $Label
                $errors.Add("${childLocation}: TimePools 只允许 TimePool 子元素")
            }
        }
        $definitions = Get-Children $container 'TimePool'
        if ($definitions.Count -lt 1) {
            $errors.Add("${Label}: 已声明 TimePools 但没有 TimePool")
        }
        if ($definitions.Count -gt $maxPools) {
            $errors.Add("${Label}: TimePool 数量 $($definitions.Count) 超过上限 $maxPools")
        }
        if (@($container.Descendants() | Where-Object {
                    $_.Name.LocalName -eq 'CaseSwitch'
                }).Count -gt 0) {
            $errors.Add("${Label}: 计时池定义禁止 CaseSwitch")
        }
    }

    $pools = @{}
    $referenceCounts = @{}
    foreach ($definition in $definitions) {
        $location = Get-LineLabel $definition $Label
        if (@($definition.Attributes()).Count -ne 0) {
            $errors.Add("${location}: TimePool 不允许属性")
        }
        $allowed = @('Id', 'DurationSeconds', 'DisplayName', 'TimeoutResult')
        foreach ($child in @($definition.Elements())) {
            if ($allowed -notcontains $child.Name.LocalName) {
                $childLocation = Get-LineLabel $child $Label
                $errors.Add("${childLocation}: TimePool 不支持 $($child.Name.LocalName)")
            }
        }

        $values = @{}
        foreach ($name in $allowed) {
            $matches = Get-Children $definition $name
            if ($matches.Count -ne 1) {
                $errors.Add("${location}: TimePool 必须且只能有一个 $name")
                continue
            }
            if ($matches[0].HasElements -or @($matches[0].Attributes()).Count -ne 0) {
                $fieldLocation = Get-LineLabel $matches[0] $Label
                $errors.Add("${fieldLocation}: $name 必须是无属性叶节点")
            }
            $values[$name] = $matches[0].Value
        }

        $id = [string]$values['Id']
        if ($id -notmatch $idPattern) {
            $errors.Add("${location}: Id 非法 '$id'")
        } elseif ($pools.ContainsKey($id)) {
            $errors.Add("${location}: Id 重复 '$id'")
        } else {
            $pools[$id] = $true
            $referenceCounts[$id] = 0
        }

        $duration = 0
        $durationText = [string]$values['DurationSeconds']
        if (-not [int]::TryParse(
                $durationText,
                [System.Globalization.NumberStyles]::None,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [ref]$duration) -or
                $duration -lt 1 -or $duration -gt $maxDurationSeconds) {
            $errors.Add("${location}: DurationSeconds 必须是 1..$maxDurationSeconds 的整数")
        }

        $displayName = [string]$values['DisplayName']
        $hasControl = $false
        foreach ($character in $displayName.ToCharArray()) {
            if ([char]::IsControl($character)) { $hasControl = $true; break }
        }
        if ([string]::IsNullOrWhiteSpace($displayName) -or
                $displayName -ne $displayName.Trim() -or
                $displayName.Length -gt 32 -or
                $displayName.Contains('|') -or $hasControl) {
            $errors.Add("${location}: DisplayName 必须为 1..32 字符且不能含首尾空白、控制符或 |")
        }

        if ([string]$values['TimeoutResult'] -ne 'FailStage') {
            $errors.Add("${location}: TimeoutResult 当前仅支持 FailStage")
        }
    }

    $subStages = Get-Children $root 'SubStage'
    foreach ($subStage in $subStages) {
        $location = Get-LineLabel $subStage $Label
        $refs = Get-Children $subStage 'TimePoolRef'
        if ($refs.Count -gt $maxActivePools) {
            $errors.Add("${location}: 同时引用 $($refs.Count) 个计时池，超过上限 $maxActivePools")
        }
        $seen = @{}
        foreach ($ref in $refs) {
            $refLocation = Get-LineLabel $ref $Label
            if ($ref.HasElements -or @($ref.Attributes()).Count -ne 0) {
                $errors.Add("${refLocation}: TimePoolRef 必须是无属性叶节点")
            }
            $id = $ref.Value
            if ($id -notmatch $idPattern) {
                $errors.Add("${refLocation}: TimePoolRef 非法 '$id'")
                continue
            }
            if ($seen.ContainsKey($id)) {
                $errors.Add("${refLocation}: 当前 SubStage 重复引用 '$id'")
                continue
            }
            $seen[$id] = $true
            if (-not $pools.ContainsKey($id)) {
                $errors.Add("${refLocation}: 引用了未知计时池 '$id'")
            } else {
                $referenceCounts[$id] = 1 + [int]$referenceCounts[$id]
            }
        }
    }

    foreach ($ref in @($root.Descendants() | Where-Object {
                $_.Name.LocalName -eq 'TimePoolRef'
            })) {
        if ($null -eq $ref.Parent -or
                $ref.Parent.Name.LocalName -ne 'SubStage' -or
                $ref.Parent.Parent -ne $root) {
            $refLocation = Get-LineLabel $ref $Label
            $errors.Add("${refLocation}: TimePoolRef 只能是 GameStage/SubStage 的直接子节点")
        }
    }

    foreach ($id in $pools.Keys) {
        if ([int]$referenceCounts[$id] -eq 0) {
            $errors.Add("${Label}: TimePool '$id' 未被任何 SubStage 引用")
        }
    }

    return @($errors)
}

function Assert-Fixture {
    param(
        [string]$Name,
        [string]$Xml,
        [bool]$ExpectedValid,
        [string]$ExpectedErrorFragment = ''
    )
    $document = Read-XDocument -Text $Xml -Label $Name
    $errors = @(Test-StageTimePoolDocument -Document $document -Label $Name)
    if ($ExpectedValid) {
        if ($errors.Count -ne 0) {
            throw "fixture $Name 应通过，实际错误: $($errors -join '; ')"
        }
    } else {
        if ($errors.Count -eq 0) { throw "fixture $Name 应失败，实际通过" }
        if ($ExpectedErrorFragment -and
                -not (($errors -join "`n").Contains($ExpectedErrorFragment))) {
            throw "fixture $Name 未包含预期错误 '$ExpectedErrorFragment': $($errors -join '; ')"
        }
    }
}

$validFixture = @'
<?xml version="1.0" encoding="UTF-8"?>
<GameStage>
    <TimePools>
        <TimePool><Id>route_a</Id><DurationSeconds>600</DurationSeconds><DisplayName>章节 A</DisplayName><TimeoutResult>FailStage</TimeoutResult></TimePool>
        <TimePool><Id>route_b</Id><DurationSeconds>300</DurationSeconds><DisplayName>章节 B</DisplayName><TimeoutResult>FailStage</TimeoutResult></TimePool>
    </TimePools>
    <SubStage id="0"><TimePoolRef>route_a</TimePoolRef></SubStage>
    <SubStage id="1"><TimePoolRef>route_a</TimePoolRef><TimePoolRef>route_b</TimePoolRef></SubStage>
    <SubStage id="2" />
    <SubStage id="3"><TimePoolRef>route_a</TimePoolRef></SubStage>
</GameStage>
'@
Assert-Fixture 'valid-overlap-reentry' $validFixture $true
Assert-Fixture 'legacy-no-pool' '<GameStage><SubStage id="0" /></GameStage>' $true
Assert-Fixture 'duplicate-id' ($validFixture.Replace('<Id>route_b</Id>', '<Id>route_a</Id>')) $false 'Id 重复'
Assert-Fixture 'unknown-ref' ($validFixture.Replace('<TimePoolRef>route_b</TimePoolRef>', '<TimePoolRef>missing</TimePoolRef>')) $false '未知计时池'
Assert-Fixture 'bad-duration' ($validFixture.Replace('<DurationSeconds>300</DurationSeconds>', '<DurationSeconds>0</DurationSeconds>')) $false '1..3600'
Assert-Fixture 'bad-label' ($validFixture.Replace('<DisplayName>章节 B</DisplayName>', '<DisplayName>章节|B</DisplayName>')) $false 'DisplayName'
Assert-Fixture 'numeric-id' ($validFixture.Replace('<Id>route_b</Id>', '<Id>7</Id>').Replace('<TimePoolRef>route_b</TimePoolRef>', '<TimePoolRef>7</TimePoolRef>')) $false 'Id 非法'
Assert-Fixture 'unsupported-result' ($validFixture.Replace('<TimeoutResult>FailStage</TimeoutResult>', '<TimeoutResult>ClearStage</TimeoutResult>')) $false '仅支持 FailStage'
Assert-Fixture 'unreferenced' ($validFixture.Replace('<TimePoolRef>route_b</TimePoolRef>', '')) $false '未被任何 SubStage'
Assert-Fixture 'case-switch' ($validFixture.Replace('<DisplayName>章节 B</DisplayName>', '<DisplayName><CaseSwitch /></DisplayName>')) $false '禁止 CaseSwitch'
Assert-Fixture 'nested-container' '<GameStage><SubStage id="0"><TimePools /></SubStage></GameStage>' $false 'TimePools 只能是 GameStage'
Assert-Fixture 'stray-pool' '<GameStage><TimePool><Id>stray</Id></TimePool><SubStage id="0" /></GameStage>' $false 'TimePool 只能是 GameStage/TimePools'

$files = @(Get-ChildItem -LiteralPath $stageRoot -Recurse -File -Filter '*.xml' |
    Where-Object { $_.Name -notin @('list.xml', '__list__.xml', 'loading_data.xml') } |
    Sort-Object FullName)
$allErrors = New-Object 'System.Collections.Generic.List[string]'
$subStageCount = 0
$poolCount = 0
$refCount = 0
$configuredFileCount = 0
foreach ($file in $files) {
    $relative = $file.FullName.Substring($projectRoot.Length + 1)
    try {
        $text = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
        $document = Read-XDocument -Text $text -Label $relative
        foreach ($validationIssue in @(Test-StageTimePoolDocument -Document $document -Label $relative)) {
            $allErrors.Add($validationIssue)
        }
        $root = $document.Root
        $subStageCount += (Get-Children $root 'SubStage').Count
        $containers = Get-Children $root 'TimePools'
        if ($containers.Count -eq 1) {
            $configuredFileCount++
            $poolCount += (Get-Children $containers[0] 'TimePool').Count
        }
        foreach ($subStage in Get-Children $root 'SubStage') {
            $refCount += (Get-Children $subStage 'TimePoolRef').Count
        }
    } catch {
        $allErrors.Add("${relative}: $($_.Exception.Message)")
    }
}

if ($allErrors.Count -gt 0) {
    foreach ($validationIssue in $allErrors) { Write-Error $validationIssue }
    throw "Stage TimePool validation failed with $($allErrors.Count) error(s)."
}

Write-Host ("[OK] Stage TimePool: fixtures=12, files={0}, substages={1}, configured={2}, pools={3}, refs={4}" -f
    $files.Count, $subStageCount, $configuredFileCount, $poolCount, $refCount)
