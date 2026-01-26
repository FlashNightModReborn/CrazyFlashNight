# BuffSystem v3.0.2 Code Review Package Script (v3)
# Pack files for GPT Pro strict review
# Includes business code for unbridged property analysis
# Auto-cleans intermediate directory after ZIP creation

param(
    [string]$OutputDir = ".\review_package_v3"
)

$ErrorActionPreference = "Stop"

# Get script directory and resolve absolute paths
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ResourcesDir = Split-Path -Parent $ScriptDir
$ScriptsBase = Join-Path $ResourcesDir "scripts"

Write-Host "Script Dir: $ScriptDir" -ForegroundColor DarkGray
Write-Host "Scripts Base: $ScriptsBase" -ForegroundColor DarkGray

# === Dynamic path discovery ===
$BuffBase = $null
$PropertyBase = $null
$UnitBase = $null

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

    $testUnitPath = Join-Path $d.FullName "org\flashNight\arki\unit"
    if (Test-Path $testUnitPath) {
        $UnitBase = $testUnitPath
        Write-Host "Found Unit Base: $UnitBase" -ForegroundColor DarkGray
    }
}

if ($null -eq $BuffBase) {
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
New-Item -ItemType Directory -Force -Path "$OutputPath\5_Business" | Out-Null

Write-Host "`n=== BuffSystem v3.0.2 Review Package (with Business Code) ===" -ForegroundColor Cyan

# ============================================================
# 1. Core Implementation Files (MUST READ)
# ============================================================
Write-Host "`n[1/5] Copying core implementation files..." -ForegroundColor Yellow

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
Write-Host "`n[2/5] Copying test files..." -ForegroundColor Yellow

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
Write-Host "`n[3/5] Copying documentation..." -ForegroundColor Yellow

$DocFiles = @(
    @{ Src = (Join-Path $ScriptDir "BuffSystem_NestedProperty_Review_Prompt_v2_CN.md"); Dst = "3_Docs\00_REVIEW_PROMPT.md"; Desc = "Review Prompt (READ FIRST)" },
    @{ Src = (Join-Path $ScriptDir "UnbridgedProperties_BusinessUsage.md"); Dst = "3_Docs\01_BUSINESS_USAGE_ANALYSIS.md"; Desc = "Business Usage Analysis (IMPORTANT)" },
    @{ Src = (Join-Path $BuffBase "BuffManager.md"); Dst = "3_Docs\02_BuffManager_Design.md"; Desc = "Design Doc v3.0 (with test results)" },
    @{ Src = (Join-Path $ScriptDir "BuffSystem_NestedProperty_Review_Feedback.md"); Dst = "3_Docs\03_Previous_Feedback.md"; Desc = "Previous Review Feedback" },
    @{ Src = (Join-Path $ScriptDir "BuffSystem_NestedProperty_Review_Feedback_V2.md"); Dst = "3_Docs\04_V2_Cross_Review_Feedback.md"; Desc = "V2 Cross Review Feedback" }
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
Write-Host "`n[4/5] Copying support files..." -ForegroundColor Yellow

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
if ($null -ne $PropertyBase) {
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
# 5. Business Files (Critical for bridge evaluation)
# ============================================================
Write-Host "`n[5/5] Copying business files (for unbridged property analysis)..." -ForegroundColor Yellow

# Business files using known subdirectory paths
# Old buff system (scripts/[ClassDef]/主角模板数值buff.as)
foreach ($d in $scriptDirs) {
    $testPath = Join-Path $d.FullName "主角模板数值buff.as"
    if (Test-Path $testPath) {
        Copy-Item $testPath "$OutputPath\5_Business\00_OldBuffSystem.as"
        Write-Host "  [OK] Old Buff System" -ForegroundColor Green
        break
    }
}

# Equipment/Unit functions (scripts/[Logic]/[UnitFunc]/*.as and scripts/[Logic]/[WeaponFunc]/*.as)
foreach ($d in $scriptDirs) {
    # Look for unit function subdir
    Get-ChildItem -Path $d.FullName -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $subDir = $_
        # Equipment config
        $equipPath = Join-Path $subDir.FullName "单位函数_fs_玩家装备配置.as"
        if (Test-Path $equipPath) {
            Copy-Item $equipPath "$OutputPath\5_Business\03_PlayerEquipConfig.as"
            Write-Host "  [OK] Player Equipment Config" -ForegroundColor Green
        }
        # Active skill
        $activeSkillPath = Join-Path $subDir.FullName "单位函数_雾人_aka_fs_主动战技.as"
        if (Test-Path $activeSkillPath) {
            Copy-Item $activeSkillPath "$OutputPath\5_Business\07_UnitFunc_ActiveSkill.as"
            Write-Host "  [OK] Active Skill" -ForegroundColor Green
        }
        # Player skill
        $playerSkillPath = Join-Path $subDir.FullName "单位函数_lsy_主角技能.as"
        if (Test-Path $playerSkillPath) {
            Copy-Item $playerSkillPath "$OutputPath\5_Business\08_UnitFunc_PlayerSkill.as"
            Write-Host "  [OK] Player Skill" -ForegroundColor Green
        }
        # Weapon functions
        $lightsaberPath = Join-Path $subDir.FullName "主唱光剑.as"
        if (Test-Path $lightsaberPath) {
            Copy-Item $lightsaberPath "$OutputPath\5_Business\04_WeaponFunc_Lightsaber.as"
            Write-Host "  [OK] Lightsaber" -ForegroundColor Green
        }
        $guitarPath = Join-Path $subDir.FullName "吉他喷火.as"
        if (Test-Path $guitarPath) {
            Copy-Item $guitarPath "$OutputPath\5_Business\05_WeaponFunc_Guitar.as"
            Write-Host "  [OK] Guitar" -ForegroundColor Green
        }
        $keyboardPath = Join-Path $subDir.FullName "键盘镰刀.as"
        if (Test-Path $keyboardPath) {
            Copy-Item $keyboardPath "$OutputPath\5_Business\06_WeaponFunc_Keyboard.as"
            Write-Host "  [OK] Keyboard" -ForegroundColor Green
        }
    }
}

# DressupInitializer (contains += operations)
if ($UnitBase) {
    $dressupFile = Join-Path $UnitBase "UnitComponent\Initializer\DressupInitializer.as"
    if (Test-Path $dressupFile) {
        Copy-Item $dressupFile "$OutputPath\5_Business\01_DressupInitializer.as"
        Write-Host "  [OK] DressupInitializer (+=)" -ForegroundColor Green
    }

    # PlayerInfoProvider (read patterns)
    $playerInfoFile = Join-Path $UnitBase "PlayerInfoProvider.as"
    if (Test-Path $playerInfoFile) {
        Copy-Item $playerInfoFile "$OutputPath\5_Business\02_PlayerInfoProvider.as"
        Write-Host "  [OK] PlayerInfoProvider (read patterns)" -ForegroundColor Green
    }
}

# Magic damage handler
$magicDamageFile = Join-Path $BuffBase "..\Damage\MagicDamageHandle.as"
if (Test-Path $magicDamageFile) {
    Copy-Item $magicDamageFile "$OutputPath\5_Business\09_MagicDamageHandle.as"
    Write-Host "  [OK] MagicDamageHandle (魔法抗性)" -ForegroundColor Green
}

# ============================================================
# Generate File List
# ============================================================
Write-Host "`n[Summary] Generating file list..." -ForegroundColor Yellow

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$FileList = @"
# BuffSystem v3.0.2 Review Package (with Business Code Analysis)
# Generated: $timestamp

## Purpose
This package includes business code to help reviewers evaluate the feasibility
of bridging unbridged properties (刀锋利度, 长枪威力, hp满血值, 魔法抗性, etc.)
to the new BuffManager system.

## Reading Order

### Phase 1: Understand the Core System
1. **3_Docs/00_REVIEW_PROMPT.md** - Review prompt (read this first)
2. **1_Core/** - Core implementation
   - 01_BuffManager.as v3.0.2
   - 02_PropertyContainer.as v2.6.2
   - 03_CascadeDispatcher.as v1.0.1

### Phase 2: Understand Business Usage
3. **3_Docs/01_BUSINESS_USAGE_ANALYSIS.md** - Business usage analysis (IMPORTANT)
4. **5_Business/** - Business code with direct property operations
   - 00_OldBuffSystem.as - Current buff implementation
   - 01_DressupInitializer.as - Equipment init (contains +=)
   - 02_PlayerInfoProvider.as - Read patterns
   - 03_PlayerEquipConfig.as - Enhancement calculation
   - 04-06_WeaponFunc_*.as - Weapon mode switching (cache-restore)
   - 07_UnitFunc_ActiveSkill.as - Active skills (+=/-=)

### Phase 3: Evaluate Test Coverage
5. **2_Test/** - Test code
   - 01_PathBindingTest.as v1.3 (89 assertions)

### Phase 4: Reference Materials
6. **3_Docs/02_BuffManager_Design.md** - Design doc with test results
7. **4_Support/** - Support files (reference as needed)

## Key Questions for Reviewers

1. **刀属性.power bridging feasibility**
   - Multiple += / -= operations in business code
   - Cache-restore pattern in weapon functions
   - Is it possible to bridge without breaking existing behavior?

2. **Long gun / Pistol power bridging**
   - DressupInitializer uses += for equipment bonus
   - Should we modify business code or keep in old system?

3. **hp/mp满血值 bridging**
   - Mostly read operations, seems safe
   - What cascade logic is needed?

4. **魔法抗性 bridging**
   - Object type with dynamic keys
   - One buff affects all keys uniformly
   - Need new BuffManager capability for Object-level buffs?

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
$ZipPath = Join-Path $ScriptDir "BuffSystem_v3.0.2_BusinessReview.zip"
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
