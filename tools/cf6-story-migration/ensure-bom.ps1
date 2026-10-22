# Ensure UTF-8 BOM on given .as files (byte-level, PS5.1-safe).
# Usage: powershell -NoProfile -File ensure-bom.ps1 <file1> [file2 ...]
chcp.com 65001 | Out-Null
foreach ($f in $args) {
    $b = [System.IO.File]::ReadAllBytes($f)
    if ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) {
        Write-Output "$f BOM ok"
    } else {
        $bom = [byte[]](0xEF, 0xBB, 0xBF)
        [System.IO.File]::WriteAllBytes($f, $bom + $b)
        Write-Output "$f BOM added"
    }
}
