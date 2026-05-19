import org.flashNight.arki.unit.UnitComponent.Routing.*;

/**
 * MockMovieClip — 路由黑箱夹具的核心 stub
 *
 * 模拟 4 个 AS2 MovieClip 黑箱行为，覆盖契约（[路由系统-黑箱夹具契约.md](../../../../../../../docs/路由系统-黑箱夹具契约.md)）：
 *
 *   §2 attachMovie + initObject 同步 enumerate + copy
 *   §3 onUnload chain（多层叠加 / 父级触发 / 级联子级）
 *   §4 removeMovieClip 幂等 + detached 签名
 *   §1 gotoAndStop frameEpoch 双层 token（旧帧 owned context poison）
 *
 * 与生产代码的接合方式：
 *   - 低层走 RoutingRuntime.setAttachMovieAdapterForTest(MockMovieClip 实例)
 *   - 任何 child MockMovieClip 也实现同一接口（attachMovie / removeMovieClip / gotoAndStop /
 *     onUnload），让端到端样例能在多层 mc tree 上跑
 *
 * ════════════════════════════════════════════════════════════════════
 * 公开 API（生产代码侧调用，模拟 MovieClip 语义）
 * ════════════════════════════════════════════════════════════════════
 *
 *   attachMovie(linkage, name, depth, init):MockMovieClip|undefined
 *       - linkage 在 __missingSymbols 中标记 → 返回 undefined
 *       - 否则 new MockMovieClip()，同步 enumerate + copy init own properties
 *       - 注册到 __children[name] 并暴露为 this[name]（mimics Flash MovieClip）
 *
 *   removeMovieClip():Void
 *       - 幂等（__removed 后再调 no-op）
 *       - 顺序：子级递归 removeMovieClip → 自身 onUnload → 标记 __removed → 从 parent 解绑
 *       - 调用方持有的引用进入 detached 状态：__parent=undefined, __children={}
 *
 *   gotoAndStop(label):Void
 *       - 仅记录 __lastLabel + __frameEpoch++
 *       - 不主动 remove 子级（生产语义：__stateTransitionJob 控制 attach 时序，
 *         attachMovie 出的子 mc 跨 gotoAndStop 存活由调用方掌握）
 *
 *   onUnload  — 生产代码可赋值 / 链式叠加（this.onUnload = function() { ... }）
 *
 * ════════════════════════════════════════════════════════════════════
 * 测试断言/查询 API（下划线前缀，与生产代码无冲突）
 * ════════════════════════════════════════════════════════════════════
 *
 *   __name / __depth / __parent / __removed     — 身份与生命周期状态
 *   __children                                  — name → MockMovieClip 字典
 *   __initObjectsReceived                       — attachMovie 调用历史快照
 *   __unloadCallCount                           — onUnload 触发次数
 *   __lastLabel / __frameEpoch                  — gotoAndStop 状态
 *   __setMissingSymbol(linkage) / __clearMissingSymbol(linkage)
 *                                               — 模拟 linkage 不存在
 *   __snapshotInitObject(o):Object              — 深一层 own-props 快照（测试 helper）
 *
 * ════════════════════════════════════════════════════════════════════
 * 实现纪律
 * ════════════════════════════════════════════════════════════════════
 *   - 字段一律在 ctor 初始化，避免 AS2 field-level init 的"共享 {}"陷阱
 *   - removeMovieClip 子级遍历前 snapshot 数组，避免迭代中 mutation
 *   - 子级 detach 前先看 parent.__removed，避免 cascade 路径反向 delete 干扰
 */
// dynamic: 业务代码会通过 parent[name] 访问 attachMovie 注册的子级（mimics
// MovieClip 的 dynamic 子访问语义），strict mode 下需 `dynamic` 关键字放行。
dynamic class org.flashNight.arki.unit.UnitComponent.Routing.MockMovieClip {

    // ──── 身份 ────
    public var __name:String;
    public var __depth:Number;
    public var __parent:Object;
    public var __removed:Boolean;

    // ──── attachMovie 状态 ────
    public var __children:Object;
    public var __initObjectsReceived:Array;
    public var __missingSymbols:Object;

    // ──── gotoAndStop / gotoAndPlay 状态 ────
    public var __lastLabel:String;
    public var __lastLabelOp:String;  // "stop" / "play"
    public var __frameEpoch:Number;

    // ──── onUnload 状态 ────
    public var __unloadCallCount:Number;

    // ──── 生产 handler ────
    public var onUnload:Function;

    public function MockMovieClip() {
        this.__name = undefined;
        this.__depth = 0;
        this.__parent = undefined;
        this.__removed = false;
        this.__children = {};
        this.__initObjectsReceived = [];
        this.__missingSymbols = {};
        this.__lastLabel = undefined;
        this.__lastLabelOp = undefined;
        this.__frameEpoch = 0;
        this.__unloadCallCount = 0;
        this.onUnload = undefined;
    }

    // ════════════════════════════════════════════════════════════════════
    // 公开 API（mimics MovieClip）
    // ════════════════════════════════════════════════════════════════════

    public function attachMovie(linkage:String, name:String, depth:Number, init:Object) {
        // 模拟 missing symbol
        if (this.__missingSymbols[linkage] === true) {
            this.__initObjectsReceived.push({
                linkage: linkage, name: name, depth: depth,
                init: __snapshotInitObject(init),
                missing: true
            });
            return undefined;
        }

        // 同名 child 覆盖 — 真实 Flash 会卸载旧的，本 mock 走显式 removeMovieClip 以保留 onUnload 语义
        var existing:Object = this.__children[name];
        if (existing != undefined) {
            existing.removeMovieClip();
        }

        var child:MockMovieClip = new MockMovieClip();
        child.__name = name;
        child._name = name;       // AS2 真实字段：业务可走 mc._name == "man" 判定
        child.__depth = depth;
        child.__parent = this;
        child._parent = this;     // AS2 真实字段：业务可走 mc._parent 反向引用 / detached signature

        // 同步 enumerate + copy init own properties（与 AS2 attachMovie 语义一致）
        if (init != undefined) {
            for (var k:String in init) {
                child[k] = init[k];
            }
        }

        this.__children[name] = child;
        this[name] = child;  // 暴露为 own property，业务代码可走 parent.man.xxx

        this.__initObjectsReceived.push({
            linkage: linkage, name: name, depth: depth,
            init: __snapshotInitObject(init),
            missing: false
        });
        return child;
    }

    public function removeMovieClip():Void {
        if (this.__removed) return;  // 幂等

        // 1. 提前标记 __removed + detach parent
        //    重要：在调用 onUnload 之前完成，让 handler 内的递归 removeMovieClip 直接走幂等 no-op，
        //    并让 detached 签名（__removed=true / __parent=undefined / _parent=undefined）在
        //    onUnload 内可见 — 与契约 §3 "onUnload 内调用 this.removeMovieClip() no-op"
        //    + [[feedback-as2-detached-mc-signature]] 一致。
        this.__removed = true;
        var oldParent:Object = this.__parent;
        this.__parent = undefined;
        this._parent = undefined;  // AS2 真实字段：detached signature 的关键观察点
        if (oldParent != undefined && oldParent.__removed !== true) {
            if (oldParent.__children != undefined && this.__name != undefined) {
                delete oldParent.__children[this.__name];
                delete oldParent[this.__name];
            }
        }

        // 2. snapshot 子级列表 → 子先于父递归 remove
        var childList:Array = [];
        for (var k:String in this.__children) {
            childList.push(this.__children[k]);
        }
        this.__children = {};

        // 3. 子级递归 remove（已 __removed=true，子级 detach 时看到 parent.__removed → 不反向 delete）
        for (var i:Number = 0; i < childList.length; i++) {
            var c:MockMovieClip = MockMovieClip(childList[i]);
            c.removeMovieClip();
        }

        // 4. 自身 onUnload（此时 detached 签名已建立）
        if (typeof this.onUnload === "function") {
            this.__unloadCallCount++;
            this.onUnload();
        }
    }

    public function gotoAndStop(label):Void {
        if (this.__removed) return;
        this.__lastLabel = label;
        this.__lastLabelOp = "stop";
        this.__frameEpoch++;
    }

    /**
     * gotoAndPlay — 与 gotoAndStop 同 bump frameEpoch（行为差异由调用方观察 __lastLabelOp）。
     *
     * 真实 Flash 中 gotoAndPlay 也会卸载当前帧元件（跟 gotoAndStop 同样属于"帧跳转 +
     * 重建时间轴元件"），所以本 mock 也 bump frameEpoch 保留 §1 旧帧 owned-context
     * poison 的可观察性。子级是否 remove 仍交由调用方控制（§1 决议）。
     */
    public function gotoAndPlay(label):Void {
        if (this.__removed) return;
        this.__lastLabel = label;
        this.__lastLabelOp = "play";
        this.__frameEpoch++;
    }

    // ════════════════════════════════════════════════════════════════════
    // 测试断言/查询 API
    // ════════════════════════════════════════════════════════════════════

    public function __setMissingSymbol(linkage:String):Void {
        this.__missingSymbols[linkage] = true;
    }

    public function __clearMissingSymbol(linkage:String):Void {
        delete this.__missingSymbols[linkage];
    }

    /**
     * 单层 own-property snapshot，避免 __initObjectsReceived 共享对象引用。
     * 不递归，足够覆盖 RoutingFieldMap 的扁平 init 装配。
     */
    public static function __snapshotInitObject(o:Object):Object {
        if (o == undefined) return undefined;
        var copy:Object = {};
        for (var k:String in o) copy[k] = o[k];
        return copy;
    }

    /**
     * §1 强契约 helper：检查 mc 当前的 __frameEpoch 是否仍等于 token。
     *
     * 用法（业务代码若错误地从旧帧闭包持有引用，应显式 snapshot epoch token）：
     *
     *   var oldMan = self.man;
     *   var oldEpoch:Number = oldMan.__frameEpoch;
     *   self.gotoAndStop("X");                                       // __frameEpoch++
     *   if (!MockMovieClip.__requireCurrentEpoch(oldMan, oldEpoch)) {
     *       // 旧帧 owned context — 业务代码不应在此触达 oldMan 的方法 / 字段
     *   }
     *
     * 返回 false 表示 mc 已 detached（__removed），或 epoch 已 advance 过 token。
     * 返回 true 表示 token 仍有效（同帧上下文）。
     *
     * 注：本 helper 是**反向断言工具**，不强制 poison 任何引用 — 实际 poison 与否由
     * 调用方根据返回值自决（trace warning / 跳过、assert FAIL、降级走 fallback）。
     */
    public static function __requireCurrentEpoch(mc:Object, token:Number):Boolean {
        if (mc == undefined) return false;
        if (mc.__removed === true) return false;
        if (mc.__frameEpoch == undefined) return false;
        return mc.__frameEpoch === token;
    }
}