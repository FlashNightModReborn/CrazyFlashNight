# G1 工单夹具编排：pinned 原生构建（含 g1fixture）→ G1Host 编译 →
# 组装 rundir（G1Host.exe 与真实 FlashInputBroker.exe/FlashInputBridge.dll/
# G1Target.exe 同目录，因为 NativePointerBridge.Start 从 AppContext.BaseDirectory 取 broker）
# → 实跑并把证据写入 <repo>\tmp\g1-evidence-<时间>\，保留历史证据。
param(
    [string]$OutDir = '',
    [ValidateSet('queue','renew','failure','geometry','maximize')][string]$Mode = 'queue'
)
$ErrorActionPreference = 'Stop'
chcp.com 65001 | Out-Null
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
if (-not $OutDir) { $OutDir = Join-Path $root 'tmp\native-out' }

# 1) pinned 原生构建（默认产物 + G1Target.exe）
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot '..\build-dev.ps1') -Target g1fixture -OutDir $OutDir
if ($LASTEXITCODE -ne 0) { Write-Host "NATIVE_BUILD_FAIL=$LASTEXITCODE"; exit $LASTEXITCODE }

# 2) G1Host（生产源码混入编译）
$dotnet = Join-Path $env:LOCALAPPDATA 'Microsoft\dotnet\dotnet.exe'
$hostOut = Join-Path $root 'tmp\g1host-out'
& $dotnet build (Join-Path $PSScriptRoot 'G1Host.csproj') -c Release -o $hostOut --nologo
if ($LASTEXITCODE -ne 0) { Write-Host "HOST_BUILD_FAIL=$LASTEXITCODE"; exit $LASTEXITCODE }

# 3) 每轮独立目录；不按名称结束其他实验或实际游戏的 broker。
$runId = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$run = Join-Path $root "tmp\g1-run-$runId"
New-Item -ItemType Directory -Force -Path $run | Out-Null
Copy-Item -Force (Join-Path $hostOut 'G1Host.*') $run
Copy-Item -Force (Join-Path $hostOut 'Newtonsoft.Json.dll') $run -ErrorAction SilentlyContinue
Copy-Item -Force (Join-Path $OutDir 'FlashInputBroker.exe') $run
Copy-Item -Force (Join-Path $OutDir 'FlashInputBridge.dll') $run
Copy-Item -Force (Join-Path $OutDir 'FlashCompositorNative.dll') $run
Copy-Item -Force (Join-Path $OutDir 'G1Target.exe') $run

# 4) 实跑（真实前台切换 + 真实鼠标点击；运行期间勿动鼠标/键盘）。
#    DOTNET_ROOT 指向 pinned 本地 .NET 10，证据目录本轮新建。
$ev = Join-Path $root "tmp\g1-evidence-$runId"
New-Item -ItemType Directory -Force -Path $ev | Out-Null
$env:DOTNET_ROOT = Join-Path $env:LOCALAPPDATA 'Microsoft\dotnet'
$env:DOTNET_ROOT_X64 = $env:DOTNET_ROOT
$priorTrace=$env:CF7_FOCUS_TRACE
try {
    $env:CF7_FOCUS_TRACE='1'
    & (Join-Path $run 'G1Host.exe') --root $root --evidence $ev --mode $Mode
    $code = $LASTEXITCODE
} finally { $env:CF7_FOCUS_TRACE=$priorTrace }
Write-Host "G1_RUN_EXIT=$code"
exit $code
