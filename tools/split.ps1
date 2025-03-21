# ================================================
# 修改版脚本：保留原始ID，仅计算预留区间
# ================================================

# -----------------------------
# 参数设置
# -----------------------------
$inputFile = "C:\Users\admin\Desktop\待处理图包\AllInOne.xml"
$outputFolder = Join-Path (Split-Path $inputFile -Parent) "Output"
$blockSize = 512  # 可修改为512

# -----------------------------
# 初始化输出目录
# -----------------------------
if (!(Test-Path $outputFolder)) {
    New-Item -ItemType Directory -Path $outputFolder | Out-Null
}

# -----------------------------
# 日志记录函数
# -----------------------------
$logFile = Join-Path $outputFolder "process_log.txt"
if (Test-Path $logFile) { Remove-Item $logFile }
function Log-Message {
    param([string]$message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] $message"
    Write-Output $line
    Add-Content -Path $logFile -Value $line
}
Log-Message "脚本启动 - 保留原始ID模式"

# -----------------------------
# XML解析辅助函数
# -----------------------------
function Get-NodeValue($item, $nodeName) {
    $node = $item.SelectSingleNode($nodeName)
    if ($node -and -not [string]::IsNullOrWhiteSpace($node.InnerText)) {
        return $node.InnerText.Trim()
    }
    return $null
}

function Get-ItemID($item) {
    $idStr = Get-NodeValue $item "id"
    if ($idStr -and $idStr -match '^\d+$') {
        return [int]$idStr
    }
    return $null
}

# -----------------------------
# 读取并验证XML
# -----------------------------
try {
    [xml]$xmlData = Get-Content $inputFile -Encoding UTF8
    Log-Message "成功读取XML文件：$inputFile"
} catch {
    Log-Message "XML读取失败：$_"
    exit
}

# -----------------------------
# 数据准备
# -----------------------------
$items = $xmlData.root.item
if (-not $items) {
    Log-Message "未找到<item>节点"
    exit
}
Log-Message "发现$($items.Count)个item节点"

# 收集全局ID并检查冲突
$globalIDs = @{}
$conflictCount = 0
foreach ($item in $items) {
    $id = Get-ItemID $item
    if ($null -ne $id) {
        if ($globalIDs.ContainsKey($id)) {
            $conflictCount++
            Log-Message "发现ID冲突：ID $id 重复出现"
        } else {
            $globalIDs[$id] = $true
        }
    }
}
if ($conflictCount -gt 0) {
    Log-Message "警告：发现$conflictCount次ID冲突"
}

# -----------------------------
# 分类处理
# -----------------------------
$classificationMap = @{}
$unclassifiedCount = 0

foreach ($item in $items) {
    $type = Get-NodeValue $item "type"
    $use = Get-NodeValue $item "use"
    
    if ([string]::IsNullOrWhiteSpace($type) -or [string]::IsNullOrWhiteSpace($use)) {
        $key = "未分类_缺失属性"
        $unclassifiedCount++
    } else {
        $safeType = $type -replace '[\\/:*?"<>|]', '_'
        $safeUse = $use -replace '[\\/:*?"<>|]', '_'
        $key = "${safeType}_${safeUse}"
    }

    if (-not $classificationMap.ContainsKey($key)) {
        $classificationMap[$key] = @{
            Items = New-Object System.Collections.Generic.List[object]
            IDs = New-Object System.Collections.Generic.List[int]
        }
    }
    $classificationMap[$key].Items.Add($item)
    
    if ($id = Get-ItemID $item) {
        $classificationMap[$key].IDs.Add($id)
    }
}

# -----------------------------
# 生成分类文件
# -----------------------------
$allocationReport = @()
$maxGlobalID = if ($globalIDs.Count -gt 0) { ($globalIDs.Keys | Measure -Maximum).Maximum } else { 0 }

foreach ($key in $classificationMap.Keys) {
    $categoryData = $classificationMap[$key]
    $categoryIDs = $categoryData.IDs | Sort-Object
    
    # 计算预留区间
    $categoryMaxID = if ($categoryIDs.Count -gt 0) { $categoryIDs[-1] } else { 0 }
    $reserveStart = $categoryMaxID + 1
    $reserveEnd = $reserveStart + $blockSize - 1
    
    # 创建XML文档
    $newXml = New-Object System.Xml.XmlDocument
    $newXml.AppendChild($newXml.CreateXmlDeclaration("1.0", "UTF-8", $null)) | Out-Null
    
    # 添加注释
    $commentText = @"
已用ID：[$(($categoryIDs | Sort-Object) -join ', ')]
预留ID区间：${reserveStart}-${reserveEnd}
"@
    $newXml.AppendChild($newXml.CreateComment($commentText)) | Out-Null
    
    # 创建根节点
    $root = $newXml.CreateElement("root")
    $newXml.AppendChild($root) | Out-Null
    
    # 导入原始节点（保持原始顺序）
    foreach ($item in $categoryData.Items) {
        $importedNode = $newXml.ImportNode($item, $true)
        $root.AppendChild($importedNode) | Out-Null
    }
    
    # 保存文件
    $fileName = "$key.xml".Replace(" ", "_")
    $outputPath = Join-Path $outputFolder $fileName
    $newXml.Save($outputPath)
    Log-Message "生成分类文件：$fileName"
    
    # 记录分配信息
    $allocationReport += [PSCustomObject]@{
        Category = $key
        UsedIDs = $categoryIDs -join ', '
        ReservedRange = "${reserveStart}-${reserveEnd}"
        ItemCount = $categoryData.Items.Count
    }
}

# -----------------------------
# 生成报告
# -----------------------------
$reportContent = @"
全局原始最大ID: $maxGlobalID
分类文件数量: $($classificationMap.Count)
未分类项数量: $unclassifiedCount
ID冲突次数: $conflictCount

各分类分配情况：
$($allocationReport | Format-Table | Out-String)
"@

$reportPath = Join-Path $outputFolder "id_allocation_report.txt"
$reportContent | Out-File $reportPath -Encoding UTF8
Log-Message "报告生成完成：id_allocation_report.txt"

Log-Message "处理完成。输出目录：$outputFolder"
