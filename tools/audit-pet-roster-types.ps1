param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"

$validTypes = @("partner", "pet", "mechanical")
$enemyDir = Join-Path $ProjectRoot "data\enemy_properties"
$enemyListPath = Join-Path $enemyDir "list.xml"
$petsPath = Join-Path $ProjectRoot "data\merc\pets.xml"
$errors = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
$derivedByIdentifier = @{}

function Load-Xml([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        $errors.Add("缺少引用文件: $Path")
        return $null
    }
    try {
        $doc = New-Object System.Xml.XmlDocument
        $doc.PreserveWhitespace = $true
        $doc.Load($Path)
        return $doc
    } catch {
        $errors.Add("XML 损坏: $Path ($($_.Exception.Message))")
        return $null
    }
}

$listDoc = Load-Xml $enemyListPath
if ($listDoc) {
    foreach ($item in $listDoc.SelectNodes("/root/items")) {
        $fileName = $item.InnerText.Trim()
        $enemyDoc = Load-Xml (Join-Path $enemyDir $fileName)
        if (-not $enemyDoc) { continue }

        foreach ($enemy in $enemyDoc.DocumentElement.ChildNodes) {
            if ($enemy.NodeType -ne [System.Xml.XmlNodeType]::Element -or $enemy.Name -eq "默认") { continue }
            $resistance = $enemy.SelectSingleNode("魔法抗性")
            $hasMechanical = $resistance -and $null -ne $resistance.SelectSingleNode("机械")
            $hasHuman = $resistance -and $null -ne $resistance.SelectSingleNode("人类")
            $derived = if ($hasMechanical) { "mechanical" } elseif ($hasHuman) { "partner" } else { "pet" }
            if ($derivedByIdentifier.ContainsKey($enemy.Name) -and $derivedByIdentifier[$enemy.Name] -ne $derived) {
                $existing = $derivedByIdentifier[$enemy.Name]
                $resolved = if ($existing -eq "mechanical" -or $derived -eq "mechanical") {
                    "mechanical"
                } elseif ($existing -eq "partner" -or $derived -eq "partner") {
                    "partner"
                } else {
                    "pet"
                }
                $warnings.Add("敌人分类冲突: $($enemy.Name) 同时推导为 $existing / $derived，按机械、人类、其他优先级归 $resolved")
                $derivedByIdentifier[$enemy.Name] = $resolved
            } else {
                $derivedByIdentifier[$enemy.Name] = $derived
            }
        }
    }
}

$counts = @{ partner = 0; pet = 0; mechanical = 0 }
$matched = 0
$unmatched = 0
$petsDoc = Load-Xml $petsPath
if ($petsDoc) {
    foreach ($pet in $petsDoc.SelectNodes("/Pets/Pet")) {
        $id = $pet.SelectSingleNode("id").InnerText
        $name = $pet.SelectSingleNode("Name").InnerText
        $identifier = $pet.SelectSingleNode("Identifier").InnerText
        $rosterNode = $pet.SelectSingleNode("RosterType")
        if (-not $rosterNode) {
            $errors.Add("Pet $id ($name) 缺少 RosterType")
            continue
        }

        $rosterType = $rosterNode.InnerText.Trim()
        if ($validTypes -notcontains $rosterType) {
            $errors.Add("Pet $id ($name) RosterType 非法: '$rosterType'")
            continue
        }
        $counts[$rosterType]++

        $derived = "pet"
        if ($derivedByIdentifier.ContainsKey($identifier)) {
            $derived = $derivedByIdentifier[$identifier]
            $matched++
        } else {
            $unmatched++
            $warnings.Add("Pet $id ($name) Identifier 未匹配敌人属性: $identifier；推导默认 pet")
        }
        if ($rosterType -ne $derived) {
            $warnings.Add("Pet $id ($name) 显式分类 $rosterType 与推导分类 $derived 不同")
        }
    }
}

foreach ($warning in $warnings) { Write-Host "[WARN] $warning" -ForegroundColor Yellow }
foreach ($error in $errors) { Write-Host "[ERROR] $error" -ForegroundColor Red }
Write-Host ("[PetRosterAudit] partner={0} pet={1} mechanical={2} matched={3} unmatched={4} warnings={5} errors={6}" -f `
    $counts.partner, $counts.pet, $counts.mechanical, $matched, $unmatched, $warnings.Count, $errors.Count)

if ($errors.Count -gt 0) { exit 1 }
