# 测试约定与方法

---

## 1. AS2 测试框架

### 核心模式：一句话启动
- 每个测试类提供静态入口（如 `runAllTests()` / `runTests()`），Flash IDE 帧脚本中一行调用
- 测试类命名：`[ClassName]Test.as`，方法命名：`test_方法名_预期结果`
- 使用 `trace()` 输出 PASS/FAIL 结果

### 同名 .md 文件惯例
- 测试类旁放置同名 `.md`（如 `TimSort.md`），第一行为启动语句，后面粘贴运行输出
- 功能稳定后逐步升级为设计文档

### 目录组织
```
scripts/类定义/org/flashNight/[包名]/
├── SomeClass.as
├── SomeClass.md          ← 启动语句 + 测试输出 → 后期升级为设计文档
└── test/
    └── SomeClassTest.as
```

### Mock 策略
- MovieClip 和 _root 引用需要 Mock；外部依赖（服务器通信等）需要 Mock
- **MovieClip Mock**：涉及原生方法（`gotoAndStop`、`hitTest`）时应继承自 `MovieClip`，勿用空 `Object`
- 类型绕过：Mock 导致编译不过时可用无类型变量绕过，但工程代码必须保持强类型
- `ArrayUtil` 可在测试中使用（工程代码不推荐）

---

## 2. Flash CS6 自动化 smoke 验证（迭代中）

### 适用范围
- 适合快速回归、`TestLoader.as` 入口验证、trace 驱动的 smoke test
- 适合确认“这次改动是否被 Flash CS6 真实编译并执行到了当前 trace”
- 不适合把 `publish_done.marker` 直接当作最终成功判据，也不适合替代所有 IDE 人工复核

### 前提条件
- 当前机器已以管理员身份运行过 `scripts/setup_compile_env.bat`
- Flash CS6 正在运行，且 `scripts/TestLoader` XFL 已打开
- 如近期更新过自动化脚本或切换设备，应先重新运行一次 setup，让脚本清理旧环境并自愈计划任务

### 触发方式
- PowerShell：`powershell -ExecutionPolicy Bypass -File scripts/compile_test.ps1`
- Bash：`bash scripts/compile_test.sh`

### 成功判据
- **编译错误检测**：`scripts/compiler_errors.txt` 由 `fl.compilerErrors.save()` 自动生成，包含 Compiler Errors 面板内容；有错误时脚本自动输出并 `exit 1`
- 优先看**本次运行新鲜生成**的 `scripts/flashlog.txt` / `%APPDATA%\Macromedia\Flash Player\Logs\flashlog.txt`
- 需要看 Output Panel 时，再核对 `scripts/compile_output.txt` 的刷新时间
- `publish_done.marker` 只能说明 JSFL 触发流程走完，**不能单独代表 SWF 已成功编译并运行**
- **注意**：AS2 帧脚本中的类型错误、未声明变量不会产生编译错误（弱类型，运行时才报错）；只有语法错误（括号不匹配、关键字误用等）和 class 文件中的类型错误才会被捕获

### 当前边界
- ~~遇到”marker 成功但没有 trace”时，仍需优先查看 Flash IDE 的编译器错误面板~~ → 现在 `compiler_errors.txt` 已自动捕获，但仍建议核对 IDE 面板确认完整性
- 长耗时套件可能超过默认 30 秒轮询上限
- 如果再次出现 UAC、旧日志未刷新、任务动作异常，先重新运行 `scripts/setup_compile_env.bat`
- 对外表述应使用“已完成自动化 smoke 验证”或“已触发 Flash CS6 编译并拿到 trace”，不要在缺少新鲜日志或人工 IDE 复核时直接写“已编译通过”

---

## 3. C# Launcher 测试

**现状**：`launcher/` 通过编译验证 + HTTP 端点检查 + 游戏集成测试。

验证手段：
- `launcher/build.ps1` — 编译验证（MSBuild，零错误即通过）
- `bash tools/cfn-cli.sh status` — 健康检查（返回 task 清单 + socket 连接状态）
- `bash tools/cfn-cli.sh console "help"` — AS2 回环测试
- 游戏集成：启动游戏后观察 hit number overlay、toast、gomoku 是否正常工作

### `--bus-only` 模式（testMovie 集成测试）

Launcher 支持 `--bus-only` 参数，仅启动通信总线（HTTP + XMLSocket + TaskRegistry），不启动 Flash Player。
用于 Flash CS6 testMovie 场景：外部 Flash Player 实例自行连接到 bus。

```powershell
# 手动启动
CRAZYFLASHER7MercenaryEmpire.exe --bus-only

# 通过 cfn-cli 启动/停止
bash tools/cfn-cli.sh start-bus
bash tools/cfn-cli.sh stop-bus
```

### 自动化 AI 调优循环

`gobang_trainer_cycle.ps1` 是完整的 AI 评测自动化入口，自动管理 bus 生命周期：

```powershell
# 全量 trainer-only（68 题，~180s）
powershell -ExecutionPolicy Bypass -File scripts/gobang_trainer_cycle.ps1 -Mode trainer_only -Json

# 定向题面（~15s）
powershell -ExecutionPolicy Bypass -File scripts/gobang_trainer_cycle.ps1 -Mode trainer_only -Problems mid_complex_diagonal,def_diag_two_two_block -Json
```

流程：自动启动 bus → 重写 TestLoader.as → 编译 testMovie → 等待 SUMMARY → 解析 JSON → 恢复 TestLoader.as。
详见 `scripts/类定义/org/flashNight/hana/Gobang/TRAINING_METHODOLOGY.md`。

**此模式不仅用于五子棋，后续任何需要 AS2↔C# 通信的 AI/模拟实验均可复用此基建。**

---

## 4. 测试覆盖目标

- 核心类库新增/修改代码应有对应测试，覆盖正常路径和边界条件
- 不强制 100% 覆盖率，优先关键路径

---

## 5. TDD 工作流约束

### 适用范围
- **强制**：`scripts/类定义/` 下的所有 `.as` class 文件（新增或修改公共 API 时必须先有测试）
- **不受限**：帧脚本（展现/引擎/通信/逻辑）、`.fla`/`.xfl` 资产、XML 数据文件

### 红-绿-重构循环
1. **红**：先写失败测试，确认测试本身能检测到预期行为缺失
2. **绿**：用最小实现让测试通过
3. **重构**：在测试全绿的保护下优化实现，每步重构后重新编译验证

### 回归保护规则
- 修改已有 class 的公共方法签名或语义行为前，**必须先确认现有测试覆盖该行为**；如无覆盖，先补测试再改代码
- 优化（性能/内存/池化等）属于重构阶段，必须在测试全绿后进行，每次优化后重新跑全套
- 测试失败时禁止提交；如需临时跳过某条测试，必须在测试方法内用注释标注原因和预计修复时间

### 测试编写要求
- 测试必须有真实断言（`assert`/`assertEq`/`assertTrue`），禁止只 `trace` 不断言
- 涉及对象池的测试：在 `resetPools()` 前捕获需要比较的值（池化对象会被后续分配覆盖）
- 测试之间互不依赖：每个 `test_xxx` 方法自行 `resetPools()` / `initWithContainer()` / `reset()`
- 噪声/随机分支测试：只变一个参数（隔离变量），用断言验证差异而非只打印

### 编译验证
- 使用 `bash scripts/compile_test.sh` 触发 Flash CS6 自动化编译
- 以 `scripts/flashlog.txt` 中的 `[PASS]`/`[FAIL]` 输出为判据
- 详见 §2 Flash CS6 自动化 smoke 验证

---

## 6. 测试日志归档

### 目的
保留测试运行历史，方便排查回归和追溯问题引入时间点。

### 归档位置与格式
- **同名 `.md` 文件**（已有惯例）：测试类旁的 `ClassName.md` 或 `ClassNameTest.md`
  - 第一行：TestLoader 启动语句（如 `import ...Test; Test.runAllTests();`）
  - 后续：粘贴最近一次完整测试输出（含 `[PASS]`/`[FAIL]` 和汇总行）
  - 功能稳定后可追加设计说明，逐步升级为设计文档
- **`scripts/flashlog.txt`**：自动化编译管线的最新一次运行日志（自动覆盖，不归档历史）
- **`scripts/compile_output.txt`**：Flash CS6 Output Panel 的最新一次副本

### 归档时机
- 完成一轮 TDD 迭代（测试全绿 + 重构完成）后，将 flashlog.txt 中相关输出粘贴到对应 `.md` 文件
- 发现并修复 bug 时，在 `.md` 文件中记录修复前后的测试输出对比（可选，推荐用于关键 bug）
- 性能基准（bench 输出）也应归档到 `.md` 文件，作为优化前后的对比基线

### 归档内容要求
- 必须包含：日期、测试汇总行（`run=N, pass=N, fail=N`）、所有 `[FAIL]` 行的完整输出
- 推荐包含：性能基准数据、关键修复的 before/after 对比
- 不必包含：全部 `[PASS]` 行（汇总行已覆盖），除非需要追溯特定用例
