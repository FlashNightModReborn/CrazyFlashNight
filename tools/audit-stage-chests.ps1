param(
    [string]$StageRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) "data\stages"),
    [switch]$Json,
    [switch]$NoBaseline
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
$gridTypes = @("装备箱", "保险柜", "生存箱")
$directTypes = @("资源箱", "隐藏资源点", "纸箱")
$modes = @("修罗", "非修罗")
$rolloutProfile = "web-loot-v1"
$rolloutPolicies = @("skip")
$gridCapacities = @{
    "装备箱" = 8
    "保险柜" = 32
    "生存箱" = 16
}

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

function Test-PositiveWholeText([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    $value = 0
    return [int]::TryParse($Text, [ref]$value) -and $value -gt 0
}

$errors = New-Object System.Collections.Generic.List[object]
$warnings = New-Object System.Collections.Generic.List[object]
$records = New-Object System.Collections.Generic.List[object]
$commentedByType = New-CountTable $chestTypes
$commentedByFile = [ordered]@{}
$declarationsByType = New-CountTable $chestTypes
$logicalGroups = @{}
$actualInstanceNodes = New-Object System.Collections.Generic.HashSet[string]
$rolloutIds = @{}
$rolloutRecords = New-Object System.Collections.Generic.List[object]

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
                $hasAnyRolloutField = $rolloutIdNodes.Count -gt 0 -or $profileNodes.Count -gt 0 -or $policyNodes.Count -gt 0
                $rolloutId = ""
                $profile = ""
                $policy = ""

                if ($hasAnyRolloutField) {
                    if ($rolloutIdNodes.Count -ne 1 -or $profileNodes.Count -ne 1 -or $policyNodes.Count -ne 1) {
                        Add-AuditError $errors "rollout" "$logicalKey ($identifier): rollout 必须恰有一个 chestRolloutId / lootFlowProfile / unlockPolicy" $relativeFile
                    } else {
                        $rolloutId = $rolloutIdNodes[0].InnerText.Trim()
                        $profile = $profileNodes[0].InnerText.Trim()
                        $policy = $policyNodes[0].InnerText.Trim()

                        if ($rolloutId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') {
                            Add-AuditError $errors "rollout" "$logicalKey ($identifier): 非法 chestRolloutId='$rolloutId'" $relativeFile
                        } elseif ($rolloutIds.ContainsKey($rolloutId)) {
                            Add-AuditError $errors "rollout" "$logicalKey ($identifier): chestRolloutId='$rolloutId' 与 $($rolloutIds[$rolloutId]) 重复" $relativeFile
                        } else {
                            $rolloutIds[$rolloutId] = $logicalKey
                        }
                        if ($profile -ne $rolloutProfile) {
                            Add-AuditError $errors "rollout" "$logicalKey ($identifier): lootFlowProfile 必须为 '$rolloutProfile'，实际 '$profile'" $relativeFile
                        }
                        if ($rolloutPolicies -notcontains $policy) {
                            Add-AuditError $errors "rollout" "$logicalKey ($identifier): unlockPolicy='$policy' 不在白名单" $relativeFile
                        }
                        if ($gridTypes -notcontains $identifier) {
                            Add-AuditError $errors "rollout" "$logicalKey ($identifier): direct 型箱子禁止进入 Web loot rollout" $relativeFile
                        }
                        if (@($parametersNode.SelectNodes("./chestS0FixtureId | ./chestS0As2GateId")).Count -gt 0) {
                            Add-AuditError $errors "rollout" "$logicalKey ($identifier): S0 开发 marker 与生产 loot rollout 禁止共存" $relativeFile
                        }

                        $dropRules = @($parametersNode.SelectNodes("./掉落物"))
                        $capacity = if ($gridCapacities.ContainsKey($identifier)) { [int]$gridCapacities[$identifier] } else { 0 }
                        if ($dropRules.Count -lt 1) {
                            Add-AuditError $errors "rollout" "$logicalKey ($identifier): rollout 箱必须至少有一条掉落物" $relativeFile
                        }
                        if ($capacity -le 0 -or $dropRules.Count -gt $capacity) {
                            Add-AuditError $errors "rollout" "$logicalKey ($identifier): 掉落规则数 $($dropRules.Count) 超过容量 $capacity" $relativeFile
                        }
                        foreach ($dropRule in $dropRules) {
                            $dropName = Get-DirectChildText $dropRule "名字"
                            $minText = Get-DirectChildText $dropRule "最小数量"
                            $maxText = Get-DirectChildText $dropRule "最大数量"
                            if ([string]::IsNullOrWhiteSpace($dropName)) {
                                Add-AuditError $errors "rollout" "$logicalKey ($identifier): 掉落物缺少唯一非空名字" $relativeFile
                            }
                            if (-not (Test-PositiveWholeText $minText) -or -not (Test-PositiveWholeText $maxText)) {
                                Add-AuditError $errors "rollout" "$logicalKey ($identifier): '$dropName' 的最小/最大数量必须为正整数" $relativeFile
                            } elseif ([int]$minText -gt [int]$maxText) {
                                Add-AuditError $errors "rollout" "$logicalKey ($identifier): '$dropName' 最小数量大于最大数量" $relativeFile
                            }
                        }

                        $rolloutRecords.Add([pscustomobject]@{
                            rolloutId = $rolloutId
                            profile = $profile
                            unlockPolicy = $policy
                            file = $relativeFile
                            logicalKey = $logicalKey
                            identifier = $identifier
                            activeModes = @($modeInfo.activeModes)
                            capacity = $capacity
                            dropRules = $dropRules.Count
                        })
                    }
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
$rockParkFile = "基地车库/摇滚公园.xml"
$rockParkActiveDeclarations = @($records | Where-Object { $_.file -eq $rockParkFile }).Count
$rockParkCommentedDeclarations = if ($commentedByFile.Contains($rockParkFile)) { $commentedByFile[$rockParkFile] } else { 0 }

if (-not $NoBaseline) {
    $baselineChecks = @(
        @{ label = "branchDeclarations"; actual = $branchDeclarations; expected = 28 },
        @{ label = "instanceNodes"; actual = $instanceNodes; expected = 27 },
        @{ label = "logicalIdentities"; actual = $logicalIdentities; expected = 26 },
        @{ label = "identityCollapses"; actual = $identityCollapses.Count; expected = 1 },
        @{ label = "caseSwitchBranchDeclarations"; actual = $caseSwitchBranchDeclarations; expected = 2 },
        @{ label = "declarationsByType.装备箱"; actual = $declarationsByType["装备箱"]; expected = 5 },
        @{ label = "declarationsByType.保险柜"; actual = $declarationsByType["保险柜"]; expected = 3 },
        @{ label = "declarationsByType.生存箱"; actual = $declarationsByType["生存箱"]; expected = 1 },
        @{ label = "declarationsByType.资源箱"; actual = $declarationsByType["资源箱"]; expected = 12 },
        @{ label = "declarationsByType.隐藏资源点"; actual = $declarationsByType["隐藏资源点"]; expected = 4 },
        @{ label = "declarationsByType.纸箱"; actual = $declarationsByType["纸箱"]; expected = 3 },
        @{ label = "修罗.logicalIdentities"; actual = $modeSummary["修罗"].logicalIdentities; expected = 26 },
        @{ label = "修罗.grid"; actual = $modeSummary["修罗"].grid; expected = 9 },
        @{ label = "修罗.direct"; actual = $modeSummary["修罗"].direct; expected = 17 },
        @{ label = "非修罗.logicalIdentities"; actual = $modeSummary["非修罗"].logicalIdentities; expected = 26 },
        @{ label = "非修罗.grid"; actual = $modeSummary["非修罗"].grid; expected = 8 },
        @{ label = "非修罗.direct"; actual = $modeSummary["非修罗"].direct; expected = 18 },
        @{ label = "摇滚公园.activeDeclarations"; actual = $rockParkActiveDeclarations; expected = 1 },
        @{ label = "摇滚公园.commentedDeclarationsExcluded"; actual = $rockParkCommentedDeclarations; expected = 8 },
        @{ label = "lootRollouts"; actual = $rolloutRecords.Count; expected = 1 }
    )
    foreach ($check in $baselineChecks) {
        if ($check.actual -ne $check.expected) {
            Add-AuditError $errors "baseline" "$($check.label): expected=$($check.expected), actual=$($check.actual)"
        }
    }
}

$result = [ordered]@{
    stageRoot = [System.IO.Path]::GetFullPath($StageRoot)
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
    rockPark = [pscustomobject]@{
        activeDeclarations = $rockParkActiveDeclarations
        commentedDeclarationsExcluded = $rockParkCommentedDeclarations
    }
    lootRollouts = $rolloutRecords.ToArray()
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
    Write-Output ("  Web loot rollouts={0}" -f $rolloutRecords.Count)
    foreach ($warning in $warnings) {
        Write-Output ("[WARN] {0}: {1}" -f $warning.file, $warning.message)
    }
    foreach ($auditError in $errors) {
        Write-Output ("[ERROR] {0} {1}: {2}" -f $auditError.kind, $auditError.file, $auditError.message)
    }
}

if ($errors.Count -gt 0) { exit 1 }
exit 0
