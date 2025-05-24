# ================================================
# �޸İ�ű�������ԭʼID��������Ԥ������
# ================================================

# -----------------------------
# ��������
# -----------------------------
$inputFile = "C:\Users\admin\Desktop\������ͼ��\AllInOne.xml"
$outputFolder = Join-Path (Split-Path $inputFile -Parent) "Output"
$blockSize = 512  # ���޸�Ϊ512

# -----------------------------
# ��ʼ�����Ŀ¼
# -----------------------------
if (!(Test-Path $outputFolder)) {
    New-Item -ItemType Directory -Path $outputFolder | Out-Null
}

# -----------------------------
# ��־��¼����
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
Log-Message "�ű����� - ����ԭʼIDģʽ"

# -----------------------------
# XML������������
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
# ��ȡ����֤XML
# -----------------------------
try {
    [xml]$xmlData = Get-Content $inputFile -Encoding UTF8
    Log-Message "�ɹ���ȡXML�ļ���$inputFile"
} catch {
    Log-Message "XML��ȡʧ�ܣ�$_"
    exit
}

# -----------------------------
# ����׼��
# -----------------------------
$items = $xmlData.root.item
if (-not $items) {
    Log-Message "δ�ҵ�<item>�ڵ�"
    exit
}
Log-Message "����$($items.Count)��item�ڵ�"

# �ռ�ȫ��ID������ͻ
$globalIDs = @{}
$conflictCount = 0
foreach ($item in $items) {
    $id = Get-ItemID $item
    if ($null -ne $id) {
        if ($globalIDs.ContainsKey($id)) {
            $conflictCount++
            Log-Message "����ID��ͻ��ID $id �ظ�����"
        } else {
            $globalIDs[$id] = $true
        }
    }
}
if ($conflictCount -gt 0) {
    Log-Message "���棺����$conflictCount��ID��ͻ"
}

# -----------------------------
# ���ദ��
# -----------------------------
$classificationMap = @{}
$unclassifiedCount = 0

foreach ($item in $items) {
    $type = Get-NodeValue $item "type"
    $use = Get-NodeValue $item "use"
    
    if ([string]::IsNullOrWhiteSpace($type) -or [string]::IsNullOrWhiteSpace($use)) {
        $key = "δ����_ȱʧ����"
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
# ���ɷ����ļ�
# -----------------------------
$allocationReport = @()
$maxGlobalID = if ($globalIDs.Count -gt 0) { ($globalIDs.Keys | Measure -Maximum).Maximum } else { 0 }

foreach ($key in $classificationMap.Keys) {
    $categoryData = $classificationMap[$key]
    $categoryIDs = $categoryData.IDs | Sort-Object
    
    # ����Ԥ������
    $categoryMaxID = if ($categoryIDs.Count -gt 0) { $categoryIDs[-1] } else { 0 }
    $reserveStart = $categoryMaxID + 1
    $reserveEnd = $reserveStart + $blockSize - 1
    
    # ����XML�ĵ�
    $newXml = New-Object System.Xml.XmlDocument
    $newXml.AppendChild($newXml.CreateXmlDeclaration("1.0", "UTF-8", $null)) | Out-Null
    
    # ���ע��
    $commentText = @"
����ID��[$(($categoryIDs | Sort-Object) -join ', ')]
Ԥ��ID���䣺${reserveStart}-${reserveEnd}
"@
    $newXml.AppendChild($newXml.CreateComment($commentText)) | Out-Null
    
    # �������ڵ�
    $root = $newXml.CreateElement("root")
    $newXml.AppendChild($root) | Out-Null
    
    # ����ԭʼ�ڵ㣨����ԭʼ˳��
    foreach ($item in $categoryData.Items) {
        $importedNode = $newXml.ImportNode($item, $true)
        $root.AppendChild($importedNode) | Out-Null
    }
    
    # �����ļ�
    $fileName = "$key.xml".Replace(" ", "_")
    $outputPath = Join-Path $outputFolder $fileName
    $newXml.Save($outputPath)
    Log-Message "���ɷ����ļ���$fileName"
    
    # ��¼������Ϣ
    $allocationReport += [PSCustomObject]@{
        Category = $key
        UsedIDs = $categoryIDs -join ', '
        ReservedRange = "${reserveStart}-${reserveEnd}"
        ItemCount = $categoryData.Items.Count
    }
}

# -----------------------------
# ���ɱ���
# -----------------------------
$reportContent = @"
ȫ��ԭʼ���ID: $maxGlobalID
�����ļ�����: $($classificationMap.Count)
δ����������: $unclassifiedCount
ID��ͻ����: $conflictCount

��������������
$($allocationReport | Format-Table | Out-String)
"@

$reportPath = Join-Path $outputFolder "id_allocation_report.txt"
$reportContent | Out-File $reportPath -Encoding UTF8
Log-Message "����������ɣ�id_allocation_report.txt"

Log-Message "������ɡ����Ŀ¼��$outputFolder"
