import org.flashNight.gesh.tooltip.NativeTooltipBridge;
import org.flashNight.gesh.tooltip.NativeTooltipDocument;

/**
 * NativeTooltipBridgeTest - 原生注释出口测试
 *
 * 重点：requestId/sceneId 走共享 NativeInteractionContext（ni:<n>）、
 * show/hide 载荷形状、迟到 hide 不消费新实例、通道不可用回退、reset；
 * owner anchorRect（真实 MovieClip getBounds(_root) / 无效或缺失回退）、
 * 已编译 ItemIcon.prototype.RollOver 幂等 patch 与 _scopedOwner 捕获/清理。
 *
 * 测试通过 _root.server 桩 + _global 路径桩 NativeInteractionContext /
 * _global...itemIcon.ItemIcon 伪类隔离真实宿主与真实 ItemIcon。
 */
class org.flashNight.gesh.tooltip.test.NativeTooltipBridgeTest {

    public static var testsRun:Number = 0;
    public static var testsPassed:Number = 0;
    public static var testsFailed:Number  = 0;

    // 桩状态（sendTaskToNode 闭包可达的公开静态字段）
    public static var recorded:Array = null;
    public static var sendResult:Boolean = true;
    public static var ctxSeq:Number = 0;
    public static var ctxScene:String = "sc.test.1";
    public static var registeredTeardown:Function = null;

    // 伪 ItemIcon 桩状态（prototype.RollOver 闭包可达的公开静态字段）
    public static var fakeRollOverCalls:Number = 0;
    public static var fakeThisOk:Boolean = false;
    public static var fakeArgCount:Number = -1;
    public static var fakeInstance:Object = null;

    private static var _savedServer = undefined;
    private static var _savedCtx = undefined;
    private static var _createdNs:Boolean = false;
    private static var _savedItemIconNs = undefined;

    private static function assert(cond:Boolean, msg:String):Void {
        testsRun++;
        if (cond) { testsPassed++; trace("[PASS] " + msg); }
        else { testsFailed++; trace("[FAIL] " + msg); }
    }

    private static function assertEq(expected, actual, msg:String):Void {
        testsRun++;
        if (expected === actual) { testsPassed++; trace("[PASS] " + msg); }
        else { testsFailed++; trace("[FAIL] " + msg + " expected=" + expected + " actual=" + actual); }
    }

    private static function assertClose(expected:Number, actual:Number, msg:String):Void {
        testsRun++;
        if (!isNaN(actual) && Math.abs(actual - expected) < 0.01) {
            testsPassed++; trace("[PASS] " + msg);
        } else { testsFailed++; trace("[FAIL] " + msg + " expected=" + expected + " actual=" + actual); }
    }

    /** 真实 MovieClip owner：空剪辑 + Drawing API 填充矩形 + _root 系位移。 */
    private static function makeOwnerMc(name:String, x:Number, y:Number, w:Number, h:Number):MovieClip {
        var mc:MovieClip = _root.createEmptyMovieClip(name, _root.getNextHighestDepth());
        mc.beginFill(0xFF0000, 100);
        mc.moveTo(0, 0);
        mc.lineTo(w, 0);
        mc.lineTo(w, h);
        mc.lineTo(0, h);
        mc.lineTo(0, 0);
        mc.endFill();
        mc._x = x;
        mc._y = y;
        var bounds:Object = mc.getBounds(_root);
        trace("[ANCHOR_PROBE] root=" + typeof _root + " mc=" + typeof mc
            + " depth=" + _root.getNextHighestDepth() + " method=" + typeof mc.getBounds
            + " btype=" + typeof bounds + " bnull=" + (bounds == null)
            + " bounds=" + bounds.xMin + "," + bounds.yMin + "," + bounds.xMax + "," + bounds.yMax);
        return mc;
    }

    // ── 桩安装/拆除 ──

    private static function installMock():Void {
        recorded = [];
        sendResult = true;
        ctxSeq = 0;
        ctxScene = "sc.test.1";

        _savedServer = _root.server;
        _root.server = {
            isSocketConnected: true,
            sendTaskToNode: function(type, payload, cb):Boolean {
                org.flashNight.gesh.tooltip.test.NativeTooltipBridgeTest.recorded.push(
                    {type:type, payload:payload});
                return org.flashNight.gesh.tooltip.test.NativeTooltipBridgeTest.sendResult;
            }
        };

        // 共享身份桩：getSceneId()/nextRequestId() → ni:<n>
        var g:Object = _global;
        if (g.org == null) g.org = {};
        if (g.org.flashNight == null) g.org.flashNight = {};
        if (g.org.flashNight.arki == null) g.org.flashNight.arki = {};
        var ns:Object = g.org.flashNight.arki;
        if (ns.interaction == null) {
            ns.interaction = {};
            _createdNs = true;
        } else {
            _createdNs = false;
        }
        _savedCtx = ns.interaction.NativeInteractionContext;
        ns.interaction.NativeInteractionContext = {
            getSceneId: function():String {
                return org.flashNight.gesh.tooltip.test.NativeTooltipBridgeTest.ctxScene;
            },
            nextRequestId: function():String {
                return "ni:" + (++org.flashNight.gesh.tooltip.test.NativeTooltipBridgeTest.ctxSeq);
            },
            onSceneTeardown: function(fn:Function):Void {
                org.flashNight.gesh.tooltip.test.NativeTooltipBridgeTest.registeredTeardown = fn;
            }
        };
    }

    private static function teardownMock():Void {
        if (_savedServer != undefined && _savedServer != null) {
            _root.server = _savedServer;
        } else {
            delete _root.server;
        }
        _savedServer = undefined;

        var ns:Object = (_global.org != null && _global.org.flashNight != null
            && _global.org.flashNight.arki != null)
            ? _global.org.flashNight.arki : null;
        if (ns != null && ns.interaction != null) {
            if (_savedCtx != undefined) {
                ns.interaction.NativeInteractionContext = _savedCtx;
            } else {
                delete ns.interaction.NativeInteractionContext;
            }
            if (_createdNs) delete ns.interaction;
        }
        _savedCtx = undefined;
        _createdNs = false;

        recorded = null;
    }

    // ── 用例 ──

    public static function runAllTests():Void {
        testsRun = testsPassed = testsFailed = 0;
        trace("--- NativeTooltipBridgeTest ---");

        installMock();
        test_show_payloadShape();
        test_teardownRegistered();
        test_show_monotonicIds();
        test_hide_current();
        test_hide_lateRequestKeepsNew();
        test_sendFailure_noActive();
        test_reset_clears();
        test_show_anchorRect_realOwner();
        test_show_anchorRect_invalidOrMissing();
        test_itemIconPatch_idempotentScoped();
        teardownMock();

        test_unavailable_noServer();
        test_unavailable_noContext();

        trace("--- NativeTooltipBridgeTest: " + testsPassed + "/" + testsRun + " passed, " + testsFailed + " failed ---");
    }

    private static function test_show_payloadShape():Void {
        var doc:Object = NativeTooltipDocument.buildBody("<B>提示</B>", null);
        // _global 解析回归：AVM1 的 _global 特殊对象与 null 宽松比较为真，
        // context() 曾以 (g==null||...) 误拒真实环境；桩就绪时 isAvailable 必须为 true。
        assert(NativeTooltipBridge.isAvailable() === true,
            "isAvailable: stubbed server + ctx 通道就绪");
        var reqId:String = NativeTooltipBridge.show(doc);
        assertEq("ni:1", reqId, "show: returns ctx requestId");
        assertEq("ni:1", NativeTooltipBridge.activeRequestId(), "show: active requestId");
        assertEq("sc.test.1", NativeTooltipBridge.activeSceneId(), "show: active sceneId");

        assertEq(1, recorded.length, "show: one sendTaskToNode call");
        var rec:Object = recorded[0];
        assertEq("native_interaction", rec.type, "show: task type");
        var p:Object = rec.payload;
        assertEq("tooltip", p.kind, "show: kind");
        assertEq("show", p.op, "show: op");
        assertEq(1, p.version, "show: version");
        assertEq("ni:1", p.requestId, "show: payload requestId");
        assertEq("sc.test.1", p.sceneId, "show: payload sceneId");
        assert(p.x != undefined && p.y != undefined, "show: x/y anchor present");
        assertEq(doc, p.document, "show: document passed through by reference");
    }

    private static function test_teardownRegistered():Void {
        // 首次 show 时桥已把 reset 注册进共享上下文的场景 teardown（只注册一次）
        assert(registeredTeardown != null, "teardown: registered on first show");
        var cur:String = NativeTooltipBridge.show(NativeTooltipDocument.buildBody("x", null));
        registeredTeardown.call(null);
        assert(NativeTooltipBridge.activeRequestId() == null, "teardown: active cleared");
        var p:Object = recorded[recorded.length - 1].payload;
        assertEq("hide", p.op, "teardown: hide op");
        assertEq(cur, p.requestId, "teardown: hide matches shown id");
    }

    private static function test_show_monotonicIds():Void {
        var a:String = NativeTooltipBridge.show(NativeTooltipDocument.buildBody("A", null));
        var b:String = NativeTooltipBridge.show(NativeTooltipDocument.buildBody("B", null));
        assert(a.indexOf("ni:") == 0, "mono: id has ni: prefix");
        assert(Number(a.substring(3)) + 1 == Number(b.substring(3)),
            "mono: shared counter increments (a=" + a + " b=" + b + ")");
        assertEq(b, NativeTooltipBridge.activeRequestId(), "mono: active = latest");
    }

    private static function test_hide_current():Void {
        var reqId:String = NativeTooltipBridge.show(NativeTooltipDocument.buildBody("x", null));
        var n0:Number = recorded.length;
        assert(NativeTooltipBridge.hideCurrent() === true, "hideCurrent: sent");
        assertEq(n0 + 1, recorded.length, "hideCurrent: one call");
        var p:Object = recorded[recorded.length - 1].payload;
        assertEq("hide", p.op, "hideCurrent: op");
        assertEq(reqId, p.requestId, "hideCurrent: matches shown requestId");
        assertEq("sc.test.1", p.sceneId, "hideCurrent: carries sceneId");
        assert(NativeTooltipBridge.activeRequestId() == null, "hideCurrent: active cleared");
        // 无活跃实例时不再发报
        assert(NativeTooltipBridge.hideCurrent() === false, "hideCurrent: no active → false");
        assertEq(n0 + 1, recorded.length, "hideCurrent: no extra send");
    }

    private static function test_hide_lateRequestKeepsNew():Void {
        var a:String = NativeTooltipBridge.show(NativeTooltipDocument.buildBody("A", null));
        var b:String = NativeTooltipBridge.show(NativeTooltipDocument.buildBody("B", null));
        // 迟到的 hide（旧 requestId）：仍下发给宿主按身份匹配，但不消费新实例状态
        assert(NativeTooltipBridge.hide(a) === true, "lateHide: stale id still sent");
        var p:Object = recorded[recorded.length - 1].payload;
        assertEq(a, p.requestId, "lateHide: stale id in payload");
        assert(p.sceneId == undefined, "lateHide: stale hide carries no sceneId");
        assertEq(b, NativeTooltipBridge.activeRequestId(), "lateHide: new instance still active");
        // 当前实例 hide 正常
        assert(NativeTooltipBridge.hideCurrent() === true, "lateHide: current hide sent");
        assert(NativeTooltipBridge.activeRequestId() == null, "lateHide: cleared after current hide");
    }

    private static function test_sendFailure_noActive():Void {
        sendResult = false;
        var reqId:String = NativeTooltipBridge.show(NativeTooltipDocument.buildBody("x", null));
        assert(reqId == null, "sendFail: show returns null");
        assert(NativeTooltipBridge.activeRequestId() == null, "sendFail: no active state");
        sendResult = true;
    }

    private static function test_reset_clears():Void {
        NativeTooltipBridge.show(NativeTooltipDocument.buildBody("x", null));
        NativeTooltipBridge.reset();
        assert(NativeTooltipBridge.activeRequestId() == null, "reset: active cleared");
        assert(NativeTooltipBridge.activeSceneId() == null, "reset: scene cleared");
        var p:Object = recorded[recorded.length - 1].payload;
        assertEq("hide", p.op, "reset: hide sent for active instance");
    }

    private static function test_unavailable_noServer():Void {
        // 无 _root.server：show/hide 返回空值，调用方走旧渲染回退
        var saved = _root.server;
        delete _root.server;
        assert(NativeTooltipBridge.isAvailable() === false, "noServer: unavailable");
        assert(NativeTooltipBridge.show(NativeTooltipDocument.buildBody("x", null)) == null,
            "noServer: show null");
        assert(NativeTooltipBridge.hideCurrent() === false, "noServer: hide false");
        if (saved != undefined) _root.server = saved;
    }

    private static function test_unavailable_noContext():Void {
        // server 就绪但共享上下文类缺失：show 返回 null（不伪造身份）
        var saved = _root.server;
        _root.server = {
            isSocketConnected: true,
            sendTaskToNode: function(type, payload, cb):Boolean { return true; }
        };
        var ns:Object = (_global.org != null && _global.org.flashNight != null
            && _global.org.flashNight.arki != null && _global.org.flashNight.arki.interaction != null)
            ? _global.org.flashNight.arki.interaction : null;
        var hadCtx:Boolean = (ns != null && ns.NativeInteractionContext != undefined);
        var savedCtx = hadCtx ? ns.NativeInteractionContext : undefined;
        if (hadCtx) delete ns.NativeInteractionContext;

        assert(NativeTooltipBridge.isAvailable() === false, "noCtx: unavailable");
        assert(NativeTooltipBridge.show(NativeTooltipDocument.buildBody("x", null)) == null,
            "noCtx: show null");

        if (hadCtx) ns.NativeInteractionContext = savedCtx;
        if (saved != undefined) _root.server = saved; else delete _root.server;
    }

    private static function test_show_anchorRect_realOwner():Void {
        var mc:MovieClip = makeOwnerMc("ntbOwner1", 100, 50, 40, 30);
        var doc:Object = NativeTooltipDocument.buildBody("锚点", null);
        var reqId:String = NativeTooltipBridge.show(doc, mc);
        assert(reqId != null, "anchor: show returns requestId");
        var p:Object = recorded[recorded.length - 1].payload;
        assert(p.anchorRect != undefined, "anchor: anchorRect present for real owner");
        assertClose(100, p.anchorRect.x, "anchor: x = owner bounds xMin");
        assertClose(50, p.anchorRect.y, "anchor: y = owner bounds yMin");
        assertClose(40, p.anchorRect.width, "anchor: width");
        assertClose(30, p.anchorRect.height, "anchor: height");
        assertEq(doc, p.document, "anchor: document still passthrough");
        assert(p.x != undefined && p.y != undefined, "anchor: pointer x/y retained");

        // placement 白名单：合法值透传，非法值省略
        NativeTooltipBridge.show(doc, mc, "right");
        p = recorded[recorded.length - 1].payload;
        assertEq("right", p.placement, "anchor: valid placement forwarded");
        NativeTooltipBridge.show(doc, mc, "bogus");
        p = recorded[recorded.length - 1].payload;
        assert(p.placement === undefined, "anchor: invalid placement omitted");

        mc.removeMovieClip();
        NativeTooltipBridge.hideCurrent();
    }

    private static function test_show_anchorRect_invalidOrMissing():Void {
        var doc:Object = NativeTooltipDocument.buildBody("x", null);
        // 无 owner：旧 payload 契约（无 anchorRect 字段）
        NativeTooltipBridge.show(doc);
        var p:Object = recorded[recorded.length - 1].payload;
        assert(p.anchorRect === undefined, "anchor: missing owner → no anchorRect");
        assert(p.x != undefined && p.document === doc, "anchor: old payload fields intact");

        // 非 MovieClip owner（无 getBounds）→ 省略
        var notMc = {};
        NativeTooltipBridge.show(doc, MovieClip(notMc));
        p = recorded[recorded.length - 1].payload;
        assert(p.anchorRect === undefined, "anchor: non-MC owner → no anchorRect");

        // getBounds 返回退化矩形（零宽高）→ 省略
        var liarMc = {getBounds: function(target) {
            return {xMin: 0, yMin: 0, xMax: 0, yMax: 0};
        }};
        NativeTooltipBridge.show(doc, MovieClip(liarMc));
        p = recorded[recorded.length - 1].payload;
        assert(p.anchorRect === undefined, "anchor: zero-size bounds → no anchorRect");

        // 空 MovieClip（无内容，退化边界）→ 省略
        var empty:MovieClip = _root.createEmptyMovieClip("ntbEmpty", _root.getNextHighestDepth());
        NativeTooltipBridge.show(doc, empty);
        p = recorded[recorded.length - 1].payload;
        assert(p.anchorRect === undefined, "anchor: empty mc → no anchorRect");
        empty.removeMovieClip();
        NativeTooltipBridge.hideCurrent();
    }

    private static function test_itemIconPatch_idempotentScoped():Void {
        var ownerMc:MovieClip = makeOwnerMc("ntbOwner2", 200, 120, 24, 24);
        var doc:Object = NativeTooltipDocument.buildBody("item", null);

        // 伪 ItemIcon 类：仿已编译产物——prototype.RollOver 无 owner 实参调桥、
        // getIconMovieClip() 返回图标 MC。经 _global 命名空间登记，用完还原。
        var itemNs:Object = _global.org.flashNight.arki.item;
        if (itemNs == null) { itemNs = {}; _global.org.flashNight.arki.item = itemNs; }
        _savedItemIconNs = itemNs.itemIcon;
        itemNs.itemIcon = {};
        var Ctor:Function = function() {};
        Ctor.prototype.getIconMovieClip = function():MovieClip { return this.__ownerMc; };
        Ctor.prototype.RollOver = function():Void {
            var T = org.flashNight.gesh.tooltip.test.NativeTooltipBridgeTest;
            T.fakeRollOverCalls++;
            T.fakeThisOk = (this === T.fakeInstance);
            T.fakeArgCount = arguments.length;
            org.flashNight.gesh.tooltip.NativeTooltipBridge.show(this.__doc);
        };
        itemNs.itemIcon.ItemIcon = Ctor;

        var inst:Object = new Ctor();
        inst.__ownerMc = ownerMc;
        inst.__doc = doc;
        fakeInstance = inst;
        fakeRollOverCalls = 0;
        fakeThisOk = false;
        fakeArgCount = -1;

        var origRollOver:Function = Ctor.prototype.RollOver;
        NativeTooltipBridge.install();
        var patched:Function = Ctor.prototype.RollOver;
        assert(patched !== origRollOver, "patch: prototype.RollOver wrapped");
        NativeTooltipBridge.install();
        assert(Ctor.prototype.RollOver === patched,
            "patch: second install keeps same wrapper (idempotent, no recursive wrap)");

        var n0:Number = recorded.length;
        inst.RollOver("probe", 42);
        assertEq(1, fakeRollOverCalls, "patch: original RollOver invoked exactly once");
        assert(fakeThisOk === true, "patch: original this = ItemIcon instance");
        assertEq(2, fakeArgCount, "patch: arguments forwarded via apply");
        assertEq(n0 + 1, recorded.length, "patch: original forwarded show() to host");
        var p:Object = recorded[recorded.length - 1].payload;
        assert(p.anchorRect != undefined, "patch: scoped owner produced anchorRect");
        assertClose(200, p.anchorRect.x, "patch: anchor x from scoped owner");
        assertClose(120, p.anchorRect.y, "patch: anchor y from scoped owner");
        assertClose(24, p.anchorRect.width, "patch: anchor w");
        assertClose(24, p.anchorRect.height, "patch: anchor h");

        // 调用结束后 _scopedOwner 已恢复：无参 show 回到旧 payload
        NativeTooltipBridge.show(doc);
        p = recorded[recorded.length - 1].payload;
        assert(p.anchorRect === undefined, "patch: scopedOwner cleared after call");

        if (_savedItemIconNs != undefined) itemNs.itemIcon = _savedItemIconNs;
        else delete itemNs.itemIcon;
        _savedItemIconNs = undefined;
        fakeInstance = null;
        ownerMc.removeMovieClip();
        NativeTooltipBridge.hideCurrent();
    }
}
