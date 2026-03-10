# Flash CS6 自动化编译指南

## 概述

Agent（Claude Code）可从终端触发 Flash CS6 编译 AS2 代码并读取 trace 输出。

## 快速开始

### 1. 环境配置（每台设备执行一次）

**a) mm.cfg 配置**

运行 `scripts/setup_flash_debug.bat`，或手动创建 `%USERPROFILE%\mm.cfg`：

```
ErrorReportingEnable=1
TraceOutputFileEnable=1
MaxWarnings=0
```

**b) JSFL 脚本部署**

将 JSFL 脚本复制到 Flash CS6 Commands 目录：

```
copy scripts\test_publish.jsfl "%LOCALAPPDATA%\Adobe\Flash CS6\<语言>\Configuration\Commands\test_simple.jsfl"
```

> 语言目录示例：`zh_CN`、`en_US`，按实际安装语言确定。

**c) UAC 绕过（创建计划任务）**

Flash CS6 需要管理员权限运行，会弹 UAC。通过计划任务可绕过：

1. Win+R 输入 `taskschd.msc` 打开任务计划程序
2. 右侧「导入任务」，选择项目根目录下 `FlashCS6Task.xml`（或手动创建）
3. 确认任务名为 `FlashCS6Task`，勾选「使用最高权限运行」，操作指向 Flash.exe

之后 Agent 可通过 `powershell -Command "Start-ScheduledTask -TaskName 'FlashCS6Task'"` 无 UAC 启动。

> **注意**：计划任务中路径含空格时，用 XML 导入方式创建，避免路径被截断。

### 2. 使用流程

1. 启动 Flash CS6，打开 `scripts/TestLoader`（XFL 工程）
2. Agent 修改 `scripts/TestLoader.as`
3. Agent 从终端触发编译并读取输出（见下方命令）

### 3. Agent 编译命令（bash）

```bash
# 清理旧状态
rm -f "C:/Users/<用户名>/flash_publish_done.txt" \
     "C:/Users/<用户名>/AppData/Roaming/Macromedia/Flash Player/Logs/flashlog.txt" 2>/dev/null

# 触发 JSFL
powershell -Command "Start-Process '<Commands目录>/test_simple.jsfl'"

# 等待完成并读取输出
for i in $(seq 1 30); do
  if [ -f "C:/Users/<用户名>/flash_publish_done.txt" ]; then
    cat "C:/Users/<用户名>/AppData/Roaming/Macromedia/Flash Player/Logs/flashlog.txt"
    rm -f "C:/Users/<用户名>/flash_publish_done.txt"
    break
  fi
  sleep 1
done
```

## 关键文件

| 文件 | 用途 | Git 跟踪 |
|------|------|----------|
| `scripts/TestLoader.as` | 测试用 AS2 源码 | 是 |
| `scripts/TestLoader/` | TestLoader XFL 工程 | 是 |
| `scripts/test_publish.jsfl` | JSFL 源文件（需复制到 Commands 目录） | 是 |
| `scripts/setup_flash_debug.bat` | mm.cfg 配置脚本 | 是 |
| `scripts/run_test.bat` | 一键测试脚本（手动使用） | 是 |
| `scripts/TestLoader.swf` | 编译产物 | 否 |
| `scripts/flashlog.txt` | trace 输出副本 | 否 |

## 踩坑记录

### 路径空格问题（最关键）
Flash CS6 和 Flash Player 对含空格路径的支持很差：
- `mm.cfg` 的 `TraceOutputFileName` 不支持含空格路径，8.3 短路径也不行 → 只用默认路径
- `fl.openDocument()` 对 URI 编码的空格路径（%20）不可靠
- JSFL 文件本身放在含空格路径下时，「运行命令」可能静默失败 → 放到 Commands 目录

### JSFL 执行方式
- `Flash.exe test.jsfl`（命令行参数）→ 失败，CS6 把 JSFL 当文档打开
- 正确方式：放到 Commands 目录（`%LOCALAPPDATA%\Adobe\Flash CS6\<语言>\Configuration\Commands\`），从菜单执行或通过文件关联 `Start-Process` 触发

### GUI 程序从终端启动
- bash 直接执行 .exe → Permission denied
- `cmd.exe /c start` → 不可靠
- 正确方式：`powershell -Command "Start-Process 'path'"`

### UAC 弹窗
- Flash CS6 需要管理员权限（注册表 `RUNASADMIN` 标记），每次启动弹 UAC
- 去掉 `RUNASADMIN` → Flash CS6 直接无法运行
- **正确方式**：创建 Windows 计划任务（`RunLevel=HighestAvailable`），通过 `Start-ScheduledTask` 触发
- 注意：计划任务的 Action 路径含空格时，通过 XML 导入创建，否则路径会被截断

### JSFL API 注意事项
- `fl.setDocumentActive()` → CS6 中不存在
- `fl.documents[i].activate()` → CS6 中不存在
- 没有打开任何文档时，JSFL 静默失败
- `FLfile` URI 格式：`file:///C|/path`（用 `C|` 而非 `C:`）

### publish() vs testMovie()
- `publish()` 只编译 SWF，不运行 → trace 不执行
- `testMovie()` 编译+运行 → trace 执行，但会弹出预览窗口需手动关闭

## JSFL 脚本参考（test_simple.jsfl）

```javascript
var markerFile = "file:///C|/Users/<用户名>/flash_publish_done.txt";

fl.outputPanel.clear();
fl.getDocumentDOM().testMovie();
fl.trace("--- test done ---");
FLfile.write(markerFile, "done");
```

## 待解决

- [ ] testMovie 弹出的 SWF 预览窗口需手动关闭（方案：publish + 独立 debug player，或 PowerShell 自动关窗口）
- [ ] openDocument 含空格路径不可靠，当前需手动打开 TestLoader
- [ ] 编译错误的捕获（AS2 语法错误是否写入 flashlog？需验证）
- [x] ~~Flash CS6 全自动启动~~ → 已通过计划任务解决
- [x] ~~UAC 弹窗~~ → 已通过计划任务解决
