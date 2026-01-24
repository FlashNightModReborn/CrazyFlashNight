# EventSystem Pack Script
# Pack event system core files into zip for GPT PRO review

$baseDir = "c:\Program Files (x86)\Steam\steamapps\common\CRAZYFLASHER7StandAloneStarter\resources"
$toolsDir = "$baseDir\tools"
$scriptsDir = "$baseDir\scripts"
$outputZip = "$toolsDir\EventSystem_v2.3.2.zip"
$tempDir = "$toolsDir\EventSystem_Review"

# Clean old files
if (Test-Path $tempDir) { Remove-Item -Recurse -Force $tempDir }
if (Test-Path $outputZip) { Remove-Item -Force $outputZip }

# Create directory structure
New-Item -ItemType Directory -Force -Path "$tempDir\Core" | Out-Null
New-Item -ItemType Directory -Force -Path "$tempDir\Dependencies" | Out-Null
New-Item -ItemType Directory -Force -Path "$tempDir\Tools" | Out-Null
New-Item -ItemType Directory -Force -Path "$tempDir\Test" | Out-Null
New-Item -ItemType Directory -Force -Path "$tempDir\Docs" | Out-Null

Write-Host "=== EventSystem Pack Script ===" -ForegroundColor Cyan

# Core files (5)
Write-Host "`n[1/5] Copying core files..." -ForegroundColor Yellow

$coreFiles = @(
    "EventBus.as",
    "EventDispatcher.as",
    "LifecycleEventDispatcher.as",
    "Delegate.as",
    "Event.as"
)

foreach ($fileName in $coreFiles) {
    $file = Get-ChildItem -Path $scriptsDir -Recurse -Filter $fileName | Where-Object { $_.FullName -like "*neur*Event*" } | Select-Object -First 1
    if ($file) {
        Copy-Item $file.FullName "$tempDir\Core\"
        Write-Host "  + $fileName" -ForegroundColor Green
    } else {
        Write-Host "  ! Not found: $fileName" -ForegroundColor Red
    }
}

# Dependency files (2)
Write-Host "`n[2/5] Copying dependency files..." -ForegroundColor Yellow

$depMapping = @{
    "Dictionary.as" = "*DataStructures*"
    "EventCoordinator.as" = "*Coordinator*"
}

foreach ($fileName in $depMapping.Keys) {
    $pattern = $depMapping[$fileName]
    $file = Get-ChildItem -Path $scriptsDir -Recurse -Filter $fileName | Where-Object { $_.FullName -like $pattern } | Select-Object -First 1
    if ($file) {
        Copy-Item $file.FullName "$tempDir\Dependencies\"
        Write-Host "  + $fileName" -ForegroundColor Green
    } else {
        Write-Host "  ! Not found: $fileName" -ForegroundColor Red
    }
}

# Tools files (2)
Write-Host "`n[3/5] Copying tools files..." -ForegroundColor Yellow

$toolsMapping = @{
    "Allocator.as" = "*neur*Event*"
    "ArgumentsUtil.as" = "*arguments*"
}

foreach ($fileName in $toolsMapping.Keys) {
    $pattern = $toolsMapping[$fileName]
    $file = Get-ChildItem -Path $scriptsDir -Recurse -Filter $fileName | Where-Object { $_.FullName -like $pattern } | Select-Object -First 1
    if ($file) {
        Copy-Item $file.FullName "$tempDir\Tools\"
        Write-Host "  + $fileName" -ForegroundColor Green
    } else {
        Write-Host "  ! Not found: $fileName" -ForegroundColor Red
    }
}

# Test files (7)
Write-Host "`n[4/5] Copying test files..." -ForegroundColor Yellow

$testFiles = @(
    "EventBusTest.as",
    "EventDispatcherTest.as",
    "EventDispatcherExtendedTest.as",
    "LifecycleEventDispatcherTest.as",
    "DelegateTest.as",
    "EventCoordinatorTest.as",
    "ArgumentsUtilTest.as"
)

foreach ($fileName in $testFiles) {
    $file = Get-ChildItem -Path $scriptsDir -Recurse -Filter $fileName | Select-Object -First 1
    if ($file) {
        Copy-Item $file.FullName "$tempDir\Test\"
        Write-Host "  + $fileName" -ForegroundColor Green
    } else {
        Write-Host "  ! Not found: $fileName" -ForegroundColor Red
    }
}

# Doc files (6)
Write-Host "`n[5/5] Copying doc files..." -ForegroundColor Yellow

$docFiles = @(
    "EventBus.md",
    "EventDispatcher.md",
    "LifecycleEventDispatcher.md",
    "Delegate.md",
    "EventCoordinator.md",
    "Dictionary.md"
)

foreach ($fileName in $docFiles) {
    $file = Get-ChildItem -Path $scriptsDir -Recurse -Filter $fileName | Select-Object -First 1
    if ($file) {
        Copy-Item $file.FullName "$tempDir\Docs\"
        Write-Host "  + $fileName" -ForegroundColor Green
    } else {
        Write-Host "  ! Not found: $fileName" -ForegroundColor Red
    }
}

# Copy prompt file
$promptFile = "$toolsDir\EventSystem_Review_Prompt_CN.md"
if (Test-Path $promptFile) {
    Copy-Item $promptFile "$tempDir\"
    Write-Host "`n  + EventSystem_Review_Prompt_CN.md (Review Prompt)" -ForegroundColor Cyan
}

# Create ZIP
Write-Host "`nCreating archive..." -ForegroundColor Yellow

Compress-Archive -Path "$tempDir\*" -DestinationPath $outputZip -Force

# Stats
$zipInfo = Get-Item $outputZip
$fileCount = (Get-ChildItem -Recurse $tempDir -File).Count

Write-Host "`n=== Pack Complete ===" -ForegroundColor Cyan
Write-Host "Output: $outputZip" -ForegroundColor Green
Write-Host "Files: $fileCount" -ForegroundColor Green
Write-Host "Size: $([math]::Round($zipInfo.Length/1KB, 2)) KB" -ForegroundColor Green

Write-Host "`nDirectory structure:" -ForegroundColor Yellow
Write-Host "EventSystem_Review/"
Write-Host "  Core/           (5 core files)"
Write-Host "  Dependencies/   (2 dependency files)"
Write-Host "  Tools/          (2 tool files)"
Write-Host "  Test/           (7 test files)"
Write-Host "  Docs/           (6 doc files)"
Write-Host "  EventSystem_Review_Prompt_CN.md"

# Cleanup temp folder
Remove-Item -Recurse -Force $tempDir
Write-Host "`nTemp folder cleaned." -ForegroundColor Gray
