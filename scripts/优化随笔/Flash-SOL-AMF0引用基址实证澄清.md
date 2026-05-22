# Flash SOL 存档 AMF0 Reference 基址的实证澄清

**文档角色**：`sol_parser` AMF0 引用语义的 canonical 记录。
**实证日期**：2026-05-22。**相关代码**：[launcher/native/sol_parser/src/lib.rs](../../launcher/native/sol_parser/src/lib.rs)、[tests/reference_semantics.rs](../../launcher/native/sol_parser/tests/reference_semantics.rs)。

---

## 0. 一句话结论

真实 Adobe Flash Player 写出的 SOL 存档里，AMF0 Reference（`0x07`）对 body 复杂对象的索引是 **1-based** —— `sol_parser` 的 `resolve_ref` 用 `raw - 1` + `raw==0 → null` **是正确的，不要再改回 0-based**。

这个结论曾在 0-based / 1-based 间振荡三次，本次用**两条不依赖 flash-lso 的独立证据链**彻底定案。

---

## 1. 背景：为什么值得专门彻查

存档权威迁移到 Launcher 后，`sol_parser`（Rust cdylib，经 flash-lso）负责把 SOL 解成 JSON。其中 AMF0 Reference 的索引基址反复改过三次，每次都「有看似充分的依据 + 通过的测试」，事后又被推翻：

| 版本 | 行为 | 当时依据 | 结局 |
|---|---|---|---|
| 初版 | `raw - 1`（1-based） | 推测 Flash HashMap 行为 | 被「第二版」推翻 |
| 第二版 | `raw` 直查（0-based） | AMF0 规范 §2.9 + flash-lso writer 0-based + 合成 round-trip 测试 | **误判**：dual-write 顶层键整体错位 |
| 当前版 | `raw - 1`（1-based） | 真实存档 7 个 dual-write 键 deep-equal | ✅ 本次证实正确 |

第二版的「合成 round-trip 测试」是**自证**——手写 fixture 字节的人同时也选定了索引约定，测试只是重复断言自己的假设。本次验证的方法论价值就在于：用真实 Flash 写侧 + 独立解码器，绕开一切自证。

---

## 2. 验证方法（可复用）

### 2.1 独立 AMF0 解码器（不经 flash-lso）

[`amf0-help/amf0_probe.py`](../../amf0-help/amf0_probe.py)：仅按 AMF0 规范从**原始字节**解码 SOL，自建「仅复杂对象、DFS 前序」引用表，把每个 `0x07` marker 的**裸 u16** 与其结构路径全部打印。不预设基址，只摊开数字。

### 2.2 testLoader 闭环（真实 Flash Player 写侧）

写侧（`SharedObject.flush()` 的 AMF0 编码）一向被当作黑盒。本次用 `scripts/compile_test.sh` → Flash CS6 `testMovie()` 链路，在 testLoader 里跑 AS2，用 `SharedObject` 构造**结构完全已知**的对象图并 flush，再从 `%APPDATA%\Macromedia\Flash Player\#SharedObjects\...\TestLoader.swf\` 把 Flash 真正写出的 `.sol` 捞回解码。

> **harness 注意**：当时 testLoader 内存中主时间轴帧脚本是空的（`#include` 未生效，编译出 1 字节空 DoAction）。临时改 `compile_action.jsfl` 用 JSFL `frame.actionScript = ...` 注入帧脚本绕过。若以后再遇到「compile_test 触发成功但 trace 为空」，优先怀疑这一点。验证后所有 harness 文件已还原。

5 个受控存档见 [`amf0-help/probe_sols/`](../../amf0-help/probe_sols/)。

---

## 3. 核心证据

### 3.1 自引用：第一个 body 对象 = `Reference(1)`

`amf0probe_self.sol`：body 只有一个对象 `node`，`node.loop` 指向 `node` 自己。

```
offset 0x3e: 07        Reference marker
offset 0x3f: 00 01     u16 索引 = 1
```

`node` 是 body 第一个（也是唯一）复杂对象 → 规范 0-based 索引为 0。Flash 把指向它的引用写成 **1**。

### 3.2 偏移恒定：跨深度 / 容器 / 目标索引

`amf0probe_nested.sol`：同一实例 `alpha` 被塞进 5 个不同位置。规范 0-based 表：`[0]=alpha [1]=beta [2]=gamma [3]=gamma.deep [4]=arr [5]=arr[2]`。

| 引用位置 | 嵌套深度 | 文件 raw | 目标 | 规范索引 | 偏移 |
|---|---|---|---|---|---|
| `beta.ptr` | 兄弟对象 | 1 | alpha | 0 | **+1** |
| `gamma.deep.ptr` | **深 2 层** | 1 | alpha | 0 | **+1** |
| `delta` | 顶层 | 1 | alpha | 0 | **+1** |
| `arr[0]` | **数组元素** | 1 | alpha | 0 | **+1** |
| `arr[1]` | **数组元素** | 2 | beta | 1 | **+1** |

最后一行目标是规范索引 1 的 `beta`、文件值 2 —— 偏移仍 +1，证明它是**加性常数**，不随深度、容器类型、目标索引大小变化。

### 3.3 真实存档复核

`real_flash_v3.sol`（174 复杂对象、6 引用）：用「顶层键名 == 嵌套对象叶子名」结构配对，5 条 dual-write 引用的 raw 值全部等于孪生对象规范索引 + 1。

### 3.4 隐式根不可被引用：`0x0D`

`amf0probe_root.sol`：`data.backToRoot = data`（子属性指回 `SharedObject.data` 根）：

```
offset 0x42: 0d   = Unsupported marker（不是 0x07 Reference）
```

子节点指回根，Flash 写的是 `0x0D Unsupported`，**不是** `Reference(0)`。

**机制结论**：与其说「index 0 被隐式根 `.data` 占用」，更准确的表述是 —— Flash 的 SharedObject AMF0 编码器对 body 复杂对象的引用计数器是 **1-based**（首个 = 1）。index 0 永远不是合法 body 引用值；根本身根本不进表（指向它只能退化成 `0x0D`）。对解析器而言：`raw - 1` + `raw==0 → null` 正是「1-based 计数器、0 非法」的正确处理。

---

## 4. 各 AMF0 类型实测核对

来自 `amf0probe_types.sol` / `amf0probe_typed.sol` 原始字节：

| 现象 | 实测 |
|---|---|
| AS2 `[10,20,30]` | `0x08` ecma-array，u32 count=3，键 `"0"/"1"/"2"` |
| AS2 `[]` 空数组 | `0x08` ecma-array，**count=0** |
| AS2 `{}` 空对象 | **`0x03`** Object |
| **空数组 vs 空对象** | **marker 不同**（`0x08` ≠ `0x03`）—— 可靠判据 |
| 带名属性数组 | `0x08`，count=`.length`，非数字键作为 assoc 一并写出 |
| `NaN` / `±Infinity` | `0x00` Number，正常 f64 位 |
| `undefined` | `0x06` Undefined（确实写进文件） |
| `null` | `0x05` Null |
| `new Date()` | `0x0B` Date，f64 毫秒 + s16 时区（实测写了非 0 时区 -480） |
| `registerClass` 类实例 | **`0x10` TypedObject**，class name = 注册的 linkage 串 |
| AVM1 strict-array `0x0A` | 0 个 —— AVM1 数组一律 ecma-array |

---

## 5. flash-lso 真实行为

源码核对（pin commit `4b049ff3`）：

- **Reader 透传，无 bug**：`amf0/read.rs::parse_element_reference` 读 u16 后原样 `Value::Reference(raw)`，不加减、不解引用。`sol_parser` 自建表 + `raw-1` 因此是必须且正确的。
- **内部 reference 计数错**：`parse_single_element` 对**每个**元素（含 String/Number/Null）都 `cache.push`；`Amf0Writer.add_element(inc_ref=true)` 对每个基本类型都 `ref_num += 1`。即 flash-lso「数所有值」，违反 AMF0 §2.9「只数复杂对象」。读侧解引用没用到这个 cache（所以读无 bug），但 **`Amf0Writer` 写出的引用值是错的**——实测它给第 2 个复杂对象写 `Reference(3)`（规范要 1、真实 Flash 要 2）。

详见向上游提交的 issue 草稿：[`amf0-help/ISSUE.md`](../../amf0-help/ISSUE.md)。

---

## 6. 对 `sol_parser` 的影响与修复建议

| 项 | 现状 | 建议 |
|---|---|---|
| **引用基址** | `raw-1` + `raw==0→null` | ✅ **正确，不要动**。`lib.rs` 里那段「DO NOT simplify」注释保留 |
| **空数组/空对象判别** | `to_json` 用 `len_attr > 0` 启发式 → 空数组被还原成 `{}` | ⚠️ **改用 marker**：flash-lso 把两者解码成不同 variant（`Value::ECMAArray` vs `Value::Object`）。`Value::ECMAArray` 一律产 JSON 数组（`len_attr` 只定长度），`Value::Object` 一律产 JSON 对象。同时修掉「带 `length` 属性的对象被误判成数组」 |
| **TypedObject 不对称** | `index_value` 的合并臂只递归常规成员、漏 sealed 成员，`to_json` 两者都发 | ⚠️ 建议修：实证确认 `registerClass` 实例会写成 `0x10`。当前真实存档 0 个 TypedObject 未触发，但一旦出现会让后续引用整体错位。拆臂、按写出顺序递归两段成员 |
| `NaN/±Inf → null`、`undefined(0x06)` 与 `null` 合流 | JSON 固有有损 | 本游戏存档不含 Date、不依赖 `=== undefined`，可不管；若将来依赖则需哨兵 |

> 改 `sol_parser` 任意 SOL 读取路径后，按 [testing-guide](../../agentsDoc/testing-guide.md) 跑 `cargo test`（`reference_semantics.rs` 回归）+ `launcher/build.ps1` + `launcher/tests/run_tests.ps1`。

---

## 7. 复现

```bash
# 独立解码器（不需要 Flash）
cd amf0-help
python amf0_probe.py sol_parser/tests/fixtures/real_flash_v3.sol
for f in self root nested types typed; do python amf0_probe.py probe_sols/amf0probe_$f.sol; done

# flash-lso 写侧引用计数复现（需 Rust）
cd sol_parser && cargo run --example flwriter_probe && cargo test

# 重新生成受控存档：Flash CS6 + testLoader 打开，把 AS2 探针写进 scripts/TestLoader.as，
#   bash scripts/compile_test.sh，再从 #SharedObjects\...\TestLoader.swf\ 取回 .sol
```

证据文件清单见 [`amf0-help/`](../../amf0-help/)：`amf0_probe.py`（独立解码器）、`probe_sols/*.sol`（5 受控存档 + flash-lso 自写样本）、`sol_parser/examples/flwriter_probe.rs`（写侧 bug 最小复现）、`ISSUE.md`（上游 issue 草稿）。
