# BuffSystem Nested Property Support - Pack Script
# Pack buff system and related files for external architecture review
# Focus: Supporting nested property paths like "长枪属性.power"

# Set UTF-8 encoding for Chinese path support
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$baseDir = "c:\Program Files (x86)\Steam\steamapps\common\CRAZYFLASHER7StandAloneStarter\resources"
$toolsDir = "$baseDir\tools"
$scriptsDir = "$baseDir\scripts"
$outputZip = "$toolsDir\BuffSystem_NestedProperty_Review_v1.0.zip"
$tempDir = "$toolsDir\BuffSystem_NestedProperty_Review"

# Clean old files
if (Test-Path $tempDir) { Remove-Item -Recurse -Force $tempDir }
if (Test-Path $outputZip) { Remove-Item -Force $outputZip }

# Create directory structure
$directories = @(
    "$tempDir\BuffSystem\Core",
    "$tempDir\BuffSystem\Component",
    "$tempDir\BuffSystem\Docs",
    "$tempDir\PrattParser",
    "$tempDir\Property",
    "$tempDir\Business"
)

foreach ($dir in $directories) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

Write-Host "=== BuffSystem Nested Property Pack Script ===" -ForegroundColor Cyan
Write-Host "Purpose: Pack files for external architecture review" -ForegroundColor Gray
Write-Host ""

$totalFiles = 0
$missingFiles = @()

# ============================================================
# 1. BuffSystem Core (11 files)
# ============================================================
Write-Host "[1/7] Copying BuffSystem Core files..." -ForegroundColor Yellow

$buffCoreFiles = @(
    "BuffManager.as",
    "PropertyContainer.as",
    "PodBuff.as",
    "MetaBuff.as",
    "BaseBuff.as",
    "IBuff.as",
    "BuffCalculator.as",
    "IBuffCalculator.as",
    "BuffCalculationType.as",
    "BuffContext.as",
    "StateInfo.as"
)

# Use wildcard search for BuffSystem Core
foreach ($fileName in $buffCoreFiles) {
    $file = Get-ChildItem -Path $scriptsDir -Recurse -Filter $fileName | Where-Object { $_.FullName -like "*arki*component*Buff*" -and $_.FullName -notlike "*test*" } | Select-Object -First 1
    if ($file) {
        Copy-Item $file.FullName "$tempDir\BuffSystem\Core\"
        Write-Host "  + $fileName" -ForegroundColor Green
        $totalFiles++
    } else {
        Write-Host "  ! Not found: $fileName" -ForegroundColor Red
        $missingFiles += $fileName
    }
}

# ============================================================
# 2. BuffSystem Components (8 files)
# ============================================================
Write-Host "`n[2/7] Copying BuffSystem Component files..." -ForegroundColor Yellow

$buffComponentFiles = @(
    "IBuffComponent.as",
    "TimeLimitComponent.as",
    "StackLimitComponent.as",
    "ConditionComponent.as",
    "TickComponent.as",
    "CooldownComponent.as",
    "DelayedTriggerComponent.as",
    "EventListenerComponent.as"
)

foreach ($fileName in $buffComponentFiles) {
    $file = Get-ChildItem -Path $scriptsDir -Recurse -Filter $fileName | Where-Object { $_.FullName -like "*Buff*Component*" } | Select-Object -First 1
    if ($file) {
        Copy-Item $file.FullName "$tempDir\BuffSystem\Component\"
        Write-Host "  + $fileName" -ForegroundColor Green
        $totalFiles++
    } else {
        Write-Host "  ! Not found: $fileName" -ForegroundColor Red
        $missingFiles += $fileName
    }
}

# ============================================================
# 3. BuffSystem Docs (1 file)
# ============================================================
Write-Host "`n[3/7] Copying BuffSystem Docs..." -ForegroundColor Yellow

$buffDocFile = Get-ChildItem -Path $scriptsDir -Recurse -Filter "BuffManager.md" | Select-Object -First 1
if ($buffDocFile) {
    Copy-Item $buffDocFile.FullName "$tempDir\BuffSystem\Docs\"
    Write-Host "  + BuffManager.md" -ForegroundColor Green
    $totalFiles++
} else {
    Write-Host "  ! Not found: BuffManager.md" -ForegroundColor Red
    $missingFiles += "BuffManager.md"
}

# ============================================================
# 4. Pratt Parser System (6 files) - Technical Reserve
# ============================================================
Write-Host "`n[4/7] Copying Pratt Parser files (technical reserve)..." -ForegroundColor Yellow

$prattFiles = @(
    "PrattLexer.as",
    "PrattParser.as",
    "PrattExpression.as",
    "PrattEvaluator.as",
    "PrattToken.as",
    "PrattParselet.as"
)

foreach ($fileName in $prattFiles) {
    $file = Get-ChildItem -Path $scriptsDir -Recurse -Filter $fileName | Where-Object { $_.FullName -like "*pratt*" -and $_.FullName -notlike "*test*" -and $_.FullName -notlike "*Test*" } | Select-Object -First 1
    if ($file) {
        Copy-Item $file.FullName "$tempDir\PrattParser\"
        Write-Host "  + $fileName" -ForegroundColor Green
        $totalFiles++
    } else {
        Write-Host "  ! Not found: $fileName" -ForegroundColor Red
        $missingFiles += $fileName
    }
}

# ============================================================
# 5. Property System (3 files)
# ============================================================
Write-Host "`n[5/7] Copying Property System files..." -ForegroundColor Yellow

$propertyFiles = @(
    "PropertyAccessor.as",
    "IProperty.as",
    "BaseProperty.as"
)

foreach ($fileName in $propertyFiles) {
    $file = Get-ChildItem -Path $scriptsDir -Recurse -Filter $fileName | Where-Object { $_.FullName -like "*property*" -and $_.FullName -notlike "*test*" -and $_.FullName -notlike "*Test*" } | Select-Object -First 1
    if ($file) {
        Copy-Item $file.FullName "$tempDir\Property\"
        Write-Host "  + $fileName" -ForegroundColor Green
        $totalFiles++
    } else {
        Write-Host "  ! Not found: $fileName" -ForegroundColor Red
        $missingFiles += $fileName
    }
}

# ============================================================
# 6. Business Code (6 files) - Affected Modules
# ============================================================
Write-Host "`n[6/7] Copying Business Code (affected modules)..." -ForegroundColor Yellow

# Business files - use wildcard search
$businessSearches = @{
    "ShootInitCore.as" = "*Shoot*"
    "WeaponFireCore.as" = "*Shoot*"
    "DressupInitializer.as" = "*Initializer*"
}

foreach ($fileName in $businessSearches.Keys) {
    $pattern = $businessSearches[$fileName]
    $file = Get-ChildItem -Path $scriptsDir -Recurse -Filter $fileName | Where-Object { $_.FullName -like $pattern } | Select-Object -First 1
    if ($file) {
        Copy-Item $file.FullName "$tempDir\Business\"
        Write-Host "  + $fileName" -ForegroundColor Green
        $totalFiles++
    } else {
        Write-Host "  ! Not found: $fileName" -ForegroundColor Red
        $missingFiles += $fileName
    }
}

# Chinese named files - use exact paths (encoding workaround)
$chineseFilePaths = @(
    @{Name="主角模板数值buff.as"; Path="$scriptsDir\类定义\主角模板数值buff.as"},
    @{Name="单位函数_lsy_主角射击函数.as"; Path="$scriptsDir\逻辑\单位函数\单位函数_lsy_主角射击函数.as"},
    @{Name="单位函数_fs_玩家装备配置.as"; Path="$scriptsDir\逻辑\单位函数\单位函数_fs_玩家装备配置.as"}
)

foreach ($fileInfo in $chineseFilePaths) {
    # Try direct path first
    if (Test-Path -LiteralPath $fileInfo.Path) {
        Copy-Item -LiteralPath $fileInfo.Path "$tempDir\Business\"
        Write-Host "  + $($fileInfo.Name)" -ForegroundColor Green
        $totalFiles++
    } else {
        # Fallback: search by partial match
        $searchResult = Get-ChildItem -Path $scriptsDir -Recurse -File | Where-Object { $_.Name -like "*buff*" -or $_.Name -like "*函数*" } | Where-Object { $_.Name -eq $fileInfo.Name } | Select-Object -First 1
        if ($searchResult) {
            Copy-Item $searchResult.FullName "$tempDir\Business\"
            Write-Host "  + $($fileInfo.Name) (fallback)" -ForegroundColor Green
            $totalFiles++
        } else {
            Write-Host "  ! Not found: $($fileInfo.Name)" -ForegroundColor Red
            $missingFiles += $fileInfo.Name
        }
    }
}

# ============================================================
# 7. Review Prompt Document
# ============================================================
Write-Host "`n[7/7] Copying Review Prompt..." -ForegroundColor Yellow

$promptFile = "$toolsDir\BuffSystem_NestedProperty_Review_Prompt_CN.md"
if (Test-Path $promptFile) {
    Copy-Item $promptFile "$tempDir\"
    Write-Host "  + BuffSystem_NestedProperty_Review_Prompt_CN.md" -ForegroundColor Cyan
    $totalFiles++
} else {
    Write-Host "  ! Not found: BuffSystem_NestedProperty_Review_Prompt_CN.md" -ForegroundColor Red
}

# ============================================================
# Create ZIP Archive
# ============================================================
Write-Host "`nCreating ZIP archive..." -ForegroundColor Yellow

Compress-Archive -Path "$tempDir\*" -DestinationPath $outputZip -Force

# ============================================================
# Summary Statistics
# ============================================================
$zipInfo = Get-Item $outputZip
$totalSize = (Get-ChildItem -Recurse $tempDir -File | Measure-Object -Property Length -Sum).Sum

Write-Host "`n=============================================" -ForegroundColor Cyan
Write-Host "=== Pack Complete ===" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Output: $outputZip" -ForegroundColor Green
Write-Host "Files: $totalFiles" -ForegroundColor Green
Write-Host "Total Size: $([math]::Round($totalSize/1KB, 2)) KB" -ForegroundColor Green
Write-Host "Zip Size: $([math]::Round($zipInfo.Length/1KB, 2)) KB" -ForegroundColor Green

if ($missingFiles.Count -gt 0) {
    Write-Host "`nMissing Files ($($missingFiles.Count)):" -ForegroundColor Yellow
    foreach ($f in $missingFiles) {
        Write-Host "  - $f" -ForegroundColor Yellow
    }
}

Write-Host "`nDirectory Structure:" -ForegroundColor Yellow
Write-Host "BuffSystem_NestedProperty_Review/"
Write-Host "  BuffSystem/"
Write-Host "    Core/           (11 files: BuffManager, PropertyContainer, PodBuff, MetaBuff, etc.)"
Write-Host "    Component/      (8 files: TimeLimitComponent, ConditionComponent, etc.)"
Write-Host "    Docs/           (1 file: BuffManager.md design documentation)"
Write-Host "  PrattParser/      (6 files: Lexer, Parser, Expression - technical reserve)"
Write-Host "  Property/         (3 files: PropertyAccessor, IProperty, BaseProperty)"
Write-Host "  Business/         (6 files: Affected business code for context)"
Write-Host "  BuffSystem_NestedProperty_Review_Prompt_CN.md"

Write-Host "`n=============================================" -ForegroundColor Cyan
Write-Host "Review Focus Areas:" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "1. Supporting nested property paths like '长枪属性.power'" -ForegroundColor White
Write-Host "2. AS2 addProperty() limitation (single object, single key)" -ForegroundColor White
Write-Host "3. Cascade triggering (weapon power -> refresh shooting system)" -ForegroundColor White
Write-Host "4. Object replacement handling (equipment swap)" -ForegroundColor White
Write-Host "5. '+=' trap prevention (read final, write base drift)" -ForegroundColor White

# Cleanup temp folder
Remove-Item -Recurse -Force $tempDir
Write-Host "`nTemp folder cleaned." -ForegroundColor Gray
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Magenta
Write-Host "1. Upload the ZIP file to GPT Pro or other AI review service"
Write-Host "2. Include the prompt document as the first message"
Write-Host "3. Ask for architecture-level review and recommendations"
Write-Host ""
