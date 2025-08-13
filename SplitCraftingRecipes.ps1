# Crafting Recipe Splitter Script
# Split default.json into 5 categories: Weapons, Accessories, Basic Armor, Advanced Armor, Others

param(
    [string]$DataPath = ".\data"
)

# Set encoding for proper Chinese character handling
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "Starting crafting recipe categorization..." -ForegroundColor Green

# 1. Read all item XML files and build item information mapping
$itemMap = @{}

# Get all XML files
$xmlFiles = Get-ChildItem -Path "$DataPath\items" -Filter "*.xml"
Write-Host "Found $($xmlFiles.Count) item XML files" -ForegroundColor Yellow

foreach ($xmlFile in $xmlFiles) {
    Write-Host "Processing file: $($xmlFile.Name)" -ForegroundColor Cyan
    try {
        [xml]$xmlContent = Get-Content $xmlFile.FullName -Encoding UTF8
        
        foreach ($item in $xmlContent.root.item) {
            if ($item.name) {
                # Determine level based on file name for armor, or item level for weapons
                $itemLevel = 0
                if ($item.level) {
                    try { $itemLevel = [int]$item.level } catch { $itemLevel = 0 }
                } elseif ($xmlFile.Name -match "防具.*0-19") {
                    $itemLevel = 15  # Average of 0-19
                } elseif ($xmlFile.Name -match "防具.*20-39") {
                    $itemLevel = 30  # Average of 20-39
                } elseif ($xmlFile.Name -match "防具.*40") {
                    $itemLevel = 50  # Represents 40+
                }
                
                $itemInfo = @{
                    name = $item.name
                    type = $item.type
                    use = $item.use
                    level = $itemLevel
                    file = $xmlFile.Name
                }
                
                # Use item name as key
                $itemMap[$item.name] = $itemInfo
            }
        }
    }
    catch {
        Write-Warning "Error processing file $($xmlFile.Name): $($_.Exception.Message)"
    }
}

Write-Host "Loaded $($itemMap.Count) item information entries" -ForegroundColor Yellow

# 2. Read crafting table JSON - only process the default file
$craftingDir = "$DataPath\crafting"
$allJsonFiles = Get-ChildItem -Path $craftingDir -Filter "*.json"
Write-Host "Available JSON files:" -ForegroundColor Yellow
$allJsonFiles | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor Cyan }

# Try to find the default file specifically, exclude backup and other generated files
$defaultFile = $allJsonFiles | Where-Object { $_.BaseName -eq "默认" -or $_.BaseName -match "^[^\w]*default[^\w]*$" } | Select-Object -First 1
if ($defaultFile) {
    $craftingFile = $defaultFile.FullName
    Write-Host "Found default crafting file: $($defaultFile.Name)" -ForegroundColor Green
} else {
    # If not found, use the largest JSON file that's not a backup or generated file
    $craftingFile = ($allJsonFiles | Where-Object { -not ($_.Name -match "backup|武器|饰品|防具|其他") } | Sort-Object Length -Descending)[0].FullName
    Write-Host "Using largest non-backup JSON file as default: $((Get-Item $craftingFile).Name)" -ForegroundColor Yellow
}

Write-Host "Reading crafting table file..." -ForegroundColor Cyan
$craftingData = Get-Content $craftingFile -Encoding UTF8 | ConvertFrom-Json

Write-Host "Crafting table contains $($craftingData.Count) recipes" -ForegroundColor Yellow

# 3. Initialize category containers
$weaponCategory = @()
$accessoryCategory = @()
$basicArmorCategory = @()
$advancedArmorCategory = @()
$otherCategory = @()

# Statistics
$weaponCount = 0
$accessoryCount = 0
$basicArmorCount = 0
$advancedArmorCount = 0
$otherCount = 0
$notFoundCount = 0

# 4. Categorization process
Write-Host "Starting categorization process..." -ForegroundColor Green

foreach ($recipe in $craftingData) {
    $itemName = $recipe.name
    $category = "other"  # default category
    
    
    if ($itemMap.ContainsKey($itemName)) {
        $itemInfo = $itemMap[$itemName]
        
        # Classification logic - use Contains to handle encoding issues
        if ($itemInfo.type -and $itemInfo.type.Contains("武器")) {
            $category = "weapon"
            $weaponCategory += $recipe
            $weaponCount++
        }
        elseif (($itemInfo.use -and $itemInfo.use.Contains("颈部装备")) -or $itemInfo.file.Contains("颈部装备")) {
            $category = "accessory"
            $accessoryCategory += $recipe
            $accessoryCount++
        }
        elseif ($itemInfo.type -and $itemInfo.type.Contains("防具")) {
            if ($itemInfo.level -le 30) {
                $category = "basicarmor"
                $basicArmorCategory += $recipe
                $basicArmorCount++
            }
            else {
                $category = "advancedarmor"
                $advancedArmorCategory += $recipe
                $advancedArmorCount++
            }
        }
        else {
            $otherCategory += $recipe
            $otherCount++
        }
    }
    else {
        $notFoundCount++
        $otherCategory += $recipe
        $otherCount++
        Write-Warning "Item not found: $itemName"
    }
}

# 5. Output statistics
Write-Host "`nCategorization Statistics:" -ForegroundColor Green
Write-Host "  Weapons: $weaponCount" -ForegroundColor White
Write-Host "  Accessories: $accessoryCount" -ForegroundColor White
Write-Host "  Basic Armor: $basicArmorCount" -ForegroundColor White
Write-Host "  Advanced Armor: $advancedArmorCount" -ForegroundColor White
Write-Host "  Others: $otherCount" -ForegroundColor White
Write-Host "  Items not found: $notFoundCount" -ForegroundColor Red

# 6. Generate category files
$outputDir = "$DataPath\crafting"
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

Write-Host "`nGenerating category files..." -ForegroundColor Green

# Helper function to save JSON with proper UTF-8 encoding
function Save-JsonFile {
    param($Data, $FilePath, $CategoryName, $Count)
    
    if ($Count -gt 0) {
        $jsonContent = $Data | ConvertTo-Json -Depth 10 -Compress:$false
        [System.IO.File]::WriteAllText($FilePath, $jsonContent, [System.Text.Encoding]::UTF8)
        Write-Host "  Generated file: $(Split-Path $FilePath -Leaf) (contains $Count recipes)" -ForegroundColor Cyan
    }
}

# Save each category
Save-JsonFile -Data $weaponCategory -FilePath "$outputDir\武器.json" -CategoryName "Weapons" -Count $weaponCount
Save-JsonFile -Data $accessoryCategory -FilePath "$outputDir\饰品.json" -CategoryName "Accessories" -Count $accessoryCount
Save-JsonFile -Data $basicArmorCategory -FilePath "$outputDir\基础防具.json" -CategoryName "Basic Armor" -Count $basicArmorCount
Save-JsonFile -Data $advancedArmorCategory -FilePath "$outputDir\进阶防具.json" -CategoryName "Advanced Armor" -Count $advancedArmorCount
Save-JsonFile -Data $otherCategory -FilePath "$outputDir\其他.json" -CategoryName "Others" -Count $otherCount

# 7. Backup original file
$backupFile = "$DataPath\crafting\default_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
Copy-Item $craftingFile $backupFile
Write-Host "`nOriginal file backed up as: $(Split-Path $backupFile -Leaf)" -ForegroundColor Yellow

Write-Host "`nProcessing completed!" -ForegroundColor Green
Write-Host "Generated files are located in: $outputDir" -ForegroundColor White

# 8. Show examples from each category
Write-Host "`nCategory Examples:" -ForegroundColor Green

if ($weaponCount -gt 0) {
    Write-Host "  Weapons (first 3):" -ForegroundColor Cyan
    $weaponCategory | Select-Object -First 3 | ForEach-Object { Write-Host "    - $($_.name)" -ForegroundColor White }
}

if ($accessoryCount -gt 0) {
    Write-Host "  Accessories (first 3):" -ForegroundColor Cyan
    $accessoryCategory | Select-Object -First 3 | ForEach-Object { Write-Host "    - $($_.name)" -ForegroundColor White }
}

if ($basicArmorCount -gt 0) {
    Write-Host "  Basic Armor (first 3):" -ForegroundColor Cyan
    $basicArmorCategory | Select-Object -First 3 | ForEach-Object { Write-Host "    - $($_.name)" -ForegroundColor White }
}

if ($advancedArmorCount -gt 0) {
    Write-Host "  Advanced Armor (first 3):" -ForegroundColor Cyan
    $advancedArmorCategory | Select-Object -First 3 | ForEach-Object { Write-Host "    - $($_.name)" -ForegroundColor White }
}

if ($otherCount -gt 0) {
    Write-Host "  Others (first 3):" -ForegroundColor Cyan
    $otherCategory | Select-Object -First 3 | ForEach-Object { Write-Host "    - $($_.name)" -ForegroundColor White }
}