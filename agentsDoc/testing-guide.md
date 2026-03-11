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
- 优先看**本次运行新鲜生成**的 `scripts/flashlog.txt` / `%APPDATA%\Macromedia\Flash Player\Logs\flashlog.txt`
- 需要看 Output Panel 时，再核对 `scripts/compile_output.txt` 的刷新时间
- `publish_done.marker` 只能说明 JSFL 触发流程走完，**不能单独代表 SWF 已成功编译并运行**

### 当前边界
- 自动化链路仍在迭代期；遇到“marker 成功但没有 trace”时，仍需优先查看 Flash IDE 的输出 / 编译器错误面板
- 长耗时套件可能超过默认 30 秒轮询上限
- 如果再次出现 UAC、旧日志未刷新、任务动作异常，先重新运行 `scripts/setup_compile_env.bat`
- 对外表述应使用“已完成自动化 smoke 验证”或“已触发 Flash CS6 编译并拿到 trace”，不要在缺少新鲜日志或人工 IDE 复核时直接写“已编译通过”

---

## 3. Node.js 测试

**现状**：`tools/Local Server/` 无正式测试框架，验证依赖手动运行。

现有手段：
- `node server.js` 启动后 HTTP 手动验证
- `testPlaySound.js` — 音频播放验证
- `/testConnection` — 健康检查（POST → `status=success`）

---

## 4. 测试覆盖目标

- 核心类库新增/修改代码应有对应测试，覆盖正常路径和边界条件
- 不强制 100% 覆盖率，优先关键路径
