# AS2 attachMovie load 时序契约（FP20 实测）

**文档角色**：AS2 attachMovie 后事件派发的 FP20 实测记录与契约草案。
**实测平台**：Flash Player 20（项目固化版本）；测试夹具见 `scripts/TestLoader/`（库内 `TestProbeSkin` / `TestProbeNested` / `TestProbeLeaf` / `child` / `leafChild`，已固化签入仓库）；runner 代码见第 5 节（`scripts/TestLoader.as` 是通用入口、被 .gitignore，每次复现需粘贴）。
**实施状态**：**契约设计中**，第 3 节列出候选方案；当前数据收集阶段，**`_执行配置` 尚未落地任何延后通道**——但 `Object.registerClass` 实测已完成，方案 B 转为推荐方向。
**最近实测**：2026-05-08（基础时序 + registerClass 类方法 onLoad 确认触发 + register-attach-unregister 精准 scope 验证）。

## Quick Sheet（速查）

- `MovieClip.onLoad = fn` 属性赋值对 attachMovie 的 clip **不触发**（Adobe 文档骗人）
- 但 `Object.registerClass` 类方法 `onLoad` **触发** ✅ —— 与属性赋值是两条派发路径
- `onClipEvent(load)`（资产侧 IDE 内嵌）对 attachMovie **触发**，递归后序遍历
- attachMovie 同步返回时：`mc._x` / placement 子的 `_x` 已就绪；`onClipEvent(load)` 写入的字段尚未就绪
- **类绑定下构造函数同步在 attachMovie 内触发**，此时子 `_x` 已就绪、子 load 字段未就绪
- 当帧 dispatch 顺序：`脚本返回 → load flush（含嵌套，类 onLoad 后序触发）→ setInterval(0) → enterFrames（reverse depth）`
- 装扮 publish 延后通道方案：**推荐方向 = `Object.registerClass` + 类 onLoad**（方案 B，详见第 3 节）；mc.onEnterFrame（A）是简易备选；unit.onEnterFrame+队列（C）只在严格交付场景才需要

## 1. 当帧 dispatch 顺序

```
[script phase]
  attachMovie(skin) 同步返回
    ├ mc._x / mc._y / placement 子 MC._x / _y → 已就绪
    └ child.loadedFlag / 子 onClipEvent(load) 写入字段 → 尚未就绪

  脚本块继续执行 ...

  脚本块返回到 player

[load flush phase]
  AVM1 后序遍历 flush load 队列：
    leafChild.onClipEvent(load)         ← 最深叶子
    leaf.onClipEvent(load)
    child.onClipEvent(load)             ← 它内部如果再 attachMovie，
                                          新生 clip 进入下一轮 load 队列
    ...嵌套递归直到无新增...
    [class-bound parent].onLoad()       ← 类方法 ✅ 后序触发（FP20 实测确认）
  MovieClip.onLoad 属性 ❌ 完全不触发（属性路径与类方法路径分离）

[class binding 额外阶段（attachMovie 同步内）]
  Object.registerClass 后 attachMovie：
    1. 创建实例（class-bound）
    2. PlaceObject 子树（_x 等矩阵就绪）
    3. ✅ 类构造函数同步触发（this.child._x 可读，this.child.loadedFlag 未就绪）
    4. attachMovie 返回

[timer phase]
  setInterval(fn, 0) 一次性触发  ← 子树全部就绪

[enterFrame phase]
  高 depth 先：skin2 (9991) → skin1 (9990) → ... → _root  ← 子树全部就绪

[render]
```

## 2. 实测原始 trace（runner 见第 5 节）

### 2.1 第一轮 (2026-05-08)：instance-level 钩子基线

仅用 `mc.onLoad = fn` / `mc.onEnterFrame = fn` 实例属性，未引入 registerClass：

```
[1] === T1: attachMovie TestProbeSkin ===
[2] [T1] after attach mc._x=0 child._x=3.5 loadedFlag=undefined loadedAt=undefined
[3] === T2: attachMovie TestProbeNested ===
[4] [T2] after attach mc._x=0 child._x=3.5 loadedFlag=undefined loadedAt=undefined child.leaf=undef
[5] === frame script end ===
[6] [T4] setInterval(0) skin1 mc._x=0 child._x=3.5 loadedFlag=yes loadedAt=5
[7] [T4] setInterval(0) skin2 mc._x=0 child._x=3.5 loadedFlag=yes loadedAt=5 leaf._x=0 leafChild._x=20.15 leafLoadedFlag=yes
[8] [T2] skin2.onEnterFrame mc._x=0 child._x=3.5 loadedFlag=yes loadedAt=5 leaf._x=0 leafChild._x=20.15 leafLoadedFlag=yes
[9] [T1] skin1.onEnterFrame mc._x=0 child._x=3.5 loadedFlag=yes loadedAt=5
[10] [T3] _root.onEnterFrame skin1 mc._x=0 child._x=3.5 loadedFlag=yes loadedAt=5
[11] [T3] _root.onEnterFrame skin2 mc._x=0 child._x=3.5 loadedFlag=yes loadedAt=5 leaf._x=0 leafChild._x=20.15 leafLoadedFlag=yes
```

关键证据：

- `skin1.onLoad` / `skin2.onLoad` 行**不存在** → onLoad 属性赋值对 attachMovie 失效
- [2] / [4] 的 `loadedFlag=undefined` + [6]+ 的 `loadedAt=5`（== "frame script end" marker）→ load 在脚本返回后 flush
- [7] 的 `leafLoadedFlag=yes` → 二阶嵌套 load 也在 setInterval(0) 之前完成
- [8][9][10] 都在 [6][7] 之后 → enterFrame 排在 setInterval(0) 之后

### 2.2 第二轮 (2026-05-08)：registerClass + 类方法

在 T1/T2 后追加 `Object.registerClass("TestProbeSkin", SkinReadyProbe)` + T5 类绑定 attachMovie：

```
[1] === T1: attachMovie TestProbeSkin (plain) ===
[2] [T1] after attach mc._x=0 child._x=3.5 loadedFlag=undefined loadedAt=undefined
[3] === T2: attachMovie TestProbeNested (plain) ===
[4] [T2] after attach mc._x=0 child._x=3.5 loadedFlag=undefined loadedAt=undefined child.leaf=undef
[5] === T5: registerClass + attachMovie TestProbeSkin (class-bound) ===
[6] [CLS] constructor mc._x=0 child._x=3.5 loadedFlag=undefined loadedAt=undefined
[7] [T5] after attach (class-bound) mc._x=0 child._x=3.5 loadedFlag=undefined loadedAt=undefined
[8] === frame script end ===
[9] [CLS] onLoad mc._x=0 child._x=3.5 loadedFlag=yes loadedAt=8
[10] [T4] setInterval(0) skin1 mc._x=0 child._x=3.5 loadedFlag=yes loadedAt=8
[11] [T4] setInterval(0) skin2 mc._x=0 child._x=3.5 loadedFlag=yes loadedAt=8 leaf._x=0 leafChild._x=20.15 leafLoadedFlag=yes
[12] [T4] setInterval(0) skin3 mc._x=0 child._x=3.5 loadedFlag=yes loadedAt=8
[13] [CLS] onEnterFrame mc._x=0 child._x=3.5 loadedFlag=yes loadedAt=8
[14] [T2] skin2.onEnterFrame mc._x=0 child._x=3.5 loadedFlag=yes loadedAt=8 leaf._x=0 leafChild._x=20.15 leafLoadedFlag=yes
[15] [T1] skin1.onEnterFrame mc._x=0 child._x=3.5 loadedFlag=yes loadedAt=8
[16] [T3] _root.onEnterFrame skin1 mc._x=0 child._x=3.5 loadedFlag=yes loadedAt=8
[17] [T3] _root.onEnterFrame skin2 mc._x=0 child._x=3.5 loadedFlag=yes loadedAt=8 leaf._x=0 leafChild._x=20.15 leafLoadedFlag=yes
[18] [T3] _root.onEnterFrame skin3 mc._x=0 child._x=3.5 loadedFlag=yes loadedAt=8
```

关键证据：

- [6] `[CLS] constructor` 在 [7] `after attach` **之前** → 构造函数同步在 attachMovie 内触发；此时 `child._x=3.5` 已就绪、`child.loadedFlag=undefined` 未就绪
- [9] `[CLS] onLoad` 在 [8] frame script end 之后、[10] setInterval(0) 之前 → **类 onLoad 在 load flush 阶段尾、定时器之前**；`child.loadedFlag=yes loadedAt=8` 说明子 load 已完成
- [13] `[CLS] onEnterFrame` 与 [14][15] instance enterFrame 同阶段（reverse depth：skin3 9992 先于 skin2 9991 / skin1 9990）
- 类方法 `onLoad` ✅ 触发，与 `mc.onLoad = fn` 属性赋值 ❌ 不触发**形成对比**——两条派发路径独立

### 2.3 第三轮 (2026-05-08)：register-attach-unregister 精准 scope 验证

在 T5 后追加 T6a/T6b/T6c：先验证 binding 持续生效，再 `Object.registerClass(name, null)` 解绑，再 attach 一次。

```
[5] === T5: registerClass + attachMovie TestProbeSkin (class-bound) ===
[6] [CLS] constructor mc._x=0 child._x=3.5 loadedFlag=undefined loadedAt=undefined
[7] [T5] after attach (class-bound) ...
[8] === T6a: another attach (registration still active) ===
[9] [CLS] constructor mc._x=0 child._x=3.5 loadedFlag=undefined loadedAt=undefined
[10] [T6a] after attach skin4 (expected class-bound) ...
[11] === T6b: Object.registerClass(TestProbeSkin, null) ===
[12] === T6c: attach after unregister ===
[13] [T6c] after attach skin5 (expected plain) ...     ← 没有 [CLS] constructor 行 ✅
[14] === frame script end ===
[15] [CLS] onLoad mc._x=0 child._x=3.5 loadedFlag=yes loadedAt=14    ← skin3 的 onLoad ✅
[16] [CLS] onLoad mc._x=0 child._x=3.5 loadedFlag=yes loadedAt=15    ← skin4 的 onLoad ✅
                                                                     ← skin5 没有 [CLS] onLoad ✅
[17] [T4] setInterval(0) skin1 ...
[18] [T4] setInterval(0) skin2 ...
[19] [T4] setInterval(0) skin3 ...
[20] [T4] setInterval(0) skin4 ...
[21] [T4] setInterval(0) skin5 ... loadedFlag=yes loadedAt=16        ← skin5.child 仍正常 load
[22] [CLS] onEnterFrame skin4 (depth 9993)                            ← skin3/4 仍走类 enterFrame ✅
[23] [CLS] onEnterFrame skin3 (depth 9992)                            ← skin5 没有 [CLS] onEnterFrame ✅
[24] [T2] skin2.onEnterFrame
[25] [T1] skin1.onEnterFrame
[26-30] [T3] _root.onEnterFrame skin1..skin5
```

关键证据：

- [13] skin5 attach 完成，**无 [CLS] constructor 行** → `Object.registerClass(name, null)` 在 FP20 实测有效，未来 attachMovie 真正解绑
- [15][16] skin3/skin4 的类 `onLoad` 仍按 load flush 顺序触发，loadedAt 显示 child.load 在 onLoad 之前 → **解绑不回溯，已 attach 的实例 class binding 不变**
- [22][23] skin3/skin4 的类 `onEnterFrame` 仍触发，**skin5 完全无 [CLS] enterFrame** → unbound 实例彻底走默认 MovieClip
- [21] skin5.child 仍然 `loadedFlag=yes loadedAt=16` → child placement 的 onClipEvent(load) 与父级 class binding 无关，照常派发
- 同一帧脚本内 `register → attach → register(null) → attach` 干净分离，AVM1 没有奇怪交互

**结论：register-attach-unregister 是真正的 per-attach 精准 scope，不污染其他 unit 的同名 attachMovie。**

## 3. 候选契约方案（设计中，未落地）

需求：装扮 publish 时机要区分两个语义——

- **同步契约**：原生属性就绪。`unit[referenceName]` 引用、`unit[referenceName]._x / _y / _visible / _parent` 等 placement 时刻已写入的字段
- **延后契约**：子树自定义字段就绪。子 MC 在自己 `onClipEvent(load)` 里写入的字段、嵌套 attachMovie 产生的孙级 MC

同步契约通过 `_执行配置` 内 `attachMovie` 紧后 `publish` 已天然成立（当前实现）；延后契约的实现方案待定，下面是候选：

### 方案 B：`Object.registerClass` 类绑定 ⭐ **推荐方向（per-attach scope 变体）**

给装扮 linkage 绑一个共享基类，类的 `onLoad` 方法作为延后钩子。

**两种 scope 变体：**

#### B-全量：startup 期一次性给所有装扮 linkage 绑类

- ✅ 实现最简单：启动期遍历列表 `for (var l in linkages) Object.registerClass(l, cls);`
- ❌ **全局污染**：所有 unit 的 attachMovie 都付出类构造函数 + onLoad 的开销，即便它们没订阅
- ❌ 多个不同配置的人形怪同帧 spawn 时，开销与怪数线性相关而非订阅者数线性相关

#### B-精准：register-attach-unregister 包在 `_执行配置` 里 ✅ **推荐**

`_执行配置` 内每次 attach 检查 `unit.syncRefs[deferredKey]`，仅订阅者临时绑类：

```as
if (unit.syncRefs[deferredKey]) {
    Object.registerClass(skinConfig, SkinReadyClass);
    skin = mc.attachMovie(skinConfig, instanceName, depth,
                          { __unit: unit, __publishKey: deferredKey });
    Object.registerClass(skinConfig, null);  // 立即解绑
} else {
    skin = mc.attachMovie(skinConfig, instanceName, depth);
}
```

- ✅ FP20 实测确认（2.3 节）：register/unregister 干净分离，已 attach 的实例 class binding 不被解绑回溯
- ✅ **per-unit per-attach scope**：未订阅 unit 零开销；订阅 unit 仅为自己付出 ~3us（2 registerClass + 1 构造 + 1 onLoad）
- ✅ 派发时机最早（onLoad 在 load flush 阶段尾，setInterval/enterFrame 之前）
- ✅ 锚点是 class instance 自身，**不依赖 limb 在下一拍 enterFrame 时是否还活着**——比方案 A 在时间轴卸载场景下更稳
- ✅ 同帧多 attachMovie 之间天然独立（每个实例的 onLoad 独立派发）
- ❌ 不能与已存在的 FLA-level `linkageClassName` 共存（unregister 会抹掉原绑定）；**当前装扮 XML 全部无 `linkageClassName`，未触雷**
- ❌ 装备 lifecycle 必须先打 `syncRefs[name + ":ready"]` 标记才会触发临时绑类；这是约定俗成

**生产基类 sketch（不带 onEnterFrame，避免每帧成本）：**

```as
dynamic class org.flashNight.dev.SkinReadyClass extends MovieClip {
    public function SkinReadyClass() {
        // 空构造：initObject (__unit / __publishKey) 由 Flash 注入
    }
    public function onLoad():Void {
        // load 后序末尾：子树（含嵌套 attachMovie）已 ready
        if (this.__unit && this.__publishKey) {
            this.__unit.dispatcher.publish(this.__publishKey, this.__unit);
        }
    }
}
```

### 方案 A：`mc.onEnterFrame` 一次性钩子

`_执行配置` 中 attachMovie 后给 `mc` 挂一次性 onEnterFrame，下一拍派发 `referenceName + ":ready"`。

- ✅ 实现简单（~10 行）；FP20 实测验证；订阅方约定低成本
- ✅ **不需要给 43+ linkage 改 FLA / 注册类**——全部走运行时
- ❌ 交付语义"尽力交付"：limb 在下一拍 enterFrame 前被时间轴卸载（gotoAndStop / PlaceObject 推进），事件丢失
- ❌ 派发时机晚一拍（在 setInterval(0) 与 enterFrame 之间，比方案 B 的 onLoad 晚）

适合作为方案 B 落地之前的过渡 / 备选。

### 方案 C：`unit.onEnterFrame` + 队列 + 活性校验

延后钩子锚到 unit（角色级 MC，不随 state MC 切换消失），多次 deferred 入队批量派发，派发前校验 mc 仍在显示树上。

- ✅ 严格交付：limb 中途被卸载也能 fire；活性校验避免发空事件
- ❌ 实现复杂（~25 行）；需要污染 unit 上一个 queue 字段；要排查 unit.onEnterFrame 是否被其他系统已占用（ParameterInitializer / AI 等）
- ❌ 派发时机最晚（与方案 A 同阶段或更晚）

只在方案 B 不能满足且确实出现 limb 卸载导致丢失事件的具体 bug 时才考虑。

### 决策状态

| 数据点 | 状态 |
|---|---|
| `Object.registerClass` 类 `onLoad` 在 FP20 attachMovie 路径触发？ | ✅ 确认触发（2026-05-08） |
| 构造函数 / onLoad 与子 load 相对顺序？ | ✅ 构造函数 < 子 load < 类 onLoad（2026-05-08） |
| `Object.registerClass(name, null)` 解绑是否成立？ | ✅ 解绑未来 attach 不影响已 attach（2026-05-08） |
| 同帧 register-attach-unregister 是否干净？ | ✅ AVM1 无奇怪交互（2026-05-08） |
| 现有 unit.onEnterFrame 占用情况？ | 待 grep 确认（仅 B-全量变体或方案 C 才需要） |
| 装扮场景 limb 卸载频率与丢失事件的实际痛点？ | 待真实场景观察（无具体 bug 时不优化） |

**方向**：以**方案 B-精准（register-attach-unregister）**为推荐落地路径。剩余调研：

1. 现有装扮 XML 中是否存在 `linkageClassName`（FLA-level 类绑定）——若存在，方案 B-精准 会抹掉；当前抽样 5 个 skin XML 都没有，需扫一遍全量确认
2. 装备 lifecycle 函数的订阅模式 audit：哪些装备需要 `:ready` 通道、各自打 `syncRefs[name + ":ready"] = true` 的位置应放在初始化哪个阶段

## 4. 反模式（不要用）

- `MovieClip.onLoad = fn` 属性赋值配 attachMovie：**不触发**（FP20 实测），bug 难定位
- `setInterval(fn, 0)`：FP20 实测稳，但 timer 队列不属于 frame phase 模型，跨 player 版本不保证
- 在同步 publish 后用 `if (引用.子.子._x === undefined) ...` 判空兜底：当前订阅方临时方案，可接受但不优；待第 3 节延后通道方案确定后应迁移

## 5. 复现步骤

### 夹具（已固化签入仓库）

`scripts/TestLoader/LIBRARY/` 下已存在的 5 个 symbol（**勿改 linkage 名**，runner 依赖它们）：

| Symbol | linkage | 内含 |
|---|---|---|
| `TestProbeSkin` | export | placement `child`，child.placement onClipEvent: `loadedFlag = "yes"; loadedAt = _root.__seq;` |
| `TestProbeNested` | export | placement `child`，child.placement onClipEvent 同上 + `attachMovie("TestProbeLeaf", "leaf", 1)` |
| `TestProbeLeaf` | export | placement `leafChild`，leafChild.placement onClipEvent: `leafLoadedFlag = "yes";` |
| `child` | export | 空容器（仅静态文本占位） |
| `leafChild` | export | 空容器 |

DOMDocument 帧脚本已固定 `#include "../TestLoader.as"`。

### Probe 类（已签入 `scripts/类定义/org/flashNight/dev/SkinReadyProbe.as`）

T5 段依赖此类做 registerClass 测试。如果删除需重新创建（保留 BOM）：

```as
dynamic class org.flashNight.dev.SkinReadyProbe extends MovieClip {
    private var efFired:Boolean;
    public function SkinReadyProbe() {
        this.efFired = false;
        _root["标记"](_root["探测"]("[CLS] constructor", this));
    }
    public function onLoad():Void {
        _root["标记"](_root["探测"]("[CLS] onLoad", this));
    }
    public function onEnterFrame():Void {
        if (this.efFired) return;
        this.efFired = true;
        _root["标记"](_root["探测"]("[CLS] onEnterFrame", this));
    }
}
```

### Runner 代码（粘进 `scripts/TestLoader.as`，**该文件被 .gitignore，写入后记得补 UTF-8 BOM**）

```as
// AS2 attachMovie load 时序闭环探测（FP20）
import org.flashNight.dev.*;

_root.__seq = 0;

_root.标记 = function(msg) {
    var line = "[" + (++_root.__seq) + "] " + msg;
    trace(line);
};

_root.探测 = function(prefix, mc) {
    if (!mc) return prefix + " mc=null";
    var s = prefix
        + " mc._x=" + mc._x
        + " child._x=" + mc.child._x
        + " loadedFlag=" + mc.child.loadedFlag
        + " loadedAt=" + mc.child.loadedAt;
    if (mc.child.leaf) {
        s += " leaf._x=" + mc.child.leaf._x;
        if (mc.child.leaf.leafChild) {
            s += " leafChild._x=" + mc.child.leaf.leafChild._x
               + " leafLoadedFlag=" + mc.child.leaf.leafChild.leafLoadedFlag;
        } else {
            s += " leaf.leafChild=undef";
        }
    } else if (mc._name == "__skin2") {
        s += " child.leaf=undef";
    }
    return s;
};

// T1: 单层 (plain)
_root.标记("=== T1: attachMovie TestProbeSkin (plain) ===");
var skin1 = _root.attachMovie("TestProbeSkin", "__skin1", 9990);
_root.标记(_root.探测("[T1] after attach", skin1));
skin1.onLoad = function() { _root.标记(_root.探测("[T1] skin1.onLoad", this)); delete this.onLoad; };
skin1.onEnterFrame = function() { _root.标记(_root.探测("[T1] skin1.onEnterFrame", this)); delete this.onEnterFrame; };

// T2: 二阶嵌套 (plain)
_root.标记("=== T2: attachMovie TestProbeNested (plain) ===");
var skin2 = _root.attachMovie("TestProbeNested", "__skin2", 9991);
_root.标记(_root.探测("[T2] after attach", skin2));
skin2.onLoad = function() { _root.标记(_root.探测("[T2] skin2.onLoad", this)); delete this.onLoad; };
skin2.onEnterFrame = function() { _root.标记(_root.探测("[T2] skin2.onEnterFrame", this)); delete this.onEnterFrame; };

// T5: registerClass + 类绑定 attachMovie（无 instance-level 钩子，让类方法独立显形）
_root.标记("=== T5: registerClass + attachMovie TestProbeSkin (class-bound) ===");
Object.registerClass("TestProbeSkin", SkinReadyProbe);
var skin3 = _root.attachMovie("TestProbeSkin", "__skin3", 9992);
_root.标记(_root.探测("[T5] after attach (class-bound)", skin3));

// T6a: 注册仍生效，再 attach 一次
_root.标记("=== T6a: another attach (registration still active) ===");
var skin4 = _root.attachMovie("TestProbeSkin", "__skin4", 9993);
_root.标记(_root.探测("[T6a] after attach skin4 (expected class-bound)", skin4));

// T6b: 注销
_root.标记("=== T6b: Object.registerClass(TestProbeSkin, null) ===");
Object.registerClass("TestProbeSkin", null);

// T6c: 解绑后再 attach，期望 plain MovieClip
_root.标记("=== T6c: attach after unregister ===");
var skin5 = _root.attachMovie("TestProbeSkin", "__skin5", 9994);
_root.标记(_root.探测("[T6c] after attach skin5 (expected plain)", skin5));

// T3 / T4: 后置 — 探针扩到 skin1..skin5
_root.onEnterFrame = function() {
    _root.标记(_root.探测("[T3] _root.onEnterFrame skin1", skin1));
    _root.标记(_root.探测("[T3] _root.onEnterFrame skin2", skin2));
    _root.标记(_root.探测("[T3] _root.onEnterFrame skin3", skin3));
    _root.标记(_root.探测("[T3] _root.onEnterFrame skin4", skin4));
    _root.标记(_root.探测("[T3] _root.onEnterFrame skin5", skin5));
    delete this.onEnterFrame;
};
var siId = setInterval(function() {
    clearInterval(siId);
    _root.标记(_root.探测("[T4] setInterval(0) skin1", skin1));
    _root.标记(_root.探测("[T4] setInterval(0) skin2", skin2));
    _root.标记(_root.探测("[T4] setInterval(0) skin3", skin3));
    _root.标记(_root.探测("[T4] setInterval(0) skin4", skin4));
    _root.标记(_root.探测("[T4] setInterval(0) skin5", skin5));
}, 0);

_root.标记("=== frame script end ===");
```

### 跑测试

1. 粘贴上述代码到 `scripts/TestLoader.as`，**确保文件首字节是 UTF-8 BOM `EF BB BF`**（否则 AS2 编译器静默忽略）。一行命令补 BOM：
   ```bash
   python -c "import sys; p='scripts/TestLoader.as'; d=open(p,'rb').read(); open(p,'wb').write(d if d.startswith(b'\xef\xbb\xbf') else b'\xef\xbb\xbf'+d)"
   ```
2. 确认 `scripts/类定义/org/flashNight/dev/SkinReadyProbe.as` 存在且有 BOM（T5 段依赖）。
3. 在 Flash CS6 把 `scripts/TestLoader.fla` 设为活动文档（自动化编译链路依赖此前提，详见 `scripts/FlashCS6自动化编译.md`）。
4. `bash scripts/compile_test.sh` → testMovie 触发 + trace 抓取（输出在 `compile_output.txt` 的 `=== FLASH TRACE OUTPUT ===` 段）。
5. 期望输出与第 2.2 节一致；偏离则说明 player 版本或夹具结构变化，重新校准本文档。
