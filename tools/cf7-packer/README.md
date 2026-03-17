# CF7-Packer — CF7 发行打包工具

将 git 仓库/工作区按声明式规则打包为发行版目录，供美术、测试同学一键操作。

## 快速开始

### GUI（推荐）

首次运行会自动安装依赖、下载 Electron 并构建渲染器，无需手动操作。

| 平台 | 启动方式 |
|------|---------|
| Windows | 双击 `launch.bat` |
| macOS / Linux | `chmod +x launch.sh && ./launch.sh` |

支持 macOS Intel / Apple Silicon (M1+) 和 Linux x64。

GUI 功能：
- Treemap 可视化查看文件分布，支持逐层下钻
- 文件树浏览 + 搜索过滤
- 右键菜单：打开文件 / 在资源管理器中显示 / **排除文件** / **删除并排除**
- 排除操作会自动写入 `pack.config.yaml` 对应层级的 `exclude` 规则
- 差异对比：对比任意两个 git tag 的打包结果差异
- 打包后可一键构建 SFX 自解压安装包

### CLI

```bash
cd tools/cf7-packer
npm install          # 首次使用（GUI 模式无需手动执行）

# 预览（不复制文件，只统计）
npm run pack:dry-run

# 执行打包
npm run pack

# 从指定 git tag 打包
npx tsx packages/cli/src/index.ts pack --tag "闪客快打7重置计划2.71整包"

# 对比两个版本的打包差异
npx tsx packages/cli/src/index.ts diff --base "闪客快打7重置计划2.66整包" --target "闪客快打7重置计划2.71整包"

# 校验配置文件
npm run validate-config

# 列出所有 git tag
npm run list-tags
```

## 打包规则

所有规则在 `pack.config.yaml` 中声明，修改后立即生效，无需改代码。

### 采集策略

| 模式 | 采集方式 | 适用场景 |
|------|---------|---------|
| worktree | 文件系统递归扫描 | 日常打包（包含未提交的新文件） |
| git-tag | `git ls-tree` | 精确还原历史版本 |

### 层级概览

| 层级 | 规则 |
|------|------|
| data/ | 全量复制（XML 配置） |
| scripts/ | 仅 asLoader.swf（运行时加载器） |
| flashswf/ | 编译后 .swf + 运行时资源（排除 XFL 源工程、.fla） |
| sounds/ | 音效 SWF + BGM（排除版权音乐） |
| config/ | 全量复制 |
| root-files | .exe / .swf / config.xml 等根目录文件 |
| root-dirs | 字体、教程文件夹 |

## 架构

```
packages/
├── core/   三层后端：collector → filter → packer
│            支持 AbortSignal 取消
├── cli/    命令行入口
└── web/    Electron + React GUI
```

## 开发

```bash
npm run typecheck    # 类型检查
npm test             # 运行测试（41 个）
npm run dev:web      # Vite 开发服务器
npm run dev:electron # Electron 开发模式
```
