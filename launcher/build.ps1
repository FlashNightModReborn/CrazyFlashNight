# ============================================================
# CF7:ME Guardian Process - Build Script (net10.0-windows)
# 构建守护进程并复制产物到项目根目录
# ============================================================
#
# 工作流（Phase 4 重写）：
#   1. TS 编译 launcher/scripts → dist/hit-number-bundle.js（V8 运行时 bundle）
#   1b. 派生 data/map/task_npc_registry.json (NPC↔hotspot 单源派生自 map-panel-data.js)
#   2. native miniaudio.dll 构建（cl.exe via vcvars64）
#   3. native sol_parser.dll 构建（cargo via rustup）
#   4. dotnet publish -r win-x64 --self-contained true -p:PublishSingleFile=true
#      → 单文件 self-contained exe 进 launcher/publish/
#   5. Copy-Item 把 publish/ 下的 exe + native side-by-side DLL 拷到 projectRoot
#   6. Verify launcher/web 运行时资产清单（80 项）
#   6a. native cursor canvas 契约校验（tools/audit-native-cursor-assets.js）
#   6b. launcher/data 运行时资产清单（3 项：map_hud_data / save_repair_dict / save_schema）
#   6c. save_repair_dict.json 与源头一致校验（cf7-save-repair-dict-build verify）
#
# 历史：本脚本 Phase 4 前走 nuget restore + msbuild + 手动 $managedFiles 13 个 DLL 复制；
# 切到 SDK-style net10 后，dotnet publish 一步出单文件，managed DLL 全打进 exe。

$ErrorActionPreference = "Stop"

$launcherDir = $PSScriptRoot
$projectRoot = Split-Path -Parent $launcherDir
$publishDir = Join-Path $launcherDir "publish"

# PowerShell 5.1 把 cmd / native exe 的 stderr 包成 NativeCommandError，在 ErrorActionPreference=Stop
# 下会中止脚本——即便是 cl.exe banner、vcvars64 提示这种无害 stderr 也会触发。
# 用 cmd 内部 2>&1 把 stderr 收编到 cmd 的 stdout，PowerShell 只看到普通输出，行为与 PS7 / CI 一致。
function Invoke-CmdBat {
    param([string]$BatPath)
    # 用 cmd /s /c 包裹整段命令；"$BatPath" 加引号兼容路径含空格；2>&1 在 cmd 内部合并 stderr
    & cmd.exe /s /c "`"$BatPath`" 2>&1"
}

# Reproducible build 闸门：源 → 目的字节相同时跳过 Copy-Item，保留目的 mtime + 防止
# FileSystemWatcher 误触发（hot-reload / IconBakeTask 类的 self-trigger）。返回 $true =
# 真复制了；$false = 跳过。配 native /Brepro + .NET Deterministic 一起用，同源重建零 git churn。
function Copy-IfDifferent {
    param(
        [Parameter(Mandatory=$true)][string]$Src,
        [Parameter(Mandatory=$true)][string]$Dst
    )
    if (-not (Test-Path $Src)) { return $false }
    if (Test-Path $Dst) {
        try {
            $srcHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Src).Hash
            $dstHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Dst).Hash
            if ($srcHash -eq $dstHash) { return $false }
        } catch {
            # 哈希失败 (文件被锁 / 权限 / IO 错误) 不阻断 build，fall through 强制覆盖；
            # 但留 [WARN] 给排查用 — 完全静默会让"为啥每次都拷"难定位。
            Write-Host "  [WARN] Hash compare failed for $Src vs $Dst — falling back to force copy: $_" -ForegroundColor Yellow
        }
    }
    Copy-Item -LiteralPath $Src -Destination $Dst -Force
    return $true
}

# dotnet host 探测：优先 user-scope (%LOCALAPPDATA%\Microsoft\dotnet)，否则系统 PATH
$userDotnet = Join-Path $env:LOCALAPPDATA "Microsoft\dotnet\dotnet.exe"
if (Test-Path $userDotnet) {
    $dotnet = $userDotnet
} else {
    $dotnet = "dotnet"
}

Write-Host "=== CF7:ME Guardian Build (net10.0-windows) ===" -ForegroundColor Cyan
Write-Host "  Project Root: $projectRoot"
Write-Host "  Launcher Dir: $launcherDir"
Write-Host "  Publish Dir : $publishDir"
Write-Host "  dotnet      : $dotnet"
# 打印 dotnet 与 global.json 解析结果作为构建日志证据：
# 1. global.json 位于 repo root（projectRoot），dotnet host 沿 CWD 向上找。本脚本所有 dotnet 调用前
#    会切到 projectRoot（Step 4 用 Push-Location），保证 SDK pin 10.0.x 生效
# 2. 如果新机器装错 SDK 版本，这里立刻看得到
$dotnetSdk = & $dotnet --version 2>&1
Write-Host "  dotnet SDK  : $dotnetSdk"
$gjLine = (& $dotnet --info 2>&1 | Select-String -Pattern "global.json file:" -Context 0,1)
if ($gjLine) { Write-Host "  global.json : $($gjLine.Context.PostContext -join ' ')" }
Write-Host ""

# Step 1a: 战队伙伴/战宠/机械显式分类审计。
# 运行时以 data/merc/pets.xml 的 RosterType 为权威；enemy_properties 仅用于审计差异。
Write-Host "[Step 1a/7] Audit pet roster types..." -ForegroundColor Yellow
$petRosterAudit = Join-Path $projectRoot "tools\audit-pet-roster-types.ps1"
if (-not (Test-Path $petRosterAudit)) {
    Write-Host "[FAIL] audit-pet-roster-types.ps1 missing: $petRosterAudit" -ForegroundColor Red
    exit 1
}
& powershell.exe -ExecutionPolicy Bypass -File $petRosterAudit -ProjectRoot $projectRoot
if ($LASTEXITCODE -ne 0) {
    Write-Host "[FAIL] pet roster classification audit failed." -ForegroundColor Red
    exit 1
}
Write-Host "  pet roster classification OK." -ForegroundColor Green

# Step 1: TypeScript compile (V8 scripts)
Write-Host "[Step 1/7] TypeScript compile..." -ForegroundColor Yellow
$tsDir = Join-Path $launcherDir "scripts"
if (Test-Path (Join-Path $tsDir "tsconfig.json")) {
    Push-Location $tsDir
    try {
        if (-not (Test-Path "node_modules")) {
            npm install --ignore-scripts 2>&1 | Out-Null
        }
        npx tsc --project tsconfig.json
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  [FAIL] TypeScript compilation failed." -ForegroundColor Red
            exit 1
        }
        Write-Host "  TypeScript compiled -> dist/hit-number-bundle.js" -ForegroundColor Green
    } finally {
        Pop-Location
    }
} else {
    Write-Host "  [SKIP] No tsconfig.json found in $tsDir" -ForegroundColor Yellow
}

# Step 1b: 派生 data/map/task_npc_registry.json
# SOT = launcher/web/modules/map-panel-data.js 的 staticAvatars + dynamicAvatars。
# 派生失败 (e.g. hotspotId 拼错 / 重名 NPC) → exit 1 在 build 阶段拦截，避免 launcher
# 启动后 DataQueryTask 返回 success:false → AS2 静默降级、任务红点全 0 的难诊断状态。
Write-Host "[Step 1b/7] Derive data/map/task_npc_registry.json..." -ForegroundColor Yellow
$deriveScript = Join-Path $projectRoot "tools\derive-task-npc-registry.js"
if (-not (Test-Path $deriveScript)) {
    Write-Host "[FAIL] derive-task-npc-registry.js missing: $deriveScript" -ForegroundColor Red
    exit 1
}
node $deriveScript
if ($LASTEXITCODE -ne 0) {
    Write-Host "[FAIL] task_npc_registry 派生失败 (上方日志含具体校验错误)" -ForegroundColor Red
    exit 1
}
Write-Host "  task_npc_registry.json OK." -ForegroundColor Green

# Step 1c: 派生 data/map/map_catalog.json （地图 hotspot 拓扑：groups/hotspots）
# SOT = launcher/web/modules/map-panel-data.js 的 unlockGroups + 各 page hotspots（公开 API）。
# 取代原 map_panel.xml 手写 <groups>/<hotspots> 段；AS2 MapPanelCatalog.applyFromCatalogJson 经
# DataQueryTask("map_catalog") 启动期消费。派生失败 (e.g. 非 base hotspot 漏 group / frame 空 /
# group 跨页) → exit 1 在 build 阶段拦截。map_catalog 是导航权威，绝不能放进 launcher 后才发现坏数据。
Write-Host "[Step 1c/7] Derive data/map/map_catalog.json..." -ForegroundColor Yellow
$deriveCatalogScript = Join-Path $projectRoot "tools\derive-map-catalog.js"
if (-not (Test-Path $deriveCatalogScript)) {
    Write-Host "[FAIL] derive-map-catalog.js missing: $deriveCatalogScript" -ForegroundColor Red
    exit 1
}
node $deriveCatalogScript
if ($LASTEXITCODE -ne 0) {
    Write-Host "[FAIL] map_catalog 派生失败 (上方日志含具体校验错误)" -ForegroundColor Red
    exit 1
}
Write-Host "  map_catalog.json OK." -ForegroundColor Green

# Step 1d: 派生 launcher/data/map_hud_data.json （NativeHud 小地图 context：outline + meta）
# SOT = launcher/web/modules/map-panel-data.js（resolveHotspotMeta + getHudOutline，与 1b/1c 同源）。
# C# MapHudDataCatalog 启动期反序列化 → RightContextWidget 按 hotspotId 渲染小地图 context。
# 历史上本文件只在 Step 7b 做"存在性校验"，不重生成 → 加 hotspot 只改 JS 时它会陈旧（旧文件仍存在、
# 过校验），导致新热点 [RightContextWidget] map hotspot not in catalog → 小地图 context 空白。
# 与 1b/1c 对齐改为每次 build 重生成，三个 SOT 派生文件一起刷新；派生失败 → exit 1。
Write-Host "[Step 1d/7] Derive launcher/data/map_hud_data.json..." -ForegroundColor Yellow
$exportMapHudScript = Join-Path $projectRoot "tools\export-maphud-data.js"
if (-not (Test-Path $exportMapHudScript)) {
    Write-Host "[FAIL] export-maphud-data.js missing: $exportMapHudScript" -ForegroundColor Red
    exit 1
}
node $exportMapHudScript
if ($LASTEXITCODE -ne 0) {
    Write-Host "[FAIL] map_hud_data 派生失败 (上方日志含具体校验错误)" -ForegroundColor Red
    exit 1
}
Write-Host "  map_hud_data.json OK." -ForegroundColor Green

# Step 1e: 派生 launcher/web/modules/tasks/task-catalog.json （WS6 任务树/事件日志 web 直读目录）
# SOT = data/task/*.json + data/task/text/*.json（游戏权威任务源，AS2 也读它；web 拿只读投影，无双源漂移）。
# web 任务面板「事件日志」tab 直读本文件渲染任务树/明细（静态内容零 AS2 传输）。
# 内含闭包校验器：任务 title/description/get_conversation/finish_conversation 的 $KEY 必须存在于
# 合并 task_texts，否则派生失败 → exit 1（防 $KEY 缺失运行时显示原始键，亦为审计 Phase1 description 下沉前置门控）。
Write-Host "[Step 1e/7] Derive launcher/web/modules/tasks/task-catalog.json..." -ForegroundColor Yellow
$deriveTaskCatalogScript = Join-Path $projectRoot "tools\derive-task-catalog.js"
if (-not (Test-Path $deriveTaskCatalogScript)) {
    Write-Host "[FAIL] derive-task-catalog.js missing: $deriveTaskCatalogScript" -ForegroundColor Red
    exit 1
}
node $deriveTaskCatalogScript
if ($LASTEXITCODE -ne 0) {
    Write-Host "[FAIL] task-catalog 派生失败 (上方日志含具体校验错误，如缺失 `$KEY)" -ForegroundColor Red
    exit 1
}
Write-Host "  task-catalog.json OK." -ForegroundColor Green

# Step 1f: 派生 launcher/web/modules/tasks/achievement-catalog.json （成就 tab web 直读目录）
# SOT = data/achievement/*.json（成就权威源，AS2 AchievementDataLoader 也读它；web 拿脱敏只读投影）。
# 内含校验器：objective 枚举 / 跨域闭包（taskFinished/chainProgress 引用任务域）/ economyCount
# counter 白名单（正则解析 AchievementMetrics.as VALID，单源）/ rewards 黑名单{经验值} /
# hidden 条目脱敏输出（明文仅经 AS2 hiddenReveals 按需回传）。派生失败 → exit 1。
# 设计：docs/成就系统-A轮-设计-2026-06-10.md §5。
Write-Host "[Step 1f/7] Derive launcher/web/modules/tasks/achievement-catalog.json..." -ForegroundColor Yellow
$deriveAchievementCatalogScript = Join-Path $projectRoot "tools\derive-achievement-catalog.js"
if (-not (Test-Path $deriveAchievementCatalogScript)) {
    Write-Host "[FAIL] derive-achievement-catalog.js missing: $deriveAchievementCatalogScript" -ForegroundColor Red
    exit 1
}
node $deriveAchievementCatalogScript
if ($LASTEXITCODE -ne 0) {
    Write-Host "[FAIL] achievement-catalog 派生失败 (上方日志含具体校验错误)" -ForegroundColor Red
    exit 1
}
Write-Host "  achievement-catalog.json OK." -ForegroundColor Green

# Step 2: Build native miniaudio DLL
Write-Host "[Step 2/7] Build native miniaudio DLL..." -ForegroundColor Yellow
$nativeBat = Join-Path $launcherDir "native\build.bat"
if (Test-Path $nativeBat) {
    Invoke-CmdBat $nativeBat
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[FAIL] Native build failed." -ForegroundColor Red
        exit 1
    }
    Write-Host "  Native build OK." -ForegroundColor Green
} else {
    Write-Host "  [SKIP] No native\build.bat found" -ForegroundColor Yellow
}

# Step 3: Build sol_parser DLL (Rust cdylib)
Write-Host "[Step 3/7] Build sol_parser.dll (Rust)..." -ForegroundColor Yellow
$solBat = Join-Path $launcherDir "native\sol_parser\build.bat"
if (-not (Test-Path $solBat)) {
    Write-Host "[FAIL] sol_parser build.bat missing: $solBat" -ForegroundColor Red
    exit 1
}
Invoke-CmdBat $solBat
if ($LASTEXITCODE -ne 0) {
    Write-Host "[FAIL] sol_parser build failed." -ForegroundColor Red
    exit 1
}
# sol_parser 的 build.bat 把产物放在 launcher/bin/Release，由 Step 5b 显式复制到 projectRoot
$solParserDll = Join-Path $launcherDir "bin\Release\sol_parser.dll"
if (-not (Test-Path $solParserDll)) {
    Write-Host "[FAIL] sol_parser.dll not found at $solParserDll after build." -ForegroundColor Red
    exit 1
}
Write-Host "  sol_parser.dll OK." -ForegroundColor Green

# Step 4: Build native bootstrap (cl.exe) — 用户面 entry exe，检测并安装 .NET 10 runtime
# 输出 launcher\bin\Release\bootstrap.exe；Step 5 拷贝到 projectRoot 并改名为
# CRAZYFLASHER7MercenaryEmpire.exe（用户双击入口）
Write-Host "[Step 4/7] Build native bootstrap (cl.exe)..." -ForegroundColor Yellow
$bootBat = Join-Path $launcherDir "native\bootstrap\build.bat"
if (-not (Test-Path $bootBat)) {
    Write-Host "[FAIL] bootstrap build.bat missing: $bootBat" -ForegroundColor Red
    exit 1
}
Invoke-CmdBat $bootBat
if ($LASTEXITCODE -ne 0) {
    Write-Host "[FAIL] bootstrap build failed." -ForegroundColor Red
    exit 1
}
$bootstrapExe = Join-Path $launcherDir "bin\Release\bootstrap.exe"
if (-not (Test-Path $bootstrapExe)) {
    Write-Host "[FAIL] bootstrap.exe not found at $bootstrapExe after build." -ForegroundColor Red
    exit 1
}
Write-Host "  bootstrap.exe OK ($('{0:N0}' -f (Get-Item $bootstrapExe).Length) bytes)." -ForegroundColor Green

# Step 5: dotnet publish (FDD — framework-dependent, NOT self-contained, NOT single-file)
# 切换历史: 2026-05-28 短期试过 self-contained single-file (146MB)，blob 太大不利于 git；
# 改 FDD ~37MB 分散到 ~18 文件，配合 bootstrap.exe + bundled runtime installer 处理 runtime 缺失
Write-Host "[Step 5/7] dotnet publish (FDD)..." -ForegroundColor Yellow
if (Test-Path $publishDir) {
    Remove-Item -Recurse -Force $publishDir
}
$csproj = Join-Path $launcherDir "CRAZYFLASHER7MercenaryEmpire.csproj"
# global.json 在 repo root，dotnet host 从 CWD 向上找；Push-Location $projectRoot 保证不管脚本怎么被
# 调用（cd launcher 后 / repo root 直接 -File launcher/build.ps1 / 任意子目录），SDK pin 都生效
Push-Location $projectRoot
try {
    & $dotnet publish $csproj `
        -c Release `
        -r win-x64 `
        --self-contained false `
        -p:DebugType=embedded `
        -o $publishDir
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[FAIL] dotnet publish failed." -ForegroundColor Red
        exit 1
    }
} finally {
    Pop-Location
}
$publishedCoreExe = Join-Path $publishDir "CRAZYFLASHER7MercenaryEmpire.Core.exe"
if (-not (Test-Path $publishedCoreExe)) {
    Write-Host "[FAIL] Published Core exe missing: $publishedCoreExe" -ForegroundColor Red
    exit 1
}
$publishTotalMB = [math]::Round(((Get-ChildItem $publishDir -File | Measure-Object -Property Length -Sum).Sum / 1MB), 1)
Write-Host "  dotnet publish OK. FDD total = ${publishTotalMB}MB / $((Get-ChildItem $publishDir -File).Count) files" -ForegroundColor Green

# Step 6: 复制 publish + bootstrap + native side-cars 到 projectRoot
# - FDD 产物（Core.exe + Core.dll + 17 DLLs + deps.json + runtimeconfig.json）从 publishDir
#   拷到 projectRoot\runtime\（**子目录**，避免用户在 projectRoot 看到 Core.exe 误点击触发
#   .NET apphost 的 English "you need .NET runtime" 默认对话框）
# - bootstrap.exe 从 bin/Release 拷到 projectRoot 并改名 CRAZYFLASHER7MercenaryEmpire.exe（用户面入口）
# - miniaudio / sol_parser 从 launcher\bin\Release（独立构建）
Write-Host "[Step 6/7] Copy runtime artifacts to projectRoot..." -ForegroundColor Yellow

# 6a: 准备 projectRoot\runtime\ 子目录（Core + DLLs 落点）
$runtimeDir = Join-Path $projectRoot "runtime"
if (-not (Test-Path $runtimeDir)) {
    New-Item -ItemType Directory -Path $runtimeDir -Force | Out-Null
}
# expectedNames：记录本轮预期落到 runtime\ 的文件名集合，用于 6e 段做 targeted stale 清理。
# 旧版直接 Remove-Item 全部再拷会让所有产物 mtime 重置（git 不在意 mtime 但 FileSystemWatcher
# 会误触发），改成 "Copy-IfDifferent + 末尾删未预期项"——同源同字节零写入，不在预期清单的
# 残留（降级依赖 / 弃用 DLL）仍会被清掉。
$expectedNames = New-Object 'System.Collections.Generic.HashSet[string]'([System.StringComparer]::OrdinalIgnoreCase)

# 6b: publish/ 下除 *.xml 外全拷到 projectRoot\runtime\
Get-ChildItem $publishDir -File | Where-Object {
    $_.Extension -ne '.xml'
} | ForEach-Object {
    $dst = Join-Path $runtimeDir $_.Name
    $copied = Copy-IfDifferent -Src $_.FullName -Dst $dst
    [void]$expectedNames.Add($_.Name)
    if ($copied) {
        Write-Host "  Copied to runtime\: $($_.Name)"
    } else {
        Write-Host "  Unchanged in runtime\: $($_.Name)" -ForegroundColor DarkGray
    }
}

# 6c: bootstrap.exe → projectRoot\CRAZYFLASHER7MercenaryEmpire.exe（用户面入口名）
$userFacingExe = Join-Path $projectRoot "CRAZYFLASHER7MercenaryEmpire.exe"
$copied = Copy-IfDifferent -Src $bootstrapExe -Dst $userFacingExe
if ($copied) {
    Write-Host "  Copied: bootstrap.exe -> CRAZYFLASHER7MercenaryEmpire.exe (user-facing entry at projectRoot)"
} else {
    Write-Host "  Unchanged: CRAZYFLASHER7MercenaryEmpire.exe (bootstrap source identical)" -ForegroundColor DarkGray
}

# 6d: native side-cars（miniaudio + sol_parser）→ projectRoot 根目录
# 这两个是 Win32 DLL，Core 通过 P/Invoke 找 DLL 走 Win32 LoadLibrary 路径搜索:
# Core.exe 所在目录 (runtime\) → System32 → PATH。我们靠 SetDllDirectory / AppContext 设定
# 让 Core 能找到根目录的 side-car。简单点: 让 Core 启动时 SetDllDirectory($projectRoot)。
# 当前实现 (Phase 4 IL3000 fix) 已经把 projectRoot 解析正确，AudioEngine.cs 等的 DllImport
# 用相对名 "miniaudio.dll"，Win32 默认搜 Core.exe 所在目录 (runtime\) 找不到。
# 所以这里同步把两个 side-car 也复制到 runtime\，让 P/Invoke 默认搜索能命中
$nativeDlls = @()
$nativeDlls += @{ Src = Join-Path $launcherDir "bin\Release\sol_parser.dll"; Name = "sol_parser.dll" }
$miniaudioCandidates = @(
    Join-Path $launcherDir "bin\Release\miniaudio.dll"
    Join-Path $launcherDir "native\miniaudio.dll"
)
foreach ($cand in $miniaudioCandidates) {
    if (Test-Path $cand) {
        $nativeDlls += @{ Src = $cand; Name = "miniaudio.dll" }
        break
    }
}

foreach ($entry in $nativeDlls) {
    if (Test-Path $entry.Src) {
        # 只放 runtime\：Core 的 P/Invoke 走 Win32 LoadLibrary 默认搜路径（Core.exe 所在目录 → System32 → PATH）
        # 不复制到 projectRoot 根：没有 caller 在 projectRoot 找这些 DLL，root 越干净越好
        $dst = Join-Path $runtimeDir $entry.Name
        $copied = Copy-IfDifferent -Src $entry.Src -Dst $dst
        [void]$expectedNames.Add($entry.Name)
        if ($copied) {
            Write-Host "  Copied to runtime\: $($entry.Name)"
        } else {
            Write-Host "  Unchanged in runtime\: $($entry.Name)" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "  [WARN] Native DLL not found: $($entry.Src)" -ForegroundColor Yellow
    }
}

# 6d.5: 清理 runtime\ 内不在本轮 expectedNames 的旧产物（替代旧版前置 Remove-Item *）。
# 防降级依赖时旧版本 DLL 残留；只删未预期项，已对齐的不动 → 不重置 mtime 不触发 watcher。
$staleRemoved = 0
Get-ChildItem $runtimeDir -File -ErrorAction SilentlyContinue | Where-Object {
    -not $expectedNames.Contains($_.Name)
} | ForEach-Object {
    Remove-Item -LiteralPath $_.FullName -Force
    Write-Host "  Removed stale: $($_.Name)" -ForegroundColor DarkYellow
    $staleRemoved++
}
if ($staleRemoved -gt 0) {
    Write-Host "  Cleaned $staleRemoved stale file(s) from runtime\"
}

# 6e: 硬断言关键运行时文件落地
# 用户面 (projectRoot):
#   - CRAZYFLASHER7MercenaryEmpire.exe = bootstrap (检测 + 安装 .NET 10 runtime + 启动 Core)
# FDD 主体 (projectRoot\runtime\):
#   - CRAZYFLASHER7MercenaryEmpire.Core.exe = FDD apphost (需要 runtime 在场)
#   - CRAZYFLASHER7MercenaryEmpire.Core.dll = main managed assembly
#   - sol_parser.dll = Rust cdylib (P/Invoke; AudioEngine 不直接用，存档决议用)
#   - miniaudio.dll = native audio engine (AudioEngine.cs DllImport)
$mustExistRoot = @(
    "CRAZYFLASHER7MercenaryEmpire.exe"  # bootstrap, 用户面入口
)
$mustExistRuntime = @(
    "CRAZYFLASHER7MercenaryEmpire.Core.exe"   # FDD apphost
    "CRAZYFLASHER7MercenaryEmpire.Core.dll"   # main managed assembly
    "sol_parser.dll"                          # Rust cdylib (Protocol 2 存档决议)
    "miniaudio.dll"                           # native audio engine (AudioEngine DllImport)
)
foreach ($f in $mustExistRoot) {
    $full = Join-Path $projectRoot $f
    if (-not (Test-Path $full)) {
        Write-Host "[FAIL] Required artifact missing at projectRoot: $f" -ForegroundColor Red
        exit 1
    }
}
foreach ($f in $mustExistRuntime) {
    $full = Join-Path $runtimeDir $f
    if (-not (Test-Path $full)) {
        Write-Host "[FAIL] Required runtime artifact missing at projectRoot\runtime\: $f" -ForegroundColor Red
        exit 1
    }
}
# bundled runtime installer 是 bootstrap 的硬依赖：runtime 缺失场景 bootstrap 会调用此 installer。
# pack.config.yaml 的 runtime-installer 层也强依赖它，build 阶段就必须 fail 而不是只 WARN。
# glob 扫 windowsdesktop-runtime-10.*-win-x64.exe，让版本 bump（10.0.9 / 10.0.10 ...）不需要改脚本
$runtimeInstallerDir = Join-Path $projectRoot "tools\dotnet-runtime"
$runtimeInstallerCandidates = @()
if (Test-Path $runtimeInstallerDir) {
    $runtimeInstallerCandidates = @(
        Get-ChildItem -LiteralPath $runtimeInstallerDir -Filter 'windowsdesktop-runtime-10.*-win-x64.exe' -File -ErrorAction SilentlyContinue
    )
}
if ($runtimeInstallerCandidates.Count -eq 0) {
    Write-Host "[FAIL] bundled runtime installer 缺失（tools\dotnet-runtime\windowsdesktop-runtime-10.*-win-x64.exe）" -ForegroundColor Red
    Write-Host "       未装 .NET 10 桌面运行时的机器双击 launcher 会因 bootstrap 找不到 installer 而失败" -ForegroundColor Red
    Write-Host "       下载: https://dotnet.microsoft.com/download/dotnet/10.0 → Desktop Runtime x64 → tools\dotnet-runtime\" -ForegroundColor Yellow
    exit 1
}
$pickedInstaller = $runtimeInstallerCandidates[0].Name
Write-Host "  bundled installer: $pickedInstaller" -ForegroundColor Green
Write-Host "  All required artifacts at projectRoot." -ForegroundColor Green

# Step 6f: 优化护栏 — 断言发布目录里的托管主程序集是优化构建（非 Debug）
# 历史卡顿真因：误把 Debug 产物（DebuggableAttribute 的 DisableOptimizations=256 置位 →
# 运行时 JIT 优化被整个关掉）当作发布版提交。详见 memory: launcher-perf-debug-vs-release。
# net10 走 `dotnet publish -c Release` 本应永远优化，这里把"必须优化"从流程纪律升级为脚本强制
# 校验：把 Debug/未优化产物溜进 runtime\ 这一失败模式物理堵死。
# 工具用 BCL 的 PEReader 直接读 DebuggableAttribute 原始 blob，不解析依赖、不联网。
Write-Host "[Step 6f/7] Assert published assembly is optimized (no Debug build)..." -ForegroundColor Yellow
$assertTool = Join-Path $projectRoot "tools\assert-optimized.cs"
$coreManaged = Join-Path $runtimeDir "CRAZYFLASHER7MercenaryEmpire.Core.dll"
if (-not (Test-Path $assertTool)) {
    Write-Host "[FAIL] optimization assert tool missing: $assertTool" -ForegroundColor Red
    exit 1
}
# Push-Location $projectRoot：让 global.json (SDK pin 10.0.x，file-based app 需要) 生效
Push-Location $projectRoot
try {
    & $dotnet run $assertTool -- $coreManaged
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[FAIL] 发布产物优化校验未通过（上方含具体程序集与 DebuggingModes）。" -ForegroundColor Red
        Write-Host "       排查：确认本次走的是 build.ps1（dotnet publish -c Release），而非 IDE / 裸" -ForegroundColor Yellow
        Write-Host "       dotnet build 的 Debug 产物被拷进 runtime\；或 csproj/Directory.Build.props 被改写了 Optimize。" -ForegroundColor Yellow
        exit 1
    }
} finally {
    Pop-Location
}
Write-Host "  Optimization gate OK." -ForegroundColor Green

# Step 7: Verify required WebView2 runtime assets
Write-Host "[Step 7/7] Verify required WebView2 runtime assets..." -ForegroundColor Yellow
$webDir = Join-Path $launcherDir "web"
$requiredWebPaths = @(
    "bootstrap.html",
    "bootstrap-main.js",
    "overlay.html",
    "config\version.js",
    "css\bootstrap.css",
    "css\welcome.css",
    "css\overlay.css",
    "css\panels.css",
    "css\task_panel.css",
    "css\pet_panel.css",
    "css\merc_panel.css",
    "css\team_panel.css",
    "lib\marked.min.js",
    "help\controls.md",
    "help\worldview.md",
    "help\easter-eggs.md",
    "icons\manifest.json",
    "data\lockbox-variants.json",
    "assets\bg\manifest.json",
    "assets\cursor\native\manifest.json",
    "assets\cursor\native\normal.png",
    "assets\cursor\native\click.png",
    "assets\cursor\native\hoverGrab.png",
    "assets\cursor\native\grab.png",
    "assets\cursor\native\attack.png",
    "assets\cursor\native\openDoor.png",
    "assets\logos\cf7me-title.png",
    "assets\logos\steam.svg",
    "assets\intro.mp4",
    "assets\map\page-base.png",
    "assets\map\page-faction.png",
    "modules\audio.js",
    "modules\factions.js",
    "modules\archive-schema.js",
    "modules\archive-editor.js",
    "modules\diagnostic-log.js",
    "modules\display.js",
    "modules\about.js",
    "modules\bridge.js",
    "modules\uidata.js",
    "modules\toast.js",
    "modules\sparkline.js",
    "modules\notch.js",
    "modules\perf-frame-limiter.js",
    "modules\cursor-feedback.js",
    "modules\currency.js",
    "modules\jukebox.js",
    "modules\combo.js",
    "modules\lazy-loader.js",
    "modules\panels.js",
    "modules\panels-lazy-registry.js",
    "modules\tooltip.js",
    "modules\icons.js",
    "modules\kshop.js",
    "modules\help-panel.js",
    "modules\intelligence-components.js",
    "modules\font-pack-banner.js",
    "modules\intelligence-panel.js",
    "modules\panels\jukebox-panel.js",
    "modules\map-avatar-source-data.js",
    "modules\map-panel-data.js",
    "modules\map-fit-presets.js",
    "modules\map-canvas-stage-renderer.js",
    "modules\map-panel.js",
    "modules\map-hud.js",
    "modules\stage-select-data.js",
    "modules\stage-select-panel.js",
    "modules\pet-panel.js",
    "modules\merc-data.js",
    "modules\merc-panel.js",
    "modules\team\team-panel.js",
    "modules\tasks\task-panel.js",
    "modules\tasks\task-catalog.json",
    "modules\tasks\achievement-catalog.json",
    "modules\tasks\achievement-tab.js",
    "assets\pets\pet_locked.png",
    "modules\tasks\assets\finish_npc.png",
    "modules\tasks\assets\item_bg.png",
    "modules\tasks\assets\requirement_contain.png",
    "modules\tasks\assets\requirement_stage.png",
    "modules\tasks\assets\requirement_submit.png",
    "modules\tasks\assets\task_icon_bg.png",
    "modules\tasks\assets\task_main_bg.png",
    "modules\tasks\assets\task_scroll.png",
    "assets\stage-select\backgrounds\waste-city.png",
    "assets\stage-select\backgrounds\wormhole-cave.jpg",
    "assets\stage-select\backgrounds\snow-interior.jpg",
    "assets\stage-select\backgrounds\wide-sky-1024x768.jpg",
    "assets\stage-select\backgrounds\crashed-warship.jpg",
    "assets\stage-select\backgrounds\trial-depth.jpg",
    "assets\stage-select\previews\_missing-preview.svg",
    "modules\overlay-audio-bindings.js",
    "modules\minigames\shared\host-bridge.js",
    "modules\minigames\shared\minigame-shell.css",
    "modules\minigames\lockbox\lockbox.css",
    "modules\minigames\lockbox\lockbox-panel.js",
    "modules\minigames\pinalign\pinalign.css",
    "modules\minigames\pinalign\pinalign-panel.js",
    "modules\minigames\gobang\gobang.css",
    "modules\minigames\gobang\gobang-panel.js",
    "modules\minigames\gobang\gobang-audio.js",
    "modules\minigames\gobang\core\index.js"
)
$missingWebPaths = @()
foreach ($relativePath in $requiredWebPaths) {
    $fullPath = Join-Path $webDir $relativePath
    if (-not (Test-Path $fullPath)) {
        $missingWebPaths += $relativePath
    }
}
if ($missingWebPaths.Count -gt 0) {
    Write-Host "[FAIL] Required launcher\\web runtime assets missing:" -ForegroundColor Red
    foreach ($missingPath in $missingWebPaths) {
        Write-Host "  - $missingPath" -ForegroundColor Red
    }
    exit 1
}
Write-Host "  OK: launcher\\web runtime assets present ($($requiredWebPaths.Count) checks)" -ForegroundColor Green

# Step 6a: Verify native cursor canvas/hotspot contract
Write-Host "[Step 7a/7] Verify native cursor canvas contract..." -ForegroundColor Yellow
$cursorAudit = Join-Path $projectRoot "tools\audit-native-cursor-assets.js"
if (-not (Test-Path $cursorAudit)) {
    Write-Host "[FAIL] Native cursor audit missing: $cursorAudit" -ForegroundColor Red
    exit 1
}
node $cursorAudit
if ($LASTEXITCODE -ne 0) {
    Write-Host "[FAIL] Native cursor canvas audit failed." -ForegroundColor Red
    exit 1
}

# Step 6b: Verify launcher\data runtime assets (NativeHud widget catalog 等)
Write-Host "[Step 7b/7] Verify launcher\data runtime assets..." -ForegroundColor Yellow
$dataDir = Join-Path $launcherDir "data"
$requiredDataPaths = @(
    "map_hud_data.json",     # MapHudWidget catalog；缺失会让 useNativeHud=true 下 MapHud 静默不可见
    "save_repair_dict.json", # SaveAutoRepairService 启动加载；缺失走 catch 分支静默跳过自动修复
    "save_schema.json"       # 存档编辑器 diff 视图基线；缺失则"已修改"tab 退化为只用 schema 内的 default 值
)
$missingDataPaths = @()
foreach ($relativePath in $requiredDataPaths) {
    $fullPath = Join-Path $dataDir $relativePath
    if (-not (Test-Path $fullPath)) {
        $missingDataPaths += $relativePath
    }
}
if ($missingDataPaths.Count -gt 0) {
    Write-Host "[FAIL] Required launcher\\data runtime assets missing:" -ForegroundColor Red
    foreach ($missingPath in $missingDataPaths) {
        Write-Host "  - $missingPath" -ForegroundColor Red
    }
    Write-Host "  Hint:" -ForegroundColor Yellow
    Write-Host "    map_hud_data.json     -> node tools/export-maphud-data.js" -ForegroundColor Yellow
    Write-Host "    save_repair_dict.json -> npm --prefix tools/cf7-save-repair-dict-build run build" -ForegroundColor Yellow
    Write-Host "    save_schema.json      -> node tools/extract-save-schema.js" -ForegroundColor Yellow
    exit 1
}
Write-Host "  OK: launcher\\data runtime assets present ($($requiredDataPaths.Count) checks)" -ForegroundColor Green

# Step 6c: Verify save_repair_dict.json 与源头一致 (cf7-save-repair-dict-build verify gate)
# 防止 data/items/*.xml 或 SaveManager.as 改动后 dict 未同步 regenerate；
# 不一致 = dict 漂移，会让 SaveAutoRepairService 用旧字典误判新条目
Write-Host "[Step 7c/7] Verify save_repair_dict.json 与源头一致..." -ForegroundColor Yellow
$repairDictDir = Join-Path $projectRoot "tools\cf7-save-repair-dict-build"
if (-not (Test-Path (Join-Path $repairDictDir "package.json"))) {
    Write-Host "[FAIL] cf7-save-repair-dict-build 未找到: $repairDictDir" -ForegroundColor Red
    exit 1
}
Push-Location $repairDictDir
try {
    if (-not (Test-Path "node_modules")) {
        npm install --ignore-scripts 2>&1 | Out-Null
    }
    npm run verify --silent
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[FAIL] save_repair_dict.json 与源头不一致 (data/**/*.xml 或 SaveManager.as 改动后未 regenerate)" -ForegroundColor Red
        Write-Host "  修复: npm --prefix tools/cf7-save-repair-dict-build run build" -ForegroundColor Yellow
        exit 1
    }
} finally {
    Pop-Location
}
Write-Host "  OK: save_repair_dict.json 与源头一致" -ForegroundColor Green

Write-Host ""
Write-Host "=== Build Complete ===" -ForegroundColor Green
Write-Host "  Output: $projectRoot\CRAZYFLASHER7MercenaryEmpire.exe"
