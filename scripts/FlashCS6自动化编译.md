# Flash CS6 自动化编译指南

## 概述

Agent（Claude Code）可从终端触发 Flash CS6 编译 AS2 代码并读取 trace 输出。

## 架构

```
Agent (bash) → compile_test.sh
  → Start-ScheduledTask 'CompileTriggerTask'  (绕过 UAC)
    → trigger_compile.ps1  (管理员权限打开 JSFL)
      → compile.jsfl  (Commands 目录，eval 动态加载器)
        → compile_action.jsfl  (项目目录，实际编译逻辑)
          → doc.publish()  (Flash CS6 编译)
            → publish_done.marker  (完成标记)
              ← compile_test.sh 检测到 marker，编译完成
```

## 快速开始

### 1. 环境配置（每台机器执行一次）

**a) 运行 setup 脚本**

以管理员身份运行 `scripts/setup_compile_env.bat`，自动完成：
- 创建 `%USERPROFILE%\mm.cfg`（Flash debug 日志配置）
- 检测 Flash CS6 语言目录
- 写入项目路径配置到 Commands 目录
- 部署 JSFL 到 Commands 目录
- 查找 Flash.exe 并创建计划任务
- 生成 `compile_env.sh`（shell 环境变量）

**b) 导入计划任务**

Win+R → `taskschd.msc`，导入以下两个任务：

| XML 文件 | 任务名 | 用途 |
|----------|--------|------|
| `scripts/FlashCS6Task.xml` | FlashCS6Task | 无 UAC 启动 Flash CS6 |
| `scripts/CompileTriggerTask.xml` | CompileTriggerTask | 无 UAC 触发编译 |

> **注意**：`CompileTriggerTask.xml` 中的 ps1 路径需与实际项目路径一致。

### 2. 使用流程

1. 启动 Flash CS6（手动或 `powershell -Command "Start-ScheduledTask 'FlashCS6Task'"`)
2. 在 Flash 中打开 `scripts/TestLoader`（XFL 工程）
3. Agent 执行 `bash scripts/compile_test.sh`

## 关键文件

### 项目目录（Git 跟踪）

| 文件 | 用途 |
|------|------|
| `scripts/compile_test.sh` | Agent 编译入口脚本 |
| `scripts/compile_action.jsfl` | 实际编译逻辑（可随时修改，不需重启 Flash） |
| `scripts/trigger_compile.ps1` | 管理员权限触发脚本 |
| `scripts/setup_compile_env.bat` | 一键环境配置 |
| `scripts/TestLoader/` | TestLoader XFL 工程 |
| `scripts/TestLoader.as` | 测试用 AS2 源码 |
| `scripts/FlashCS6Task.xml` | Flash 启动计划任务 |
| `scripts/CompileTriggerTask.xml` | 编译触发计划任务 |

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

### publish() vs testMovie()
- `publish()` 只编译 SWF，不运行 trace
- `testMovie()` 编译+运行，但弹出预览窗口

## 待解决

- [ ] testMovie 模式（运行 trace + 自动关闭预览窗口）
- [ ] 编译错误捕获和返回
- [x] ~~Agent 全自动编译~~ → 计划任务 + JSFL eval
- [x] ~~JSFL 缓存~~ → eval 动态加载
- [x] ~~UAC 弹窗~~ → 计划任务
- [x] ~~硬编码路径~~ → flash_project_path.cfg
