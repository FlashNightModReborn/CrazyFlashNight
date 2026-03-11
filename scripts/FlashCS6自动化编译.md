# Flash CS6 自动化编译指南

## 概述

Agent（Claude Code）可从终端触发 Flash CS6 编译 AS2 代码并读取 trace 输出。还可截取 Flash CS6 窗口截图，利用多模态能力辅助 UI 排版与交互调试。

## 当前经验总结（2026-03-11）

- 当前链路已能在本机完成“修改 `TestLoader.as` → 触发 Flash CS6 `testMovie()` → 拿到新鲜 trace / `compile_output.txt`”的自动化 smoke 验证
- 当前最容易导致跨设备失效的不是代码本身，而是**旧环境残留**：旧版 `CompileTriggerTask`、旧 Loader、旧 `flash_project_path.cfg`、旧日志都会造成“看起来能跑，实际跑的是旧路径”
- `scripts/setup_compile_env.bat` 现在应被视为**清理环境 + 自检 + 自愈**入口，而不只是首次安装脚本；拉取自动化相关更新后应重新运行一次
- 当前自动化验证仍应定义为**smoke 级**：新鲜 trace / 新鲜 `compile_output.txt` 才算有效信号，`publish_done.marker` 只能说明 JSFL 触发结束
- 当前链路仍在迭代期；遇到无 trace、长耗时套件、编译器面板错误、UI 状态异常时，仍需回到 Flash IDE 做人工复核
- PowerShell 5 环境下，含中文的 `.ps1` 脚本建议保持 **UTF-8 with BOM**，否则可能被系统本地编码误读，导致解析错误或乱码

## 架构

```
Agent → compile_test.sh (bash) 或 compile_test.ps1 (PowerShell)
  → Start-ScheduledTask 'CompileTriggerTask'  (绕过 UAC)
    → cmd.exe /c start cf7_compile_loader.jsfl  (计划任务直接打开 JSFL)
      → cf7_compile_loader.jsfl  (Commands 目录，项目专用动态加载器)
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
- 清理旧 marker / 旧日志 / 旧 shell 环境文件，避免残留结果干扰验证
- 创建 `%USERPROFILE%\mm.cfg`（Flash debug 日志配置）
- 检测 Flash CS6 语言目录
- 写入项目路径配置 `flash_project_path.cfg` 到 Commands 目录
- 部署 `cf7_compile_loader.jsfl` 到 Commands 目录，并保留 `compile.jsfl` 兼容入口
- 优先复用已有 `FlashCS6Task` 路径，找不到时再要求手动输入 `Flash.exe`
- 覆盖修复两个计划任务：`FlashCS6Task`、`CompileTriggerTask`
- 生成 `compile_env.sh`（shell 环境变量，机器相关，已 gitignore）
- 对 `mm.cfg`、项目路径配置、Loader、计划任务动作做一次自检，失败直接报错

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
Get-ChildItem "$env:LOCALAPPDATA\Adobe\Flash CS6" -Directory |
  Where-Object { Test-Path (Join-Path $_.FullName 'Configuration\Commands\cf7_compile_loader.jsfl') } |
  ForEach-Object {
    Get-ChildItem (Join-Path $_.FullName 'Configuration\Commands') cf7_compile_loader.jsfl,flash_project_path.cfg
  }
```

> 所有路径均自动检测。只要拉过自动化相关更新，就重新运行一次 setup，让脚本清理旧环境并修复任务定义。

### 2. 使用流程

1. 启动 Flash CS6（手动或 `powershell -Command "Start-ScheduledTask 'FlashCS6Task'"`)
2. 在 Flash 中打开 `scripts/TestLoader`（XFL 工程）
3. Agent 触发编译（二选一）：
   - **Bash**（Git Bash / WSL）：`bash scripts/compile_test.sh`
   - **PowerShell**：`powershell -ExecutionPolicy Bypass -File scripts/compile_test.ps1`

### 3. 修改测试代码

编辑 `scripts/TestLoader.as`（Git 跟踪），再触发编译。
`compile_action.jsfl` 通过 `eval()` 动态加载，修改后无需重启 Flash。

补充约束：
- `TestLoader.as` 适合作为 smoke test 入口，默认内容应尽量在数秒内结束并输出明确 trace
- 编辑 `.as` 文件后应保持 **UTF-8 with BOM**
- PowerShell 手动执行命令前先跑 `chcp.com 65001 | Out-Null`，否则中文输出容易乱码

### 4. 快速套件与长耗时套件

- `scripts/compile_test.ps1` 的轮询上限是 **30 秒**，适合快速回归
- 如果把 `TestLoader.as` 临时切到长耗时测试（例如 `RegExpTest.runAllTests()` 含性能基准），当前工作站实测可达 **约 37 秒**
- 长耗时场景下不要直接依赖 `compile_test.ps1` 的默认超时，应改用更长轮询脚本，或手动等待 `publish_done.marker` 与 `flashlog.txt`

## 关键文件

### 项目目录（Git 跟踪）

| 文件 | 用途 |
|------|------|
| `scripts/compile_test.sh` | Agent 编译入口（Bash 版，需 Git Bash） |
| `scripts/compile_test.ps1` | Agent 编译入口（PowerShell 版，无需额外依赖） |
| `scripts/compile_action.jsfl` | 实际编译逻辑（可随时修改，不需重启 Flash） |
| `scripts/trigger_compile.ps1` | 旧任务兼容触发脚本（内部已改为 `cmd /c start`，新环境不再直接依赖它） |
| `scripts/setup_compile_env.bat` | 一键环境配置（每台机器运行一次） |
| `scripts/setup_compile_env.ps1` | setup 的实际实现，负责清理、自检、自愈、任务重建 |
| `scripts/TestLoader/` | TestLoader XFL 工程 |
| `scripts/TestLoader.as` | 测试用 AS2 源码（修改此文件改变测试内容） |
| `scripts/capture_screenshot.ps1` | Agent 截取 Flash CS6 窗口截图（前置窗口 + CopyFromScreen） |

### 机器相关（gitignore）

| 文件 | 用途 |
|------|------|
| `scripts/compile_env.sh` | shell 环境变量（setup 自动生成） |
| `scripts/publish_done.marker` | 编译完成标记 |
| `scripts/publish_error.marker` | 编译错误标记 |
| `scripts/flashlog.txt` | Flash trace 输出副本 |
| `scripts/TestLoader.swf` | 编译产物 |
| `scripts/screenshot.png` | 窗口截图产物 |

### Commands 目录（部署到 Flash CS6 配置）

| 文件 | 用途 |
|------|------|
| `cf7_compile_loader.jsfl` | 主动态加载器（计划任务直开） |
| `compile.jsfl` | 兼容入口（仅为旧环境保留） |
| `flash_project_path.cfg` | 项目路径（JSFL URI 格式） |

## 踩坑记录

### JSFL 缓存（最关键）
- Flash CS6 **启动时缓存** Commands 目录下 JSFL 文件内容（用于 Commands 菜单调用）
- **修改已有 JSFL** → Commands 菜单中执行的仍是缓存的旧内容，需**重启 Flash** 才生效
- **新增 JSFL** → 通过文件关联（`Start-Process`/`cmd /c start`）打开可立即执行，**无需重启**
- **绝不要修改已有的 Commands 目录 JSFL 文件来添加功能**，永远新建文件
- **解决方案**：主入口改为项目专用的 `cf7_compile_loader.jsfl`，计划任务始终直开这个文件；旧环境如果还在走 `trigger_compile.ps1`，脚本也会回落到同一个 Loader

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
- 计划任务的 Action 必须用 `cmd.exe /c start "" "path\to\cf7_compile_loader.jsfl"` 直接打开 JSFL
- `trigger_compile.ps1` 仅保留给旧任务做兼容包装；它内部也必须走 `cmd /c start`，不能再走 `explorer.exe`

### testMovie() vs publish()
- `testMovie()` 编译+运行 SWF，产生 trace 输出，弹出预览窗口（再次调用自动关闭旧窗口）
- `publish()` 只编译 SWF，不运行，无 trace 输出
- 当前使用 `testMovie()` 以获取 trace 调试信息

### `publish_done.marker` 不等于 SWF 已成功运行
- `compile_action.jsfl` 在 `doc.testMovie()` 返回后就会写入 `publish_done.marker`
- 实际验证中，若 AS2 存在编译期静态类型错误，依然可能出现：
  - `publish_done.marker` 已生成
  - `scripts/compile_output.txt` 只有 `[compile] done`
  - `%APPDATA%\Macromedia\Flash Player\Logs\flashlog.txt` 仍为 0 字节或没有新 trace
- 结论：`publish_done.marker` 只能说明 **JSFL 已完成触发**，不能单独当作“编译并运行成功”的判据

### `compile_output.txt` 的局限
- `scripts/compile_output.txt` 保存的是 JSFL 通过 `fl.outputPanel.save()` 能拿到的 Output Panel 文本
- 目前它不能稳定带回 Flash 编译器面板里的 AS2 错误详情
- 遇到 “marker 成功但没有 trace” 时，应优先查看 Flash CS6 IDE 里的 **输出 / 编译器错误** 面板

### 旧环境残留是当前第一风险
- 这轮实测中，真正导致编译时再次弹 UAC 的根因是：机器里保留了旧版 `CompileTriggerTask`，动作仍指向 `trigger_compile.ps1 -> explorer.exe`
- 结论：跨设备或跨版本同步后，**不要假设已有计划任务仍然正确**；应重新运行 setup，让它覆盖修复任务动作、Loader 和项目路径配置
- 如果 `compile_test.ps1` 报 loader 缺失、日志未刷新、仍在走 legacy wrapper，优先怀疑环境漂移，而不是先怀疑 AS2 代码本身

## 跨设备同步

1. `git pull` 获取最新代码
2. 以管理员身份运行 `scripts/setup_compile_env.bat`
3. 启动 Flash CS6，打开 TestLoader，即可使用

所有机器相关文件（路径、环境变量）均由 setup 脚本自动生成，已加入 `.gitignore`。
setup 默认会清掉旧日志、旧 marker、旧 shell 环境，并覆盖修复计划任务，避免“旧环境残留看起来像成功”。
当前建议：只要自动化相关脚本有更新，就把 setup 当作升级步骤再跑一遍。

## 故障排查

### 编译超时（30 秒无 marker）

1. **Flash CS6 未运行或 TestLoader 未打开**：检查 `Get-Process -Name Flash`
2. **计划任务不存在**：`Get-ScheduledTask -TaskName 'CompileTriggerTask'`，不存在则重新运行 setup
3. **计划任务执行失败**：`(Get-ScheduledTaskInfo -TaskName 'CompileTriggerTask').LastTaskResult`，非 0 表示异常
4. **Loader 未部署**：检查 Commands 目录下是否存在 `cf7_compile_loader.jsfl`
5. **flash_project_path.cfg 路径错误**：重新运行 setup，或检查与当前项目对应的 Commands 目录里的 `flash_project_path.cfg`
6. **仍然弹 UAC**：当前环境大概率还残留旧任务定义；重新运行 setup，`compile_test.ps1` 也会直接提示是否仍在走 legacy wrapper

### marker 已生成，但 `flashlog.txt` 为空

1. 先看 Flash CS6 IDE 的 **输出 / 编译器错误** 面板，确认是否有 AS2 编译错误
2. 检查 `scripts/compile_output.txt`；如果只有 `[compile] done`，不能据此判断 SWF 已成功运行
3. 检查真实日志 `%APPDATA%\Macromedia\Flash Player\Logs\flashlog.txt` 的时间戳与长度是否刷新
4. 确认 `scripts/TestLoader.as` 是否仍保留明确的 trace 入口
5. 最近如果改过 `.as` 文件编码，确认文件仍为 **UTF-8 with BOM**

### 长耗时测试被 `compile_test.ps1` 提前超时

- 默认脚本只等 30 秒，超时不代表 Flash 停止工作
- 性能基准或大套件请改用更长轮询
- 推荐把 `TestLoader.as` 默认保持为 quick suite，只在需要时临时切换到 full suite

### setup 脚本计划任务创建失败

- 必须**右键 → 以管理员身份运行**，普通权限下任务注册会失败
- 验证：`Get-ScheduledTask -TaskName 'CompileTriggerTask','FlashCS6Task'`

### JSFL 修改后不生效

- Commands 目录下的 JSFL 被 Flash **启动时缓存**，修改不会自动生效
- `compile_action.jsfl`（项目目录）是通过 `eval(FLfile.read())` 实时读取的，修改**立即生效**
- 如果确实需要修改 Commands 目录下的 JSFL：新建文件，不要修改已有文件

## IDE 窗口截图

### 用途

Agent 需要查看 Flash CS6 当前状态时（UI 排版检查、编译器错误面板、运行时画面），可截取整个 Flash 窗口。

### 使用方式

```powershell
powershell -ExecutionPolicy Bypass -File scripts/capture_screenshot.ps1
```

截图保存到 `scripts/screenshot.png`，Agent 通过 Read 工具直接读取图片进行多模态分析。

### 典型工作流

```
修改 UI 代码 → compile_test.ps1 编译运行
  → capture_screenshot.ps1 截取 Flash 窗口
    → Agent 读取 screenshot.png（多模态）
      → 评估布局/间距/对齐/字体 → 给出修改建议 → 循环
```

### 技术细节

- 使用 Win32 `SetForegroundWindow` + `CopyFromScreen`，先将 Flash 窗口前置再截取
- Flash CS6 不响应 `PrintWindow` 消息（老程序），因此不能用后台截取方案
- 截图时会短暂切换前台焦点到 Flash 窗口（约 500ms）
- 需要 Flash CS6 正在运行（`Get-Process -Name Flash`）

### 局限

- 截图为整个 Flash CS6 IDE 窗口（含菜单栏、时间轴、面板等），不是纯 SWF 画面
- testMovie 的预览子窗口在 IDE 内浮动显示，能在截图中看到
- 窗口被最小化时会自动 Restore，但如果 Flash 被另一个全屏窗口完全覆盖可能截到切换瞬间

## 已解决

- [x] Agent 全自动编译 → 计划任务 + JSFL eval
- [x] JSFL 缓存 → eval 动态加载
- [x] UAC 弹窗 → 计划任务
- [x] 硬编码路径 → flash_project_path.cfg + setup 自动检测
- [x] 跨设备同步 → setup_compile_env.bat 一键配置
- [x] IDE 窗口截图 → SetForegroundWindow + CopyFromScreen

## 待解决

- [ ] 编译错误捕获和返回（Flash 编译器错误目前不能稳定回传到自动化脚本）
- [ ] testMovie 预览窗口自动关闭
