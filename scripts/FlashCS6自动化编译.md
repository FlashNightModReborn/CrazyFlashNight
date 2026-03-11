# Flash CS6 自动化编译指南

## 概述

Agent（Claude Code）可从终端触发 Flash CS6 编译 AS2 代码并读取 trace 输出。

## 架构

```
Agent → compile_test.sh (bash) 或 compile_test.ps1 (PowerShell)
  → Start-ScheduledTask 'CompileTriggerTask'  (绕过 UAC)
    → cmd.exe /c start compile.jsfl  (计划任务直接打开 JSFL)
      → compile.jsfl  (Commands 目录，eval 动态加载器，固定不变)
        → compile_action.jsfl  (项目目录，实际编译逻辑，可随时修改)
          → doc.testMovie()  (Flash CS6 编译+运行)
            → publish_done.marker  (完成标记)
              ← 脚本检测到 marker，读取 flashlog.txt
```

## 快速开始

### 1. 环境配置（每台机器执行一次）

#### 方式 A：一键脚本（推荐）

**右键** `scripts/setup_compile_env.bat` → **以管理员身份运行**。

自动完成：
- 创建 `%USERPROFILE%\mm.cfg`（Flash debug 日志配置）
- 检测 Flash CS6 语言目录
- 写入项目路径配置 `flash_project_path.cfg` 到 Commands 目录
- 部署 `compile.jsfl` 到 Commands 目录（已存在则跳过，避免缓存问题）
- 查找 Flash.exe（常见路径自动检测 + 手动输入）
- 创建两个计划任务：`FlashCS6Task`、`CompileTriggerTask`
- 生成 `compile_env.sh`（shell 环境变量，机器相关，已 gitignore）

> **重要**：必须以管理员身份运行，否则计划任务创建会静默失败。

#### 方式 B：Agent 辅助创建计划任务

如果 setup 脚本的计划任务创建失败（未以管理员运行），Agent 可通过单次 UAC 提权补救：
```powershell
# 生成创建脚本到 C:\tmp\，然后提权执行（只弹一次 UAC）
Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -File C:\tmp\create_tasks.ps1' -Verb RunAs -Wait
```

#### 验证配置

```powershell
# 检查计划任务是否存在
Get-ScheduledTask -TaskName 'CompileTriggerTask','FlashCS6Task' | Select TaskName, State
# 检查 Commands 目录
ls "$env:LOCALAPPDATA\Adobe\Flash CS6\zh_CN\Configuration\Commands\compile.jsfl"
ls "$env:LOCALAPPDATA\Adobe\Flash CS6\zh_CN\Configuration\Commands\flash_project_path.cfg"
```

> 所有路径均自动检测，无硬编码。Git 同步后在新机器上只需重新运行 setup。

### 2. 使用流程

1. 启动 Flash CS6（手动或 `powershell -Command "Start-ScheduledTask 'FlashCS6Task'"`)
2. 在 Flash 中打开 `scripts/TestLoader`（XFL 工程）
3. Agent 触发编译（二选一）：
   - **Bash**（Git Bash / WSL）：`bash scripts/compile_test.sh`
   - **PowerShell**：`powershell -ExecutionPolicy Bypass -File scripts/compile_test.ps1`

### 3. 修改测试代码

编辑 `scripts/TestLoader.as`（Git 跟踪），再触发编译。
`compile_action.jsfl` 通过 `eval()` 动态加载，修改后无需重启 Flash。

## 关键文件

### 项目目录（Git 跟踪）

| 文件 | 用途 |
|------|------|
| `scripts/compile_test.sh` | Agent 编译入口（Bash 版，需 Git Bash） |
| `scripts/compile_test.ps1` | Agent 编译入口（PowerShell 版，无需额外依赖） |
| `scripts/compile_action.jsfl` | 实际编译逻辑（可随时修改，不需重启 Flash） |
| `scripts/trigger_compile.ps1` | 管理员权限触发脚本（已弃用，计划任务直接用 cmd.exe 打开 JSFL） |
| `scripts/setup_compile_env.bat` | 一键环境配置（每台机器运行一次） |
| `scripts/TestLoader/` | TestLoader XFL 工程 |
| `scripts/TestLoader.as` | 测试用 AS2 源码（修改此文件改变测试内容） |

### 机器相关（gitignore）

| 文件 | 用途 |
|------|------|
| `scripts/compile_env.sh` | shell 环境变量（setup 自动生成） |
| `scripts/publish_done.marker` | 编译完成标记 |
| `scripts/publish_error.marker` | 编译错误标记 |
| `scripts/flashlog.txt` | Flash trace 输出副本 |
| `scripts/TestLoader.swf` | 编译产物 |

### Commands 目录（部署到 Flash CS6 配置）

| 文件 | 用途 |
|------|------|
| `compile.jsfl` | 动态加载器（eval 执行 compile_action.jsfl） |
| `flash_project_path.cfg` | 项目路径（JSFL URI 格式） |

## 踩坑记录

### JSFL 缓存（最关键）
- Flash CS6 **启动时缓存** Commands 目录下 JSFL 文件内容（用于 Commands 菜单调用）
- **修改已有 JSFL** → Commands 菜单中执行的仍是缓存的旧内容，需**重启 Flash** 才生效
- **新增 JSFL** → 通过文件关联（`Start-Process`/`cmd /c start`）打开可立即执行，**无需重启**
- **绝不要修改已有的 Commands 目录 JSFL 文件来添加功能**，永远新建文件
- **解决方案**：`compile.jsfl` 固定不变（部署后永不修改），用 `eval(FLfile.read())` 动态加载 `compile_action.jsfl`（位于项目目录，可随时修改，每次执行时实时读取）

### fl.addEventListener 不支持 idle
- CS6 报错「参数数目 1 无效」，"idle" 不在支持的事件类型中
- 无法用 JSFL 实现文件轮询 daemon

### fl.runScript 行为
- `fl.runScript(uri)` 加载文件但不执行顶层代码
- `fl.runScript(uri, "funcName")` 可调用指定函数
- `eval(FLfile.read())` 更可靠

### UAC 与权限
- Flash CS6 需管理员权限，非管理员进程打开 JSFL 会弹 UAC
- **解决方案**：计划任务（RunLevel=HighestAvailable）
- 计划任务的 Action 必须用 `cmd.exe /c start "" "path\to\compile.jsfl"` 直接打开 JSFL
- **不要**通过 PowerShell 脚本（trigger_compile.ps1）间接打开——`Start-Process` 和 `explorer.exe` 在计划任务环境中都无法可靠地将 JSFL 传递给运行中的 Flash 实例

### testMovie() vs publish()
- `testMovie()` 编译+运行 SWF，产生 trace 输出，弹出预览窗口（再次调用自动关闭旧窗口）
- `publish()` 只编译 SWF，不运行，无 trace 输出
- 当前使用 `testMovie()` 以获取 trace 调试信息

## 跨设备同步

1. `git pull` 获取最新代码
2. 以管理员身份运行 `scripts/setup_compile_env.bat`
3. 启动 Flash CS6，打开 TestLoader，即可使用

所有机器相关文件（路径、环境变量）均由 setup 脚本自动生成，已加入 `.gitignore`。

## 已解决

- [x] Agent 全自动编译 → 计划任务 + JSFL eval
- [x] JSFL 缓存 → eval 动态加载
- [x] UAC 弹窗 → 计划任务
- [x] 硬编码路径 → flash_project_path.cfg + setup 自动检测
- [x] 跨设备同步 → setup_compile_env.bat 一键配置

## 故障排查

### 编译超时（30 秒无 marker）

1. **Flash CS6 未运行或 TestLoader 未打开**：检查 `Get-Process -Name Flash`
2. **计划任务不存在**：`Get-ScheduledTask -TaskName 'CompileTriggerTask'`，不存在则重新运行 setup
3. **计划任务执行失败**：`(Get-ScheduledTaskInfo -TaskName 'CompileTriggerTask').LastTaskResult`，非 0 表示异常
4. **compile.jsfl 未部署**：检查 Commands 目录下是否存在
5. **flash_project_path.cfg 路径错误**：`cat "$env:LOCALAPPDATA\Adobe\Flash CS6\zh_CN\Configuration\Commands\flash_project_path.cfg"`，应为 `file:///C|/...` 格式

### setup 脚本计划任务创建失败

- 必须**右键 → 以管理员身份运行**，普通权限下 `schtasks /create` 会静默失败
- 验证：`Get-ScheduledTask -TaskName 'CompileTriggerTask','FlashCS6Task'`

### JSFL 修改后不生效

- Commands 目录下的 JSFL 被 Flash **启动时缓存**，修改不会自动生效
- `compile_action.jsfl`（项目目录）是通过 `eval(FLfile.read())` 实时读取的，修改**立即生效**
- 如果确实需要修改 Commands 目录下的 JSFL：新建文件，不要修改已有文件

## 待解决

- [ ] 编译错误捕获和返回（目前只有 error_marker 简单标记）
- [ ] testMovie 预览窗口自动关闭
