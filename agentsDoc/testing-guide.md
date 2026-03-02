# 测试约定与方法

> AS2 测试框架约定和 Node.js 测试方法。

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

## 2. Node.js 测试

**现状**：`tools/Local Server/` 无正式测试框架，验证依赖手动运行。

现有手段：
- `node server.js` 启动后 HTTP 手动验证
- `testPlaySound.js` — 音频播放验证
- `/testConnection` — 健康检查（POST → `status=success`）

---

## 3. 测试覆盖目标

- 核心类库新增/修改代码应有对应测试，覆盖正常路径和边界条件
- 不强制 100% 覆盖率，优先关键路径
