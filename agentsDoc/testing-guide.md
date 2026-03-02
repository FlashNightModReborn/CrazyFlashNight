# 测试约定与方法

> 本项目的 AS2 测试框架约定和 Node.js 测试方法。

---

## 1. AS2 测试框架

### 核心模式：runAllTests()
- 每个测试类提供 `runAllTests():Void` 入口方法
- 测试类命名：`[ClassName]Test.as`
- 测试方法命名：`test_方法名_预期结果`
- 使用 `trace()` 输出测试结果

### 目录组织
```
scripts/类定义/org/flashNight/[包名]/
├── SomeClass.as
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

<!-- TODO: 确认 tools/Local Server/ 是否有现有测试，补充实际测试方法 -->

- 服务器代码可直接运行验证
- 使用 `node server.js` 启动后通过 HTTP 请求验证

---

## 3. XML 配置验证

- 所有 XML 配置文件应验证格式正确性
- 可通过 Node.js 脚本进行批量 XML 格式校验

---

## 4. 测试覆盖目标

- 核心类库中的新增/修改代码应有对应测试
- 测试应覆盖正常路径和边界条件
- 不强制 100% 覆盖率，优先覆盖关键路径
