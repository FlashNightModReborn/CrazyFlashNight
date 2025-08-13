# Simple Crafting Recipe Splitter Script v2
# Split default.json into 5 categories using simple string matching

param(
    [string]$DataPath = ".\data"
)

# Force UTF-8 encoding for all operations
$PSDefaultParameterValues['*:Encoding'] = 'utf8'
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

Write-Host "=== Crafting Recipe Categorization v2 ===" -ForegroundColor Green

# 1. Build item information map
$itemMap = @{}
$xmlFiles = Get-ChildItem -Path "$DataPath\items" -Filter "*.xml"

foreach ($xmlFile in $xmlFiles) {
    Write-Host "Processing: $($xmlFile.Name)" -ForegroundColor Cyan
    try {
        [xml]$xmlContent = Get-Content $xmlFile.FullName -Encoding UTF8
        
        foreach ($item in $xmlContent.root.item) {
            if ($item.name) {
                # Determine level
                $itemLevel = 0
                if ($item.level) {
                    try { $itemLevel = [int]$item.level } catch { $itemLevel = 0 }
                } elseif ($xmlFile.Name -like "*0-19*") {
                    $itemLevel = 15
                } elseif ($xmlFile.Name -like "*20-39*") {
                    $itemLevel = 30  
                } elseif ($xmlFile.Name -like "*40*") {
                    $itemLevel = 50
                }
                
                $itemMap[$item.name] = @{
                    type = [string]$item.type
                    use = [string]$item.use
                    level = $itemLevel
                    file = $xmlFile.Name
                }
            }
        }
    }
    catch {
        Write-Warning "Error processing $($xmlFile.Name): $($_.Exception.Message)"
    }
}

Write-Host "Loaded $($itemMap.Count) items" -ForegroundColor Yellow

# 2. Find the original default crafting file using wildcards
$craftingDir = "$DataPath\crafting"
$allJsonFiles = Get-ChildItem -Path $craftingDir -Filter "*.json" | Where-Object { $_.Length -lt 50000 }
$defaultFile = $allJsonFiles | Sort-Object Length -Descending | Select-Object -First 1

if (-not $defaultFile) {
    Write-Error "Cannot find original default crafting file"
    exit 1
}

Write-Host "Using file: $($defaultFile.Name)" -ForegroundColor Green
$craftingData = Get-Content $defaultFile.FullName -Encoding UTF8 | ConvertFrom-Json
Write-Host "Found $($craftingData.Count) recipes" -ForegroundColor Yellow

# 3. Category containers
$weapons = @()
$accessories = @()
$basicArmor = @()
$advancedArmor = @()
$others = @()

# 4. Categorize each recipe
foreach ($recipe in $craftingData) {
    $itemName = $recipe.name
    
    if ($itemMap.ContainsKey($itemName)) {
        $itemInfo = $itemMap[$itemName]
        $type = $itemInfo.type
        $use = $itemInfo.use
        $level = $itemInfo.level
        $file = $itemInfo.file
        
# Simple text matching with UTF-8 string comparison
        if ($type -eq "武器") {
            $weapons += $recipe
        }
        elseif ($use -eq "颈部装备" -or $file -like "*颈部装备*") {
            $accessories += $recipe
        }
        elseif ($type -eq "防具") {
            if ($level -le 30) {
                $basicArmor += $recipe
            } else {
                $advancedArmor += $recipe
            }
        }
        else {
            $others += $recipe
        }
    }
    else {
        $others += $recipe
    }
}

# 5. Results
Write-Host "`n=== RESULTS ===" -ForegroundColor Green
Write-Host "Weapons: $($weapons.Count)" -ForegroundColor White
Write-Host "Accessories: $($accessories.Count)" -ForegroundColor White  
Write-Host "Basic Armor: $($basicArmor.Count)" -ForegroundColor White
Write-Host "Advanced Armor: $($advancedArmor.Count)" -ForegroundColor White
Write-Host "Others: $($others.Count)" -ForegroundColor White

# 6. Save files with English names to avoid encoding issues
if ($weapons.Count -gt 0) {
    $weaponsJson = $weapons | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText("$craftingDir\weapons.json", $weaponsJson, [System.Text.Encoding]::UTF8)
    Write-Host "Created weapons.json" -ForegroundColor Cyan
}

if ($accessories.Count -gt 0) {
    $accessoriesJson = $accessories | ConvertTo-Json -Depth 10  
    [System.IO.File]::WriteAllText("$craftingDir\accessories.json", $accessoriesJson, [System.Text.Encoding]::UTF8)
    Write-Host "Created accessories.json" -ForegroundColor Cyan
}

if ($basicArmor.Count -gt 0) {
    $basicArmorJson = $basicArmor | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText("$craftingDir\basic_armor.json", $basicArmorJson, [System.Text.Encoding]::UTF8)  
    Write-Host "Created basic_armor.json" -ForegroundColor Cyan
}

if ($advancedArmor.Count -gt 0) {
    $advancedArmorJson = $advancedArmor | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText("$craftingDir\advanced_armor.json", $advancedArmorJson, [System.Text.Encoding]::UTF8)
    Write-Host "Created advanced_armor.json" -ForegroundColor Cyan  
}

if ($others.Count -gt 0) {
    $othersJson = $others | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText("$craftingDir\others.json", $othersJson, [System.Text.Encoding]::UTF8)
    Write-Host "Created others.json" -ForegroundColor Cyan
}

# 7. Show examples
Write-Host "`n=== EXAMPLES ===" -ForegroundColor Green
if ($weapons.Count -gt 0) {
    Write-Host "Weapons (first 3): $($weapons[0..2] | ForEach-Object { $_.name } | Join-String -Separator ', ')" -ForegroundColor White
}
if ($accessories.Count -gt 0) {
    Write-Host "Accessories (first 3): $($accessories[0..2] | ForEach-Object { $_.name } | Join-String -Separator ', ')" -ForegroundColor White
}
if ($basicArmor.Count -gt 0) {
    Write-Host "Basic Armor (first 3): $($basicArmor[0..2] | ForEach-Object { $_.name } | Join-String -Separator ', ')" -ForegroundColor White
}
if ($advancedArmor.Count -gt 0) {
    Write-Host "Advanced Armor (first 3): $($advancedArmor[0..2] | ForEach-Object { $_.name } | Join-String -Separator ', ')" -ForegroundColor White
}

Write-Host "`nCompleted!" -ForegroundColor Green