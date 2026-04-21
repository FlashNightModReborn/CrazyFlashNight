# Flash CS6 自动化编译指南

**文档角色**：Flash CS6 编译 smoke canonical doc。  
**最后核对代码基线**：commit `c2118e295`（2026-04-20）。

本文件只讲 **Flash CS6 编译与 smoke 验证链**：计划任务、JSFL、trace、编译器错误、截图与故障排查。  
游戏启动与运行自动化请看 [automation/README.md](../automation/README.md)。

## 1. 当前定位

- Agent 可从终端触发 Flash CS6 `testMovie()` 并读取 trace / 编译器输出
- 这条链路当前仍属于 **smoke 级验证**
- 没有新鲜 trace、`compiler_errors.txt`、Output Panel 副本或 IDE 复核时，不要直接声称“已编译通过”

## 2. 前提条件

- 已以管理员身份运行过 `scripts/setup_compile_env.bat`
- Flash CS6 正在运行
- `scripts/TestLoader` XFL 已打开
- 如果近期更新过编译自动化脚本或换过机器，先重新运行一次 setup

## 3. 使用方式

### PowerShell

```powershell
chcp.com 65001 | Out-Null
powershell -ExecutionPolicy Bypass -File scripts/compile_test.ps1
```

### Bash

```bash
bash scripts/compile_test.sh
```

## 4. 当前链路

```
compile_test.ps1 / compile_test.sh
  → Start-ScheduledTask 'CompileTriggerTask'
    → cf7_compile_loader.jsfl
      → compile_action.jsfl
        → doc.testMovie()
        → fl.compilerErrors.save()
          → publish_done.marker / flashlog / compiler_errors
```

## 5. 关键产物与判据

| 文件 | 用途 | 判读方式 |
|------|------|----------|
| `scripts/flashlog.txt` | Flash trace 副本 | 优先看是否为本次运行新鲜生成 |
| `scripts/compile_output.txt` | Output Panel 副本 | 辅助看 JSFL / 输出面板文本 |
| `scripts/compiler_errors.txt` | Compiler Errors 面板副本 | 有错误时应直接视为失败 |
| `scripts/publish_done.marker` | JSFL 触发完成标记 | 不能单独代表编译并运行成功 |

### 正确表述

- `已完成 Flash CS6 自动化 smoke 验证`
- `已触发 Flash CS6 编译并拿到新鲜 trace`

### 不正确表述

- 只看到 `publish_done.marker` 就说 `已编译通过`
- 没有新鲜 trace 或 IDE 复核还说 `编译成功`

## 6. 当前边界

- AS2 帧脚本中的类型错误、未声明变量不会稳定体现在编译期错误里
- 只有语法错误和 class 文件中的静态类型错误更容易被自动捕获
- 长耗时套件可能超过默认轮询上限
- 遇到“marker 成功但没有 trace”，优先怀疑：
  - 旧环境残留
  - TestLoader 未正确打开
  - Flash IDE 编译器错误

## 7. 截图与界面检查

需要查看 Flash CS6 当前状态时，可使用：

```powershell
chcp.com 65001 | Out-Null
powershell -ExecutionPolicy Bypass -File scripts/capture_screenshot.ps1
```

适用场景：

- UI 排版检查
- Output / Compiler Errors 面板复核
- 运行时画面与窗口状态确认

## 8. 故障排查

### 30 秒内无 marker

- Flash CS6 未运行
- TestLoader 未打开
- `CompileTriggerTask` 不存在或失效
- Loader / `flash_project_path.cfg` 未部署

### marker 已生成但 `flashlog.txt` 为空

- 先看 Flash IDE 的 **输出 / 编译器错误** 面板
- 再看 `scripts/compiler_errors.txt`
- 再核对 `scripts/compile_output.txt` 和真实 `flashlog.txt` 时间戳

### 仍然弹 UAC

- 旧计划任务残留概率最高
- 重新运行 `scripts/setup_compile_env.bat`

## 9. 相关文档

- 启动与运行自动化：[`automation/README.md`](../automation/README.md)
- 测试矩阵：[`agentsDoc/testing-guide.md`](../agentsDoc/testing-guide.md)
- 顶层硬约束：[`AGENTS.md`](../AGENTS.md)
