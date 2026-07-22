param(
    [string]$StageRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) "data\stages"),
    [string]$ItemRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) "data\items"),
    [switch]$Json,
    [switch]$NoItemCatalog
)

$ErrorActionPreference = "Stop"

$chestTypes = @(
    "装备箱",
    "保险柜",
    "生存箱",
    "资源箱",
    "隐藏资源点",
    "纸箱"
)
$modes = @("修罗", "非修罗")

function New-CountTable([string[]]$Keys) {
    $table = [ordered]@{}
    foreach ($key in $Keys) {
        $table[$key] = 0
    }
    return $table
}

function Get-AttributeValue($Node, [string]$Name) {
    if (-not $Node.Attributes) { return $null }
    $attribute = $Node.Attributes[$Name]
    if (-not $attribute) { return $null }
    return $attribute.Value.Trim()
}

function Get-IdentifierModes($IdentifierNode, $InstanceNode) {
    $active = [ordered]@{ "修罗" = $true; "非修罗" = $true }
    $switches = New-Object System.Collections.Generic.List[object]
    $warnings = New-Object System.Collections.Generic.List[string]
    $errors = New-Object System.Collections.Generic.List[string]
    $node = $IdentifierNode.ParentNode

    while ($node -and -not [object]::ReferenceEquals($node, $InstanceNode)) {
        if ($node.NodeType -eq [System.Xml.XmlNodeType]::Element -and $node.Name -eq "Case") {
            $switchNode = $node.ParentNode
            if (-not $switchNode -or $switchNode.Name -ne "CaseSwitch") {
                $errors.Add("Case 节点不在 CaseSwitch 下")
            } else {
                $expression = Get-AttributeValue $switchNode "expression"
                $params = Get-AttributeValue $switchNode "params"
                $caseValue = Get-AttributeValue $node "casevalue"
                $descriptor = [ordered]@{
                    expression = $expression
                    params = $params
                    caseValue = $caseValue
                    recognizedDifficultyGate = $false
                }

                if ($expression -eq "_root.难度是否达到" -and $params -eq "修罗") {
                    $descriptor.recognizedDifficultyGate = $true
                    $normalizedCaseValue = if ($null -eq $caseValue) { "" } else { $caseValue.ToLowerInvariant() }
                    switch ($normalizedCaseValue) {
                        "true" {
                            $active["非修罗"] = $false
                        }
                        "false" {
                            $active["修罗"] = $false
                        }
                        "default" {
                            $active["修罗"] = $false
                        }
                        default {
                            $errors.Add("难度 CaseSwitch 使用未知 casevalue='$caseValue'")
                        }
                    }
                } else {
                    $errors.Add("Identifier 位于未静态求值的 CaseSwitch expression='$expression' params='$params' casevalue='$caseValue'，无法可靠投影难度口径")
                }
                $switches.Add([pscustomobject]$descriptor)
            }
        }
        $node = $node.ParentNode
    }

    $activeModes = @($modes | Where-Object { $active[$_] })
    if ($activeModes.Count -eq 0) {
        $errors.Add("Identifier 的嵌套 CaseSwitch 条件互相冲突，两个难度口径均不可达")
    }

    return [pscustomobject]@{
        activeModes = $activeModes
        switches = $switches.ToArray()
        warnings = $warnings.ToArray()
        errors = $errors.ToArray()
    }
}

function Get-RelativePath([string]$Root, [string]$FullPath) {
    $rootPath = [System.IO.Path]::GetFullPath($Root).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $filePath = [System.IO.Path]::GetFullPath($FullPath)
    $prefix = $rootPath + [System.IO.Path]::DirectorySeparatorChar
    if (-not $filePath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $filePath.Replace("\", "/")
    }
    return $filePath.Substring($prefix.Length).Replace("\", "/")
}

function Add-AuditError($List, [string]$Kind, [string]$Message, [string]$File = "") {
    $List.Add([pscustomobject]@{
        kind = $Kind
        file = $File
        message = $Message
    })
}

function Get-DirectChildText($Node, [string]$Name) {
    if (-not $Node) { return $null }
    $children = @($Node.SelectNodes("./$Name"))
    if ($children.Count -ne 1) { return $null }
    return $children[0].InnerText.Trim()
}

function Test-PositiveWholeText([string]$Text, [long]$Maximum = [long]::MaxValue) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    [long]$value = 0
    return [long]::TryParse($Text, [ref]$value) -and
        $value -gt 0 -and $value -le $Maximum
}

function Get-WebGridCapability([string]$LootServicePath,
                               [string]$MaterializationPlannerPath,
                               $ErrorList) {
    $result = [ordered]@{
        maxColumns = 0
        maxCapacity = 0
        materializationMaxCapacity = 0
        maxSafeInteger = 0
        maxRandomSpan = 0
    }
    if (-not (Test-Path -LiteralPath $LootServicePath -PathType Leaf)) {
        Add-AuditError $ErrorList "preset-shape" "LootContainerService 真源不存在: $LootServicePath"
        return [pscustomobject]$result
    }
    $source = Get-Content -LiteralPath $LootServicePath -Raw -Encoding UTF8
    foreach ($entry in @(
        @{ name = "MAX_WEB_COLUMNS"; property = "maxColumns" },
        @{ name = "MAX_WEB_CAPACITY"; property = "maxCapacity" }
    )) {
        $pattern = '(?m)^\s*private\s+static\s+var\s+' +
            $entry.name + ':Number\s*=\s*(?<value>[0-9]+)\s*;'
        $matches = [regex]::Matches($source, $pattern)
        if ($matches.Count -ne 1) {
            Add-AuditError $ErrorList "preset-shape" (
                "LootContainerService.$($entry.name) 必须恰有一个正整数定义；actual=$($matches.Count)")
            continue
        }
        $value = [int]$matches[0].Groups["value"].Value
        if ($value -le 0) {
            Add-AuditError $ErrorList "preset-shape" (
                "LootContainerService.$($entry.name) 必须大于 0；actual=$value")
            continue
        }
        $result[$entry.property] = $value
    }

    if (-not (Test-Path -LiteralPath $MaterializationPlannerPath -PathType Leaf)) {
        Add-AuditError $ErrorList "capacity-contract" `
            "LootMaterializationPlanner 真源不存在: $MaterializationPlannerPath"
        return [pscustomobject]$result
    }
    $plannerSource = Get-Content -LiteralPath $MaterializationPlannerPath -Raw -Encoding UTF8
    $plannerCapacityMatches = [regex]::Matches(
        $plannerSource,
        '(?m)^\s*private\s+static\s+var\s+MAX_CAPACITY:Number\s*=\s*(?<value>[0-9]+)\s*;')
    if ($plannerCapacityMatches.Count -ne 1) {
        Add-AuditError $ErrorList "capacity-contract" (
            "LootMaterializationPlanner.MAX_CAPACITY 必须恰有一个正整数定义；actual=$($plannerCapacityMatches.Count)")
        return [pscustomobject]$result
    }
    $result.materializationMaxCapacity = [int]$plannerCapacityMatches[0].Groups["value"].Value
    if ($result.materializationMaxCapacity -le 0) {
        Add-AuditError $ErrorList "capacity-contract" (
            "LootMaterializationPlanner.MAX_CAPACITY 必须大于 0；actual=$($result.materializationMaxCapacity)")
    } elseif ($result.maxCapacity -gt 0 -and
            $result.materializationMaxCapacity -ne $result.maxCapacity) {
        Add-AuditError $ErrorList "capacity-contract" (
            "Web 容器容量与物化容量不一致；service=$($result.maxCapacity), planner=$($result.materializationMaxCapacity)")
    }
    foreach ($entry in @(
        @{ name = "MAX_SAFE_INTEGER"; property = "maxSafeInteger" },
        @{ name = "MAX_RANDOM_SPAN"; property = "maxRandomSpan" }
    )) {
        $matches = [regex]::Matches(
            $plannerSource,
            ('(?m)^\s*private\s+static\s+var\s+' + $entry.name +
                ':Number\s*=\s*(?<value>[0-9]+)\s*;'))
        [long]$value = 0
        if ($matches.Count -ne 1 -or
                -not [long]::TryParse($matches[0].Groups["value"].Value, [ref]$value) -or
                $value -le 0) {
            Add-AuditError $ErrorList "quantity-contract" (
                "LootMaterializationPlanner.$($entry.name) 必须恰有一个 Int64 范围内的正整数定义；actual=$($matches.Count)")
            continue
        }
        $result[$entry.property] = $value
    }
    return [pscustomobject]$result
}

function Get-PresetShapeMap([string]$PresetManagerPath, [string[]]$Types,
                            [int]$MaxColumns, [int]$MaxCapacity, $ErrorList) {
    $shapeMap = [ordered]@{}
    if (-not (Test-Path -LiteralPath $PresetManagerPath -PathType Leaf)) {
        Add-AuditError $ErrorList "preset-shape" "PresetManager 真源不存在: $PresetManagerPath"
        return $shapeMap
    }

    $source = Get-Content -LiteralPath $PresetManagerPath -Raw -Encoding UTF8
    foreach ($type in $Types) {
        $presetPattern = '(?s)PresetManager\.registerPreset\("' +
            [regex]::Escape($type) + '"\s*,\s*\{(?<body>.*?)\}\s*\);'
        $presetMatches = [regex]::Matches($source, $presetPattern)
        if ($presetMatches.Count -ne 1) {
            Add-AuditError $ErrorList "preset-shape" (
                "'$type' 必须在 PresetManager 中恰有一个默认 preset；actual=$($presetMatches.Count)")
            continue
        }

        $body = $presetMatches[0].Groups["body"].Value
        $rowMatches = [regex]::Matches($body, '(?m)^\s*row\s*:\s*(?<value>-?[0-9]+(?:\.[0-9]+)?)\s*,?\s*$')
        $colMatches = [regex]::Matches($body, '(?m)^\s*col\s*:\s*(?<value>-?[0-9]+(?:\.[0-9]+)?)\s*,?\s*$')
        if ($rowMatches.Count -ne 1 -or $colMatches.Count -ne 1) {
            Add-AuditError $ErrorList "preset-shape" (
                "'$type' 必须在默认 preset 中恰有一个数值 row/col；row=$($rowMatches.Count), col=$($colMatches.Count)")
            continue
        }

        $row = [double]::Parse(
            $rowMatches[0].Groups["value"].Value,
            [System.Globalization.CultureInfo]::InvariantCulture)
        $col = [double]::Parse(
            $colMatches[0].Groups["value"].Value,
            [System.Globalization.CultureInfo]::InvariantCulture)
        $delivery = if ($row -ne [Math]::Floor($row) -or $col -ne [Math]::Floor($col)) {
            "unsupported"
        } elseif ($row -eq 0 -and $col -eq 0) {
            "direct"
        } elseif ($row -le 0 -or $col -le 0) {
            "unsupported"
        } elseif ($col -le $MaxColumns -and $row * $col -le $MaxCapacity) {
            "grid"
        } else {
            "unsupported"
        }
        $shapeMap[$type] = [pscustomobject]@{
            row = $row
            col = $col
            delivery = $delivery
        }
        if ($delivery -eq "unsupported") {
            Add-AuditError $ErrorList "preset-shape" (
                "'$type' 的默认 shape row=$row col=$col 超出当前 Web/direct 能力；必须显式修正 preset 或能力契约")
        }
    }
    return $shapeMap
}

function Test-ProbabilityText([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    $value = 0.0
    return [double]::TryParse(
        $Text,
        [System.Globalization.NumberStyles]::Float,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [ref]$value) -and $value -gt 0 -and $value -le 100
}

function Get-DropRuleVariants($DropRule) {
    $variants = New-Object System.Collections.Generic.List[object]
    $variantErrors = New-Object System.Collections.Generic.List[string]
    $switchNodes = @($DropRule.SelectNodes("./CaseSwitch"))

    if ($switchNodes.Count -eq 0) {
        $variants.Add([pscustomobject]@{
            node = $DropRule
            activeModes = @($modes)
        })
        return [pscustomobject]@{
            variants = $variants.ToArray()
            errors = $variantErrors.ToArray()
        }
    }

    $elementChildren = @($DropRule.ChildNodes | Where-Object {
        $_.NodeType -eq [System.Xml.XmlNodeType]::Element
    })
    if ($switchNodes.Count -ne 1 -or $elementChildren.Count -ne 1) {
        $variantErrors.Add("掉落物的条件形式必须只包含一个 CaseSwitch")
        return [pscustomobject]@{
            variants = $variants.ToArray()
            errors = $variantErrors.ToArray()
        }
    }

    $switchNode = $switchNodes[0]
    $expression = Get-AttributeValue $switchNode "expression"
    $params = Get-AttributeValue $switchNode "params"
    if ($expression -ne "_root.难度是否达到" -or $params -ne "修罗") {
        $variantErrors.Add("掉落物 CaseSwitch 只允许 expression='_root.难度是否达到' params='修罗'")
        return [pscustomobject]@{
            variants = $variants.ToArray()
            errors = $variantErrors.ToArray()
        }
    }

    $seenShura = $false
    $seenNonShura = $false
    foreach ($caseNode in @($switchNode.SelectNodes("./Case"))) {
        $caseValue = Get-AttributeValue $caseNode "casevalue"
        $normalized = if ($null -eq $caseValue) { "" } else { $caseValue.ToLowerInvariant() }
        if ($normalized -eq "true") {
            if ($seenShura) {
                $variantErrors.Add("掉落物 CaseSwitch 重复声明修罗分支")
                continue
            }
            $seenShura = $true
            $activeModes = @("修罗")
        } elseif ($normalized -eq "false" -or $normalized -eq "default") {
            if ($seenNonShura) {
                $variantErrors.Add("掉落物 CaseSwitch 重复声明非修罗分支")
                continue
            }
            $seenNonShura = $true
            $activeModes = @("非修罗")
        } else {
            $variantErrors.Add("掉落物 CaseSwitch 使用未知 casevalue='$caseValue'")
            continue
        }
        if (@($caseNode.SelectNodes("./CaseSwitch")).Count -gt 0) {
            $variantErrors.Add("掉落物 CaseSwitch 不允许嵌套 CaseSwitch")
            continue
        }
        $variants.Add([pscustomobject]@{
            node = $caseNode
            activeModes = $activeModes
        })
    }

    if (-not $seenShura -or -not $seenNonShura) {
        $variantErrors.Add("掉落物 CaseSwitch 必须同时覆盖修罗与非修罗")
    }
    return [pscustomobject]@{
        variants = $variants.ToArray()
        errors = $variantErrors.ToArray()
    }
}

function Get-ChestDropAudit($ParametersNode, [int]$Capacity,
                            [long]$MaxSafeInteger, [long]$MaxRandomSpan) {
    $messages = New-Object System.Collections.Generic.List[string]
    $dropRules = @(if ($ParametersNode) { $ParametersNode.SelectNodes("./掉落物") })
    if ($dropRules.Count -lt 1) {
        $messages.Add("地图箱必须至少有一条掉落物")
    }
    if ($Capacity -gt 0 -and $dropRules.Count -gt $Capacity) {
        $messages.Add("掉落物规则数 $($dropRules.Count) 超过容器容量 $Capacity")
    }

    $dropVariantCount = 0
    foreach ($dropRule in $dropRules) {
        $resolvedDrop = Get-DropRuleVariants $dropRule
        foreach ($message in $resolvedDrop.errors) { $messages.Add($message) }
        foreach ($variant in $resolvedDrop.variants) {
            $dropVariantCount++
            $variantNode = $variant.node
            $dropName = Get-DirectChildText $variantNode "名字"
            $minNodes = @($variantNode.SelectNodes("./最小数量"))
            $maxNodes = @($variantNode.SelectNodes("./最大数量"))
            $minText = Get-DirectChildText $variantNode "最小数量"
            $maxText = Get-DirectChildText $variantNode "最大数量"
            $probabilityNodes = @($variantNode.SelectNodes("./概率"))
            $totalNodes = @($variantNode.SelectNodes("./总数"))
            $probabilityText = if ($probabilityNodes.Count -eq 1) {
                $probabilityNodes[0].InnerText.Trim()
            } else { "" }
            $totalText = if ($totalNodes.Count -eq 1) {
                $totalNodes[0].InnerText.Trim()
            } else { "" }
            $modeLabel = @($variant.activeModes) -join "/"
            if ([string]::IsNullOrWhiteSpace($dropName)) {
                $messages.Add("[$modeLabel] 掉落物缺少唯一非空名字")
            } elseif ($script:itemCatalogEnabled -and -not $script:itemNames.Contains($dropName)) {
                $messages.Add("[$modeLabel] '$dropName' 不在 data/items/list.xml 权威物品目录")
            }
            [long]$effectiveMin = 1
            if ($minNodes.Count -gt 1 -or $maxNodes.Count -gt 1) {
                $messages.Add("[$modeLabel] '$dropName' 的最小/最大数量不得重复")
            } elseif (($minNodes.Count -eq 0) -ne ($maxNodes.Count -eq 0)) {
                $messages.Add("[$modeLabel] '$dropName' 的最小/最大数量必须同时缺省或同时提供")
            } elseif ($minNodes.Count -eq 1 -and $maxNodes.Count -eq 1) {
                if (-not (Test-PositiveWholeText $minText $MaxSafeInteger) -or
                        -not (Test-PositiveWholeText $maxText $MaxSafeInteger)) {
                    $messages.Add("[$modeLabel] '$dropName' 的显式最小/最大数量必须为正整数且不超过 $MaxSafeInteger")
                } elseif ([long]$minText -gt [long]$maxText) {
                    $messages.Add("[$modeLabel] '$dropName' 最小数量大于最大数量")
                } elseif (([long]$maxText - [long]$minText + 1) -gt $MaxRandomSpan) {
                    $messages.Add("[$modeLabel] '$dropName' 的数量随机跨度不得超过 $MaxRandomSpan")
                } else {
                    $effectiveMin = [long]$minText
                }
            }
            if ($probabilityNodes.Count -gt 1 -or
                    ($probabilityNodes.Count -eq 1 -and
                        -not (Test-ProbabilityText $probabilityText))) {
                $messages.Add("[$modeLabel] '$dropName' 的概率必须为 (0,100] 数字")
            }
            if ($totalNodes.Count -gt 1 -or
                    ($totalNodes.Count -eq 1 -and
                        (-not (Test-PositiveWholeText $totalText $MaxSafeInteger) -or
                            ((Test-PositiveWholeText $totalText $MaxSafeInteger) -and
                                [long]$totalText -lt $effectiveMin)))) {
                $messages.Add("[$modeLabel] '$dropName' 的总数必须为不小于最小数量的正整数")
            }
        }
    }

    return [pscustomobject]@{
        dropRules = $dropRules.Count
        dropVariants = $dropVariantCount
        errors = $messages.ToArray()
    }
}

$errors = New-Object System.Collections.Generic.List[object]
$warnings = New-Object System.Collections.Generic.List[object]
$records = New-Object System.Collections.Generic.List[object]
$commentedByType = New-CountTable $chestTypes
$commentedByFile = [ordered]@{}
$declarationsByType = New-CountTable $chestTypes
$logicalGroups = @{}
$actualInstanceNodes = New-Object System.Collections.Generic.HashSet[string]
$obsoleteRolloutRecords = New-Object System.Collections.Generic.List[object]
$script:itemCatalogEnabled = -not $NoItemCatalog
$script:itemNames = New-Object System.Collections.Generic.HashSet[string]
$itemCatalogFiles = 0
$projectRoot = Split-Path -Parent $PSScriptRoot
$presetManagerPath = Join-Path $projectRoot `
    "scripts\类定义\org\flashNight\arki\unit\UnitComponent\Initializer\ElementComponent\PresetManager.as"
$lootServicePath = Join-Path $projectRoot `
    "scripts\类定义\org\flashNight\arki\item\LootContainerService.as"
$materializationPlannerPath = Join-Path $projectRoot `
    "scripts\类定义\org\flashNight\arki\item\LootMaterializationPlanner.as"
$webGridCapability = Get-WebGridCapability $lootServicePath `
    $materializationPlannerPath $errors
$presetShapes = Get-PresetShapeMap $presetManagerPath $chestTypes `
    $webGridCapability.maxColumns $webGridCapability.maxCapacity $errors
$gridTypes = @($chestTypes | Where-Object {
    $presetShapes.Contains($_) -and $presetShapes[$_].delivery -eq "grid"
})
$directTypes = @($chestTypes | Where-Object {
    $presetShapes.Contains($_) -and $presetShapes[$_].delivery -eq "direct"
})

if ($script:itemCatalogEnabled) {
    $resolvedItemRoot = [System.IO.Path]::GetFullPath($ItemRoot)
    $itemRootPrefix = $resolvedItemRoot.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $itemListPath = Join-Path $resolvedItemRoot "list.xml"
    if (-not (Test-Path -LiteralPath $itemListPath -PathType Leaf)) {
        Add-AuditError $errors "item-catalog" "物品目录入口不存在: $itemListPath"
    } else {
        try {
            [xml]$itemListDocument = Get-Content -LiteralPath $itemListPath -Raw -Encoding UTF8
            $itemEntries = @($itemListDocument.SelectNodes("/root/items"))
            if ($itemEntries.Count -lt 1) {
                Add-AuditError $errors "item-catalog" "data/items/list.xml 没有 items 条目" "list.xml"
            }
            foreach ($entry in $itemEntries) {
                $relativeItemPath = $entry.InnerText.Trim()
                if ([string]::IsNullOrWhiteSpace($relativeItemPath)) {
                    Add-AuditError $errors "item-catalog" "data/items/list.xml 含空 items 条目" "list.xml"
                    continue
                }
                $itemPath = [System.IO.Path]::GetFullPath(
                    (Join-Path $resolvedItemRoot $relativeItemPath))
                if (-not $itemPath.StartsWith(
                        $itemRootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                    Add-AuditError $errors "item-catalog" "items 路径越出 data/items: $relativeItemPath" "list.xml"
                    continue
                }
                if (-not (Test-Path -LiteralPath $itemPath -PathType Leaf)) {
                    Add-AuditError $errors "item-catalog" "items 文件不存在: $relativeItemPath" "list.xml"
                    continue
                }
                try {
                    [xml]$itemDocument = Get-Content -LiteralPath $itemPath -Raw -Encoding UTF8
                    $itemCatalogFiles++
                    foreach ($nameNode in @($itemDocument.SelectNodes("/root/item/name"))) {
                        $itemName = $nameNode.InnerText.Trim()
                        if (-not [string]::IsNullOrWhiteSpace($itemName)) {
                            [void]$script:itemNames.Add($itemName)
                        }
                    }
                } catch {
                    Add-AuditError $errors "item-catalog" $_.Exception.Message $relativeItemPath
                }
            }
        } catch {
            Add-AuditError $errors "item-catalog" $_.Exception.Message "list.xml"
        }
    }
}

if (-not (Test-Path -LiteralPath $StageRoot -PathType Container)) {
    Add-AuditError $errors "input" "关卡目录不存在: $StageRoot"
    $stageFiles = @()
} else {
    $stageFiles = @(Get-ChildItem -LiteralPath $StageRoot -Recurse -File -Filter "*.xml" | Sort-Object FullName)
}

$commentPattern = "<Identifier>\s*(?<name>" + (($chestTypes | ForEach-Object { [regex]::Escape($_) }) -join "|") + ")\s*</Identifier>"

foreach ($file in $stageFiles) {
    $relativeFile = Get-RelativePath $StageRoot $file.FullName
    $doc = New-Object System.Xml.XmlDocument
    $doc.PreserveWhitespace = $true
    $doc.XmlResolver = $null
    try {
        $doc.Load($file.FullName)
    } catch {
        Add-AuditError $errors "parse" $_.Exception.Message $relativeFile
        continue
    }

    $commentCountForFile = 0
    foreach ($comment in @($doc.SelectNodes("//comment()"))) {
        foreach ($match in [regex]::Matches($comment.Value, $commentPattern)) {
            $name = $match.Groups["name"].Value
            $commentedByType[$name]++
            $commentCountForFile++
        }
    }
    if ($commentCountForFile -gt 0) {
        $commentedByFile[$relativeFile] = $commentCountForFile
    }

    $subStages = @($doc.SelectNodes("//SubStage"))
    for ($subOrdinal = 0; $subOrdinal -lt $subStages.Count; $subOrdinal++) {
        $subStage = $subStages[$subOrdinal]
        $subStageId = Get-AttributeValue $subStage "id"
        $subIdentity = if ($null -ne $subStageId -and $subStageId -ne "") { $subStageId } else { "@ordinal:$subOrdinal" }
        $instances = @($subStage.SelectNodes("./Instances/Instance"))

        for ($instanceOrdinal = 0; $instanceOrdinal -lt $instances.Count; $instanceOrdinal++) {
            $instance = $instances[$instanceOrdinal]
            $instanceId = Get-AttributeValue $instance "id"
            $instanceIdentity = if ($null -ne $instanceId -and $instanceId -ne "") { $instanceId } else { "@ordinal:$instanceOrdinal" }
            $actualNodeKey = "$relativeFile|SubStage@$subOrdinal|Instance@$instanceOrdinal"
            $logicalKey = "$relativeFile|SubStage=$subIdentity|Instance=$instanceIdentity"
            $identifierNodes = @($instance.SelectNodes(".//Identifier"))

            foreach ($identifierNode in $identifierNodes) {
                $identifier = $identifierNode.InnerText.Trim()
                if ($chestTypes -notcontains $identifier) { continue }

                [void]$actualInstanceNodes.Add($actualNodeKey)
                $declarationsByType[$identifier]++
                $modeInfo = Get-IdentifierModes $identifierNode $instance
                foreach ($message in $modeInfo.warnings) {
                    $warnings.Add([pscustomobject]@{ kind = "case-switch"; file = $relativeFile; logicalKey = $logicalKey; message = $message })
                }
                foreach ($message in $modeInfo.errors) {
                    Add-AuditError $errors "case-switch" "$logicalKey ($identifier): $message" $relativeFile
                }

                $branchNode = $identifierNode.ParentNode
                $parametersNode = if ($branchNode) { $branchNode.SelectSingleNode("./Parameters") } else { $null }
                $rolloutIdNodes = @(if ($parametersNode) { $parametersNode.SelectNodes("./chestRolloutId") })
                $profileNodes = @(if ($parametersNode) { $parametersNode.SelectNodes("./lootFlowProfile") })
                $policyNodes = @(if ($parametersNode) { $parametersNode.SelectNodes("./unlockPolicy") })
                $rowOverrideNodes = @(if ($parametersNode) { $parametersNode.SelectNodes("./row") })
                $colOverrideNodes = @(if ($parametersNode) { $parametersNode.SelectNodes("./col") })
                $hasAnyRolloutField = $rolloutIdNodes.Count -gt 0 -or $profileNodes.Count -gt 0 -or $policyNodes.Count -gt 0
                $hasShapeOverride = $rowOverrideNodes.Count -gt 0 -or $colOverrideNodes.Count -gt 0
                $presetShape = $presetShapes[$identifier]
                $presetCapacity = if ($gridTypes -contains $identifier) {
                    [int]($presetShape.row * $presetShape.col)
                } else {
                    0
                }
                $dropAudit = Get-ChestDropAudit $parametersNode $presetCapacity `
                    $webGridCapability.maxSafeInteger $webGridCapability.maxRandomSpan
                $dropErrorKind = if ($gridTypes -contains $identifier) { "grid" } else { "direct" }
                foreach ($message in $dropAudit.errors) {
                    Add-AuditError $errors $dropErrorKind "$logicalKey ($identifier): $message" $relativeFile
                }

                if ($hasAnyRolloutField) {
                    Add-AuditError $errors "obsolete-rollout-marker" "$logicalKey ($identifier): chestRolloutId / lootFlowProfile / unlockPolicy 已停用；正网格由服务统一路由" $relativeFile
                    $obsoleteRolloutRecords.Add([pscustomobject]@{
                        file = $relativeFile
                        logicalKey = $logicalKey
                        identifier = $identifier
                    })
                }
                if ($hasShapeOverride) {
                    Add-AuditError $errors "shape-override" "$logicalKey ($identifier): stage Parameters 不得覆盖 row/col；静态分类以六箱 preset 的权威 shape 为准" $relativeFile
                }

                $record = [pscustomobject]@{
                    file = $relativeFile
                    subStageId = $subStageId
                    subStageOrdinal = $subOrdinal
                    instanceId = $instanceId
                    instanceOrdinal = $instanceOrdinal
                    actualNodeKey = $actualNodeKey
                    logicalKey = $logicalKey
                    identifier = $identifier
                    delivery = if ($gridTypes -contains $identifier) {
                        "grid"
                    } elseif ($directTypes -contains $identifier) {
                        "direct"
                    } else {
                        "unknown"
                    }
                    activeModes = @($modeInfo.activeModes)
                    caseSwitches = @($modeInfo.switches)
                    hasObsoleteRolloutMarker = $hasAnyRolloutField
                    hasShapeOverride = $hasShapeOverride
                }
                $records.Add($record)

                if (-not $logicalGroups.ContainsKey($logicalKey)) {
                    $logicalGroups[$logicalKey] = New-Object System.Collections.Generic.List[object]
                }
                $logicalGroups[$logicalKey].Add($record)
            }
        }
    }
}

$modeSummary = [ordered]@{}
foreach ($mode in $modes) {
    $byType = New-CountTable $chestTypes
    $logicalCount = 0
    $gridCount = 0
    $directCount = 0
    $ambiguous = New-Object System.Collections.Generic.List[object]

    foreach ($logicalKey in @($logicalGroups.Keys | Sort-Object)) {
        $activeRecords = @($logicalGroups[$logicalKey] | Where-Object { $_.activeModes -contains $mode })
        $activeIdentifiers = @($activeRecords | ForEach-Object { $_.identifier } | Sort-Object -Unique)
        if ($activeIdentifiers.Count -eq 0) { continue }

        $logicalCount++
        $deliveries = @($activeRecords | ForEach-Object { $_.delivery } | Sort-Object -Unique)
        if ($deliveries.Count -eq 1) {
            if ($deliveries[0] -eq "grid") { $gridCount++ } else { $directCount++ }
        } else {
            $ambiguous.Add([pscustomobject]@{ logicalKey = $logicalKey; identifiers = $activeIdentifiers; deliveries = $deliveries })
            Add-AuditError $errors "classification" "$logicalKey 在 $mode 口径同时可能为 grid/direct: $($activeIdentifiers -join ', ')"
        }

        if ($activeIdentifiers.Count -eq 1) {
            $byType[$activeIdentifiers[0]]++
        } else {
            $ambiguous.Add([pscustomobject]@{ logicalKey = $logicalKey; identifiers = $activeIdentifiers; deliveries = $deliveries })
            Add-AuditError $errors "classification" "$logicalKey 在 $mode 口径存在多个候选 Identifier: $($activeIdentifiers -join ', ')"
        }
    }

    $modeSummary[$mode] = [pscustomobject]@{
        logicalIdentities = $logicalCount
        grid = $gridCount
        direct = $directCount
        byType = [pscustomobject]$byType
        ambiguous = $ambiguous.ToArray()
    }
}

$sameIdentifierDedupes = New-Object System.Collections.Generic.List[object]
$identityCollapses = New-Object System.Collections.Generic.List[object]
foreach ($logicalKey in @($logicalGroups.Keys | Sort-Object)) {
    $groupRecords = @($logicalGroups[$logicalKey].ToArray())
    $nodeKeys = @($groupRecords | ForEach-Object { $_.actualNodeKey } | Sort-Object -Unique)
    if ($nodeKeys.Count -gt 1) {
        $identityCollapses.Add([pscustomobject]@{
            logicalKey = $logicalKey
            actualInstanceNodes = $nodeKeys
            identifiers = @($groupRecords | ForEach-Object { $_.identifier } | Sort-Object -Unique)
        })
    }

    foreach ($identifierGroup in @($groupRecords | Group-Object identifier)) {
        if ($identifierGroup.Count -gt 1) {
            $sameIdentifierDedupes.Add([pscustomobject]@{
                logicalKey = $logicalKey
                identifier = $identifierGroup.Name
                declarations = $identifierGroup.Count
                actualInstanceNodes = @($identifierGroup.Group | ForEach-Object { $_.actualNodeKey } | Sort-Object -Unique)
            })
        }
    }
}

$branchDeclarations = $records.Count
$instanceNodes = $actualInstanceNodes.Count
$logicalIdentities = $logicalGroups.Count
$commentedIdentifierMentions = 0
foreach ($type in $chestTypes) { $commentedIdentifierMentions += $commentedByType[$type] }
$caseSwitchBranchDeclarations = @($records | Where-Object { $_.caseSwitches.Count -gt 0 }).Count
$autoGridRecords = @($records | Where-Object { $_.delivery -eq "grid" })
$autoGridModes = [ordered]@{}
foreach ($mode in $modes) {
    $autoGridModes[$mode] = @($autoGridRecords | Where-Object {
        $_.activeModes -contains $mode
    }).Count
}
$rockParkFile = "基地车库/摇滚公园.xml"
$rockParkActiveDeclarations = @($records | Where-Object { $_.file -eq $rockParkFile }).Count
$rockParkCommentedDeclarations = if ($commentedByFile.Contains($rockParkFile)) { $commentedByFile[$rockParkFile] } else { 0 }

$result = [ordered]@{
    stageRoot = [System.IO.Path]::GetFullPath($StageRoot)
    presetManagerPath = [System.IO.Path]::GetFullPath($presetManagerPath)
    lootServicePath = [System.IO.Path]::GetFullPath($lootServicePath)
    webGridCapability = $webGridCapability
    presetShapes = [pscustomobject]$presetShapes
    xmlFiles = $stageFiles.Count
    branchDeclarations = $branchDeclarations
    instanceNodes = $instanceNodes
    logicalIdentities = $logicalIdentities
    declarationsByType = [pscustomobject]$declarationsByType
    modes = [pscustomobject]$modeSummary
    caseSwitchBranchDeclarations = $caseSwitchBranchDeclarations
    sameIdentifierDedupes = $sameIdentifierDedupes.ToArray()
    identityCollapses = $identityCollapses.ToArray()
    commentedIdentifierMentionsExcluded = $commentedIdentifierMentions
    commentedByType = [pscustomobject]$commentedByType
    commentedByFile = [pscustomobject]$commentedByFile
    chestRecords = $records.ToArray()
    rockPark = [pscustomobject]@{
        activeDeclarations = $rockParkActiveDeclarations
        commentedDeclarationsExcluded = $rockParkCommentedDeclarations
    }
    obsoleteLootRolloutMarkers = $obsoleteRolloutRecords.ToArray()
    autoRoutedGridDeclarations = $autoGridRecords
    autoRoutedGridModes = [pscustomobject]$autoGridModes
    itemCatalog = [pscustomobject]@{
        enabled = $script:itemCatalogEnabled
        referencedFiles = $itemCatalogFiles
        uniqueNames = $script:itemNames.Count
    }
    warnings = $warnings.ToArray()
    errors = $errors.ToArray()
}

if ($Json) {
    $result | ConvertTo-Json -Depth 10
} else {
    Write-Output ("stage chest audit: declarations={0}, instanceNodes={1}, logicalIdentities={2}" -f $branchDeclarations, $instanceNodes, $logicalIdentities)
    foreach ($mode in $modes) {
        $summary = $modeSummary[$mode]
        Write-Output ("  {0}: logicalIdentities={1}, grid={2}, direct={3}" -f $mode, $summary.logicalIdentities, $summary.grid, $summary.direct)
    }
    Write-Output ("  CaseSwitch branch declarations={0}; same-Identifier dedupes={1}; identity collapses={2}" -f $caseSwitchBranchDeclarations, $sameIdentifierDedupes.Count, $identityCollapses.Count)
    Write-Output ("  XML comments excluded={0}; 摇滚公园 active={1}, commented/excluded={2}" -f $commentedIdentifierMentions, $rockParkActiveDeclarations, $rockParkCommentedDeclarations)
    Write-Output ("  Web auto-routed grid declarations={0}; obsolete rollout markers={1}" -f $autoGridRecords.Count, $obsoleteRolloutRecords.Count)
    foreach ($warning in $warnings) {
        Write-Output ("[WARN] {0}: {1}" -f $warning.file, $warning.message)
    }
    foreach ($auditError in $errors) {
        Write-Output ("[ERROR] {0} {1}: {2}" -f $auditError.kind, $auditError.file, $auditError.message)
    }
}

if ($errors.Count -gt 0) { exit 1 }
exit 0
