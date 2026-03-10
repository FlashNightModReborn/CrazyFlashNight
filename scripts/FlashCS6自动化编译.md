# Flash CS6 自动化编译指南

## 概述

Agent（Claude Code）可从终端触发 Flash CS6 编译 AS2 代码并读取 trace 输出。

## 架构

```
Agent → compile_test.sh (bash) 或 compile_test.ps1 (PowerShell)
  → Start-ScheduledTask 'CompileTriggerTask'  (绕过 UAC)
    → trigger_compile.ps1  (管理员权限打开 JSFL)
      → compile.jsfl  (Commands 目录，eval 动态加载器)
        → compile_action.jsfl  (项目目录，实际编译逻辑)
          → doc.testMovie()  (Flash CS6 编译+运行)
            → publish_done.marker  (完成标记)
              ← 脚本检测到 marker，读取 flashlog.txt
```

## 快速开始

### 1. 环境配置（每台机器执行一次）

以**管理员身份**运行 `scripts/setup_compile_env.bat`，自动完成：
- 创建 `%USERPROFILE%\mm.cfg`（Flash debug 日志配置）
- 检测 Flash CS6 语言目录
- 写入项目路径配置 `flash_project_path.cfg` 到 Commands 目录
- 部署 `compile.jsfl` 到 Commands 目录（已存在则跳过，避免缓存问题）
- 查找 Flash.exe（常见路径自动检测 + 手动输入）
- 创建两个计划任务：`FlashCS6Task`、`CompileTriggerTask`
- 生成 `compile_env.sh`（shell 环境变量，机器相关，已 gitignore）

> 所有路径均自动检测，无硬编码。Git 同步后在新机器上只需重新运行此脚本。

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
| `scripts/trigger_compile.ps1` | 管理员权限触发脚本 |
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
- Flash CS6 **启动时缓存** Commands 目录下 JSFL 文件内容
- 修改已有 JSFL 需**重启 Flash** 才生效
- **新增** JSFL 可立即使用
- **解决方案**：`compile.jsfl` 固定不变，用 `eval(FLfile.read())` 动态加载 `compile_action.jsfl`

### fl.addEventListener 不支持 idle
- CS6 报错「参数数目 1 无效」，"idle" 不在支持的事件类型中
- 无法用 JSFL 实现文件轮询 daemon

### fl.runScript 行为
- `fl.runScript(uri)` 加载文件但不执行顶层代码
- `fl.runScript(uri, "funcName")` 可调用指定函数
- `eval(FLfile.read())` 更可靠

### UAC 与权限
- Flash CS6 需管理员权限，非管理员进程无法 SendKeys / 打开 JSFL
- **解决方案**：计划任务（RunLevel=HighestAvailable）

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

## 待解决

- [ ] 编译错误捕获和返回（目前只有 error_marker 简单标记）
- [ ] testMovie 预览窗口自动关闭
