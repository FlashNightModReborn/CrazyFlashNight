[CmdletBinding()]
param(
    [string]$Profile = 'tools/weapon-animation/profiles/qjz171.json',
    [string]$PythonExe = 'python',
    [ValidateRange(1, 3600)][int]$TimeoutSeconds = 180
)

chcp.com 65001 | Out-Null
$ErrorActionPreference = 'Stop'
$waRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$waProfilePath = [System.IO.Path]::GetFullPath((Join-Path $waRoot $Profile))
if (-not $waProfilePath.StartsWith($waRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)) { throw 'Profile 路径越界。' }
$waProfile = Get-Content -LiteralPath $waProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
$waRun = [Guid]::NewGuid().ToString('N')
$waRelativeOut = 'tmp/weapon-animation/native/' + $waRun
$waOut = Join-Path $waRoot $waRelativeOut
$waActionPath = Join-Path $waRoot 'scripts/compile_action.jsfl'
$waHasher = [System.Security.Cryptography.SHA256]::Create()
try {
    $waNormalized = $waRoot.TrimEnd('\').ToUpperInvariant()
    $waHash = ([BitConverter]::ToString($waHasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($waNormalized)))).Replace('-', '').Substring(0, 24)
} finally { $waHasher.Dispose() }
$waMutex = [Threading.Mutex]::new($false, 'Local\CF7_FlashCompile_' + $waHash)
$waHeld = $false
$waPatched = $false
Push-Location $waRoot
try {
    try { $waHeld = $waMutex.WaitOne(0) }
    catch [Threading.AbandonedMutexException] {
        $waHeld = $true
        Add-Content -LiteralPath 'scripts/compile_state_uncertain.marker' -Encoding UTF8 -Value 'weapon-animation publish observed an abandoned compile mutex; inspect Flash and late diagnostics before continuing.'
        throw '上一轮 Flash 编译异常退出；原生动画发布未开始。'
    }
    if (-not $waHeld) { throw '已有 Flash 编译正在运行。' }
    if (Test-Path -LiteralPath 'scripts/compile_state_uncertain.marker') { throw '先处理既有编译不确定状态。' }
    & $PythonExe -X utf8 -B tools/weapon-animation/xfl_recoil.py emit-probe --profile $Profile --output-dir $waRelativeOut
    if ($LASTEXITCODE -ne 0) { throw '无法生成原生校验输入。' }
    $waOriginal = [IO.File]::ReadAllBytes($waActionPath)
    $waSource = [Text.Encoding]::UTF8.GetString($waOriginal).TrimStart([char]0xFEFF)
    $waAnchor = "`t`tfl.trace(`"[compile] publish (no testMovie): `" + doc.name);"
    if ($waSource.Split(@($waAnchor), [StringSplitOptions]::None).Count -ne 2) { throw '现役 JSFL 发布入口发生变化。' }
    $waHook = @'
        var __weaponAnimationProbe = eval("(" + FLfile.read(projectURI + "/__PROBE__/native-probe.json") + ")");
        var __weaponAnimationCode = FLfile.read(projectURI + "/tools/weapon-animation/native_check.jsfl");
        if (!__weaponAnimationCode) throw new Error("无法读取原生动画校验脚本");
        eval(__weaponAnimationCode);
        var __weaponAnimationLog = FLfile.read(__weaponAnimationProbe.reportUri);
        if (!__weaponAnimationLog || __weaponAnimationLog.indexOf("ERROR ") >= 0 || __weaponAnimationLog.indexOf("COMPLETE") < 0) throw new Error("原生动画校验未完成");
'@
    $waHook = $waHook.Replace('__PROBE__', $waRelativeOut)
    $waModified = $waSource.Replace($waAnchor, $waHook + "`n" + $waAnchor)
    [IO.File]::WriteAllBytes((Join-Path $waOut 'compile_action.original.jsfl'), $waOriginal)
    [IO.File]::WriteAllText($waActionPath, $waModified, [Text.UTF8Encoding]::new($false))
    $waPatched = $true
    $waSwf = $waProfile.swf
    if ([string]::IsNullOrWhiteSpace($waSwf)) { throw 'Profile 必须声明现役 SWF 输出路径。' }
    & (Join-Path $waRoot 'scripts/compile_test.ps1') -Target $waProfile.xfl -PublishOnly -VerifySwf $waSwf -TimeoutSeconds $TimeoutSeconds
    $waExit = $LASTEXITCODE
    foreach ($waName in @('compiler_errors.txt', 'compile_output.txt')) {
        if (Test-Path -LiteralPath ('scripts/' + $waName)) {
            Copy-Item -LiteralPath ('scripts/' + $waName) -Destination (Join-Path $waOut $waName)
        }
    }
    if ($waExit -ne 0) { throw ('CS6 发布失败，证据：' + $waOut) }
    & $PythonExe -X utf8 -B tools/weapon-animation/xfl_recoil.py build --profile $Profile --check
    if ($LASTEXITCODE -ne 0) { throw 'CS6 写回与 profile 存在语义差异，先审查。' }
    Write-Host ('[OK] 原生保存、逐帧矩阵及发布门通过：' + $waOut)
} finally {
    try {
        if ($waPatched) {
            if ([IO.File]::ReadAllText($waActionPath, [Text.Encoding]::UTF8) -cne $waModified) {
                throw ('编译脚本发生并发变化，拒绝覆盖；原始备份：' + $waOut)
            }
            [IO.File]::WriteAllBytes($waActionPath, $waOriginal)
        }
    } finally {
        if ($waHeld) { $waMutex.ReleaseMutex() }
        $waMutex.Dispose()
        Pop-Location
    }
}
