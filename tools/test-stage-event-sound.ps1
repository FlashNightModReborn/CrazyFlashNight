param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoRoot "scripts\类定义\org\flashNight\arki\scene\StageEvent.as"
$bytes = [System.IO.File]::ReadAllBytes($sourcePath)
$source = [System.Text.Encoding]::UTF8.GetString($bytes)
$passed = 0
$failed = 0

function Assert-StageEventSound {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if ($Condition) {
        $script:passed++
        Write-Host "[PASS] $Message"
    } else {
        $script:failed++
        Write-Host "[FAIL] $Message"
    }
}

Assert-StageEventSound ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) "StageEvent.as 保持 UTF-8 BOM"
Assert-StageEventSound ($source -match 'public var sound:Array;') "Sound 权威字段保持数组类型"
Assert-StageEventSound ($source -match 'sound\s*=\s*ObjectUtil\.toArray\(data\.Sound\);') "单值与多值在构造器统一归一化"
Assert-StageEventSound ($source -match '// 播放音效\s*\r?\n\s*executeSound\(\);') "execute 主流程调用音效执行器"
Assert-StageEventSound ($source -match 'private function executeSound\(\):Void') "音效执行器存在"
Assert-StageEventSound ($source -match 'if \(this\.sound == null\) return;') "空声明 fail-safe"
Assert-StageEventSound ($source -match 'for \(var i:Number = 0; i < this\.sound\.length; i\+\+\)') "遍历 0..N 个音效并保持声明顺序"
Assert-StageEventSound ($source -match 'var soundName = this\.sound\[i\];') "逐项读取音效名"
Assert-StageEventSound ($source -match 'typeof soundName === "string" && soundName\.length > 0') "非法值与空字符串 fail-safe"
Assert-StageEventSound ($source -match '_root\.播放音效\(soundName\);') "每个合法音效调用一次权威播放入口"
Assert-StageEventSound ($source -notmatch 'typeof this\.sound === "string"') "移除永远不可达的数组按字符串判断"

Write-Host "StageEvent Sound checks: $passed passed, $failed failed"
if ($failed -gt 0) {
    exit 1
}
