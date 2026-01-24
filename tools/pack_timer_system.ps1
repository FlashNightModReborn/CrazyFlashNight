# TimerSystem Pack Script
# Pack timer system core files into zip for external review

$baseDir = "c:\Program Files (x86)\Steam\steamapps\common\CRAZYFLASHER7StandAloneStarter\resources"
$toolsDir = "$baseDir\tools"
$scriptsDir = "$baseDir\scripts"
$outputZip = "$toolsDir\TimerSystem_v1.0.zip"
$tempDir = "$toolsDir\TimerSystem_Review"

# Clean old files
if (Test-Path $tempDir) { Remove-Item -Recurse -Force $tempDir }
if (Test-Path $outputZip) { Remove-Item -Force $outputZip }

# Create directory structure
New-Item -ItemType Directory -Force -Path "$tempDir\Core" | Out-Null
New-Item -ItemType Directory -Force -Path "$tempDir\Dependencies" | Out-Null
New-Item -ItemType Directory -Force -Path "$tempDir\SharedDeps" | Out-Null
New-Item -ItemType Directory -Force -Path "$tempDir\Macros" | Out-Null
New-Item -ItemType Directory -Force -Path "$tempDir\Test" | Out-Null
New-Item -ItemType Directory -Force -Path "$tempDir\Docs" | Out-Null

Write-Host "=== TimerSystem Pack Script ===" -ForegroundColor Cyan

# Core files (5)
Write-Host "`n[1/6] Copying core files..." -ForegroundColor Yellow

$coreMapping = @{
    "TaskManager.as" = "*ScheduleTimer*"
    "CerberusScheduler.as" = "*ScheduleTimer*"
    "Task.as" = "*ScheduleTimer*"
    "CooldownWheel.as" = "*ScheduleTimer*"
    "EnhancedCooldownWheel.as" = "*ScheduleTimer*"
}

foreach ($fileName in $coreMapping.Keys) {
    $pattern = $coreMapping[$fileName]
    $file = Get-ChildItem -Path $scriptsDir -Recurse -Filter $fileName | Where-Object { $_.FullName -like $pattern } | Select-Object -First 1
    if ($file) {
        Copy-Item $file.FullName "$tempDir\Core\"
        Write-Host "  + $fileName" -ForegroundColor Green
    } else {
        Write-Host "  ! Not found: $fileName" -ForegroundColor Red
    }
}

# Dependency files (5)
Write-Host "`n[2/6] Copying dependency files..." -ForegroundColor Yellow

$depMapping = @{
    "SingleLevelTimeWheel.as" = "*TimeWheel*"
    "FrameTaskMinHeap.as" = "*DataStructures*"
    "TaskIDNode.as" = "*DataStructures*"
    "TaskIDLinkedList.as" = "*DataStructures*"
    "TaskNode.as" = "*DataStructures*"
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

# Shared dependency files (4)
Write-Host "`n[3/6] Copying shared dependency files..." -ForegroundColor Yellow

$sharedMapping = @{
    "Delegate.as" = "*neur*Event*"
    "Dictionary.as" = "*DataStructures*"
    "EventCoordinator.as" = "*Coordinator*"
    "ArgumentsUtil.as" = "*arguments*"
}

foreach ($fileName in $sharedMapping.Keys) {
    $pattern = $sharedMapping[$fileName]
    $file = Get-ChildItem -Path $scriptsDir -Recurse -Filter $fileName | Where-Object { $_.FullName -like $pattern } | Select-Object -First 1
    if ($file) {
        Copy-Item $file.FullName "$tempDir\SharedDeps\"
        Write-Host "  + $fileName" -ForegroundColor Green
    } else {
        Write-Host "  ! Not found: $fileName" -ForegroundColor Red
    }
}

# Macro files (2)
Write-Host "`n[4/6] Copying macro files..." -ForegroundColor Yellow

$macroFiles = @(
    "WHEEL_SIZE_MACRO.as",
    "WHEEL_MASK_MACRO.as"
)

foreach ($fileName in $macroFiles) {
    $file = Get-ChildItem -Path "$scriptsDir\macros" -Filter $fileName | Select-Object -First 1
    if ($file) {
        Copy-Item $file.FullName "$tempDir\Macros\"
        Write-Host "  + $fileName" -ForegroundColor Green
    } else {
        Write-Host "  ! Not found: $fileName" -ForegroundColor Red
    }
}

# Test files (4)
Write-Host "`n[5/6] Copying test files..." -ForegroundColor Yellow

$testFiles = @(
    "TaskManagerTester.as",
    "CerberusSchedulerTest.as",
    "CooldownWheelTests.as",
    "EnhancedCooldownWheelTests.as"
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

# Doc files (5)
Write-Host "`n[6/7] Copying doc files..." -ForegroundColor Yellow

$docMapping = @{
    "TaskManager.md" = "*ScheduleTimer*"
    "CerberusScheduler.md" = "*ScheduleTimer*"
    "CooldownWheel.md" = "*ScheduleTimer*"
    "EnhancedCooldownWheel.md" = "*ScheduleTimer*"
    "SingleLevelTimeWheel.md" = "*TimeWheel*"
}

foreach ($fileName in $docMapping.Keys) {
    $pattern = $docMapping[$fileName]
    $file = Get-ChildItem -Path $scriptsDir -Recurse -Filter $fileName | Where-Object { $_.FullName -like $pattern } | Select-Object -First 1
    if ($file) {
        Copy-Item $file.FullName "$tempDir\Docs\"
        Write-Host "  + $fileName" -ForegroundColor Green
    } else {
        Write-Host "  ! Not found: $fileName" -ForegroundColor Red
    }
}

# Copy prompt file
Write-Host "`n[7/7] Copying review prompt..." -ForegroundColor Yellow
$promptFile = "$toolsDir\TimerSystem_Review_Prompt_CN.md"
if (Test-Path $promptFile) {
    Copy-Item $promptFile "$tempDir\"
    Write-Host "  + TimerSystem_Review_Prompt_CN.md" -ForegroundColor Cyan
}

# Create ZIP
Write-Host "`nCreating archive..." -ForegroundColor Yellow

Compress-Archive -Path "$tempDir\*" -DestinationPath $outputZip -Force

# Stats
$zipInfo = Get-Item $outputZip
$fileCount = (Get-ChildItem -Recurse $tempDir -File).Count
$totalSize = (Get-ChildItem -Recurse $tempDir -File | Measure-Object -Property Length -Sum).Sum

Write-Host "`n=== Pack Complete ===" -ForegroundColor Cyan
Write-Host "Output: $outputZip" -ForegroundColor Green
Write-Host "Files: $fileCount" -ForegroundColor Green
Write-Host "Total Size: $([math]::Round($totalSize/1KB, 2)) KB" -ForegroundColor Green
Write-Host "Zip Size: $([math]::Round($zipInfo.Length/1KB, 2)) KB" -ForegroundColor Green

Write-Host "`nDirectory structure:" -ForegroundColor Yellow
Write-Host "TimerSystem_Review/"
Write-Host "  Core/           (5 core files: TaskManager, CerberusScheduler, Task, CooldownWheel, EnhancedCooldownWheel)"
Write-Host "  Dependencies/   (5 dependency files: TimeWheel, Heap, LinkedList, Node)"
Write-Host "  SharedDeps/     (4 shared files: Delegate, Dictionary, EventCoordinator, ArgumentsUtil)"
Write-Host "  Macros/         (2 macro files: WHEEL_SIZE, WHEEL_MASK)"
Write-Host "  Test/           (4 test files)"
Write-Host "  Docs/           (5 doc files: design documentation)"
Write-Host "  TimerSystem_Review_Prompt_CN.md"

# Cleanup temp folder
Remove-Item -Recurse -Force $tempDir
Write-Host "`nTemp folder cleaned." -ForegroundColor Gray
