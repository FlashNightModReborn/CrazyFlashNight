# 测试约定与验证矩阵

**文档角色**：验证矩阵 canonical doc。  
**最后核对代码基线**：commit `c2118e295`（2026-04-20）。

本项目的验证方式必须按子栈选择，不能再用“编译一下 Flash”或“跑一下 launcher/build.ps1”笼统覆盖全部任务。

## 1. 任务 → 验证入口矩阵

| 任务类型 | 必跑验证 | 视改动追加 |
|----------|----------|------------|
| AS2 class / 帧脚本 / Flash 资源联动 | `scripts/compile_test.ps1` 或 `scripts/compile_test.sh` | Flash IDE 复核、截图、专项 TestLoader 套件 |
| XML / 数据 / 游戏数值 | 受影响路径的运行时 smoke | `compile_test`、游戏内人工验证 |
| Launcher C# / Host / Bus | `launcher/build.ps1` | `launcher/tests/run_tests.ps1`、`tools/cfn-cli`、`--bus-only` |
| Launcher Web / Minigame | `node launcher/tools/run-minigame-qa.js --game ...` | 打开 browser harness、`node launcher/tools/validate-minigame-final-state.js` |
| 文档与治理 | `node tools/validate-doc-governance.js` | 交叉 grep / 链接检查 / 基线复核 |

## 2. AS2 / Flash 验证

### 入口

- PowerShell：`powershell -ExecutionPolicy Bypass -File scripts/compile_test.ps1`
- Bash：`bash scripts/compile_test.sh`

### 成功判据

- 有**本次运行新鲜生成**的 `scripts/flashlog.txt`
- 需要时核对 `scripts/compile_output.txt`
- 编译期错误看 `scripts/compiler_errors.txt`
- `publish_done.marker` 只能说明 JSFL 触发结束，**不能单独视为成功**

### 对外表述边界

- 可以说：`已完成 Flash CS6 自动化 smoke 验证`
- 可以说：`已触发 Flash CS6 编译并拿到新鲜 trace`
- 不要在缺少新鲜 trace / 编译器错误面板 / IDE 复核时直接写：`已编译通过`

## 3. Launcher Host 验证

### 构建

```powershell
chcp.com 65001 | Out-Null
powershell -File launcher/build.ps1
```

### xUnit

```powershell
chcp.com 65001 | Out-Null
powershell -File launcher/tests/run_tests.ps1
```

### CLI / 总线健康检查

```powershell
chcp.com 65001 | Out-Null
bash tools/cfn-cli.sh status
bash tools/cfn-cli.sh console "help"
```

### `--bus-only` 集成测试

```powershell
CRAZYFLASHER7MercenaryEmpire.exe --bus-only
```

适用场景：

- Flash CS6 testMovie 与 Launcher 通信链验证
- AI / 模拟实验需要外部 Flash 实例自行连总线
- 排查是否为启动链路问题，而非总线问题

## 4. Launcher Web / Minigame 验证

### Node QA

```powershell
chcp.com 65001 | Out-Null
node launcher/tools/run-minigame-qa.js --game lockbox
node launcher/tools/run-minigame-qa.js --game pinalign
node launcher/tools/run-minigame-qa.js --game all
```

适用场景：

- 纯逻辑 QA
- 确定性 / 导出结构 / solver 一致性
- 回归脚本

### Browser harness

直接打开：

- `launcher/web/modules/minigames/lockbox/dev/harness.html`
- `launcher/web/modules/minigames/pinalign/dev/harness.html`

标准能力：

- `?qa=1` 自动跑断言
- `?case=` 跑单条测试
- `?scenario=` 跑脚本化 UI 场景
- `?dump=1` 输出结构化结果 / 布局快照

### 静态校验

```powershell
chcp.com 65001 | Out-Null
node launcher/tools/validate-minigame-final-state.js
```

用于阻止：

- 旧平铺 Lockbox 入口回流
- 旧 `lockbox_session` / `pinalign_session` 回流
- 旧共享结构 class 名回流

## 5. 自动化与文档治理验证

### 自动化 / 启动链

- 运行文档：`automation/README.md`
- 编译 smoke 文档：`scripts/FlashCS6自动化编译.md`
- 两者职责分离：启动与运行 ≠ Flash 编译验证

### 文档治理巡检

```powershell
chcp.com 65001 | Out-Null
node tools/validate-doc-governance.js
```

当前脚本只检查高价值静态约束：

- `AGENTS.md` 的关键链接存在
- 治理规则与关键角色说明未回退
- 关键文档存在基线标记或维护约束
- 关键版本 / 角色描述未明显回退

## 6. 推荐收尾话术

- 文档改动：`已更新文档并运行文档治理巡检`
- Minigame 改动：`已跑 Node QA / 静态校验；browser harness 未人工点开`
- Launcher 改动：`已跑 build / xUnit；未做完整运行态手点`
- Flash 改动：`已完成 Flash smoke；未在缺少新鲜 trace 或 IDE 复核时声称编译通过`
