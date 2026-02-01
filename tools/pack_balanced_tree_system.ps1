# BalancedTreeSystem - Pack Script
# Pack balanced tree data structure system for external architecture review
# Focus: Self-balancing BST implementations (AVL, WAVL, Red-Black, Zip Tree)

# Set UTF-8 encoding for Chinese path support
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$baseDir = "c:\Program Files (x86)\Steam\steamapps\common\CRAZYFLASHER7StandAloneStarter\resources"
$toolsDir = "$baseDir\tools"
$scriptsDir = "$baseDir\scripts"
$outputZip = "$toolsDir\BalancedTreeSystem_Review_v1.0.zip"
$tempDir = "$toolsDir\BalancedTreeSystem_Review"

# Clean old files
if (Test-Path $tempDir) { Remove-Item -Recurse -Force $tempDir }
if (Test-Path $outputZip) { Remove-Item -Force $outputZip }

# Create directory structure
$directories = @(
    "$tempDir\DataStructures\Core",
    "$tempDir\DataStructures\Trees",
    "$tempDir\DataStructures\Nodes",
    "$tempDir\DataStructures\Application",
    "$tempDir\DataStructures\Docs",
    "$tempDir\DataStructures\Tests",
    "$tempDir\Dependencies"
)

foreach ($dir in $directories) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

Write-Host "=== BalancedTreeSystem Pack Script ===" -ForegroundColor Cyan
Write-Host "Purpose: Pack files for external architecture review" -ForegroundColor Gray
Write-Host ""

$totalFiles = 0
$missingFiles = @()

# ============================================================
# 1. Interface & Abstract Base (3 files)
# ============================================================
Write-Host "[1/8] Copying Interface & Abstract Base files..." -ForegroundColor Yellow

$coreFiles = @(
    "IBalancedSearchTree.as",
    "ITreeNode.as",
    "AbstractBalancedSearchTree.as"
)

foreach ($fileName in $coreFiles) {
    $file = Get-ChildItem -Path $scriptsDir -Recurse -Filter $fileName | Where-Object { $_.FullName -like "*DataStructures*" -and $_.FullName -notlike "*test*" -and $_.FullName -notlike "*Test*" } | Select-Object -First 1
    if ($file) {
        Copy-Item $file.FullName "$tempDir\DataStructures\Core\"
        Write-Host "  + $fileName" -ForegroundColor Green
        $totalFiles++
    } else {
        Write-Host "  ! Not found: $fileName" -ForegroundColor Red
        $missingFiles += $fileName
    }
}

# ============================================================
# 2. Tree Implementations (5 files)
# ============================================================
Write-Host "`n[2/8] Copying Tree Implementation files..." -ForegroundColor Yellow

$treeFiles = @(
    "AVLTree.as",
    "WAVLTree.as",
    "RedBlackTree.as",
    "LLRedBlackTree.as",
    "ZipTree.as"
)

foreach ($fileName in $treeFiles) {
    $file = Get-ChildItem -Path $scriptsDir -Recurse -Filter $fileName | Where-Object { $_.FullName -like "*DataStructures*" -and $_.FullName -notlike "*test*" -and $_.FullName -notlike "*Test*" } | Select-Object -First 1
    if ($file) {
        Copy-Item $file.FullName "$tempDir\DataStructures\Trees\"
        Write-Host "  + $fileName" -ForegroundColor Green
        $totalFiles++
    } else {
        Write-Host "  ! Not found: $fileName" -ForegroundColor Red
        $missingFiles += $fileName
    }
}

# ============================================================
# 3. Node Classes (4 files)
# ============================================================
Write-Host "`n[3/8] Copying Node Class files..." -ForegroundColor Yellow

$nodeFiles = @(
    "AVLNode.as",
    "WAVLNode.as",
    "RedBlackNode.as",
    "ZipNode.as"
)

foreach ($fileName in $nodeFiles) {
    $file = Get-ChildItem -Path $scriptsDir -Recurse -Filter $fileName | Where-Object { $_.FullName -like "*DataStructures*" -and $_.FullName -notlike "*test*" -and $_.FullName -notlike "*Test*" } | Select-Object -First 1
    if ($file) {
        Copy-Item $file.FullName "$tempDir\DataStructures\Nodes\"
        Write-Host "  + $fileName" -ForegroundColor Green
        $totalFiles++
    } else {
        Write-Host "  ! Not found: $fileName" -ForegroundColor Red
        $missingFiles += $fileName
    }
}

# ============================================================
# 4. Application Layer (2 files)
# ============================================================
Write-Host "`n[4/8] Copying Application Layer files..." -ForegroundColor Yellow

$appFiles = @(
    "TreeSet.as",
    "OrderedMap.as"
)

foreach ($fileName in $appFiles) {
    $file = Get-ChildItem -Path $scriptsDir -Recurse -Filter $fileName | Where-Object { $_.FullName -like "*DataStructures*" -and $_.FullName -notlike "*test*" -and $_.FullName -notlike "*Test*" } | Select-Object -First 1
    if ($file) {
        Copy-Item $file.FullName "$tempDir\DataStructures\Application\"
        Write-Host "  + $fileName" -ForegroundColor Green
        $totalFiles++
    } else {
        Write-Host "  ! Not found: $fileName" -ForegroundColor Red
        $missingFiles += $fileName
    }
}

# ============================================================
# 5. Documentation (5 files)
# ============================================================
Write-Host "`n[5/8] Copying Documentation files..." -ForegroundColor Yellow

$docFiles = @(
    "AVLTree.md",
    "WAVLTree.md",
    "RedBlackTree.md",
    "ZipTree.md",
    "TreeSet.md",
    "OrderedMap.md"
)

foreach ($fileName in $docFiles) {
    $file = Get-ChildItem -Path $scriptsDir -Recurse -Filter $fileName | Where-Object { $_.FullName -like "*DataStructures*" } | Select-Object -First 1
    if ($file) {
        Copy-Item $file.FullName "$tempDir\DataStructures\Docs\"
        Write-Host "  + $fileName" -ForegroundColor Green
        $totalFiles++
    } else {
        Write-Host "  ? Optional not found: $fileName" -ForegroundColor DarkYellow
    }
}

# ============================================================
# 6. Test Files (6 files)
# ============================================================
Write-Host "`n[6/8] Copying Test files..." -ForegroundColor Yellow

$testFiles = @(
    "AVLTreeTest.as",
    "WAVLTreeTest.as",
    "RedBlackTreeTest.as",
    "ZipTreeTest.as",
    "TreeSetTest.as",
    "OrderedMapTest.as"
)

foreach ($fileName in $testFiles) {
    $file = Get-ChildItem -Path $scriptsDir -Recurse -Filter $fileName | Where-Object { $_.FullName -like "*DataStructures*" } | Select-Object -First 1
    if ($file) {
        Copy-Item $file.FullName "$tempDir\DataStructures\Tests\"
        Write-Host "  + $fileName" -ForegroundColor Green
        $totalFiles++
    } else {
        Write-Host "  ? Optional not found: $fileName" -ForegroundColor DarkYellow
    }
}

# ============================================================
# 7. Dependencies (2 files)
# ============================================================
Write-Host "`n[7/8] Copying Dependencies..." -ForegroundColor Yellow

$depFiles = @(
    "TimSort.as",
    "StringUtils.as"
)

foreach ($fileName in $depFiles) {
    $file = Get-ChildItem -Path $scriptsDir -Recurse -Filter $fileName | Where-Object { $_.FullName -notlike "*test*" -and $_.FullName -notlike "*Test*" } | Select-Object -First 1
    if ($file) {
        Copy-Item $file.FullName "$tempDir\Dependencies\"
        Write-Host "  + $fileName" -ForegroundColor Green
        $totalFiles++
    } else {
        Write-Host "  ? Optional not found: $fileName" -ForegroundColor DarkYellow
    }
}

# Also copy IIterator if exists
$iteratorFile = Get-ChildItem -Path $scriptsDir -Recurse -Filter "IIterator.as" | Select-Object -First 1
if ($iteratorFile) {
    Copy-Item $iteratorFile.FullName "$tempDir\Dependencies\"
    Write-Host "  + IIterator.as" -ForegroundColor Green
    $totalFiles++
}

# ============================================================
# 8. Review Prompt Document
# ============================================================
Write-Host "`n[8/8] Copying Review Prompt..." -ForegroundColor Yellow

$promptFile = "$toolsDir\BalancedTreeSystem_Review_Prompt_CN.md"
if (Test-Path $promptFile) {
    Copy-Item $promptFile "$tempDir\"
    Write-Host "  + BalancedTreeSystem_Review_Prompt_CN.md" -ForegroundColor Cyan
    $totalFiles++
} else {
    Write-Host "  ! Not found: BalancedTreeSystem_Review_Prompt_CN.md" -ForegroundColor Red
    Write-Host "    Please create the review prompt document first!" -ForegroundColor Yellow
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
Write-Host "BalancedTreeSystem_Review/"
Write-Host "  DataStructures/"
Write-Host "    Core/           (3 files: IBalancedSearchTree, ITreeNode, AbstractBalancedSearchTree)"
Write-Host "    Trees/          (5 files: AVLTree, WAVLTree, RedBlackTree, LLRedBlackTree, ZipTree)"
Write-Host "    Nodes/          (4 files: AVLNode, WAVLNode, RedBlackNode, ZipNode)"
Write-Host "    Application/    (2 files: TreeSet, OrderedMap)"
Write-Host "    Docs/           (documentation files)"
Write-Host "    Tests/          (test files)"
Write-Host "  Dependencies/     (TimSort, StringUtils, IIterator)"
Write-Host "  BalancedTreeSystem_Review_Prompt_CN.md"

Write-Host "`n=============================================" -ForegroundColor Cyan
Write-Host "Review Focus Areas:" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "1. Algorithm Correctness: AVL/WAVL/RB/Zip tree invariants" -ForegroundColor White
Write-Host "2. Performance Optimization: AS2-specific optimizations" -ForegroundColor White
Write-Host "3. Architecture Design: Interface/Abstract/Facade pattern" -ForegroundColor White
Write-Host "4. WAVL Bug Fix Verification: (2,2) non-leaf node detection" -ForegroundColor White
Write-Host "5. Comparative Analysis: Performance trade-offs between trees" -ForegroundColor White

# Cleanup temp folder
Remove-Item -Recurse -Force $tempDir
Write-Host "`nTemp folder cleaned." -ForegroundColor Gray
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Magenta
Write-Host "1. Upload the ZIP file to GPT Pro or other AI review service"
Write-Host "2. Include the prompt document as the first message"
Write-Host "3. Ask for algorithm correctness and performance review"
Write-Host ""
