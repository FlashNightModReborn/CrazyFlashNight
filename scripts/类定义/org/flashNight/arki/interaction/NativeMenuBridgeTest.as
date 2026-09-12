import org.flashNight.arki.interaction.NativeMenuBridge;

/**
 * NativeMenuBridgeTest - NPC 功能菜单兼容桥行为测试（focused runner 用）
 *
 * 覆盖：旧 NPC 五连写只在显式 刷新显示() 时发布；占位两菜单不产生请求；
 *   action 一次性消费；迟到/重复/错误 sceneId/错误 actionId/跨 kind cancel
 *   拒绝；同场景同名目标重建拒绝；场景 teardown 撤销；动作可用性变化拒绝；
 *   任务/雇佣/商店(resolve 路由)/技能调用点保真；无 socket 时 Flash 回退。
 *
 * 隔离方式：_global 路径桩替换 NativeInteractionContext / NativeTooltipBridge
 *   （桥内全限定名调用经 _global 运行期解析，桩自然拦截），_root.server /
 *   gameworld / gameCommands / 路由函数全部可恢复桩；临时 MovieClip 作
 *   authored 菜单体；测试结束统一恢复，不触真实存档。
 */
class org.flashNight.arki.interaction.NativeMenuBridgeTest {

    public static var testsRun:Number = 0;
    public static var testsPassed:Number = 0;
    public static var testsFailed:Number = 0;

    // 桩状态（闭包可达的公开静态字段）
    public static var recorded:Array = null;       // {type, payload}
    public static var sendResult:Boolean = true;
    public static var ctxSeq:Number = 0;
    public static var ctxScene:String = "sc.test.1";
    public static var ctxWorldOk:Boolean = true;
    public static var teardowns:Array = null;
    public static var tipInstalled:Number = 0;
    public static var calls:Object = null;         // 路由调用记录
    public static var shopOpenResult:Boolean = true;

    private static var _saved:Object = null;
    private static var _savedCtx = undefined;
    private static var _savedTip = undefined;
    private static var _savedTipNs:Object = null;
    private static var _menuMc:MovieClip = null;
    private static var _viewMc:MovieClip = null;
    private static var _modifyMc:MovieClip = null;
    private static var _npcA:Object = null;

    private static var ROOT_KEYS:Array = [
        "server", "gameworld", "gameCommands", "__nativeMenu",
        "NPC功能菜单", "查看详细菜单", "修改详细菜单",
        "对话赋值到对话框", "数组洗牌", "发布消息", "获得翻译",
        "getTaskData", "openSkillTrainer", "UI系统", "受雇欲望基准"
    ];

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

    // ── 桩安装/拆除 ─────────────────────────────────────────────

    private static function resetCalls():Void {
        recorded = [];
        sendResult = true;
        calls = {
            dlg:0, dlgArg:undefined, shuffle:0, msg:[],
            taskData:[], webDungeon:[], npcShop:[], webHire:[],
            skill:0, skillArg:undefined, skillNpc:undefined, resolve:0
        };
        shopOpenResult = true;
    }

    private static function installMock():Void {
        resetCalls();
        ctxSeq = 0;
        ctxScene = "sc.test.1";
        ctxWorldOk = true;
        teardowns = [];
        tipInstalled = 0;

        _saved = {};
        for (var i:Number = 0; i < ROOT_KEYS.length; i++) {
            _saved[ROOT_KEYS[i]] = _root[ROOT_KEYS[i]];
        }

        // 共享身份上下文桩（_global 路径替换，拦截桥内全限定名调用）
        var g:Object = _global;
        if (g.org == null) g.org = {};
        if (g.org.flashNight == null) g.org.flashNight = {};
        if (g.org.flashNight.arki == null) g.org.flashNight.arki = {};
        var ns:Object = g.org.flashNight.arki;
        if (ns.interaction == null) ns.interaction = {};
        _savedCtx = ns.interaction.NativeInteractionContext;
        ns.interaction.NativeInteractionContext = {
            install: function():Void {},
            getSceneId: function():String {
                return org.flashNight.arki.interaction.NativeMenuBridgeTest.ctxScene;
            },
            getSceneIdentity: function():Object { return {fake:1}; },
            isCurrentWorld: function(w:Object):Boolean {
                return org.flashNight.arki.interaction.NativeMenuBridgeTest.ctxWorldOk;
            },
            nextRequestId: function():String {
                return "ni:" + (++org.flashNight.arki.interaction.NativeMenuBridgeTest.ctxSeq);
            },
            onSceneTeardown: function(fn:Function):Void {
                org.flashNight.arki.interaction.NativeMenuBridgeTest.teardowns.push(fn);
            }
        };

        // content 岗位桥桩：install() 接力点验证，不产生副作用
        if (g.org.flashNight.gesh == null) g.org.flashNight.gesh = {};
        var gesh:Object = g.org.flashNight.gesh;
        if (gesh.tooltip == null) gesh.tooltip = {};
        _savedTipNs = gesh.tooltip;
        _savedTip = gesh.tooltip.NativeTooltipBridge;
        gesh.tooltip.NativeTooltipBridge = {
            install: function():Void {
                org.flashNight.arki.interaction.NativeMenuBridgeTest.tipInstalled++;
            }
        };

        // socket 桩
        _root.server = {
            isSocketConnected: true,
            sendTaskToNode: function(type, payload, cb):Boolean {
                org.flashNight.arki.interaction.NativeMenuBridgeTest.recorded.push(
                    {type:type, payload:payload});
                return org.flashNight.arki.interaction.NativeMenuBridgeTest.sendResult;
            }
        };

        // 世界桩 + NPC 目标（具备全部五项能力）
        _npcA = makeNpc();
        _root.gameworld = {npcA: _npcA};

        // 路由/命令桩
        _root.gameCommands = {};
        _root.gameCommands.openNpcShop = function(o:Object):Boolean {
            var t:Object = org.flashNight.arki.interaction.NativeMenuBridgeTest;
            t.calls.npcShop.push(o);
            return t.shopOpenResult;
        };
        _root.gameCommands.openWebHire = function(o:Object):Void {
            org.flashNight.arki.interaction.NativeMenuBridgeTest.calls.webHire.push(o);
        };
        _root.gameCommands.openWebDungeon = function(o:Object):Void {
            org.flashNight.arki.interaction.NativeMenuBridgeTest.calls.webDungeon.push(o);
        };
        _root.对话赋值到对话框 = function(d):Void {
            var t:Object = org.flashNight.arki.interaction.NativeMenuBridgeTest;
            t.calls.dlg++; t.calls.dlgArg = d;
        };
        _root.数组洗牌 = function(a):Void {
            org.flashNight.arki.interaction.NativeMenuBridgeTest.calls.shuffle++;
        };
        _root.发布消息 = function(s):Void {
            org.flashNight.arki.interaction.NativeMenuBridgeTest.calls.msg.push(s);
        };
        _root.获得翻译 = function(s:String):String { return s; };
        _root.getTaskData = function(p):Object {
            org.flashNight.arki.interaction.NativeMenuBridgeTest.calls.taskData.push(p);
            return {id:"T42"};
        };
        _root.openSkillTrainer = function(npc, src):Object {
            var t:Object = org.flashNight.arki.interaction.NativeMenuBridgeTest;
            t.calls.skill++; t.calls.skillArg = src; t.calls.skillNpc = npc;
            return {success:true, opened:true};
        };
        _root.UI系统 = {NPC商店WebView: {
            resolveShopIdByCatalog: function(items):String {
                org.flashNight.arki.interaction.NativeMenuBridgeTest.calls.resolve++;
                return "shopResolved";
            }
        }};
        _root.受雇欲望基准 = 50;

        // 临时 authored 菜单 MovieClip（_parent = _root）
        _menuMc = _root.createEmptyMovieClip("__niTestMenuMc", _root.getNextHighestDepth());
        _viewMc = _root.createEmptyMovieClip("__niTestViewMc", _root.getNextHighestDepth());
        _modifyMc = _root.createEmptyMovieClip("__niTestModifyMc", _root.getNextHighestDepth());

        NativeMenuBridge.install();
        NativeMenuBridge.attachCompat("NPC功能菜单", _menuMc);
        NativeMenuBridge.attachCompat("查看详细菜单", _viewMc);
        NativeMenuBridge.attachCompat("修改详细菜单", _modifyMc);
    }

    private static function teardownMock():Void {
        NativeMenuBridge.detachCompat("NPC功能菜单", _menuMc);
        NativeMenuBridge.detachCompat("查看详细菜单", _viewMc);
        NativeMenuBridge.detachCompat("修改详细菜单", _modifyMc);
        if (_menuMc != null) _menuMc.removeMovieClip();
        if (_viewMc != null) _viewMc.removeMovieClip();
        if (_modifyMc != null) _modifyMc.removeMovieClip();
        _menuMc = null; _viewMc = null; _modifyMc = null; _npcA = null;

        var g:Object = _global;
        var ns:Object = (g.org != null && g.org.flashNight != null
            && g.org.flashNight.arki != null && g.org.flashNight.arki.interaction != null)
            ? g.org.flashNight.arki.interaction : null;
        if (ns != null) {
            if (_savedCtx != undefined) ns.NativeInteractionContext = _savedCtx;
            else delete ns.NativeInteractionContext;
        }
        _savedCtx = undefined;
        if (_savedTipNs != null) {
            if (_savedTip != undefined) _savedTipNs.NativeTooltipBridge = _savedTip;
            else delete _savedTipNs.NativeTooltipBridge;
        }
        _savedTip = undefined; _savedTipNs = null;

        if (_saved != null) {
            for (var i:Number = 0; i < ROOT_KEYS.length; i++) {
                var k:String = ROOT_KEYS[i];
                if (_saved[k] != undefined) _root[k] = _saved[k];
                else delete _root[k];
            }
        }
        _saved = null;
        recorded = null;
    }

    // ── 测试辅助 ────────────────────────────────────────────────

    private static function makeNpc():Object {
        var npc:Object = {};
        npc.名字 = "测试甲";
        npc.默认对话 = [["甲线1", "甲线2"]];
        npc.物品栏 = ["it1"];
        npc.NPC商店检索名 = "";
        npc.佣兵数据 = {id: 1};
        npc.受雇欲望 = 60;
        npc.NPC任务_任务_关卡路径 = "task/p_alpha";
        npc.可学的技能 = ["sk1"];
        return npc;
    }

    private static function fiveWrite(menuName:String, npcName:String):Void {
        var m:Object = _root[menuName];
        m._visible = 1;
        m._x = 111;
        m._y = 222;
        m.当前NPC = npcName;
        m.刷新显示();
    }

    private static function curRid():String {
        return "ni:" + ctxSeq;
    }

    private static function fireAction(rid:String, sid:String, aid:String):Void {
        var h:Function = _root.gameCommands["nativeInteractionAction"];
        var params:Object = {version:1, requestId:rid, sceneId:sid, actionId:aid};
        // 首选走真实 gameCommands 接线；install 幂等下同会话重跑时回退公开静态入口
        if (typeof h == "function") h(params);
        else NativeMenuBridge.handleAction(params);
    }

    private static function fireCancel(rid:String, sid:String):Void {
        var h:Function = _root.gameCommands["nativeInteractionCancel"];
        var params:Object = {version:1, requestId:rid, sceneId:sid};
        if (typeof h == "function") h(params);
        else NativeMenuBridge.handleCancel(params);
    }

    private static function fireTeardown():Void {
        for (var i:Number = 0; i < teardowns.length; i++) teardowns[i].call(null);
    }

    private static function lastPayload():Object {
        return recorded[recorded.length - 1].payload;
    }

    // ── 用例 ────────────────────────────────────────────────────

    public static function runAllTests():Void {
        testsRun = testsPassed = testsFailed = 0;
        trace("--- NativeMenuBridgeTest ---");

        installMock();
        // install 幂等：本会话首次 install 才重注册 handler/接力 tooltip
        if (typeof _root.gameCommands["nativeInteractionAction"] == "function") {
            assertEq(1, tipInstalled, "install: NativeTooltipBridge.install 接力一次");
        }

        test_fiveWrite_publishes();
        test_placeholder_noPublish();
        test_unarmedRefresh_noPublish();
        test_action_consumedOnce();
        test_action_rejects();
        test_cancel_consumesNoHide();
        test_crossKindCancel_safe();
        test_sceneTeardown_revokes();
        test_sameNameRebuild_rejects();
        test_worldIdentity_rejects();
        test_availabilityChange_rejects();
        test_visibleFalse_hides();
        test_routes_verbatim();
        test_sendFailure_fallback();
        test_detach_hides();
        test_lateUnload_keepsNewCompat();

        teardownMock();

        trace("NativeMenuBridgeTest Tests Passed: " + testsPassed);
        trace("NativeMenuBridgeTest Tests Failed: " + testsFailed);
    }

    private static function test_fiveWrite_publishes():Void {
        resetCalls();
        fiveWrite("NPC功能菜单", "npcA");
        assertEq(1, recorded.length, "fiveWrite: exactly one sendTaskToNode");
        var p:Object = lastPayload();
        assertEq("native_interaction", recorded[0].type, "fiveWrite: task type");
        assertEq("menu", p.kind, "fiveWrite: kind");
        assertEq("show", p.op, "fiveWrite: op");
        assertEq(1, p.version, "fiveWrite: version");
        assertEq("ni:1", p.requestId, "fiveWrite: requestId ni:1");
        assertEq("sc.test.1", p.sceneId, "fiveWrite: sceneId");
        assertEq(111, p.x, "fiveWrite: x from compat._x");
        assertEq(222, p.y, "fiveWrite: y from compat._y");
        assertEq("npcA", p.targetName, "fiveWrite: targetName");
        assertEq("测试甲", p.title, "fiveWrite: title from npc.名字");
        assertEq(5, p.actions.length, "fiveWrite: five actions");
        assert(p.actions[0].id == "dialogue" && p.actions[0].enabled === true,
            "fiveWrite: dialogue enabled");
        assert(p.actions[2].id == "hire" && p.actions[2].enabled === true,
            "fiveWrite: hire enabled (受雇欲望 60 > 基准-1)");
        // 再写一次不带刷新：不追加发布
        _root.NPC功能菜单._x = 333;
        assertEq(1, recorded.length, "fiveWrite: no publish without 刷新显示");
        // 清 pending（teardown 发 hide），供后续用例干净起步
        fireTeardown();
    }

    private static function test_placeholder_noPublish():Void {
        resetCalls();
        fiveWrite("查看详细菜单", "npcA");
        fiveWrite("修改详细菜单", "npcA");
        assertEq(0, recorded.length, "placeholder: no wire published");
        assertEq("npc.viewDetail", _root.查看详细菜单.__nativeExt.id,
            "placeholder: viewDetail ext id kept");
        assertEq("npc.modifyDetail", _root.修改详细菜单.__nativeExt.id,
            "placeholder: modifyDetail ext id kept");
        assert(_root.查看详细菜单.__nativeExt.enabled === false,
            "placeholder: viewDetail disabled");
        assert(_root.修改详细菜单.__nativeExt.enabled === false,
            "placeholder: modifyDetail disabled");
    }

    private static function test_unarmedRefresh_noPublish():Void {
        resetCalls();
        var m:Object = _root.NPC功能菜单;
        m._visible = 0;                 // 不武装
        m._x = 1; m._y = 2; m.当前NPC = "npcA";
        m.刷新显示();
        assertEq(0, recorded.length, "unarmed: refresh without _visible publishes nothing");
    }

    private static function test_action_consumedOnce():Void {
        resetCalls();
        fiveWrite("NPC功能菜单", "npcA");
        var rid:String = curRid();
        fireAction(rid, ctxScene, "dialogue");
        assertEq(1, calls.dlg, "consume: dialogue route fired");
        assertEq(1, calls.shuffle, "consume: dialogue reshuffled");
        assert(_npcA.对话index === 1, "consume: 对话index advanced");
        fireAction(rid, ctxScene, "dialogue");
        assertEq(1, calls.dlg, "consume: duplicate action rejected");
    }

    private static function test_action_rejects():Void {
        resetCalls();
        fiveWrite("NPC功能菜单", "npcA");
        var rid:String = curRid();
        fireAction("ni:999", ctxScene, "dialogue");
        assertEq(0, calls.dlg, "reject: wrong requestId");
        fireAction(rid, "sc.other", "dialogue");
        assertEq(0, calls.dlg, "reject: wrong sceneId");
        fireAction(rid, ctxScene, "noSuchAction");
        assertEq(0, calls.dlg, "reject: unknown actionId consumed silently");
        fireAction(rid, ctxScene, "dialogue");
        assertEq(0, calls.dlg, "reject: late action after consume");
        // version 非 1
        _root.gameCommands["nativeInteractionAction"](
            {version:2, requestId:"ni:1", sceneId:ctxScene, actionId:"dialogue"});
        assertEq(0, calls.dlg, "reject: version!=1");
    }

    private static function test_cancel_consumesNoHide():Void {
        resetCalls();
        fiveWrite("NPC功能菜单", "npcA");
        var rid:String = curRid();
        var n0:Number = recorded.length;
        fireCancel(rid, ctxScene);
        assertEq(n0, recorded.length, "cancel: no hide echoed back");
        fireAction(rid, ctxScene, "dialogue");
        assertEq(0, calls.dlg, "cancel: pending consumed, action rejected");
    }

    private static function test_crossKindCancel_safe():Void {
        resetCalls();
        fiveWrite("NPC功能菜单", "npcA");
        var rid:String = curRid();
        // 宿主对 tooltip 实例发起的 cancel 用同一 action 名、不同 requestId：
        // ni:<n> 全局唯一，不匹配即不消费菜单 pending。
        fireCancel("ni:999", ctxScene);
        fireAction(rid, ctxScene, "dialogue");
        assertEq(1, calls.dlg, "crossKind: foreign-requestId cancel does not clear menu");
    }

    private static function test_sceneTeardown_revokes():Void {
        resetCalls();
        fiveWrite("NPC功能菜单", "npcA");
        var rid:String = curRid();
        var n0:Number = recorded.length;
        fireTeardown();
        assertEq(n0 + 1, recorded.length, "teardown: one hide sent");
        var p:Object = lastPayload();
        assertEq("menu", p.kind, "teardown: hide kind");
        assertEq("hide", p.op, "teardown: hide op");
        assertEq(rid, p.requestId, "teardown: hide matches pending requestId");
        assertEq(ctxScene, p.sceneId, "teardown: hide carries sceneId");
        fireAction(rid, ctxScene, "dialogue");
        assertEq(0, calls.dlg, "teardown: revoked pending rejects action");
    }

    private static function test_sameNameRebuild_rejects():Void {
        resetCalls();
        fiveWrite("NPC功能菜单", "npcA");
        var rid:String = curRid();
        _root.gameworld.npcA = makeNpc();   // 同场景同名重建：新对象无快照 token
        fireAction(rid, ctxScene, "dialogue");
        assertEq(0, calls.dlg, "rebuild: same-name new target rejected");
        _root.gameworld.npcA = _npcA;       // 恢复旧对象引用，防跨用例污染
    }

    private static function test_worldIdentity_rejects():Void {
        resetCalls();
        fiveWrite("NPC功能菜单", "npcA");
        var rid:String = curRid();
        ctxWorldOk = false;
        fireAction(rid, ctxScene, "dialogue");
        assertEq(0, calls.dlg, "world: stale scene identity rejected");
        ctxWorldOk = true;
    }

    private static function test_availabilityChange_rejects():Void {
        resetCalls();
        // 用本用例自己的当前 fixture，不依赖前序用例遗留的 gameworld 状态
        _npcA = makeNpc();
        _root.gameworld.npcA = _npcA;
        fiveWrite("NPC功能菜单", "npcA");
        var rid:String = curRid();
        _npcA.物品栏 = undefined;           // show 后商店能力消失
        fireAction(rid, ctxScene, "shop");
        assertEq(0, calls.npcShop.length, "avail: shop no longer enabled → rejected");
        // 受雇欲望掉到基准下：雇佣同样按现况拒
        fiveWrite("NPC功能菜单", "npcA");
        rid = curRid();
        _npcA.受雇欲望 = 10;
        fireAction(rid, ctxScene, "hire");
        assertEq(0, calls.webHire.length, "avail: hire 受雇欲望 re-check rejected");
        // 恢复 fixture 全能力字段，供后续路由用例
        _npcA.物品栏 = ["it1"];
        _npcA.受雇欲望 = 60;
    }

    private static function test_visibleFalse_hides():Void {
        resetCalls();
        fiveWrite("NPC功能菜单", "npcA");
        var rid:String = curRid();
        var n0:Number = recorded.length;
        _root.NPC功能菜单._visible = 0;
        assertEq(n0 + 1, recorded.length, "visible=false: hide sent");
        assertEq(rid, lastPayload().requestId, "visible=false: hide requestId");
        fireAction(rid, ctxScene, "dialogue");
        assertEq(0, calls.dlg, "visible=false: pending cleared");
    }

    private static function test_routes_verbatim():Void {
        // task：getTaskData(关卡路径) → openWebDungeon({taskId: taskData.id})
        resetCalls();
        fiveWrite("NPC功能菜单", "npcA");
        var rid:String = curRid();
        fireAction(rid, ctxScene, "task");
        assertEq(1, calls.taskData.length, "task: getTaskData called once");
        assertEq("task/p_alpha", calls.taskData[0], "task: getTaskData arg = 关卡路径");
        assertEq(1, calls.webDungeon.length, "task: openWebDungeon called once");
        assertEq("T42", calls.webDungeon[0].taskId, "task: taskId from taskData.id");

        // hire：openWebHire({npcId: targetName})
        fiveWrite("NPC功能菜单", "npcA");
        rid = curRid();
        fireAction(rid, ctxScene, "hire");
        assertEq(1, calls.webHire.length, "hire: openWebHire called once");
        assertEq("npcA", calls.webHire[0].npcId, "hire: npcId = targetName");

        // shop：NPC商店检索名="" → resolveShopIdByCatalog → openNpcShop
        fiveWrite("NPC功能菜单", "npcA");
        rid = curRid();
        fireAction(rid, ctxScene, "shop");
        assertEq(1, calls.resolve, "shop: catalog resolve used for empty 检索名");
        assertEq(1, calls.npcShop.length, "shop: openNpcShop called once");
        assertEq("shopResolved", calls.npcShop[0].shopId, "shop: resolved shopId");
        assertEq("world_npc_dialogue", calls.npcShop[0].source, "shop: source tag");

        // shop 打开失败 → 发布消息 回退
        shopOpenResult = false;
        fiveWrite("NPC功能菜单", "npcA");
        rid = curRid();
        fireAction(rid, ctxScene, "shop");
        assert(calls.msg.length > 0
            && calls.msg[calls.msg.length - 1] == "商店面板暂时不可用",
            "shop: open failure falls back to 发布消息");

        // train：openSkillTrainer(npc, "world_skill_trainer")
        fiveWrite("NPC功能菜单", "npcA");
        rid = curRid();
        fireAction(rid, ctxScene, "train");
        assertEq(1, calls.skill, "train: openSkillTrainer called once");
        assertEq("world_skill_trainer", calls.skillArg, "train: source tag");
        assertEq(_npcA, calls.skillNpc, "train: npc passed through");
    }

    private static function test_sendFailure_fallback():Void {
        resetCalls();
        sendResult = false;
        fiveWrite("NPC功能菜单", "npcA");
        assertEq(1, recorded.length, "fallback: show attempted once");
        assert(_menuMc._visible === true, "fallback: authored MC re-shown");
        assertEq("npcA", _menuMc.当前NPC, "fallback: 当前NPC backfilled");
        assertEq(111, _menuMc._x, "fallback: _x backfilled");
        assertEq(222, _menuMc._y, "fallback: _y backfilled");
        // pending 已清：迟到 action 拒绝
        fireAction(curRid(), ctxScene, "dialogue");
        assertEq(0, calls.dlg, "fallback: no dangling pending");
        // socket 恢复后下一次发布成功 → 原生接管并收敛 MC
        sendResult = true;
        fiveWrite("NPC功能菜单", "npcA");
        assert(_menuMc._visible === false, "fallback: native retakes, MC hidden");
        fireTeardown();
    }

    private static function test_detach_hides():Void {
        resetCalls();
        fiveWrite("NPC功能菜单", "npcA");
        var rid:String = curRid();
        var n0:Number = recorded.length;
        NativeMenuBridge.detachCompat("NPC功能菜单", _menuMc);
        assertEq(n0 + 1, recorded.length, "detach: hide sent");
        assertEq(rid, lastPayload().requestId, "detach: hide requestId");
        assert(_root.NPC功能菜单 === undefined, "detach: root name cleared");
        // 后续用例/拆除仍需要 compat：重新挂接
        NativeMenuBridge.attachCompat("NPC功能菜单", _menuMc);
        assert(_root.NPC功能菜单 != undefined, "detach: re-attach restores compat");
    }

    private static function test_lateUnload_keepsNewCompat():Void {
        // R2 场景：同名 MC 重建，新实例 load 已 attach，旧实例 unload 迟到。
        // 旧 unload 不得误清新 compat（clip 携带的旧 attach token 失配即跳过）。
        var mc2:MovieClip = _root.createEmptyMovieClip(
            "__niTestMenuMc2", _root.getNextHighestDepth());
        NativeMenuBridge.attachCompat("NPC功能菜单", mc2);   // 同名重建 → 新 compat
        assert(_root.NPC功能菜单 != undefined, "lateUnload: rebuilt compat registered");
        NativeMenuBridge.detachCompat("NPC功能菜单", _menuMc); // 旧实例迟到 unload
        assert(_root.NPC功能菜单 != undefined,
            "lateUnload: old unload does not clear new compat");
        recorded = [];
        fiveWrite("NPC功能菜单", "npcA");
        assertEq(1, recorded.length, "lateUnload: new compat still publishes");
        fireTeardown();
        // 正常 unload 正常清：本周期 clip 携带匹配 token
        NativeMenuBridge.detachCompat("NPC功能菜单", mc2);
        assert(_root.NPC功能菜单 === undefined,
            "normalUnload: own unload clears compat");
        mc2.removeMovieClip();
        // 恢复 _menuMc 的 compat 供收尾清理一致
        NativeMenuBridge.attachCompat("NPC功能菜单", _menuMc);
    }
}
