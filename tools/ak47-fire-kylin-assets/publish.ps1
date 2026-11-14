[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds = 1800)
chcp.com 65001 | Out-Null
$ErrorActionPreference = 'Stop'
$assetRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$assetAction = Join-Path $assetRoot 'scripts/compile_action.jsfl'
$assetOut = Join-Path $assetRoot ('tmp/ak47-fire-kylin/publish-' + [Guid]::NewGuid().ToString('N'))
$assetHasher = [Security.Cryptography.SHA256]::Create()
try {
    $assetHash = ([BitConverter]::ToString($assetHasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($assetRoot.TrimEnd('\').ToUpperInvariant())))).Replace('-','').Substring(0,24)
} finally { $assetHasher.Dispose() }
$assetMutex = [Threading.Mutex]::new($false, 'Local\CF7_FlashCompile_' + $assetHash)
$assetHeld = $false
$assetPatched = $false
Push-Location $assetRoot
try {
    try { $assetHeld = $assetMutex.WaitOne(0) }
    catch [Threading.AbandonedMutexException] {
        $assetHeld = $true
        Add-Content -LiteralPath 'scripts/compile_state_uncertain.marker' -Encoding UTF8 -Value 'AK47 asset publisher observed abandoned compile mutex; inspect previous compile.'
        throw '编译互斥锁异常，需先核对旧编译。'
    }
    if (-not $assetHeld) { throw '已有编译正在运行。' }
    if (Test-Path -LiteralPath 'scripts/compile_state_uncertain.marker') { throw '存在编译未知结果，先核对现场。' }
    # A previous asset preview may still hold the production SWF open.
    if (Get-Process -Name Flash -ErrorAction SilentlyContinue) {
        & (Join-Path $assetRoot 'scripts/compile_test.ps1') -StopTestPlayers
        if ($LASTEXITCODE -ne 0) { throw '无法结束既有 Test Movie，未开始覆盖素材文件。' }
    }
    python -B -X utf8 tools/ak47-fire-kylin-assets/prepare_native.py
    if ($LASTEXITCODE -ne 0) { throw '无法准备火麒麟独立原生核对工程。' }
    New-Item -ItemType Directory -Path $assetOut | Out-Null
    $assetOriginal = [IO.File]::ReadAllBytes($assetAction)
    $assetText = [Text.Encoding]::UTF8.GetString($assetOriginal).TrimStart([char]0xFEFF)
    $assetAnchor = "`t`tfl.trace(`"[compile] publish (no testMovie): `" + doc.name);"
    if ($assetText.Split(@($assetAnchor),[StringSplitOptions]::None).Count -ne 2) { throw '编译入口已变化。' }
    $assetHook = @'
        var __kylinCode = FLfile.read(projectURI + "/tools/ak47-fire-kylin-assets/native_check.jsfl");
        if (!__kylinCode) throw new Error("Missing AK47 native check");
        eval(__kylinCode);
        var __kylinReport = FLfile.read(projectURI + "/tmp/ak47-fire-kylin/native-save.txt");
        if (!__kylinReport || __kylinReport.indexOf("ERROR ") >= 0 || __kylinReport.indexOf("COMPLETE") < 0) throw new Error("AK47 native save incomplete");
'@
    $assetModified = $assetText.Replace($assetAnchor, $assetHook + "`n" + $assetAnchor)
    [IO.File]::WriteAllBytes((Join-Path $assetOut 'compile_action.original.jsfl'), $assetOriginal)
    [IO.File]::WriteAllText($assetAction, $assetModified, [Text.UTF8Encoding]::new($false))
    $assetPatched = $true
    & (Join-Path $assetRoot 'scripts/compile_test.ps1') -Target 'tmp/ak47-fire-kylin/NativeInput/NativeInput.xfl' -PublishOnly -VerifySwf 'tmp/ak47-fire-kylin/NativeInput.swf' -TimeoutSeconds $TimeoutSeconds
    $assetExit = $LASTEXITCODE
    foreach ($assetLog in @('compiler_errors.txt','compile_output.txt')) {
        if (Test-Path -LiteralPath ('scripts/' + $assetLog)) { Copy-Item -LiteralPath ('scripts/' + $assetLog) -Destination (Join-Path $assetOut $assetLog) }
    }
    if ($assetExit -ne 0) { throw ('CS6 素材编译失败，证据：' + $assetOut) }
    Copy-Item -LiteralPath 'tmp/ak47-fire-kylin/native-save.txt' -Destination $assetOut
    if ([IO.File]::ReadAllText($assetAction,[Text.Encoding]::UTF8) -cne $assetModified) { throw '编译脚本被并发修改。' }
    [IO.File]::WriteAllBytes($assetAction,$assetOriginal)
    $assetPatched = $false
    python -B -X utf8 tools/ak47-fire-kylin-assets/prepare_native.py --apply
    if ($LASTEXITCODE -ne 0) { throw '原生元件回装失败。' }
    python -B -X utf8 tools/ak47-fire-kylin-assets/build.py --check
    if ($LASTEXITCODE -ne 0) { throw '原生元件语义不符。' }
    & (Join-Path $assetRoot 'scripts/compile_test.ps1') -Target 'flashswf/arts/new/Codex专用素材/Codex专用素材.xfl' -PublishOnly -VerifySwf 'flashswf/arts/new/Codex专用素材.swf' -TimeoutSeconds $TimeoutSeconds
    $assetExit = $LASTEXITCODE
    foreach ($assetLog in @('compiler_errors.txt','compile_output.txt')) {
        if (Test-Path -LiteralPath ('scripts/' + $assetLog)) { Copy-Item -LiteralPath ('scripts/' + $assetLog) -Destination (Join-Path $assetOut ('library-' + $assetLog)) }
    }
    if ($assetExit -ne 0) { throw ('Codex 素材库编译失败，证据：' + $assetOut) }
    Write-Host ('[OK] 原生保存、语义对照与现役素材库编译完成：' + $assetOut)
} finally {
    try {
        if ($assetPatched) {
            if ([IO.File]::ReadAllText($assetAction,[Text.Encoding]::UTF8) -cne $assetModified) { throw ('编译脚本被并发修改，保留原件：' + $assetOut) }
            [IO.File]::WriteAllBytes($assetAction,$assetOriginal)
        }
    } finally {
        if ($assetHeld) { $assetMutex.ReleaseMutex() }
        $assetMutex.Dispose()
        Pop-Location
    }
}
