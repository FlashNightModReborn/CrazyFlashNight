# Git 大型仓库瘦身完整指南

> **安全提示：** 本操作涉及强制推送和历史重写，务必做好多重备份！

## 目录

1. [背景与目标](#1-背景与目标)
2. [准备阶段](#2-准备阶段)
3. [本地清理阶段](#3-本地清理阶段)
4. [镜像推送阶段](#4-镜像推送阶段)
5. [GitHub 设置调整](#5-github-设置调整)
6. [常见网络/报错排查](#6-常见网络报错排查)
7. [与 GitHub Support 配合](#7-与-github-support-配合)
8. [回滚预案](#8-回滚预案)
9. [验证与收尾](#9-验证与收尾)
10. [经验要点速查表](#10-经验要点速查表)
11. [参考脚本（附录）](#11-参考脚本附录)

---

## 1. 背景与目标

| 项目         | 说明                                                         |
| ------------ | ------------------------------------------------------------ |
| 原仓库       | `FlashNightModReborn/CrazyFlashNight`（≈ 9 GB，`main` 为默认分支） |
| clean 仓库   | `CrazyFlashNight-clean`（1.6 GB，已含瘦身历史）             |
| archive 仓库 | `CrazyFlashNight-archive-20250523`（完整备份）              |
| **目标**     | 保留原 URL、Star、Issue、Release，但把 `.git` 体积降到 < 2 GB |
| **核心难点** | GitHub packfile（Git对象存储文件）上限 2 GB；远端默认分支保护；国内网络不稳 |
| **预估时间** | 总计 6-12 小时（含 GitHub 后台 GC）                         |

---

## 2. 准备阶段

### 2-1 环境与工具准备

| 步骤           | 命令 & 操作                                                  | 说明                                      |
| -------------- | ------------------------------------------------------------ | ----------------------------------------- |
| **工具安装**   | `winget install Git.Git -e`<br>`pip install git-filter-repo git-sizer` | `git-sizer` 分析体积，`filter-repo` 精确清理 |
| **工作目录**   | 选择 `C:\git-work` 或 `/home/user/git-work`                 | **避免** `Program Files` 等含空格的路径   |
| **权限确认**   | 确认对目标仓库拥有 **Admin** 权限                            | 组织仓库可能需要 Owner 权限才能强推       |
| **协作者通知** | 提前通知所有协作者**暂停推送 24-48 小时**                    | 避免瘦身过程中产生冲突                    |

### 2-2 多重备份策略

| 备份类型     | 命令                                                         | 用途                     |
| ------------ | ------------------------------------------------------------ | ------------------------ |
| **镜像备份** | `git clone --mirror https://github.com/FlashNightModReborn/CrazyFlashNight CrazyFlashNight-backup.git` | 完整远程备份             |
| **Bundle备份**| `git bundle create full-backup.bundle --all`                | 便携式单文件备份         |
| **本地备份** | `cp -r .git .git-backup-$(date +%Y%m%d)`                    | 当前工作目录快照         |

> **💡 提示：** Bundle 格式可以在任何地方恢复，是最安全的备份方式。

### 2-3 网络与性能优化

```bash
# HTTP 配置（适用于 HTTPS 推送）
git config --global http.postBuffer 524288000      # 500MB 缓冲区
git config --global http.maxRequestBuffer 104857600 # 100MB 请求缓冲
git config --global http.lowSpeedLimit 0           # 禁用低速检测
git config --global http.lowSpeedTime 999999       # 超长超时时间

# SSH 配置（推荐用于大文件，更稳定）
ssh-keygen -t ed25519 -C "your_email@example.com"
# 将公钥添加到 GitHub，然后测试连接：
ssh -T git@github.com
```

---

## 3. 本地清理阶段

> **注意：** 此轮清理已在 GitHub 网页端"CrazyFlashNight-clean" 完成。若需重新清理，可参考以下两种模式：

### 模式 A：只保留最新快照（激进瘦身）

```bash
# 创建新的孤立分支，只含当前状态
git checkout --orphan clean-main
git reset --hard HEAD    # 保持工作区文件
git add .
git commit -m "Initial clean snapshot - $(date)"

# 删除所有旧分支和标签
git for-each-ref --format='%(refname)' refs/heads/ | grep -v clean-main | xargs -n1 git update-ref -d
git tag -d $(git tag -l)

# 清理引用日志和垃圾回收
git reflog expire --expire=now --all
git gc --aggressive --prune=now

# 检查效果
git count-objects -vH
```

### 模式 B：保留历史但删除大文件（温和瘦身）

```bash
# 分析哪些文件最占空间
git-sizer --verbose

# 删除超过 25MB 的文件（保留历史结构）
git filter-repo --force --strip-blobs-bigger-than 25M

# 或者删除特定路径
# git filter-repo --force --path 'large-assets/' --invert-paths

# 强制垃圾回收
git reflog expire --expire=now --all
git gc --aggressive --prune=now

# 再次检查
git count-objects -vH
```

---

## 4. 镜像推送阶段

### 4-1 时间预估

| 阶段     | 预估时间     | 影响因素                     |
| -------- | ------------ | ---------------------------- |
| 克隆准备 | 10-30 分钟   | 网络带宽、仓库大小           |
| 镜像推送 | 1-6 小时     | 网络稳定性、packfile 大小    |
| 后台处理 | 12-24 小时   | GitHub 服务器 GC 队列        |

### 4-2 克隆干净仓库为裸镜像

```bash
cd /c/git-work  # 或 ~/git-work
echo "开始克隆干净仓库..."
git clone --mirror https://github.com/FlashNightModReborn/CrazyFlashNight-clean.git
cd CrazyFlashNight-clean.git

# 检查当前状态
echo "当前仓库大小："
du -sh .
git count-objects -vH
```

### 4-3 切换远端到原仓库

```bash
# 改用 SSH（推荐）以获得更好的稳定性
git remote set-url origin git@github.com:FlashNightModReborn/CrazyFlashNight.git

# 或继续使用 HTTPS
# git remote set-url origin https://github.com/FlashNightModReborn/CrazyFlashNight.git

# 验证远端设置
git remote -v
```

### 4-4 规避 2GB packfile 限制

```bash
# 重新打包，限制单个 packfile 大小
echo "重新打包以规避 2GB 限制..."
git repack -Ad --max-pack-size=1500m --depth=50 --window=50 --no-write-bitmap-index

# 检查 packfile 大小
ls -lh objects/pack/*.pack

# 如果仍有超过 1.8GB 的包，进一步拆分
find objects/pack -name "*.pack" -size +1800M -exec echo "警告：发现大包文件 {}" \;
```

### 4-5 执行镜像推送

```bash
echo "开始镜像推送..."
echo "推送开始时间：$(date)"

# 由于使用了裸仓库（bare repository），推送时会包含所有引用
# 只需一句命令：
git push --mirror

echo "推送完成时间：$(date)"
```

### 4-6 监控推送进度（可选）

在另一个终端窗口运行：

```bash
# 监控网络流量
watch -n 5 'netstat -i'

# 或监控 Git 对象状态
watch -n 10 'git count-objects -v'
```

---

## 5. GitHub 设置调整

### 5-1 绕过默认分支保护

由于 GitHub 不允许删除或强制推送默认分支，需要临时调整：

1. **创建临时分支**
   - 在 GitHub 网页端：Create new branch → 输入 `temp`
   
2. **更改默认分支**
   - Settings → General → Default branch → 选择 `temp` → Update
   
3. **确认更改生效**
   - 刷新仓库主页，确认显示 `temp` 分支

### 5-2 推送完成后的恢复

1. **恢复默认分支**
   - Settings → General → Default branch → 选择 `main` → Update
   
2. **删除临时分支**
   - Branches 页面 → 删除 `temp` 分支

---

## 6. 常见网络/报错排查

| 报错信息                                          | 可能原因                         | 解决方案                                              |
| ------------------------------------------------- | -------------------------------- | ----------------------------------------------------- |
| `fatal: --mirror can't be combined with refspecs` | 在镜像仓库中错误使用了具体分支名 | 只使用 `git push --mirror`，不要指定分支             |
| `refusing to delete the current branch`           | 尝试删除默认分支                 | 先更改默认分支到其他分支                              |
| `RPC failed; curl 55/56 Recv failure`             | 网络连接被重置或不稳定           | 1. 重试推送<br>2. 使用 SSH 代替 HTTPS<br>3. 拆分packfile |
| `pack exceeds maximum allowed size (2GB)`         | 单个 packfile 超过 GitHub 限制   | 使用 `--max-pack-size=1500m` 重新打包                |
| `Updates were rejected because the remote contains work` | 远端有新提交与本地冲突       | 使用 `--force-with-lease` 或确认后用 `--force`      |
| `Permission denied (publickey)`                   | SSH 密钥配置问题                 | 检查 `ssh -T git@github.com` 或改用 HTTPS           |
| `The remote end hung up unexpectedly`             | 推送数据包太大或网络超时         | 增加 `http.maxRequestBuffer` 或分批推送              |

### 网络问题诊断命令

```bash
# 测试 GitHub 连接
curl -I https://github.com
ssh -T git@github.com

# 检查 Git 配置
git config --list | grep -E "(http|ssh)"

# 重置网络配置（如果需要）
git config --global --unset http.proxy
git config --global --unset https.proxy
```

---

## 7. 与 GitHub Support 配合

### Support Ticket 流程

我们的实际工单号：**#3423832**

| 阶段                     | 你向 Support 发送的信息                                      | Support 的回复/操作               |
| ------------------------ | ------------------------------------------------------------ | --------------------------------- |
| **初始咨询**             | 描述目标：将 9GB 仓库瘦身到 <2GB，保留 stars/issues/releases | 解释 2GB packfile 限制，提供方案  |
| **推送完成后**           | "I've successfully completed the mirror push using `git push --mirror`. The repository history has been rewritten. Could you please trigger a garbage collection on the server side to reclaim the storage space?" | Support 触发后台 `git gc`         |
| **跟进确认**（24小时后） | "Could you please confirm the GC status? The repository size should now be under 1GB." | 确认 GC 完成，提供最终大小信息    |

### 邮件模板

```
Subject: Request for Server-side Garbage Collection - Repository Slimming

Hello GitHub Support,

I have successfully completed a repository slimming operation for:
Repository: FlashNightModReborn/CrazyFlashNight

Actions taken:
- Cleaned repository history using git-filter-repo
- Used mirror push to update all references
- Repository size reduced from ~9GB to ~1.6GB locally

Request:
Could you please trigger a server-side garbage collection (git gc) to reclaim storage space on GitHub's servers?

This will ensure the remote repository reflects the size reduction achieved locally.

Thank you for your assistance!
```

---

## 8. 回滚预案

### 紧急回滚步骤

如果推送后发现严重问题，可以快速回滚：

```bash
# 方法1：使用镜像备份回滚
cd /path/to/CrazyFlashNight-backup.git
git remote set-url origin git@github.com:FlashNightModReborn/CrazyFlashNight.git
git push --mirror --force-with-lease

# 方法2：使用 bundle 文件回滚
git clone full-backup.bundle recovered-repo
cd recovered-repo
git remote add origin git@github.com:FlashNightModReborn/CrazyFlashNight.git
git push --mirror --force
```

### 数据完整性验证

回滚前验证备份完整性：

```bash
# 检查 bundle 文件
git bundle verify full-backup.bundle

# 对比备份与当前状态
git clone --mirror your-backup.git temp-check
cd temp-check
git log --oneline -10  # 查看最近提交
git tag -l             # 查看所有标签
```

---

## 9. 验证与收尾

### 9-1 技术验证

等待 GitHub 后台 GC 完成（通常12-24小时）后：

```bash
# 1. 重新克隆验证大小
git clone https://github.com/FlashNightModReborn/CrazyFlashNight.git test-clone
cd test-clone
du -sh .git     # 目标：< 1GB

# 2. 验证数据完整性
git log --oneline -10                    # 检查提交历史
git tag -l                               # 检查标签
git branch -r                            # 检查远程分支
git fsck --full --strict                 # 检查仓库完整性

# 3. 验证功能性
git checkout main
ls -la          # 确认文件都在
# 运行项目特定的验证命令
```

### 9-2 GitHub 网页端验证

1. **仓库主页**
   - ✅ Code 页显示简洁的提交历史
   - ✅ 仓库大小显示正确（< 2GB）
   - ✅ Stars 和 watchers 数量保持不变

2. **功能完整性**
   - ✅ Issues 和 Pull Requests 正常显示
   - ✅ Releases 页面内容正确
   - ✅ Wiki（如有）内容完整
   - ✅ Actions（如有）可以正常运行

### 9-3 协作者指导

向所有协作者发送通知：

```markdown
## 🔄 仓库瘦身完成通知

我们已经完成了 CrazyFlashNight 仓库的瘦身操作，仓库大小从 9GB 减少到 <1GB。

**所有协作者需要执行以下操作：**

```bash
# 进入你的本地仓库目录
cd /path/to/your/CrazyFlashNight

# 获取最新的远程状态
git fetch --all --prune

# 重置本地主分支（⚠️ 会丢失未推送的本地更改）
git checkout main
git reset --hard origin/main

# 清理本地无用分支
git branch -vv | grep ': gone]' | awk '{print $1}' | xargs -r git branch -D

# 垃圾回收
git gc --aggressive --prune=now
```

**注意事项：**
- 如有未推送的本地更改，请提前备份
- 瘦身后的历史记录有所变化，这是正常的
- 如遇问题请及时联系项目维护者
```

### 9-4 文档更新

在项目 README 中添加：

```markdown
## 📦 仓库历史

本仓库于 2025年5月 进行了历史瘦身，从 ~9GB 减少到 <1GB。
完整的历史记录备份保存在 `CrazyFlashNight-archive-20250523` 仓库中。
```

---

## 10. 经验要点速查表

| 分类         | 最佳实践                                              | 注意事项                          |
| ------------ | ----------------------------------------------------- | --------------------------------- |
| **历史清理** | 优先使用 `git filter-repo`，比 BFG 更灵活精确        | 操作前必须做多重备份              |
| **推送策略** | 裸仓库 + `git push --mirror` 最省心                  | 避免混用 `--mirror` 和具体分支名  |
| **Pack限制** | `--max-pack-size=1500m` 预留安全余量                 | GitHub 硬限制 2GB，建议不超过1.8GB |
| **分支保护** | 先改默认分支到临时分支，完成后再改回                  | 避免 `refusing to delete` 错误   |
| **网络优化** | SSH > HTTPS，调大缓冲区，保持网络稳定                 | 准备备用网络或VPN                 |
| **Support配合** | 推送完成后立即联系 GitHub Support 请求 GC            | 通常24小时内完成                  |
| **验证流程** | 多维度验证：大小、完整性、功能性                      | 等待 GitHub GC 完成后再验证       |
| **团队协作** | 提前通知，提供详细的本地更新指令                      | 准备应急回滚方案                  |

---

## 11. 参考脚本（附录）

### A. 完整的一键瘦身脚本

```bash
#!/bin/bash
# Git 仓库瘦身自动化脚本
# 使用方法: ./slim_repo.sh <clean-repo-url> <target-repo-url>

set -e  # 遇到错误立即退出

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查参数
if [ $# -ne 2 ]; then
    echo -e "${RED}使用方法: $0 <clean-repo-url> <target-repo-url>${NC}"
    echo "示例: $0 https://github.com/user/repo-clean.git https://github.com/user/repo.git"
    exit 1
fi

CLEAN_REPO=$1
TARGET_REPO=$2
WORK_DIR="git-slim-work-$(date +%Y%m%d-%H%M%S)"

echo -e "${GREEN}=== Git 仓库瘦身脚本启动 ===${NC}"
echo "清理仓库: $CLEAN_REPO"
echo "目标仓库: $TARGET_REPO"
echo "工作目录: $WORK_DIR"

# 检查必要工具
echo -e "${YELLOW}检查工具依赖...${NC}"
for cmd in git ssh; do
    if ! command -v $cmd >/dev/null 2>&1; then
        echo -e "${RED}错误: 未找到 $cmd 命令${NC}"
        exit 1
    fi
done

# 配置网络参数
echo -e "${YELLOW}配置网络参数...${NC}"
git config --global http.postBuffer 524288000
git config --global http.maxRequestBuffer 104857600
git config --global http.lowSpeedLimit 0
git config --global http.lowSpeedTime 999999

# 创建工作目录
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# 克隆清理过的镜像
echo -e "${YELLOW}克隆清理过的仓库镜像...${NC}"
git clone --mirror "$CLEAN_REPO" slim-mirror.git
cd slim-mirror.git

# 检查当前大小
echo -e "${YELLOW}检查仓库大小...${NC}"
du -sh .
git count-objects -vH

# 设置目标远程仓库
echo -e "${YELLOW}设置目标远程仓库...${NC}"
git remote set-url origin "$TARGET_REPO"
git remote -v

# 重新打包以规避 2GB 限制
echo -e "${YELLOW}重新打包以规避 2GB 限制...${NC}"
git repack -Ad --max-pack-size=1500m --depth=50 --window=50 --no-write-bitmap-index

# 检查 packfile 大小
echo -e "${YELLOW}检查 packfile 大小...${NC}"
ls -lh objects/pack/*.pack || echo "No pack files found"

# 执行镜像推送
echo -e "${YELLOW}开始镜像推送...${NC}"
echo "推送开始时间: $(date)"

if git push --mirror; then
    echo -e "${GREEN}✅ 推送成功完成!${NC}"
    echo "推送完成时间: $(date)"
else
    echo -e "${RED}❌ 推送失败，请检查网络和权限${NC}"
    exit 1
fi

# 完成提示
echo -e "${GREEN}=== 瘦身操作完成 ===${NC}"
echo -e "${YELLOW}下一步操作:${NC}"
echo "1. 检查 GitHub 网页端仓库状态"
echo "2. 联系 GitHub Support 请求服务器端 GC"
echo "3. 等待 12-24 小时后验证最终大小"
echo "4. 通知协作者更新本地仓库"
echo ""
echo "Support 请求模板："
echo "---"
echo "Hi GitHub Support,"
echo "I've completed a mirror push to slim down the repository."
echo "Repository: ${TARGET_REPO}"
echo "Could you please trigger server-side garbage collection?"
echo "Thanks!"
echo "---"

# 清理工作目录（可选）
read -p "是否删除工作目录 $WORK_DIR? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    cd ../..
    rm -rf "$WORK_DIR"
    echo "工作目录已清理"
fi

echo -e "${GREEN}脚本执行完成!${NC}"
```

### B. 分段推送脚本（备用方案）

```bash
#!/bin/bash
# 当 --mirror 推送仍然失败时的分段推送备用方案

set -e

echo "开始分段推送..."

# 推送所有分支（每个分支单独推送）
echo "推送所有分支..."
git for-each-ref --format='%(refname:short)' refs/heads/ | while read branch; do
    echo "推送分支: $branch"
    git push origin "+refs/heads/$branch:refs/heads/$branch" || echo "分支 $branch 推送失败，跳过"
done

# 推送所有标签（分批推送）
echo "推送所有标签..."
git tag -l | split -l 100 - tags-batch-
for batch_file in tags-batch-*; do
    echo "推送标签批次: $batch_file"
    while read tag; do
        git push origin "refs/tags/$tag:refs/tags/$tag" || echo "标签 $tag 推送失败，跳过"
    done < "$batch_file"
    rm "$batch_file"
done

echo "分段推送完成！"
```

### C. 仓库大小监控脚本

```bash
#!/bin/bash
# 监控仓库瘦身效果

REPO_URL=$1
if [ -z "$REPO_URL" ]; then
    echo "使用方法: $0 <repository-url>"
    exit 1
fi

REPO_NAME=$(basename "$REPO_URL" .git)
MONITOR_DIR="size-monitor-$(date +%Y%m%d)"

mkdir -p "$MONITOR_DIR"
cd "$MONITOR_DIR"

echo "开始监控仓库大小变化..."
echo "仓库: $REPO_URL"
echo "监控开始时间: $(date)"
echo "---"

while true; do
    echo "$(date): 克隆仓库检查大小..."
    
    # 清理之前的克隆
    rm -rf "$REPO_NAME" 2>/dev/null || true
    
    # 克隆并检查大小
    if git clone "$REPO_URL" "$REPO_NAME" >/dev/null 2>&1; then
        cd "$REPO_NAME"
        SIZE=$(du -sh .git | cut -f1)
        OBJECTS=$(git count-objects -v | grep "size-pack" | awk '{print $2}')
        echo "$(date): .git 大小: $SIZE, 对象大小: ${OBJECTS}K"
        cd ..
    else
        echo "$(date): 克隆失败，可能仓库正在更新中..."
    fi
    
    # 等待1小时后再次检查
    sleep 3600
done
```

### D. 协作者本地更新脚本

```bash
#!/bin/bash
# 协作者用于更新本地仓库的脚本

echo "=== 仓库瘦身后的本地更新脚本 ==="
echo "⚠️  警告：此操作会丢失未推送的本地更改！"
echo ""

# 确认操作
read -p "确认要继续吗？本地未推送的更改将会丢失！(yes/no): " -r
if [[ ! $REPLY =~ ^yes$ ]]; then
    echo "操作已取消"
    exit 1
fi

# 检查当前是否在 Git 仓库中
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "错误：当前目录不是 Git 仓库"
    exit 1
fi

echo "开始更新本地仓库..."

# 获取当前分支
CURRENT_BRANCH=$(git branch --show-current)
echo "当前分支: $CURRENT_BRANCH"

# 备份当前更改（如果有）
if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "检测到未提交的更改，创建备份..."
    git stash push -u -m "Backup before repository slimming update - $(date)"
    echo "更改已备份到 stash"
fi

# 获取最新的远程状态
echo "获取远程仓库状态..."
git fetch --all --prune

# 重置主分支
echo "重置本地分支..."
git checkout main
git reset --hard origin/main

# 清理无用的本地分支
echo "清理无用的本地分支..."
git branch -vv | grep ': gone]' | awk '{print $1}' | xargs -r git branch -D

# 返回原来的分支（如果不是main）
if [ "$CURRENT_BRANCH" != "main" ] && [ -n "$CURRENT_BRANCH" ] && git show-ref --verify --quiet refs/remotes/origin/"$CURRENT_BRANCH"; then
    echo "返回分支: $CURRENT_BRANCH"
    git checkout "$CURRENT_BRANCH"
    git reset --hard origin/"$CURRENT_BRANCH"
fi

# 垃圾回收
echo "执行本地垃圾回收..."
git gc --aggressive --prune=now

# 显示最终状态
echo ""
echo "=== 更新完成 ==="
echo "仓库大小: $(du -sh .git | cut -f1)"
echo "当前分支: $(git branch --show-current)"
echo "最近提交: $(git log --oneline -3)"

# 检查是否有 stash
if git stash list | grep -q "Backup before repository slimming"; then
    echo ""
    echo "💡 提示：你的本地更改已备份到 git stash"
    echo "如需恢复，使用: git stash pop"
fi

echo ""
echo "✅ 本地仓库更新完成！"
```

---

> **📝 文档更新日志**
> - **v1.0** (2025-05-28): 初始版本，基于 CrazyFlashNight 瘦身实践
> - **v1.1** (2025-05-28): 增加安全性控制、回滚预案、完整脚本支持
