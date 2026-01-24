# BuffSystem Packaging Script with Event Dependencies
# Encoding: UTF-8

$ErrorActionPreference = "Stop"
$baseDir = "c:\Program Files (x86)\Steam\steamapps\common\CRAZYFLASHER7StandAloneStarter\resources"
$toolsDir = Join-Path $baseDir "tools"
$outputDir = Join-Path $toolsDir "BuffSystem_Package"
$zipPath = Join-Path $toolsDir "BuffSystem_v1.0.zip"

# Chinese directory name
$chineseDir = [char]0x7C7B + [char]0x5B9A + [char]0x4E49  # "类定义"
$classDefDir = Join-Path $baseDir "scripts\$chineseDir"

# Clean and create output directory
if (Test-Path $outputDir) {
    Remove-Item -Path $outputDir -Recurse -Force
}
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

# Create subdirectories
$buffCoreDir = Join-Path $outputDir "Buff\Core"
$buffComponentDir = Join-Path $outputDir "Buff\Component"
$buffTestDir = Join-Path $outputDir "Buff\Test"
$eventDir = Join-Path $outputDir "Dependencies\Event"
$dataStructuresDir = Join-Path $outputDir "Dependencies\DataStructures"
$argumentsDir = Join-Path $outputDir "Dependencies\Arguments"
$propertyDir = Join-Path $outputDir "Dependencies\Property"

New-Item -ItemType Directory -Path $buffCoreDir -Force | Out-Null
New-Item -ItemType Directory -Path $buffComponentDir -Force | Out-Null
New-Item -ItemType Directory -Path $buffTestDir -Force | Out-Null
New-Item -ItemType Directory -Path $eventDir -Force | Out-Null
New-Item -ItemType Directory -Path $dataStructuresDir -Force | Out-Null
New-Item -ItemType Directory -Path $argumentsDir -Force | Out-Null
New-Item -ItemType Directory -Path $propertyDir -Force | Out-Null

Write-Host "=== BuffSystem Packaging Script ===" -ForegroundColor Cyan

# 1. Copy Buff system core files
Write-Host "`n[1/7] Copying Buff system core files..." -ForegroundColor Yellow
$buffSourceDir = Join-Path $classDefDir "org\flashNight\arki\component\Buff"
$coreFiles = @(
    "BuffManager.as",
    "BuffCalculator.as",
    "BuffCalculationType.as",
    "IBuffCalculator.as",
    "BuffContext.as",
    "BaseBuff.as",
    "IBuff.as",
    "MetaBuff.as",
    "PodBuff.as",
    "PropertyContainer.as",
    "StateInfo.as"
)
foreach ($file in $coreFiles) {
    $sourcePath = Join-Path $buffSourceDir $file
    if (Test-Path $sourcePath) {
        Copy-Item $sourcePath -Destination $buffCoreDir
        Write-Host "  Copied: $file" -ForegroundColor Gray
    } else {
        Write-Host "  Warning: $file not found!" -ForegroundColor Red
    }
}

# 2. Copy Buff component files
Write-Host "`n[2/7] Copying Buff component files..." -ForegroundColor Yellow
$componentSourceDir = Join-Path $buffSourceDir "Component"
if (Test-Path $componentSourceDir) {
    Get-ChildItem -Path $componentSourceDir -Filter "*.as" | ForEach-Object {
        Copy-Item $_.FullName -Destination $buffComponentDir
        Write-Host "  Copied: $($_.Name)" -ForegroundColor Gray
    }
}

# 3. Copy Buff test files
Write-Host "`n[3/7] Copying Buff test files..." -ForegroundColor Yellow
$testSourceDir = Join-Path $buffSourceDir "test"
if (Test-Path $testSourceDir) {
    Get-ChildItem -Path $testSourceDir -Filter "*.as" | ForEach-Object {
        Copy-Item $_.FullName -Destination $buffTestDir
        Write-Host "  Copied: $($_.Name)" -ForegroundColor Gray
    }
}

# 4. Copy Event system dependencies (EventDispatcher, EventBus, Delegate)
Write-Host "`n[4/7] Copying Event system dependencies..." -ForegroundColor Yellow
$eventSourceDir = Join-Path $classDefDir "org\flashNight\neur\Event"
$requiredEventFiles = @("EventDispatcher.as", "EventBus.as", "Delegate.as")
foreach ($file in $requiredEventFiles) {
    $sourcePath = Join-Path $eventSourceDir $file
    if (Test-Path $sourcePath) {
        Copy-Item $sourcePath -Destination $eventDir
        Write-Host "  Copied: $file" -ForegroundColor Gray
    } else {
        Write-Host "  Warning: $file not found!" -ForegroundColor Red
    }
}

# 5. Copy Dictionary.as from DataStructures
Write-Host "`n[5/7] Copying DataStructures dependency (Dictionary.as)..." -ForegroundColor Yellow
$dictSourcePath = Join-Path $classDefDir "org\flashNight\naki\DataStructures\Dictionary.as"
if (Test-Path $dictSourcePath) {
    Copy-Item $dictSourcePath -Destination $dataStructuresDir
    Write-Host "  Copied: Dictionary.as" -ForegroundColor Gray
} else {
    Write-Host "  Warning: Dictionary.as not found!" -ForegroundColor Red
}

# 6. Copy ArgumentsUtil.as from gesh/arguments
Write-Host "`n[6/7] Copying Arguments dependency (ArgumentsUtil.as)..." -ForegroundColor Yellow
$argsSourcePath = Join-Path $classDefDir "org\flashNight\gesh\arguments\ArgumentsUtil.as"
if (Test-Path $argsSourcePath) {
    Copy-Item $argsSourcePath -Destination $argumentsDir
    Write-Host "  Copied: ArgumentsUtil.as" -ForegroundColor Gray
} else {
    Write-Host "  Warning: ArgumentsUtil.as not found!" -ForegroundColor Red
}

# 7. Copy PropertyAccessor.as from gesh/property
Write-Host "`n[7/9] Copying Property dependency (PropertyAccessor.as)..." -ForegroundColor Yellow
$propSourcePath = Join-Path $classDefDir "org\flashNight\gesh\property\PropertyAccessor.as"
if (Test-Path $propSourcePath) {
    Copy-Item $propSourcePath -Destination $propertyDir
    Write-Host "  Copied: PropertyAccessor.as" -ForegroundColor Gray
} else {
    Write-Host "  Warning: PropertyAccessor.as not found!" -ForegroundColor Red
}

# 8. Copy Buff system MD documentation files
Write-Host "`n[8/9] Copying Buff system documentation (*.md)..." -ForegroundColor Yellow
# Core MD files
$buffMdFiles = @("BuffManager.md", "BuffCalculator.md", "PropertyContainerTest.md")
foreach ($file in $buffMdFiles) {
    $sourcePath = Join-Path $buffSourceDir $file
    if (Test-Path $sourcePath) {
        Copy-Item $sourcePath -Destination $buffCoreDir
        Write-Host "  Copied: $file" -ForegroundColor Gray
    }
}
# Test MD files
$testMdFiles = @("Tier1ComponentTest.md", "Tier2ComponentTest.md")
foreach ($file in $testMdFiles) {
    $sourcePath = Join-Path $testSourceDir $file
    if (Test-Path $sourcePath) {
        Copy-Item $sourcePath -Destination $buffTestDir
        Write-Host "  Copied: $file" -ForegroundColor Gray
    }
}

# 9. Copy Dependency MD documentation files
Write-Host "`n[9/9] Copying dependency documentation (*.md)..." -ForegroundColor Yellow
# Event MD files
$eventMdFiles = @("EventDispatcher.md", "EventBus.md", "Delegate.md")
foreach ($file in $eventMdFiles) {
    $sourcePath = Join-Path $eventSourceDir $file
    if (Test-Path $sourcePath) {
        Copy-Item $sourcePath -Destination $eventDir
        Write-Host "  Copied: $file" -ForegroundColor Gray
    }
}
# Dictionary MD
$dictMdPath = Join-Path $classDefDir "org\flashNight\naki\DataStructures\Dictionary.md"
if (Test-Path $dictMdPath) {
    Copy-Item $dictMdPath -Destination $dataStructuresDir
    Write-Host "  Copied: Dictionary.md" -ForegroundColor Gray
}
# PropertyAccessor MD
$propMdPath = Join-Path $classDefDir "org\flashNight\gesh\property\PropertyAccessor.md"
if (Test-Path $propMdPath) {
    Copy-Item $propMdPath -Destination $propertyDir
    Write-Host "  Copied: PropertyAccessor.md" -ForegroundColor Gray
}

# 10. Copy Review Prompt
Write-Host "`n[10/10] Copying review prompt..." -ForegroundColor Yellow
$promptPath = Join-Path $toolsDir "BuffSystem_Review_Prompt_CN.md"
if (Test-Path $promptPath) {
    Copy-Item $promptPath -Destination $outputDir
    Write-Host "  Copied: BuffSystem_Review_Prompt_CN.md" -ForegroundColor Gray
}

# Create ZIP
Write-Host "`n[Creating ZIP archive...]" -ForegroundColor Yellow
if (Test-Path $zipPath) {
    Remove-Item -Path $zipPath -Force
}
Compress-Archive -Path "$outputDir\*" -DestinationPath $zipPath -CompressionLevel Optimal

# Summary
Write-Host "`n=== Packaging Complete ===" -ForegroundColor Green
Write-Host "Output: $zipPath" -ForegroundColor Cyan

# Count files
$totalFiles = (Get-ChildItem -Path $outputDir -Recurse -File).Count
Write-Host "Total files: $totalFiles" -ForegroundColor Cyan

# List structure
Write-Host "`nPackage structure:" -ForegroundColor Yellow
function Show-Tree {
    param([string]$Path, [string]$Indent = "")
    Get-ChildItem -Path $Path | ForEach-Object {
        if ($_.PSIsContainer) {
            $count = (Get-ChildItem -Path $_.FullName -File -Recurse).Count
            Write-Host "$Indent$($_.Name)/ ($count files)" -ForegroundColor Gray
            Show-Tree -Path $_.FullName -Indent "  $Indent"
        }
    }
}
Show-Tree -Path $outputDir

# Cleanup temp folder
Remove-Item -Path $outputDir -Recurse -Force
Write-Host "`nTemporary folder cleaned." -ForegroundColor Gray
