### 研究记录：AS2 中 `__proto__ = null` 对象的相等性退化与工程边界

#### 1. 背景

在一次 `LiteJSON.parse()` 的激进性能优化中，曾对解析出的普通对象统一执行 `obj.__proto__ = null`，以消除原型链查找开销。

运行后发现：

- 数组根的配置数据仍可正常工作
- 对象根的配置数据更容易失效
- 失效点集中在加载器、回调、配置合并、通用工具函数等“模块边界”

初始猜想是“断开原型链后，下游 `!= null` 判空会误判”。后续实验表明，这个方向是对的，但更准确的说法是：

> `proto-null` 对象在 AVM1/AS2 下会触发 loose equality（`==` / `!=`）语义退化；对象本身没有坏掉，但会在通用 `Object` 语义边界上失真。

---

#### 2. 已验证行为

以下结论来自可复现的最小实验。

**2.1 基础判定**

对

```actionscript
var obj:Object = {};
obj.__proto__ = null;
```

实测有：

- `typeof obj` 为 `"object"`
- `obj == null` 为 `true`
- `obj === null` 为 `false`
- `obj == undefined` 为 `true`
- `obj === undefined` 为 `false`

这说明它不是“严格类型层面被直接当成 null/undefined”，而是 **loose equality 路径发生了退化**。

**2.2 对象仍然存活**

对同类 `proto-null` 对象实测：

- 自有属性读写正常
- `delete` 正常
- `for...in` 仍能枚举自有属性
- `bare == bare` 与 `bare === bare` 都为 `true`

这说明对象并没有损坏，也不是“空壳对象”。

换言之，问题不在对象活性，而在“对象被拿去做通用比较/通用 `Object` 操作”时的兼容性。

**2.3 原型方法确实不可达**

对 `proto-null` 对象：

- `obj.hasOwnProperty` 为 `undefined`
- `obj.valueOf` 为 `undefined`

这符合“原型链断开”的预期。

**2.4 自有 `valueOf` 可恢复比较行为**

若手动补一个自有 `valueOf`：

```actionscript
var patched:Object = {};
patched.__proto__ = null;
patched.valueOf = function() { return 1; };
```

则实测：

- `patched == null` 为 `false`
- `patched == 1` 为 `true`
- `patched == undefined` 为 `false`

这说明 loose equality 的退化和 `valueOf` 可达性高度相关。

**2.5 仅补 `toString` 不足以恢复**

若只补自有 `toString`：

- `patched2 == null` 仍为 `true`
- `patched2 == "hello"` 为 `false`

至少从当前实验看，`toString` 不是这条退化路径的有效补救手段。

**2.6 只要原型链尾为 `null`，问题就会传播**

若构造：

```actionscript
var fakeProto:Object = {};
fakeProto.__proto__ = null;

var semibare:Object = {};
semibare.__proto__ = fakeProto;
```

则 `semibare == null` 仍为 `true`。

这说明问题不只是“直接 `__proto__ = null`”，而是 **整条原型链到链尾找不到正常的原生能力** 时，比较语义都会退化。

**2.7 恢复 `Object.prototype` 后可恢复正常**

对测试对象重新赋回：

```actionscript
test4.__proto__ = Object.prototype;
```

后，`test4 == null` 恢复为 `false`，`valueOf` 也重新可达。

---

#### 3. 当前能下到什么结论

可以下结论的部分：

1. `proto-null` 对象在 AS2 中不是“坏对象”；它们仍可持有和枚举自有属性。
2. `proto-null` 会破坏 loose equality 的工程可用性，尤其是 `== null`、`!= null`、`== undefined`、`!= undefined`。
3. 问题会沿原型链尾传播；不是只有“直接断链”才出问题。
4. `valueOf` 可达性与比较恢复强相关；`toString` 不是当前实验中可行的替代物。

不能下得过满的部分：

1. 目前还不能把 VM 内部算法写死为某一种精确实现。
2. 现阶段更稳妥的表述是“**loose equality / ToPrimitive 路径退化**”，而不是声称已经完全逆向出 AVM1 的比较细节。

---

#### 4. 工程结论

**4.1 `proto-null` 只适合封闭内部字典**

可以使用 `obj.__proto__ = null` 的场景：

- 封闭实现内部的字典/哈希表
- 生命周期和使用边界都清晰的局部缓存
- 不会传出当前模块的内部映射结构

**4.2 会泄露到模块边界的数据结果，必须保持普通 `Object`**

禁止默认断链的场景：

- JSON 解析结果
- 配置对象
- 加载器返回值
- 跨模块传递对象
- 会进入通用工具函数、UI 逻辑、回调链、`_root` 挂载对象的数据

原因不是“这些地方一定会用到原型方法”，而是你无法保证它们 **永远不会** 依赖：

- `== null` / `!= null`
- `hasOwnProperty`
- `constructor`
- `:Object` 形参
- 其他默认把它当普通 `Object` 的工程约定

**4.3 解析器不应替调用方批量制造异形对象**

需要 `proto-null` 字典时，应在消费端显式创建，而不是让解析器对所有对象统一断链。

这条规则尤其适用于 `LiteJSON.parse()` 一类公共基础设施。

---

#### 5. 对性能优化的实际启示

本次结论不是在否定“断开原型链有性能收益”，而是在补充它的 **适用边界**：

- 在封闭内部字典上，这依然可能是合理优化
- 在公共数据对象上，兼容性成本远高于潜在收益

因此，推荐策略不是“一刀切禁用”，而是：

1. 将 `proto-null` 限定在封闭内部字典
2. 让公共解析结果、配置对象、模块边界对象保持普通 `Object`
3. 把“性能优化”和“数据语义边界”分开决策

---

#### 6. 可直接写入工程规范的短结论

- `proto-null` 对象在 AS2 中会让 `== null` / `== undefined` 失真
- `===` 仍正常；对象自有属性和 `for...in` 仍然可用
- 这不是对象损坏，而是 loose equality / 通用 `Object` 语义退化
- 仅封闭内部字典可断链；凡会泄露到模块边界的数据结果都应保持普通 `Object`

这批信息已经足够进入 `agentsDoc` 的总结层；若未来拿到更多 VM 级证据，再补充底层机制即可。

```actionscript

var obj:Object = {};
obj.__proto__ = null;

trace(typeof obj);           // 预期 "object"，确认字面类型
trace(obj == null);          // 预期 true（你遇到的问题）
trace(obj === null);         // 如果也 true，说明类型判定层就错了
trace(obj === undefined);    // 测试它到底被当成了什么
trace(obj == undefined);     // 应该也是 true
// 如果能拿到 valueOf：
trace(obj.valueOf);          // 预期 undefined（原型链断了）

// ============================================
// 准备
// ============================================
var bare:Object = {};
bare.__proto__ = null;
bare.x = 42;

var normal:Object = {};
normal.x = 42;

// ============================================
// 测试组 1: 区分 A vs B —— 是"类型判定错误"还是"ToPrimitive 退化"
// 给无原型对象手动挂 valueOf，看 == 行为是否恢复
// ============================================
var patched:Object = {};
patched.__proto__ = null;
patched.valueOf = function() { return 1; };

trace("--- Group 1: valueOf patch ---");
trace("patched == null:  " + (patched == null));    // 如果 B: false（ToPrimitive 能正常返回 1）
                                                     // 如果 A: 仍 true（根本没走到 ToPrimitive）
trace("patched == 1:     " + (patched == 1));        // B 下预期 true
trace("patched == undefined: " + (patched == undefined));

// 同理测 toString
var patched2:Object = {};
patched2.__proto__ = null;
patched2.toString = function() { return "hello"; };

trace("patched2 == null: " + (patched2 == null));
trace("patched2 == 'hello': " + (patched2 == "hello"));

// ============================================
// 测试组 2: 区分 B vs C —— 断原型后对象本身是否还"活着"
// ============================================
trace("--- Group 2: object liveness ---");
trace("bare.x:           " + bare.x);               // 42 = 自有属性存活, undefined = 对象已损坏
trace("bare.hasOwnProperty: " + bare.hasOwnProperty); // 预期 undefined（原型方法不可达）

// 断原型后能否正常增删属性
bare.y = 99;
trace("bare.y:           " + bare.y);
delete bare.x;
trace("bare.x after del: " + bare.x);

// for-in 是否还能枚举
var keys = "";
for (var k in bare) { keys += k + ","; }
trace("bare keys:        " + keys);                 // C 下可能完全空或异常

// ============================================
// 测试组 3: 区分 A 的子假说 —— VM 是否检查 __proto__ 是否为 null
// ============================================
// 设 __proto__ 为非 null 的"假"值，看 == 是否恢复
var fakeProto:Object = {};
fakeProto.__proto__ = null;

var semibare:Object = {};
semibare.__proto__ = fakeProto; // 原型链: semibare -> fakeProto -> null(断)

trace("--- Group 3: shallow vs deep proto ---");
trace("semibare == null: " + (semibare == null));    // 如果 A 只检查直接 __proto__: false
                                                      // 如果 A 遍历到链尾: true
trace("fakeProto == null:" + (fakeProto == null));   // 对照: 这个是直接断的

// ============================================
// 测试组 4: __proto__ = null 的实际语义
// ============================================
trace("--- Group 4: proto assignment semantics ---");
var test4:Object = {};
trace("before: " + test4.__proto__);                 // [object Object] 或类似
test4.__proto__ = null;
trace("after:  " + test4.__proto__);                 // null? undefined? 还是什么
test4.__proto__ = Object.prototype;                  // 能否恢复？
trace("restored: " + (test4 == null));               // 如果 C: 可能恢复不了
trace("restored valueOf: " + test4.valueOf);         // 能否重新访问原型方法

// ============================================
// 测试组 5: 与其他类型做 == 比较，摸清退化的完整行为
// ============================================
trace("--- Group 5: == against various types ---");
trace("bare == false:    " + (bare == false));
trace("bare == 0:        " + (bare == 0));
trace("bare == '':       " + (bare == ""));
trace("bare == bare:     " + (bare == bare));        // 自反性，如果这都失败就是 C
trace("bare === bare:    " + (bare === bare));       // 对照

```


```log

object
true
false
false
true
undefined
--- Group 1: valueOf patch ---
patched == null:  false
patched == 1:     true
patched == undefined: false
patched2 == null: true
patched2 == 'hello': false
--- Group 2: object liveness ---
bare.x:           42
bare.hasOwnProperty: undefined
bare.y:           99
bare.x after del: undefined
bare keys:        y,
--- Group 3: shallow vs deep proto ---
semibare == null: true
fakeProto == null:true
--- Group 4: proto assignment semantics ---
before: [object Object]
after:  null
restored: false
restored valueOf: [type Function]
--- Group 5: == against various types ---
bare == false:    false
bare == 0:        false
bare == '':       false
bare == bare:     true
bare === bare:    true


```