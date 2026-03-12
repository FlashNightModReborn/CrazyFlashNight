# 跨 Agent 共享记忆

---

## 1. 用户偏好与工作习惯


---

## 2. 已知坑与临时 Workaround

### ▸ [2026-03-02] Git 中文文件名显示

```bash
# 每个 clone 执行一次，使 git 直接显示中文文件名（而非八进制转义）
git config --local core.quotePath false
```

> 终端编码（chcp 65001）的规则已在 AGENTS.md「硬约束（最高优先级）」中定义，此处不重复。

### ▸ [2026-03-12] AS2 / AVM1 NaN 陷阱与风险模式

> 详细案例见：`scripts/优化随笔/性能基准评估/AS2_NaN陷阱总结.md`

#### 核心：`!=` 遇到 NaN 是死循环

AVM1 遵循 IEEE 754，NaN 的比较行为：

| 表达式 | NaN 时 | 危险性 |
|---|---|---|
| `x != target` | `true` | **死循环** |
| `x < target` | `false` | 安全，自动退出 |
| `x > target` | `false` | 安全，自动退出 |
| `x >= target` | `false` | 安全，自动退出 |

**高危模式（必须替换）**：
```actionscript
while (currentX != targetX) { ... }   // NaN → 死循环
while (steps != 0) { steps--; ... }   // NaN → 死循环
```

**天生抗 NaN 的替换写法（零额外开销）**：
```actionscript
while (currentX < targetX) { ... }              // 单向移动
while (Math.abs(targetX - currentX) > 0.5) { } // 双向收敛
for (var i:Number = 0; i < steps; i++) { ... } // 步数驱动
while (steps-- > 0) { ... }                    // 倒计时
```

#### AS2 特有的 NaN 来源

1. **一元加不转换 String**：`+s` 对 String 类型无效，必须用 `Number(s)`
2. **`isNaN` 无法检测 String 污染**：`isNaN("123")` 返回 `false`，用 `typeof x == "number" && !isNaN(x)` 或从根源守卫
3. **`undefined` 坐标算术**：MovieClip 未加载时 `._x` 为 `undefined`，参与加减后得 NaN
4. **Array.pop/shift 耗尽**：超出长度返回 `undefined`，参与算术得 NaN
5. **NaN 级联感染**：一旦 NaN 进入累加变量，后续所有运算结果都是 NaN

#### 风险替换优先级

- **P0（死循环风险）**：所有 `while (x != y)` / `while (steps != 0)` 类循环
- **P1（NaN 静默传播）**：移动/碰撞/坐标计算中依赖 `isNaN` 守卫的地方
- **P2（根源防御）**：读取 MovieClip 坐标前检查 `_parent` 存在性（参考 `电感切割刃.as` 的 `刀口 && 刀口._parent` 模式）

> **明日计划**：全项目彻查上述高危模式，逐一风险替换。

---

### ▸ [2026-03-03] HTML 富文本中的特殊字符转义

tooltip 系统使用 HTML 富文本渲染（`<FONT>` 标签等）。在拼接用户可见文本时，`<` `>` `&` 必须写为 `&lt;` `&gt;` `&amp;`，否则会被 Flash HTML 解析器当作标签吞掉，导致文本丢失或显示异常。

**易错场景**：数学符号（< > ≤ ≥）、条件运算符显示、任何含尖括号的描述文本。

---

## 3. 高频操作备忘

