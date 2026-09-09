# 项目长期记忆

## 怎么编译（Flash CS6 自动化）

**本质**：脚本通过计划任务拉起 `Flash.exe` 跑 JSFL 自动执行 `doc.publish()` / `testMovie()`。省的是手动点击，**Flash CS6 仍在链路上**，没有脱离 CS6 的独立编译器。

### 命令

```powershell
chcp.com 65001 | Out-Null
powershell -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -Target publish -TimeoutSeconds 180
```

Git Bash 等价：`bash scripts/compile_test.sh -Target publish -TimeoutSeconds 180`

### 目标选择（改了哪层就编哪个）

| 改动位置                                                                        | 命令                |
| ------------------------------------------------------------------------------- | ------------------- |
| `scripts/类定义/`、\*`_WebView.as`、\*`PanelService.as`（注入 `_root`） | `-Target publish` |
| `scripts/TestLoader.as`、测试 class / fixture（要跑 trace 断言）              | `-Target test`    |
| `CRAZYFLASHER7MercenaryEmpire/`、`LIBRARY/*`、主时间轴、主文件 linkage      | `-Target main`    |
| `flashswf/UI                                                                    | levels              |

- `publish` / `main` 别名已隐含 publish-only 与自动 `-VerifySwf`，无需再写 `-PublishOnly`
- `-Target main` **不会**更新 `scripts/asLoader.swf`；改注入层逻辑必须用 `publish`
- 不用手动预先打开 XFL：`-Target` 会自己 close+reopen 从磁盘重读
- `scripts/类定义/` 下的类走 classpath 自动编译，不在 `asLoaderManifest` 里，新增类 import 即可，不需注册清单

### 成功判据（两条同时成立才算过）

1. `scripts/compiler_errors.txt` 属于本轮、内容严格 `0 个错误 / 0 个警告`
2. 目标 SWF 已刷新（asLoader 即 `scripts/asLoader.swf`）

`publish_done.marker` 单独出现不算通过。publish-only 不产行为 trace，`flashlog.txt` 不刷新属正常。

### 前提条件

- 以管理员身份跑过 `scripts/setup_compile_env.bat`（注册 `CompileTriggerTask` / `FlashCS6Task`，必须 `RunLevel=Highest`）
- Flash CS6 可启动；换机器或改过编译脚本后重跑一次 setup
- Node.js 在 PATH（TestLoader 目标是硬门，缺 `node` 直接不触发 Flash）
- 唯一受支持入口是 `compile_test.ps1` / `compile_test.sh`；不要单独执行 `compile_action.jsfl`

### 注意

- 被 `#include` 的 `.as` 丢 UTF-8 BOM 时 CS6 静默跳过内容：Compiler 报 0/0、marker 正常，但帧脚本 0 字节，smoke 抓不到。新增/重建 `.as` 必须保留 BOM
- `[TIMEOUT]` 会留 `scripts/compile_state_uncertain.marker` 卡住后续编译；需人工确认 Flash / 计划任务已静止、`TestLoader.as` 已恢复后再删
- 现在编译环境没好，除非用户要求，否则不必编译

## 用户约定

- **不要擅自改 `flashswf/` 下的 XFL/XML**。需要改 NPC 帧脚本这类资产时，先在 `scripts/`（AS2 注入层）找能绕开的办法，改资产前先问过用户
- **不要往 `_root` 一级塞新属性**（_root 已经太臃肿）。新状态统一放二级容器，如作弊开关全部收在 `_root.cheatFlags.*` 下
- **作弊码不进存档**，只在本次游戏内有效

### 现有作弊开关（_root.cheatFlags）

- `强制显示NPC`：true 时 `_root.初始化NPC` 不再用 `任务需求` / `任务需求支线` 挡人
- 命令：`shownpc`（toggle，切换场景生效）。各 NPC 帧脚本里的"任务完成后消失"上界判定不归它管，需单独在 XFL 里改

### Web 设置面板"作弊码帮助"的三处位置

1. **数据生成（AS2，唯一数据源）**：`scripts/类定义/org/flashNight/arki/ui/GameSettingsPanelService.as` → `buildCheatHelp()`（约 747 行），硬编码 `{command, description, effectScope}` 数组。挑战模式下只返回 3 条模式切换命令
2. **校验转发（C#）**：`launcher/src/Tasks/SettingsTask.cs` 的 `IsValidCheatHelp()`，只校验不生产
3. **渲染（Web）**：`launcher/web/modules/settings-runtime.js`（接收 `cheatHelp`）+ `launcher/web/modules/settings-panel.js` 的 `cheatCommandForm()` / `openCheatHelp()` / `renderCheatHelpDocument()`

`classifyCheat()`（同文件约 766 行）决定每条命令的 effectScope（read / session / save）。不在 read/save 白名单里的 `cheatFunction` 命令默认落 `session`，即"本次运行有效"

### 作弊码执行链路（**执行仍在 AS2，没迁到 Web**）

Web 输入框 → C# `SettingsTask` → AS2 `GameSettingsPanelService`，三段职责：

1. **Web**（`settings-panel.js`）：只管输入、二次确认 UI、帮助弹窗渲染，不做命令校验
2. **C#**（`SettingsTask.NormalizeCheat`）：校验 payload 形状（v/command/confirmed）、command ≤240 字符、无控制字符，转成 action `settingsCheat` 转发给 Flash
3. **AS2**（`GameSettingsPanelService`）：“settingsCheat” 入口（约 40 行）→ `executeCheat()`（约 283 行）→ `classifyCheat()` 定 effectScope（返回 null 就报 `unknown_command`，web 显示"无法识别该作弊码"）→ `_root.cheatCode(command)` → `_root.cheatFunction[命令]()`

**排查要点**：新增作弊码后 web 上提示"无法识别该作弊码"，几乎都是 `scripts/asLoader.swf` 没重新 publish，`_root.cheatFunction` 里还没有这个命令。可用已有命令（如 `status`）对照验证

### 编辑 XFL 的坑

Flash CS6 若正开着同项目，外部改 XFL 会触发它自动保存，顺带重写 `META-INF/metadata.xml`、`bin/SymDepend.cache` 和部分元件 xml（Edge 路径重排，几何等价但 diff 巨大）。看到非预期 diff 先查 `xmp:CreatorTool` / `MetadataDate` 判断是不是 CS6 写的，别误判成自己的改动

### 深度管理器与 swapDepths 接管的坑（2026-09-09）

- Twip Trick 后单位都在 0~1048575 高深度带；authored 元件 native `swapDepths(this._y)` 只落几百的低带 → 永远被玩家压住。凡遇"地图元件/NPC 不再和玩家交换层级"，先查它有没有被 DepthManager 接管
- authored 子级的 onClipEvent(load)（含 初始化NPC）在 attachMovie 时同步执行，**早于** initGameWorld 创建本场景 DepthManager（此时 instance=null，AVM1 静默空操作）→ 初始化NPC 里的注册/劫持在场景加载时序下不可靠。兜底：SceneManager.initGameWorld → hijackAuthoredChildren（续38）
- 素材库出生点的 `swapDepths(-this._y)` = "永远在最底"；劫持后被钳到 yMin 桶，语义保持
