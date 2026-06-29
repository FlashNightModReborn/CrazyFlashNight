# Flash CS6 自动化编译指南

**文档角色**：Flash CS6 编译 smoke canonical doc。  
**最后核对代码基线**：commit `6ed0404f9a`（2026-06-17）。

本文件只讲 **Flash CS6 编译与 smoke 验证链**：计划任务、JSFL、trace、编译器错误、截图与故障排查。  
游戏启动与运行自动化请看 [automation/README.md](../automation/README.md)。
`compile_test.ps1` 只保存本次新增 Flash trace 到 `scripts/flashlog.txt`，并将 `[TEST_FAIL]` / `[FAIL]` / `Tests Failed: N>0` 视为失败。

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

### 目标选择速查

先判断改动属于哪一层，再选 `-Target`；默认频率 / 优先级是 **asLoader → TestLoader → main**，不要把“改了 `.as`”直接等价为 `main`。

| 层级 | 职责 | 典型改动 | 推荐目标 |
|------|------|----------|----------|
| asLoader 逻辑注入层 | 运行时 AS2 class / boot include / `_root` 方法与 WebView bridge 注入 | 多数 `scripts/类定义/`、`scripts/逻辑/`、`scripts/逻辑系统分区/*_WebView.as`、`*PanelService.as` | `-Target publish` |
| TestLoader 测试层 | 测试入口、mock、专项断言、trace 验证 | `scripts/TestLoader.as`、测试 class、测试 fixture | `-Target test` |
| 主文件运行壳 / 资产挂载层 | 运行入口、主 FLA 时间轴、库元件、linkage、资产挂载 | `CRAZYFLASHER7MercenaryEmpire/LIBRARY/*`、主 XFL/FLA、主时间轴帧脚本、linkage 变更；少用，多集中于 UI 迁移业务 | `-Target main` |

`main` 是最重的主文件 publish-only 验证，只应在触及主 FLA / 资产 / linkage / 主时间轴时使用；普通 asLoader 注入逻辑跑 `main` 不会证明 `scripts/asLoader.swf` 已更新。若同轮跨层改动，按实际层级分别跑对应目标。

### PowerShell

```powershell
chcp.com 65001 | Out-Null
powershell -ExecutionPolicy Bypass -File scripts/compile_test.ps1
```

默认等待完成 marker 30 秒；慢 CPU / 低压设备可显式增大等待时间：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -TimeoutSeconds 120
```

### 选择编译目标（`-Target`，免手动切活动文档）

不传 `-Target` = 编译 **Flash 当前活动文档**（旧行为）。传 `-Target` 则由参数指定，脚本写 `scripts/compile_target.cfg`；`compile_action.jsfl` 读取后立即删除该文件，并据此 close+reopen 目标 FLA 从盘重读：

```powershell
# 测试构建（带 trace）：跑 TestLoader → TransitionsTest + BootSequencerTest + BootstrapHandshakeTest
powershell -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -Target test -TimeoutSeconds 180

# 发布构建：编 asLoader（自动启用 -VerifySwf scripts/asLoader.swf 刷新门）
powershell -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -Target publish -TimeoutSeconds 180

# 主文件构建：只用于主 FLA / 资产 / linkage / 主时间轴相关改动
# publish-only（doc.publish() 不 testMovie），不会拉起整套游戏；产出仓库根 CRAZYFLASHER7MercenaryEmpire.swf
# 自动启用 -VerifySwf；成功判据 = Compiler Errors 0 个错误 + 主 SWF 已刷新
powershell -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -Target main -TimeoutSeconds 300

# 任意 FLA/XFL（相对仓库根或绝对路径）
powershell -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -Target scripts/asLoader/asLoader.xfl
```

`test`|`testloader` → `scripts/TestLoader`；`publish`|`asloader` → `scripts/asLoader`（自动 `-VerifySwf`）；`main`|`mainfile`|`empire` → `CRAZYFLASHER7MercenaryEmpire/CRAZYFLASHER7MercenaryEmpire.xfl`（**publish-only** + 自动 `-VerifySwf CRAZYFLASHER7MercenaryEmpire.swf`）。多个目标可同时开在 CS6，`-Target` 决定编哪个，无需手动切到前台。

> ⚠️ **编译单元归属铁律（踩过坑）**：`scripts/类定义/` 下的 **类**（如 `*PanelService`）与 `scripts/逻辑系统分区/*_WebView.as`、`scripts/展现/UI交互/*.as` 这些 **boot `#include` 脚本** 都编进 **asLoader**——asLoader 编译 class + 把方法注入 `_root`（`_root.gameCommands.*` 等）全局提供给主文件和其他 SWF 使用。**改这些必须 `-Target publish`（asLoader），`-Target main` 不会生效！** `-Target main` 只编主文件 FLA 自身的元件 / 时间轴帧脚本（如 `Symbol 1770`、库元件增删）。判断方法：被改的东西在 `asLoaderManifest`(`grep 文件名 scripts/asLoaderManifest/`) 里 → 用 `publish`；是主 FLA 的 `DOMSymbolInstance`/库元件 → 用 `main`；两边都动了 → 两个都编。验证可 `ffdec -export script` 后 grep 改动标志串确认进了哪个 SWF。

**main 与 test/publish 的差别**：`main` 走 `doc.publish()` 而非 `doc.testMovie()`——主文件 testMovie 会启动整套游戏（连不上 launcher socket 卡住 / 撞反盗版层 / 留僵尸窗口），publish 只编译产出 SWF + 填充 Compiler Errors。模式由 `compile_test.ps1` 写 `scripts/compile_mode.cfg`（`publish`/缺省 `test`），`compile_action.jsfl` 读取后选 `publish()` vs `testMovie()`，一次性指令读到即删。`main` 不产 trace（发布设置 `OmitTraceActions=1`），`flashlog.txt 未刷新` 属正常，看 `compiler_errors.txt`。预编译 BOM 门已扩展覆盖主文件 classpath 高频迁移类子树 `arki\task`/`arki\merc`/`arki\stageSelect`。

### Bash

```bash
bash scripts/compile_test.sh
```

`compile_test.sh` 会把参数原样透传给 PowerShell 脚本：

```bash
bash scripts/compile_test.sh -TimeoutSeconds 120
```

`TimeoutSeconds` 允许 `1..3600`，只调整等待 marker 的轮询上限，不改变编译内容或成功判据。

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
- 长耗时套件可能超过默认 30 秒轮询上限；先确认 Flash / TestLoader / 计划任务状态，再按需用 `-TimeoutSeconds` 调大
- **被 FLA 帧脚本 `#include` 的 `.as` 文件失去 BOM 时，CS6 编译器静默跳过其内容**，生成 SWF 的对应帧 DoAction 为 0 字节，但 `compiler_errors.txt` 仍报 `0 个错误`、`publish_done.marker` 正常落盘、`compile_test.sh` 报 `[OK] 编译完成` —— smoke 链路无法捕获此类静默失败
- 遇到“marker 成功但没有 trace”，优先怀疑：
  - 旧环境残留
  - TestLoader 未正确打开
  - Flash IDE 编译器错误
  - `TestLoader.as` 或其它被 `#include` 的帧脚本 `.as` 丢失 BOM（见 §8 同名条目）

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

### 等待上限内无 marker

- Flash CS6 未运行
- TestLoader 未打开
- `CompileTriggerTask` 不存在或失效
- Loader / `flash_project_path.cfg` 未部署
- 慢 CPU / 低压设备尚未完成；排除前述环境问题后，用 `-TimeoutSeconds` 调大重试

### marker 已生成但 `flashlog.txt` 为空

- 先看 Flash IDE 的 **输出 / 编译器错误** 面板
- 再看 `scripts/compiler_errors.txt`
- 再核对 `scripts/compile_output.txt` 和真实 `flashlog.txt` 时间戳
- 若 `compiler_errors.txt` 报 `0 个错误`、SWF 体积异常小（kB 级而非数十 kB）、debug player 直跑也无 trace —— 大概率是被 `#include` 的帧脚本 `.as` **丢了 BOM**，编译器静默跳过 include 内容，生成空帧脚本。验证手段：

  ```bash
  "/c/Program Files (x86)/FFDec/ffdec.bat" -export script ./tmp_swf_dump scripts/TestLoader.swf
  ls -la tmp_swf_dump/scripts/frame_1/DoAction.as   # 0 字节 = 帧脚本未被编译进去
  head -c 3 scripts/TestLoader.as | od -An -tx1     # 应为 ef bb bf；若不是则补 BOM
  ```

  修复后用 IDE 的"另存为 UTF-8 with BOM"重写一次，或用 `printf '\xef\xbb\xbf'` 前置后再编译

### 仍然弹 UAC

- **`CompileTriggerTask` / `FlashCS6Task` 必须 `RunLevel=Highest`**（`setup_compile_env.ps1::Register-CompileTask` 的默认值）。Task Scheduler 服务在 SYSTEM 上下文预置 elevation 令牌，子进程 cmd 已经 elevated，再唤起 Flash 不跨 UAC 边界。改成 `RunLevel=Limited` 反而让 cmd 没 elevated，碰到 `Flash.exe` 的 AppCompat `RUNASADMIN` 标志被强制弹 UAC
- Flash CS6 在某些机器上必须保留 HKLM `SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers` 下 `Flash.exe = ~ RUNASADMIN ...` 才能启动（去掉直接运行失败），所以这条 AppCompat 不能简单清空
- 旧计划任务残留概率次高
- 重新运行 `scripts/setup_compile_env.bat`（`Register-ScheduledTask -Force` 会把 RunLevel 重置回 Highest，覆盖任何手工降级）

## 9. 相关文档

- 启动与运行自动化：[`automation/README.md`](../automation/README.md)
- 测试矩阵：[`agentsDoc/testing-guide.md`](../agentsDoc/testing-guide.md)
- 顶层硬约束：[`AGENTS.md`](../AGENTS.md)
