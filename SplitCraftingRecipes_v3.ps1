# UTF-8 Crafting Recipe Splitter v3

param([string]$DataPath = ".\data")

# Force UTF-8 BOM-less encoding everywhere
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.Console]::OutputEncoding = $utf8NoBom
[System.Console]::InputEncoding = $utf8NoBom

Write-Host "=== UTF-8 Crafting Recipe Categorization v3 ===" -ForegroundColor Green

# 1. Load item data with explicit UTF-8
$itemMap = @{}
$xmlFiles = Get-ChildItem -Path "$DataPath\items" -Filter "*.xml"

foreach ($xmlFile in $xmlFiles) {
    Write-Host "Processing: $($xmlFile.Name)" -ForegroundColor Cyan
    try {
        # Read with UTF-8 BOM-less
        $xmlText = [System.IO.File]::ReadAllText($xmlFile.FullName, $utf8NoBom)
        [xml]$xmlContent = $xmlText
        
        foreach ($item in $xmlContent.root.item) {
            if ($item.name) {
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
                
                $itemMap[[string]$item.name] = @{
                    type = [string]$item.type
                    use = [string]$item.use
                    level = $itemLevel
                    file = [string]$xmlFile.Name
                }
            }
        }
    }
    catch {
        Write-Warning "Error: $($_.Exception.Message)"
    }
}

Write-Host "Loaded $($itemMap.Count) items" -ForegroundColor Yellow

# 2. Find default crafting file
$craftingDir = "$DataPath\crafting"
$jsonFiles = Get-ChildItem -Path $craftingDir -Filter "*.json" | Where-Object { $_.Length -lt 50000 -and $_.Name -notlike "*backup*" }
$defaultFile = $jsonFiles | Sort-Object Length -Descending | Select-Object -First 1

Write-Host "Using: $($defaultFile.Name)" -ForegroundColor Green

# Read with UTF-8 BOM-less
$jsonText = [System.IO.File]::ReadAllText($defaultFile.FullName, $utf8NoBom)
$craftingData = $jsonText | ConvertFrom-Json

Write-Host "Recipes: $($craftingData.Count)" -ForegroundColor Yellow

# 3. Category arrays
$weapons = @()
$accessories = @()  
$basicArmor = @()
$advancedArmor = @()
$others = @()

# Define UTF-8 byte patterns to avoid encoding issues
$weaponBytes = [System.Text.Encoding]::UTF8.GetBytes("武器")
$armorBytes = [System.Text.Encoding]::UTF8.GetBytes("防具") 
$neckBytes = [System.Text.Encoding]::UTF8.GetBytes("颈部装备")

# 4. Categorize
foreach ($recipe in $craftingData) {
    $itemName = [string]$recipe.name
    
    if ($itemMap.ContainsKey($itemName)) {
        $itemInfo = $itemMap[$itemName]
        $type = $itemInfo.type
        $use = $itemInfo.use
        $level = $itemInfo.level
        $file = $itemInfo.file
        
        # Convert to bytes for comparison
        $typeBytes = [System.Text.Encoding]::UTF8.GetBytes($type)
        $useBytes = [System.Text.Encoding]::UTF8.GetBytes($use)
        $fileBytes = [System.Text.Encoding]::UTF8.GetBytes($file)
        
        # Byte-level comparison
        if ([System.Linq.Enumerable]::SequenceEqual($typeBytes, $weaponBytes)) {
            $weapons += $recipe
        }
        elseif ([System.Linq.Enumerable]::SequenceEqual($useBytes, $neckBytes) -or 
                ([System.Text.Encoding]::UTF8.GetString($fileBytes) -like "*颈部装备*")) {
            $accessories += $recipe
        }
        elseif ([System.Linq.Enumerable]::SequenceEqual($typeBytes, $armorBytes)) {
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

# 6. Save with UTF-8 BOM-less
$outputDir = $craftingDir
if ($weapons.Count -gt 0) {
    $json = $weapons | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText("$outputDir\武器.json", $json, $utf8NoBom)
    Write-Host "Created 武器.json" -ForegroundColor Cyan
}

if ($accessories.Count -gt 0) {
    $json = $accessories | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText("$outputDir\饰品.json", $json, $utf8NoBom)
    Write-Host "Created 饰品.json" -ForegroundColor Cyan
}

if ($basicArmor.Count -gt 0) {
    $json = $basicArmor | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText("$outputDir\基础防具.json", $json, $utf8NoBom)
    Write-Host "Created 基础防具.json" -ForegroundColor Cyan
}

if ($advancedArmor.Count -gt 0) {
    $json = $advancedArmor | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText("$outputDir\进阶防具.json", $json, $utf8NoBom)
    Write-Host "Created 进阶防具.json" -ForegroundColor Cyan
}

if ($others.Count -gt 0) {
    $json = $others | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText("$outputDir\其他.json", $json, $utf8NoBom)
    Write-Host "Created 其他.json" -ForegroundColor Cyan
}

Write-Host "`nCompleted!" -ForegroundColor Green