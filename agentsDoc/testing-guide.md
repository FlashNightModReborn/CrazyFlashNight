# 测试约定与方法

> 本项目的 AS2 测试框架约定和 Node.js 测试方法。

---

## 1. AS2 测试框架

### 核心模式：一句话启动
- 每个测试类提供一个静态入口方法（如 `runAllTests()` 或 `runTests()`），可在 Flash IDE 帧脚本中**一行调用**启动全部测试
- 测试类命名：`[ClassName]Test.as`
- 测试方法命名：`test_方法名_预期结果`
- 使用 `trace()` 输出 PASS/FAIL 结果

### 同名 .md 文件惯例
- 测试类旁放置同名 `.md` 文件（如 `TimSort.md`），第一行记录启动语句，后面粘贴运行输出
- 开发阶段作为测试记录使用；功能稳定后逐步升级为完整的设计文档（补充算法说明、基准数据、决策记录等）

示例（`TimSort.md`）：
```
org.flashNight.naki.Sort.TimSortTest.runTests();

Starting Enhanced TimSort Tests...
=== 基础功能测试 ===
PASS: 空数组测试
PASS: 单元素数组测试
...
```

### 目录组织
```
scripts/类定义/org/flashNight/[包名]/
├── SomeClass.as
├── SomeClass.md          ← 启动语句 + 测试输出 → 后期升级为设计文档
└── test/
    └── SomeClassTest.as
```

### Mock 策略
- MovieClip 和 _root 引用需要 Mock
- 外部依赖（如服务器通信）需要 Mock
- **MovieClip Mock 原则**：如果测试涉及影片剪辑的原生方法（`gotoAndStop`、`hitTest` 等），应继承或修改自 `MovieClip`，而非使用空 `Object`，以避免测试中方法行为不一致
- 类型绕过：Mock 对象可能导致编译期类型检查不通过，此时可使用无类型变量绕过编译，但工程代码本身必须保持强类型
- 工具类：`org.flashNight.gesh.array.ArrayUtil` 可在测试中使用（工程代码不推荐，性能损耗较高）

---

## 2. Node.js 测试

**现状**：`tools/Local Server/` 无正式测试框架（无 mocha/jest 等依赖，无 test 脚本，无测试目录）。服务器早期编写较粗糙，验证依赖手动运行。

现有验证手段：
- `node server.js` 启动后通过 HTTP 请求手动验证
- `testPlaySound.js` — 独立的音频播放验证脚本
- `/testConnection` 端点 — 连接健康检查（POST → `status=success`）
- 各 controller 内有参数校验和错误处理，但非自动化测试

---

## 3. XML 配置验证

- 所有 XML 配置文件应验证格式正确性
- 可通过 Node.js 脚本进行批量 XML 格式校验

---

## 4. 测试覆盖目标

- 核心类库中的新增/修改代码应有对应测试
- 测试应覆盖正常路径和边界条件
- 不强制 100% 覆盖率，优先覆盖关键路径
