# ============================================================
# git-auto-pull.ps1
#
# 自动轮询拉取最新更新，适用于直连 GitHub 不稳定、时通时断的情况。
# 每隔指定秒数尝试一次 `git pull origin main`，直到成功一次为止；
# 成功后自动结束轮询（下次要更新时再运行一次即可）。
# 拉取失败通常是因为网络问题，脚本会继续等待重试；
# 如果是本地冲突 / 未提交修改等重试也解决不了的问题，会停止并给出提示。
#
# 用法（推荐双击同目录的 git-auto-pull.cmd，或在此运行）：
#   powershell -NoProfile -ExecutionPolicy Bypass -File git-auto-pull.ps1
#   git-auto-pull.ps1 300           每 300 秒轮询一次，直到成功
#   git-auto-pull.ps1 60 200        每 60 秒轮询一次，最多 200 次后停止
#
# 停止：按 Ctrl+C，或直接关闭窗口。
# ============================================================

param(
    [int]$Interval = 60,    # 轮询间隔（秒）
    [int]$MaxAttempts = 0   # 最大尝试次数，0 表示不限
)

# 设置 UTF-8 控制台，避免中文乱码（见 AGENTS.md 终端编码规范）
chcp.com 65001 | Out-Null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ---------- 定位仓库根目录（从脚本所在目录向上找 .git） ----------
$root = $PSScriptRoot
while ($true) {
    if (Test-Path (Join-Path $root '.git')) { break }
    $parent = Split-Path -Parent $root
    if ([string]::IsNullOrEmpty($parent) -or $parent -eq $root) {
        Write-Host "[错误] 从 $PSScriptRoot 向上找不到 .git，请把本脚本放在游戏仓库内（如 tools 目录）。"
        exit 1
    }
    $root = $parent
}
Set-Location $root

# ---------- 参数校验 ----------
if ($Interval -lt 5)   { $Interval = 5 }
if ($Interval -gt 3600) { $Interval = 3600 }
if ($MaxAttempts -lt 0) { $MaxAttempts = 0 }

# ---------- 检查 git 是否可用 ----------
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host ""
    Write-Host "[错误] 未找到 git 命令。请先安装 Git for Windows：https://git-scm.com/download/win"
    Write-Host "       安装时保持默认选项，勾选Git from the command line and 3rd-party software。"
    exit 1
}

# ---------- 当前分支提示 ----------
$branch = (git branch --show-current 2>$null)
if ($branch -and ($branch.Trim() -ne 'main')) {
    Write-Host "[提示] 当前分支是 $($branch.Trim())，本脚本拉取的是 origin/main。"
}

# ---------- 启动横幅 ----------
Write-Host ""
Write-Host "============================================================"
Write-Host " 自动轮询 git pull 已启动"
Write-Host " 仓库目录：$root"
Write-Host " 轮询间隔：每 $Interval 秒一次"
if ($MaxAttempts -gt 0) { Write-Host " 最大尝试次数：$MaxAttempts 次（达到即停止）" }
Write-Host " 拉到成功即停止；网络不通会自动继续等待。"
Write-Host " 想随时停止：按 Ctrl+C 或直接关闭本窗口。"
Write-Host "============================================================"
Write-Host ""

# ---------- 判定永久性本地问题的特征文本（重试也解决不了） ----------
$permanentPatterns = @(
    'your local changes to the following files would be overwritten',
    'please commit your changes or stash them',
    'merge conflict',
    'automatic merge failed',
    'you have not concluded your merge',
    'refusing to merge unrelated histories',
    'the following untracked working tree files would be overwritten',
    'please move or remove them',
    'could not read username',
    'terminal prompts disabled',
    'authentication failed',
    'access denied',
    'permission denied',
    'repository not found',
    'does not appear to be a git repository',
    'not currently on a branch'
)

# 禁止 git 弹出交互式认证提示（避免挂死等输入）
$env:GIT_TERMINAL_PROMPT = '0'
$attempt = 1

while ($true) {
    Write-Host ("[{0}] 第 {1} 次尝试拉取 ..." -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $attempt)

    # 清理上次中断可能残留的合并 / 变基状态
    if (Test-Path (Join-Path $root '.git\MERGE_HEAD')) {
        Write-Host "[警告] 发现上次未完成的合并状态，正在自动清理（git merge --abort）..."
        git merge --abort 2>&1 | Out-Null
    }
    if ((Test-Path (Join-Path $root '.git\rebase-merge')) -or (Test-Path (Join-Path $root '.git\rebase-apply'))) {
        Write-Host "[警告] 发现上次未完成的变基状态，正在自动清理（git rebase --abort）..."
        git rebase --abort 2>&1 | Out-Null
    }

    # 执行拉取（带低速率超时，避免卡死）
    # 2>&1 会把 git 的 stderr 变成 ErrorRecord，这里转成纯文本，避免输出出现红字错误块
    $out = (git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=30 pull origin main 2>&1 |
        ForEach-Object { $_.ToString() }) -join "`r`n"
    $rc = $LASTEXITCODE

    # ---------- 成功：结束轮询 ----------
    if ($rc -eq 0) {
        Write-Host ""
        Write-Host "============================================================"
        Write-Host ("[{0}] 拉取成功！已获取到最新更新。" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
        Write-Host "本次 git 输出："
        if ($out) { Write-Host $out }
        Write-Host "============================================================"
        exit 0
    }

    # ---------- 失败：判断是否永久性本地问题 ----------
    $permanent = $false
    foreach ($p in $permanentPatterns) {
        if ($out -match [regex]::Escape($p)) { $permanent = $true; break }
    }

    if ($permanent) {
        Write-Host ""
        Write-Host "============================================================"
        Write-Host ("[{0}] 拉取失败，判断为本地问题（重试无法解决），已停止。" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
        Write-Host "git 输出如下："
        if ($out) { Write-Host $out }
        Write-Host ""
        Write-Host "常见处理方式："
        Write-Host "  - 本地有未提交修改：先提交，或用 git stash 暂存后，再运行本脚本"
        Write-Host "  - 合并冲突：手动解决冲突后 git add + git commit"
        Write-Host "  - 与远端分叉：确认无需本地改动后 git reset --hard origin/main"
        Write-Host "  - 权限 / 仓库不存在：用 git remote -v 检查 origin 地址是否正确"
        Write-Host "============================================================"
        exit 1
    }

    # ---------- 瞬时失败（多半是网络问题）：继续轮询 ----------
    Write-Host ""
    Write-Host ("[{0}] 第 {1} 次拉取失败 —— 通常为网络问题，{2} 秒后自动重试。" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $attempt, $Interval)
    Write-Host "             不想继续等待可按 Ctrl+C 停止。"
    Write-Host ""
    if ($out) { Write-Host $out; Write-Host "" }

    if ($MaxAttempts -gt 0 -and $attempt -ge $MaxAttempts) {
        Write-Host "[提示] 已达最大尝试次数（$MaxAttempts 次），停止轮询。"
        exit 1
    }

    $attempt++
    Start-Sleep -Seconds $Interval
}
