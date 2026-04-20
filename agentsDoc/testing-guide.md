# 测试约定与验证矩阵

**文档角色**：验证矩阵 canonical doc。  
**最后核对代码基线**：commit `9f8f0c225`（2026-04-20）。

按子栈选验证；不要用「编译一下」「跑一下 build」笼统覆盖跨栈任务。

## 0. 通用前缀

PowerShell 命令前先跑（避免 GBK 乱码）：

```powershell
chcp.com 65001 | Out-Null
```

下方所有 PowerShell 命令默认已执行该前缀,不再每条重复。

## 1. 任务 → 验证入口矩阵

| 任务类型 | 必跑 | 视改动追加 |
|----------|------|------------|
| AS2 class / 帧脚本 / Flash 资源联动 | `scripts/compile_test.ps1` 或 `bash scripts/compile_test.sh` | Flash IDE 复核、截图、专项 TestLoader 套件 |
| XML / 数据 / 游戏数值 | 受影响路径运行时 smoke | `compile_test`、游戏内人工验证 |
| Launcher C# / Host / Bus | `launcher/build.ps1` | `launcher/tests/run_tests.ps1`、`tools/cfn-cli`、`--bus-only` |
| Launcher Web / Minigame | `node launcher/tools/run-minigame-qa.js --game ...` | browser harness、`node launcher/tools/validate-minigame-final-state.js` |
| 文档与治理 | `node tools/validate-doc-governance.js` | 交叉 grep / 链接检查 / 基线复核 |

## 2. AS2 / Flash 验证

**入口**：`powershell -ExecutionPolicy Bypass -File scripts/compile_test.ps1` 或 `bash scripts/compile_test.sh`

**成功判据**（缺一不可视为成功）：

- 本次运行**新鲜生成**的 `scripts/flashlog.txt`
- 必要时核对 `scripts/compile_output.txt`
- `scripts/compiler_errors.txt` 为空或无新错误
- `publish_done.marker` **仅说明 JSFL 触发结束**,不能单独视为成功

**对外表述边界**：

- 可以说：`已完成 Flash CS6 自动化 smoke 验证` / `已触发编译并拿到新鲜 trace`
- **不要**在缺少新鲜 trace、编译器错误面板或 IDE 复核时说「已编译通过」

详见 [scripts/FlashCS6自动化编译.md](../scripts/FlashCS6自动化编译.md)。

## 3. Launcher Host 验证

| 用途 | 命令 |
|------|------|
| 构建 | `powershell -File launcher/build.ps1` |
| xUnit | `powershell -File launcher/tests/run_tests.ps1` |
| 总线健康 | `bash tools/cfn-cli.sh status` |
| AS2 回环 | `bash tools/cfn-cli.sh console "help"` |
| 集成 (testMovie) | `CRAZYFLASHER7MercenaryEmpire.exe --bus-only` |

`--bus-only` 适用：Flash CS6 testMovie ↔ Launcher 通信链验证;AI / 模拟实验需外部 Flash 自连总线;排查启动链路 vs 总线本身。

## 4. Launcher Web / Minigame 验证

| 用途 | 命令 |
|------|------|
| Node QA(单局) | `node launcher/tools/run-minigame-qa.js --game lockbox` |
| Node QA(单局) | `node launcher/tools/run-minigame-qa.js --game pinalign` |
| Node QA(全套) | `node launcher/tools/run-minigame-qa.js --game all` |
| 静态校验 | `node launcher/tools/validate-minigame-final-state.js` |

**Browser harness**(直接打开):

- `launcher/web/modules/minigames/lockbox/dev/harness.html`
- `launcher/web/modules/minigames/pinalign/dev/harness.html`

**默认顺序**：

- 纯逻辑 / 确定性问题先跑 Node QA
- 协议 / DOM / 布局 / 交互问题进 browser harness
- 目录 / 协议 / 旧入口回流问题再补静态校验

URL 参数:`?qa=1` 自动断言 / `?case=` 单条 / `?scenario=` 脚本场景 / `?dump=1` 结构化输出。

若改动后的行为无法被现有 harness 或 QA 覆盖，同轮补测试入口，不把“靠人工记得点开”当作默认收尾。

静态校验拦截:旧平铺 Lockbox 入口、旧 `lockbox_session` / `pinalign_session`、旧共享结构 class 名。

## 5. 自动化与文档治理

| 用途 | 入口 |
|------|------|
| 启动 / 运行链 | [automation/README.md](../automation/README.md) |
| Flash 编译 smoke 细节 | [scripts/FlashCS6自动化编译.md](../scripts/FlashCS6自动化编译.md) |
| 文档治理巡检 | `node tools/validate-doc-governance.js` |

巡检脚本检查:必读文件存在、AGENTS.md 关键链接存在、回流模式未重新进入入口、关键文档基线标记存在、关键版本未回退。脚本是巡检器,不是 source of truth。

## 6. 收尾话术参考

- 文档改动:`已更新文档并运行文档治理巡检`
- Minigame:`已跑 Node QA / 静态校验;browser harness 未人工点开`
- Launcher:`已跑 build / xUnit;未做完整运行态手点`
- Flash:`已完成 Flash smoke;未在缺少新鲜 trace 或 IDE 复核时声称编译通过`

完整失败模式与重入约束看 [agent-harness.md](agent-harness.md)。
