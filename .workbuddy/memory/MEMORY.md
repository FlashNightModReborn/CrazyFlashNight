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
