# BuffSystem v3.0.2 Code Review Package Script
# Pack files for GPT Pro strict review
# Uses dynamic path discovery to handle encoding issues
# Auto-cleans intermediate directory after ZIP creation

param(
    [string]$OutputDir = ".\review_package_v2",
    [switch]$IncludeBusiness = $false
)

$ErrorActionPreference = "Stop"

# Get script directory and resolve absolute paths
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ResourcesDir = Split-Path -Parent $ScriptDir
$ScriptsBase = Join-Path $ResourcesDir "scripts"

Write-Host "Script Dir: $ScriptDir" -ForegroundColor DarkGray
Write-Host "Scripts Base: $ScriptsBase" -ForegroundColor DarkGray

# === Dynamic path discovery ===
# Find Buff folder by searching for known subpath
$BuffBase = $null
$PropertyBase = $null

$scriptDirs = Get-ChildItem -Path $ScriptsBase -Directory
foreach ($d in $scriptDirs) {
    $testBuffPath = Join-Path $d.FullName "org\flashNight\arki\component\Buff"
    if (Test-Path $testBuffPath) {
        $BuffBase = $testBuffPath
        Write-Host "Found Buff Base: $BuffBase" -ForegroundColor DarkGray
    }

    $testPropertyPath = Join-Path $d.FullName "org\flashNight\gesh\property"
    if (Test-Path $testPropertyPath) {
        $PropertyBase = $testPropertyPath
        Write-Host "Found Property Base: $PropertyBase" -ForegroundColor DarkGray
    }
}

if ($BuffBase -eq $null) {
    Write-Host "ERROR: Could not find Buff directory!" -ForegroundColor Red
    exit 1
}

# Create output directories
$OutputPath = [System.IO.Path]::GetFullPath((Join-Path $ScriptDir $OutputDir))
if (Test-Path $OutputPath) {
    Remove-Item -Recurse -Force $OutputPath
}
New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null
New-Item -ItemType Directory -Force -Path "$OutputPath\1_Core" | Out-Null
New-Item -ItemType Directory -Force -Path "$OutputPath\2_Test" | Out-Null
New-Item -ItemType Directory -Force -Path "$OutputPath\3_Docs" | Out-Null
New-Item -ItemType Directory -Force -Path "$OutputPath\4_Support" | Out-Null

Write-Host "`n=== BuffSystem v3.0.2 Review Package ===" -ForegroundColor Cyan

# ============================================================
# 1. Core Implementation Files (MUST READ)
# ============================================================
Write-Host "`n[1/4] Copying core implementation files..." -ForegroundColor Yellow

$CoreFiles = @(
    @{ Src = (Join-Path $BuffBase "BuffManager.as"); Dst = "1_Core\01_BuffManager.as"; Desc = "Core Manager v3.0.2" },
    @{ Src = (Join-Path $BuffBase "PropertyContainer.as"); Dst = "1_Core\02_PropertyContainer.as"; Desc = "Property Container v2.6.2" },
    @{ Src = (Join-Path $BuffBase "CascadeDispatcher.as"); Dst = "1_Core\03_CascadeDispatcher.as"; Desc = "Cascade Dispatcher v1.0.1" }
)

foreach ($file in $CoreFiles) {
    if (Test-Path $file.Src) {
        Copy-Item $file.Src "$OutputPath\$($file.Dst)"
        Write-Host "  [OK] $($file.Desc)" -ForegroundColor Green
    } else {
        Write-Host "  [MISSING] $($file.Src)" -ForegroundColor Red
    }
}

# ============================================================
# 2. Test Files (MUST READ)
# ============================================================
Write-Host "`n[2/4] Copying test files..." -ForegroundColor Yellow

$TestDir = Join-Path $BuffBase "test"
$TestFiles = @(
    @{ Src = (Join-Path $TestDir "PathBindingTest.as"); Dst = "2_Test\01_PathBindingTest.as"; Desc = "PathBinding Test v1.3 (89 assertions)" },
    @{ Src = (Join-Path $TestDir "BuffManagerTest.as"); Dst = "2_Test\02_BuffManagerTest.as"; Desc = "Core Functionality Test" },
    @{ Src = (Join-Path $TestDir "BugfixRegressionTest.as"); Dst = "2_Test\03_BugfixRegressionTest.as"; Desc = "Bugfix Regression Test" }
)

foreach ($file in $TestFiles) {
    if (Test-Path $file.Src) {
        Copy-Item $file.Src "$OutputPath\$($file.Dst)"
        Write-Host "  [OK] $($file.Desc)" -ForegroundColor Green
    } else {
        Write-Host "  [MISSING] $($file.Src)" -ForegroundColor Red
    }
}

# ============================================================
# 3. Documentation (MUST READ)
# ============================================================
Write-Host "`n[3/4] Copying documentation..." -ForegroundColor Yellow

$DocFiles = @(
    @{ Src = (Join-Path $ScriptDir "BuffSystem_NestedProperty_Review_Prompt_v2_CN.md"); Dst = "3_Docs\00_REVIEW_PROMPT.md"; Desc = "Review Prompt (READ FIRST)" },
    @{ Src = (Join-Path $BuffBase "BuffManager.md"); Dst = "3_Docs\01_BuffManager_Design.md"; Desc = "Design Doc v3.0 (with test results)" },
    @{ Src = (Join-Path $ScriptDir "BuffSystem_NestedProperty_Review_Feedback.md"); Dst = "3_Docs\02_Previous_Feedback.md"; Desc = "Previous Review Feedback" }
)

foreach ($file in $DocFiles) {
    if (Test-Path $file.Src) {
        Copy-Item $file.Src "$OutputPath\$($file.Dst)"
        Write-Host "  [OK] $($file.Desc)" -ForegroundColor Green
    } else {
        Write-Host "  [SKIP] $($file.Src)" -ForegroundColor DarkYellow
    }
}

# ============================================================
# 4. Support Files (Reference)
# ============================================================
Write-Host "`n[4/4] Copying support files..." -ForegroundColor Yellow

$SupportFiles = @(
    @{ Src = (Join-Path $BuffBase "PodBuff.as"); Dst = "4_Support\01_PodBuff.as"; Desc = "PodBuff" },
    @{ Src = (Join-Path $BuffBase "MetaBuff.as"); Dst = "4_Support\02_MetaBuff.as"; Desc = "MetaBuff" },
    @{ Src = (Join-Path $BuffBase "BaseBuff.as"); Dst = "4_Support\03_BaseBuff.as"; Desc = "BaseBuff" },
    @{ Src = (Join-Path $BuffBase "IBuff.as"); Dst = "4_Support\04_IBuff.as"; Desc = "IBuff Interface" },
    @{ Src = (Join-Path $BuffBase "BuffCalculator.as"); Dst = "4_Support\05_BuffCalculator.as"; Desc = "Buff Calculator" },
    @{ Src = (Join-Path $BuffBase "IBuffCalculator.as"); Dst = "4_Support\06_IBuffCalculator.as"; Desc = "Calculator Interface" },
    @{ Src = (Join-Path $BuffBase "BuffCalculationType.as"); Dst = "4_Support\07_BuffCalculationType.as"; Desc = "Calculation Types" },
    @{ Src = (Join-Path $BuffBase "BuffContext.as"); Dst = "4_Support\08_BuffContext.as"; Desc = "Buff Context" },
    @{ Src = (Join-Path $BuffBase "StateInfo.as"); Dst = "4_Support\09_StateInfo.as"; Desc = "State Info" }
)

# Add PropertyAccessor if found
if ($PropertyBase -ne $null) {
    $SupportFiles = @(
        @{ Src = (Join-Path $PropertyBase "PropertyAccessor.as"); Dst = "4_Support\00_PropertyAccessor.as"; Desc = "Property Accessor" }
    ) + $SupportFiles
}

foreach ($file in $SupportFiles) {
    if (Test-Path $file.Src) {
        Copy-Item $file.Src "$OutputPath\$($file.Dst)"
        Write-Host "  [OK] $($file.Desc)" -ForegroundColor Green
    } else {
        Write-Host "  [MISSING] $($file.Src)" -ForegroundColor Red
    }
}

# ============================================================
# Optional: Business Files
# ============================================================
if ($IncludeBusiness) {
    Write-Host "`n[Optional] Copying business files..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Force -Path "$OutputPath\5_Business" | Out-Null

    # Find business directories dynamically
    foreach ($d in $scriptDirs) {
        # Look for logic directory (contains equipment config)
        $equipFile = Get-ChildItem -Path $d.FullName -Filter "*玩家装备配置*" -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($equipFile) {
            Copy-Item $equipFile.FullName "$OutputPath\5_Business\01_PlayerEquipConfig.as"
            Write-Host "  [OK] Player Equipment Config" -ForegroundColor Green
        }

        # Look for DressupInitializer
        $dressupFile = Get-ChildItem -Path $d.FullName -Filter "DressupInitializer.as" -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($dressupFile) {
            Copy-Item $dressupFile.FullName "$OutputPath\5_Business\02_DressupInitializer.as"
            Write-Host "  [OK] DressupInitializer" -ForegroundColor Green
        }
    }
}

# ============================================================
# Generate File List
# ============================================================
Write-Host "`n[Summary] Generating file list..." -ForegroundColor Yellow

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$FileList = @"
# BuffSystem v3.0.2 Review Package
# Generated: $timestamp

## Reading Order

1. **3_Docs/00_REVIEW_PROMPT.md** - Review prompt (read this first)
2. **1_Core/** - Core implementation (focus review)
   - 01_BuffManager.as v3.0.2
   - 02_PropertyContainer.as v2.6.2
   - 03_CascadeDispatcher.as v1.0.1
3. **2_Test/** - Test code (verify coverage)
   - 01_PathBindingTest.as v1.3 (89 assertions)
4. **3_Docs/01_BuffManager_Design.md** - Design doc with test results archive
5. **4_Support/** - Support files (reference as needed)

## File Statistics

"@

$TotalFiles = 0
$TotalLines = 0

Get-ChildItem -Path $OutputPath -Recurse -File | ForEach-Object {
    $lines = (Get-Content $_.FullName -ErrorAction SilentlyContinue | Measure-Object -Line).Lines
    $relPath = $_.FullName.Substring($OutputPath.Length + 1)
    $FileList += "- $relPath ($lines lines)`n"
    $TotalFiles++
    $TotalLines += $lines
}

$FileList += "`n## Total: $TotalFiles files, $TotalLines lines of code`n"

Set-Content -Path "$OutputPath\README.md" -Value $FileList -Encoding UTF8

Write-Host "`n=== Package Complete ===" -ForegroundColor Cyan
Write-Host "Output: $OutputPath" -ForegroundColor White
Write-Host "Files: $TotalFiles" -ForegroundColor White
Write-Host "Lines: $TotalLines" -ForegroundColor White

# Create ZIP
$ZipPath = Join-Path $ScriptDir "BuffSystem_v3.0.2_Review.zip"
if (Test-Path $ZipPath) {
    Remove-Item $ZipPath -Force
}
Compress-Archive -Path "$OutputPath\*" -DestinationPath $ZipPath -Force
Write-Host "`nZIP created: $ZipPath" -ForegroundColor Green

# ============================================================
# Auto-cleanup: Remove intermediate directory
# ============================================================
Write-Host "`n[Cleanup] Removing intermediate directory..." -ForegroundColor Yellow
if (Test-Path $OutputPath) {
    Remove-Item -Recurse -Force $OutputPath
    Write-Host "  [OK] Deleted: $OutputPath" -ForegroundColor Green
}
Write-Host "`n=== Done ===" -ForegroundColor Cyan
