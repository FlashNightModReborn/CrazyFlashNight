# Flash CS6 自动化编译指南

**文档角色**：Flash CS6 编译 smoke canonical doc。  
**最后核对代码基线**：commit `b4d1267d51e5bdf4957fe56d21f6ee2c0a5049de` + 当前工作树的编译 mutex、fresh Compiler Errors、Node 前置与 TestLoader 近墙门收口。

本文件只讲 **Flash CS6 编译与 smoke 验证链**：计划任务、JSFL、trace、编译器错误、截图与故障排查。  
游戏启动与运行自动化请看 [automation/README.md](../automation/README.md)。
`compile_test.ps1` 只保存本次新增 Flash trace 到 `scripts/flashlog.txt`，并将 `[TEST_FAIL]` / `[FAIL]` / `Tests Failed: N>0`、缺失/陈旧/非 `0/0` 的 Compiler Errors 视为失败。

## 1. 当前定位

- Agent 可从终端触发 Flash CS6 `testMovie()` 或 `publish()`，并读取对应的 trace / 编译器输出
- 这条链路当前仍属于 **smoke 级验证**
- 没有目标所需的新鲜证据组合（至少本轮 `compiler_errors.txt` `0/0`；publish 另需 SWF 刷新，测试另需行为证据）时，不要直接声称“已编译通过”

## 2. 前提条件

- 已以管理员身份运行过 `scripts/setup_compile_env.bat`
- Flash CS6 正在运行
- `scripts/TestLoader` XFL 已打开
- 已安装 Node.js；TestLoader 的 `function codeSize < 60000` 是硬门，缺少 `node` 或 `tools/swf-function-sizes.js` 时会在触发 Flash 前失败。非 TestLoader 目标缺少 Node 时，预编译 BOM 门仍只告警降级
- 如果近期更新过编译自动化脚本或换过机器，先重新运行一次 setup

## 3. 使用方式

### 目标选择速查

先判断改动属于哪一层，再选 `-Target`；默认频率 / 优先级是 **asLoader → TestLoader → main**，不要把“改了 `.as`”直接等价为 `main`。

| 层级 | 职责 | 典型改动 | 推荐目标 |
|------|------|----------|----------|
| asLoader 逻辑注入层 | 运行时 AS2 class / boot include / `_root` 方法与 WebView bridge 注入 | 多数 `scripts/类定义/`、`scripts/逻辑/`、`scripts/逻辑系统分区/*_WebView.as`、`*PanelService.as` | `-Target publish`（别名已隐含 publish-only） |
| TestLoader 测试层 | 测试入口、mock、专项断言、trace 验证 | `scripts/TestLoader.as`、测试 class、测试 fixture | `-Target test` |
| 主文件运行壳 | 运行入口、主 FLA 时间轴、主文件库元件、主文件 linkage | `CRAZYFLASHER7MercenaryEmpire/LIBRARY/*`、主 XFL/FLA、主时间轴帧脚本、主文件 linkage 变更 | `-Target main` |
| 独立资源 XFL / 子 SWF | UI、关卡、素材库等由主文件加载或引用的独立 SWF | `flashswf/UI/*/LIBRARY/*.xml`、`flashswf/levels/*/LIBRARY/*.xml`、`flashswf/arts/*/LIBRARY/*.xml` | `-Target <xfl> -PublishOnly -VerifySwf <对应.swf>` |

`main` 是主运行壳 publish-only 验证，只证明 `CRAZYFLASHER7MercenaryEmpire.xfl` 及其直接库资源已发布；它不是所有 `flashswf/` 资产的兜底目标。普通 asLoader 注入逻辑跑 `main` 不会证明 `scripts/asLoader.swf` 已更新；独立 UI / 关卡 / 素材库 XFL 跑 `main` 也不会证明对应子 SWF 已更新。若同轮跨层改动，按实际层级分别跑对应目标。

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
# 测试构建（带 trace）：跑本机被 gitignore 的 TestLoader scratch 入口；仓库不保证固定 suite，专项施工须显式装入并记录 aggregate/template、suite 名与断言数
powershell -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -Target test -TimeoutSeconds 180

# 发布构建：编 asLoader（别名自动走 doc.publish()，并启用 -VerifySwf scripts/asLoader.swf；无需再写 -PublishOnly）
powershell -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -Target publish -TimeoutSeconds 180

# 主文件构建：只用于主 FLA / 资产 / linkage / 主时间轴相关改动
# publish-only（doc.publish() 不 testMovie），不会拉起整套游戏；产出仓库根 CRAZYFLASHER7MercenaryEmpire.swf
# 自动启用 -VerifySwf；成功判据 = Compiler Errors 0 个错误 + 主 SWF 已刷新
powershell -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -Target main -TimeoutSeconds 300

# 任意 FLA/XFL（相对仓库根或绝对路径）
powershell -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -Target scripts/asLoader/asLoader.xfl

# 独立资源 XFL / 子 SWF：先看同目录 PublishSettings.xml 的输出名，再给 -VerifySwf
powershell -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -Target 'flashswf/UI/玩家信息界面/玩家信息界面.xfl' -PublishOnly -VerifySwf 'flashswf/UI/玩家信息界面.swf'
```

`test`|`testloader` → `scripts/TestLoader`（`doc.testMovie()`）；`publish`|`asloader` → `scripts/asLoader`（隐式 **publish-only** + 自动 `-VerifySwf scripts/asLoader.swf`）；`main`|`mainfile`|`empire` → `CRAZYFLASHER7MercenaryEmpire/CRAZYFLASHER7MercenaryEmpire.xfl`（隐式 **publish-only** + 自动 `-VerifySwf CRAZYFLASHER7MercenaryEmpire.swf`）。因此 `publish/asloader/main` 别名都可省略 `-PublishOnly`；只有任意显式 FLA/XFL 路径需要禁止 testMovie 时才额外传该开关。多个目标可同时开在 CS6，`-Target` 决定编哪个，无需手动切到前台。

显式目标若已经在 CS6 打开，`compile_action.jsfl` 会先以“不保存”关闭，写入一次性 `compile_reopen.marker`；`compile_test.ps1` 校验 exact 目标与模式后最多重触发一次，再从磁盘打开并编译，确保外部编辑的 XFL XML 是 source of truth。关闭与重开必须分属两次 JSFL 调用：Flash CS6 在同一调用栈内关闭并立即重开 XFL 时可能直接中止宿主脚本。比较 cfg URI 与 `doc.pathURI` 时只做纯字符串 URI 解码、斜杠和大小写归一化；不要对所有已打开文档调用 `FLfile` 平台路径转换，未保存或含非 ASCII 路径的其他 XFL 可能让 CS6 绕过 JavaScript `try/catch` 整体中止。中文路径在两处可能分别表现为直写 Unicode 与 percent-encoded URI；不归一会漏关带 `*` 的旧文档，使 `doc.publish()` 复用旧 symbol 缓存。部分独立 XFL 在重开时会弹缺失字体确认框，计划任务会一直等不到 terminal marker；编译时间异常拉长时先截图/检查 CS6 前台并人工确认，不要重复触发多个编译任务。`-VerifySwf` 只能证明文件被重写，关键 XML 帧脚本还应以 FFDec 导出 script 检查新增标志串是否进入 SWF。

> ⚠️ **编译单元归属铁律（踩过坑）**：`scripts/类定义/` 下的 **类**（如 `*PanelService`）与 `scripts/逻辑系统分区/*_WebView.as`、`scripts/展现/UI交互/*.as` 这些 **boot `#include` 脚本** 都编进 **asLoader**——asLoader 编译 class + 把方法注入 `_root`（`_root.gameCommands.*` 等）全局提供给主文件和其他 SWF 使用。**改这些必须 `-Target publish`（asLoader），`-Target main` 不会生效！** `-Target main` 只编主文件 FLA 自身的元件 / 时间轴帧脚本（如 `Symbol 1770`、主文件库元件增删）。判断方法：被改的东西在 `asLoaderManifest`(`grep 文件名 scripts/asLoaderManifest/`) 里 → 用 `publish`；路径属于 `CRAZYFLASHER7MercenaryEmpire/` → 用 `main`；路径属于 `flashswf/UI/*`、`flashswf/levels/*`、`flashswf/arts/*` 这类独立 XFL → 找同目录 `.xfl` 和 `PublishSettings.xml` 输出 SWF，用显式 `-Target <xfl> -PublishOnly -VerifySwf <swf>`；两边都动了 → 分别编。验证可 `ffdec -export script` 后 grep 改动标志串确认进了哪个 SWF。

独立资源 XFL 的输出位置通常不在该 XFL 子目录的 `bin/` 下；`bin/` 多为 XFL cache。以 `flashswf/UI/玩家信息界面` 为例，源入口是 `flashswf/UI/玩家信息界面/玩家信息界面.xfl`，发布产物由 `PublishSettings.xml` 指向 `flashswf/UI/玩家信息界面.swf`。改 `LIBRARY/*.xml` 后，主文件 `-Target main` 刷新不代表这个 SWF 已刷新。

**test 与 publish-only 的差别**：`test/testloader` 走 `doc.testMovie()`；`publish/asloader` 与 `main/mainfile/empire` 别名都隐式走 `doc.publish()`，任意显式路径则只有加 `-PublishOnly` 才切到该模式。此前 `publish/asloader` 别名只自动设置 `VerifySwf`、却误走 testMovie，现已修复为在解析别名时同时写入 publish mode。publish 只编译产出 SWF + 填充 Compiler Errors，不启动测试播放器；主文件 testMovie 会启动整套游戏并可能因 launcher socket / 反盗版层留下僵尸窗口。模式由 `compile_test.ps1` 写 `scripts/compile_mode.cfg`（`publish`/缺省 `test`），`compile_action.jsfl` 读取后选 `publish()` vs `testMovie()`，一次性指令读到即删。publish-only 不产新鲜行为 trace，`flashlog.txt 未刷新` 属正常；判据是本轮 `compiler_errors.txt` 与 `-VerifySwf` 刷新门。预编译 BOM 门已扩展覆盖主文件 classpath 高频迁移类子树 `arki\task`/`arki\merc`/`arki\stageSelect`。

### Bash

```bash
bash scripts/compile_test.sh
```

`compile_test.sh` 会把参数原样透传给 PowerShell 脚本：

```bash
bash scripts/compile_test.sh -TimeoutSeconds 120
```

`TimeoutSeconds` 允许 `1..3600`，只调整等待 marker 的轮询上限，不改变编译内容或成功判据。

`compile_test.ps1` 在 `Start-ScheduledTask` 前先写本轮 exact-owned in-flight `scripts/compile_state_uncertain.marker`；`[TIMEOUT]`、触发后的 host 崩溃或其它非 terminal 退出都会保留它，后续编译在仓库 mutex 内 fail-closed。terminal 路径只删除内容仍与本轮 in-flight body 完全相同的文件，避免旧 lease child 擦掉另一故障刚写入的新闸。非 terminal 路径保留 `compile_target.cfg` / `compile_mode.cfg` 给迟到 JSFL 按原目标消费，不能提前删 target 后让它回退并误编当前活动文档。focused / map / Gobang / protocol scratch writer 另在改写 `TestLoader.as` 前创建 `scripts/.testloader-scratch-recovery/<token>.as`、验证原件 SHA-256，并写 `scripts/testloader_scratch_inflight.marker`；普通编译见该 marker 一律拒绝，只有 installed/original SHA-256 均验证后才删除 marker 与 sidecar。先确认 Flash / `CompileTriggerTask` / 旧 test player 已静止并核对迟到的 marker、SWF 与 diagnostics；若 scratch marker 仍在，按其中 `backup_path/original_sha256/had_runner` 恢复 `scripts/TestLoader.as`，不能只删闸或把遗留 scratch 当原件。完成这些人工复核后再删除 compile uncertain marker；下轮在触发前会清理未被迟到 JSFL 消费的旧 cfg。lease 不是鉴权，marker 是人工复核与恢复材料，不会自动猜测覆盖。

二阶段重开请求是事务内握手，不是 terminal 成功证据。marker 正文固定为两行 exact `targetURI` + `test|publish`；PowerShell 只接受与本轮目标/模式一致的一次请求，漂移、畸形或第二次请求立即失败并清理本轮 cfg。首次 JSFL 返回后才允许重新触发计划任务，防止同一宿主调用栈内 close/open；成功、已知失败等 terminal 路径都会清理该 marker，timeout/nonterminal 则继续由 uncertain marker 阻断后续编译。协议静态回归入口为 `node tools/test-flash-compile-jsfl.js`。

仓库内唯一受支持的人工编译入口是 `compile_test.ps1` / `compile_test.sh`；`cf7_compile_loader.jsfl` 与 `compile_action.jsfl` 只是该事务内部组件，不应单独打开或执行。旧诊断入口 `test_publish.jsfl`、`test_trace.jsfl` 以及绕过事务的 `train_cycle.sh` 已删除；Gobang 长耗时回归改走持同一仓库 mutex 的 `gobang_trainer_cycle.ps1`。

## 4. 当前链路

```
compile_test.ps1 / compile_test.sh
  → 取得仓库级 CF7_FlashCompile mutex（scratch 父 runner持同一把锁，并以持久事务 marker + exact-match lease 允许子进程复用）
  → 显式 TestLoader 目标先检查 node + swf-function-sizes.js；缺失则不触发 Flash
  → Start-ScheduledTask 'CompileTriggerTask'
    → cf7_compile_loader.jsfl
      → compile_action.jsfl
        → 目标已打开时关闭并写 compile_reopen.marker 后返回
  → 若收到重开请求：校验 exact target/mode，最多重触发一次 CompileTriggerTask
    → compile_action.jsfl（目标原本未打开，或二阶段重触发）从磁盘打开目标
        → 清空独立 Compiler Errors 面板并删除旧导出
        → 按 compile_mode.cfg 选择 doc.testMovie() 或 doc.publish()
        → fl.compilerErrors.save()（只保存本轮诊断）
        → 仅当唯一汇总可解析、warnings=0、且汇总前逐行含「32K」的诊断数恰等于 errors 时重试一次
          → 首轮诊断先 trace 到 Output Panel；混合/多行上下文/汇总后文本/不可解析格式均不重试
          → publish_done.marker / flashlog / compiler_errors
  → marker 后要求 compiler_errors 本轮刷新且严格 0/0
  → TestLoader 另要求 SWF 刷新与 codeSize < 60000
```

## 5. 关键产物与判据

| 文件 | 用途 | 判读方式 |
|------|------|----------|
| `scripts/flashlog.txt` | Flash trace 副本 | 优先看是否为本次运行新鲜生成 |
| `scripts/compile_output.txt` | Output Panel 副本 | 辅助看 JSFL / 输出面板文本；若触发纯 32K 重试，首轮完整诊断保存在这里 |
| `scripts/compiler_errors.txt` | 最终 Compiler Errors 面板副本 | JSFL 会在每个目标编译前清独立面板并删除旧导出；PowerShell 要求文件存在、身份/mtime 属于本轮且内容严格 `0/0`；若发生纯 32K 重试，本文件属于第二轮 |
| `scripts/compile_reopen.marker` | JSFL → PowerShell 二阶段重开请求 | 仅为一次性内部握手；exact target/mode 且每轮最多一次，不能视为完成或成功 |
| `scripts/publish_done.marker` | JSFL 触发完成标记 | 不能单独代表编译并运行成功 |

2026-07-21 17:12:59 +08 的最终资源箱回归使用 `-Target publish`（未额外传 `-PublishOnly`）实际走 `doc.publish()`：生成 `scripts/asLoader.swf` **1,041,903 bytes**，SHA-256 `AD799970A8A2AFD0F9A402C704934F08985A3144FA608A7564E17BC4899C815E`，Git blob `3dd59f73f9fc71128da99c2eb03796290df1e010`；本轮 Compiler Errors 为 **0/0**。该 publish-only 证据只证明目标 SWF 刷新与编译器零错误，AS2 行为结论由随后独立 fresh TestLoader 的 **166/166** trace 支撑。

### 正确表述

- `已完成 Flash CS6 自动化 smoke 验证`
- `已触发 Flash CS6 编译并拿到新鲜 trace`

接近 AS2 单分支 32K 上限的旧类在切换 XFL 后可能出现首次 ASO 编译失败、同目标再次编译通过。JSFL 只接受保守的一行一诊断格式：唯一最终汇总可解析、errors>0、warnings=0，且汇总前恰有同数量的非空诊断行、每行自身含 `32K`。只要混有语法/链接错误、多行上下文、汇总后文本或无法解析，就不重试。重试前的完整诊断会 trace 到 `compile_output.txt`，第二轮诊断才写入最终 `compiler_errors.txt`；第二轮仍失败则照常失败。focused runner 只接受唯一闭合 runId block，且健康基线必须 `32K retry=0`；自动恢复只能作为诊断证据，不能冒充健康通过。

### 不正确表述

- 只看到 `publish_done.marker` 就说 `已编译通过`
- 缺少该目标要求的新鲜证据组合还说 `编译成功`（例如 publish-only 缺本轮 Compiler Errors `0/0` 或目标 SWF 刷新；testMovie 缺其要求的 trace / Output 证据）

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

### `CompileTriggerTask` 返回 Access Denied

- Windows 沙箱可能允许读写仓库，却拒绝读取 Task Scheduler；这不等于计划任务不存在，也不代表 CS6 编译链损坏
- `compile_test.ps1` 会把该情况明确报告为“无权读取”，应先批准同一条编译命令在沙箱外运行
- 只有沙箱外运行仍明确报告任务缺失时，才以管理员身份重跑 `scripts/setup_compile_env.bat`

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
