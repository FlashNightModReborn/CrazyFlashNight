# AS2 (AVM1) NaN 陷阱总结

基准测试开发中遭遇的 `_bh` (blackhole accumulator) NaN 感染问题，逐层剥离共发现 **5 个独立根因**。本文档记录每个陷阱的机制、最小复现和修复方式，供后续 AS2 开发参考。

---

## 陷阱 0：死代码——检测逻辑放在 return 之后

**现象**：NaN 诊断 trace 从未触发，误以为不存在 NaN。

**原因**：
```actionscript
function _measurePair(...):Object {
    return { ... };
    // 以下永远不会执行
    if (isNaN(_bh)) trace("NaN!");
}
```

**修复**：把检测移到 `return` 之前。

**教训**：AS2 编译器不会对 return 后的死代码发出警告。

---

## 陷阱 1：一元加 `+s` 不转换类型

**现象**：`_bh` 从 Number 变成 String，后续所有 `+=` 变为字符串拼接。`isNaN()` 无法检测（因为字符串内容是合法数字）。

**原因**：AS2 的 `+s`（一元加）对 String 类型**不做 Number 转换**，直接返回原 String。这是 AVM1 编译器优化的 bug。

**最小复现**：
```actionscript
var s:String = "42";
var b:Number = +s;   // b 实际是 String "42"，不是 Number 42
trace(typeof(b));     // "string" !!!
var n:Number = 0;
n += b;               // n 变成 "042"（字符串拼接）
trace(isNaN(n));      // false —— "042" 可解析为数字，isNaN 检测不到
```

**修复**：用 `Number(s)` 替代 `+s`。

**检测技巧**：`typeof` 能立即发现类型污染，`isNaN` 不能（字符串内容为合法数字时 `isNaN` 返回 false）。

---

## 陷阱 2：Array.pop() / Array.shift() 返回类型是 Object

**现象**：编译错误「赋值语句中的类型不匹配」。

**原因**：AS2 的 `Array.pop()` 和 `Array.shift()` 签名返回 `Object`，不是元素的实际类型。赋值给 `var b:Number` 时编译器报类型不匹配。

**修复**：用无类型变量接收，再显式转换：
```actionscript
var b = 0;            // 无类型声明
b = arr.pop();        // OK
_bh += Number(b);     // 显式转换确保安全
```

---

## 陷阱 3：展开次数 > 数组长度 → undefined → NaN

**现象**：`arr.pop()` / `arr.shift()` / `arr.splice()` 在循环展开中耗尽数组，后续调用返回 `undefined`。

**原因**：基准测试使用 `STRUCT_UNROLL=10`（每次循环迭代展开 10 次操作），但数组只有 5 个元素。第 6 次 `pop()` 起返回 `undefined`，`Number + undefined = NaN`。

**最小复现**：
```actionscript
var arr:Array = [1,2,3,4,5];
var b = 0;
// 展开 10 次
b = arr.pop(); // 5
b = arr.pop(); // 4
b = arr.pop(); // 3
b = arr.pop(); // 2
b = arr.pop(); // 1
b = arr.pop(); // undefined !!!
// ...
_bh += Number(b); // NaN
```

**修复**：
- `pop`/`shift`：数组长度 >= 展开次数（10 元素 for UNROLL=10）
- `splice(2,1)`：每次删 1 个，需 >= 展开次数的余量（15 元素 for UNROLL=10）
- `resetEach` 每次迭代重建数组

---

## 陷阱 4：base 函数中变量未赋值 → finalize 访问 undefined 属性

**现象**：`gc_arr_literal` 和 `gc_arr_10elem` 的 base 函数产生 NaN，级联感染后续所有 GC 测试。

**原因**：base/test 共享同一个 `finalize` 表达式。test 函数中 `a=[1,2,3]` 给 `a` 赋值了，但 base 函数只执行 `b=cst;`，从未给 `a` 赋值。finalize 中 `_bh += a.length + b` 访问了 `undefined.length`：

```actionscript
// base 函数生成的代码
function base_gc_arr_literal():Number {
    var a:Array;          // undefined —— base 从不赋值 a
    var b:Number = 0;
    var cst:Number = 0;
    while (i--) {
        b = cst;          // 只操作 b
    }
    _bh += a.length + b;  // undefined.length → undefined
                           // undefined + 0 → NaN
                           // _bh += NaN → _bh 永久 NaN
    return getTimer() - t0;
}
```

**修复**：用三元守卫保护可能未赋值的变量：
```javascript
finalize: '_bh += (a==undefined?0:a.length)+b;'
```

其他 GC 测试（`gc_new_object`、`gc_obj_literal` 等）已经用了这种模式：
```javascript
finalize: '_bh += (o.x==undefined?0:o.x)+b;'
```

---

## NaN 级联感染机制

```
_bh: 正常 Number
       │
       ▼ 某个测试的 finalize 引入 NaN/String
_bh: NaN 或 String
       │
       ▼ 后续所有 _bh += x 操作
_bh: 永久 NaN（或持续拼接的字符串）
       │
       ▼ 最终输出
bh_post=NaN
```

一旦 `_bh` 被污染，**所有后续测试都会报告 NaN**，但只有第一个感染源是真正的 bug。因此排查时需要找到**第一个**报告异常的测试名。

---

## 防御性编程检查清单

| 规则 | 说明 |
|------|------|
| 不用 `+s` 转数字 | AS2 一元加不转换 String，必须用 `Number(s)` |
| 不用 `isNaN` 检测类型污染 | `isNaN("123")` 返回 false；用 `typeof(x) != "number"` |
| Array 方法返回值用无类型变量接收 | `pop()`/`shift()` 返回 Object，显式类型声明会编译错误 |
| 破坏性数组操作注意元素耗尽 | 循环展开 N 次，数组至少需要 N 个元素 |
| base/test 共享 finalize 时守卫未赋值变量 | `(x==undefined?0:x.prop)` |
| `typeof` 优先于 `isNaN` 做诊断 | typeof 能区分 Number/String/undefined，isNaN 不能 |
| NaN 感染后找第一个报错点 | 级联效应会让后续全部异常，只有首发点是真 bug |
| 检测代码不要放在 return 之后 | AS2 编译器不警告死代码 |
