import org.flashNight.arki.dialogue.NativeDialogueService;
import org.flashNight.arki.pause.PauseManager;
import org.flashNight.neur.Event.EventDispatcher;

/**
 * NativeDialogueServiceTest - native_dialogue 会话生命周期测试（focused runner 用）
 *
 * 覆盖：
 *   - 普通对白不开暂停；追加续同 requestId；覆盖开新会话并 hide 旧会话；
 *   - StageEvent 对白持 claim（暂停=true），finish 后按 OR 语义恢复；
 *   - advance/close 的 requestId+sceneId+revision 三重校验（stale 全拒）；
 *   - finish 先清会话与 followingEvent 再一次性发布；cancel 绝不发布；
 *   - D/W/R（对白 claim × web claim × reward pending）交叠真值流程；
 *   - facade 成员面、_visible 惰性影子、AVM1 重绑后 ensureCompat 自愈；
 *   - 佣兵 target 外观快照不回落当前玩家；
 *   - Host 不可达（发送失败）时按显式结束兜底、防剧情软锁。
 *
 * 隔离方式：_global 路径桩替换 NativeInteractionContext（同 NativeMenuBridgeTest
 *   约定），_root.server / gameworld.dispatcher / 组装单次对话 / 对话框界面
 *   全部保存-桩替换-恢复；PauseManager 用真实实例验证 claim 协调（测试内产生的
 *   claim 全部释放，_root.暂停 恢复原值），不触真实存档。
 */
class org.flashNight.arki.dialogue.NativeDialogueServiceTest {

    public static var testsRun:Number = 0;
    public static var testsPassed:Number = 0;
    public static var testsFailed:Number = 0;

    public static var recorded:Array = null;        // {type, payload}
    public static var sendResult:Boolean = true;
    public static var published:Array = null;       // {name, args}
    public static var teardowns:Array = null;
    public static var ctxScene:String = "sc.dlg.1";

    private static var _saved:Object = null;
    private static var _savedCtx = undefined;
    private static var _fakeMc:MovieClip = null;
    private static var _savedPause = undefined;

    private static var ROOT_KEYS:Array = [
        "server", "gameworld", "对话框界面", "__nativeDialogueCompat",
        "组装单次对话", "互动键", "服务器", "控制目标", "脸型", "发型", "性别", "角色名",
        "物品栏"
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
        // 先终结上一用例遗留会话，避免本条 handleAssign 误入追加路径
        if (NativeDialogueService.getSessionSnapshot() != null) {
            NativeDialogueService.cancelActive("test_reset");
        }
        recorded = [];
        published = [];
        sendResult = true;
        if (_root.暂停 !== false) _root.暂停 = false;
        if (_root.暂停 === true) {
            // 上个用例可能遗留 claim：不在这里强拆（会污染真值表），由用例自管
        }
    }

    private static function installMock():Void {
        _savedPause = _root.暂停;
        teardowns = [];
        resetCalls();
        ctxScene = "sc.dlg.1";

        _saved = {};
        for (var i:Number = 0; i < ROOT_KEYS.length; i++) {
            _saved[ROOT_KEYS[i]] = _root[ROOT_KEYS[i]];
        }

        // NativeInteractionContext 桩（_global 运行期解析拦截）
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
                return org.flashNight.arki.dialogue.NativeDialogueServiceTest.ctxScene;
            },
            getSceneIdentity: function():Object { return {fake:1}; },
            isCurrentWorld: function(w:Object):Boolean { return true; },
            nextRequestId: function():String { return "ni:999"; },
            onSceneTeardown: function(fn:Function):Void {
                org.flashNight.arki.dialogue.NativeDialogueServiceTest.teardowns.push(fn);
            }
        };

        _root.server = {
            isSocketConnected: true,
            sendTaskToNode: function(type, payload, cb):Boolean {
                org.flashNight.arki.dialogue.NativeDialogueServiceTest.recorded.push(
                    {type:type, payload:payload});
                return org.flashNight.arki.dialogue.NativeDialogueServiceTest.sendResult;
            }
        };
        _root.服务器 = {发布服务器消息: function():Void {}};
        _root.gameworld = {
            dispatcher: {
                publish: function(name:String):Void {
                    var args:Array = [];
                    for (var i:Number = 1; i < arguments.length; i++) args.push(arguments[i]);
                    org.flashNight.arki.dialogue.NativeDialogueServiceTest.published.push(
                        {name:name, args:args.length > 0 ? args : null});
                }
            }
        };
        _root.组装单次对话 = function(arr:Array):Array {
            var out:Array = [];
            for (var i:Number = 0; i < arr.length; i++) {
                var o:Object = arr[i];
                var c:String = String(o.char != undefined ? o.char : "");
                var cp:Array = c.split("#");
                out.push([o.name, o.title, cp[0], o.text,
                    cp.length > 1 ? cp[1] : "普通", o.target, o.imageurl]);
            }
            return out;
        };

        // PauseManager 用真实实例（install 幂等）；测试前确保干净基线
        PauseManager.install();
        _root.暂停 = false;

        NativeDialogueService.install();
    }

    private static function teardownMock():Void {
        NativeDialogueService.cancelActive("test_teardown");
        var g:Object = _global;
        var ns:Object = (g.org != null && g.org.flashNight != null
            && g.org.flashNight.arki != null && g.org.flashNight.arki.interaction != null)
            ? g.org.flashNight.arki.interaction : null;
        if (ns != null) {
            if (_savedCtx != undefined) ns.NativeInteractionContext = _savedCtx;
            else delete ns.NativeInteractionContext;
        }
        _savedCtx = undefined;

        if (_saved != null) {
            for (var i:Number = 0; i < ROOT_KEYS.length; i++) {
                var k:String = ROOT_KEYS[i];
                if (_saved[k] != undefined) _root[k] = _saved[k];
                else delete _root[k];
            }
        }
        _saved = null;
        if (_fakeMc != null) { _fakeMc.removeMovieClip(); _fakeMc = null; }
        _root.暂停 = _savedPause;
        recorded = null; published = null; teardowns = null;
    }

    // ── 测试辅助 ────────────────────────────────────────────────

    private static function rows(n:Number):Array {
        var r:Array = [];
        for (var i:Number = 0; i < n; i++) {
            r.push(["NPC" + i, "称号", "卫兵", "第" + i + "句", "普通", null, ""]);
        }
        return r;
    }

    private static function curSession():Object {
        return NativeDialogueService.getSessionSnapshot();
    }

    private static function curRid():String {
        var s:Object = curSession();
        return s != null ? String(s.requestId) : "";
    }

    private static function curRev():Number {
        var s:Object = curSession();
        return s != null ? Number(s.revision) : -1;
    }

    private static function act(verb:String, rid:String, sid:String, rev:Number):Void {
        NativeDialogueService.handleAction({
            task:"cmd", action:"nativeDialogueAction",
            requestId:rid, sceneId:sid, revision:rev, verb:verb});
    }

    private static function lastPayload():Object {
        return recorded[recorded.length - 1].payload;
    }

    private static function countOp(op:String):Number {
        var n:Number = 0;
        for (var i:Number = 0; i < recorded.length; i++) {
            if (recorded[i].payload.op == op) n++;
        }
        return n;
    }

    private static function fireTeardown():Void {
        for (var i:Number = 0; i < teardowns.length; i++) teardowns[i].call(null);
    }

    // ── 用例 ────────────────────────────────────────────────────

    public static function runAllTests():Void {
        testsRun = testsPassed = testsFailed = 0;
        trace("--- NativeDialogueServiceTest ---");
        installMock();

        test_ordinary_noPause();
        test_append_sameRequest();
        test_overwrite_newSession();
        test_action_validation();
        test_advance_to_finish();
        test_stage_pause_and_event_once();
        test_close_consumes_once();
        test_cancel_never_publishes();
        test_teardown_cancels();
        test_web_overlap_ordering();
        test_reward_pending_overlap();
        test_send_failure_finishes();
        test_compat_facade();
        test_merc_appearance_snapshot();
        test_real_dispatcher_reentry();
        test_transport_and_stage_replacement();
        test_appearance_frozen_at_entry();
        test_hero_shell_uses_authority();
        test_stranger_shell_never_player();
        test_stage_attrobj_player_line();
        test_custom_attrobj_keeps_own();
        test_same_name_not_hero();
        test_frozen_no_root_drift();

        teardownMock();
        trace("NativeDialogueServiceTest Tests Passed: " + testsPassed);
        trace("NativeDialogueServiceTest Tests Failed: " + testsFailed);
    }

    private static function test_ordinary_noPause():Void {
        resetCalls();
        _root.暂停 = false;
        NativeDialogueService.handleAssign(rows(2), false);
        assertEq(1, recorded.length, "ordinary: one show sent");
        var p:Object = lastPayload();
        assertEq("native_dialogue", recorded[0].type, "ordinary: task type");
        assertEq("show", p.op, "ordinary: op show");
        assertEq("nd:1", p.requestId, "ordinary: nd:1");
        assertEq("sc.dlg.1", p.sceneId, "ordinary: sceneId");
        assertEq(1, p.revision, "ordinary: revision 1");
        assertEq(0, p.lineIndex, "ordinary: lineIndex 0");
        assertEq(2, p.lineCount, "ordinary: lineCount 2");
        assertEq("NPC0", p.name, "ordinary: name");
        assertEq("static", p.portrait.kind, "ordinary: static kind");
        assertEq("卫兵", p.portrait.key, "ordinary: portrait key");
        assert(_root.暂停 === false, "ordinary: no pause added");
        assert(_root.对话框界面 != null && typeof _root.对话框界面 == "object"
            && typeof _root.对话框界面 != "movieclip", "ordinary: facade bound");
        assertEq(2, _root.对话框界面.本轮对话内容.length,
            "ordinary: facade mirrors session lines");
        assertEq(0, _root.对话框界面.对话进度, "ordinary: facade 进度=0");
        assert(_root.对话框界面._visible === true, "ordinary: facade visible while active");
    }

    private static function test_append_sameRequest():Void {
        resetCalls();
        var source:Array = rows(2);
        source[0][0] = "角色名";
        var previousName = _root.角色名;
        _root.角色名 = "测试玩家";
        NativeDialogueService.handleAssign(source, false);
        assertEq("测试玩家", lastPayload().name, "name: legacy player name placeholder resolved");
        _root.角色名 = previousName;
        var rid:String = curRid();
        NativeDialogueService.advance();
        var oldRevision:Number = curSession().revision;
        var n0:Number = recorded.length;
        NativeDialogueService.handleAssign(rows(1), false);
        assertEq(n0 + 1, recorded.length, "append: refreshed first line sent");
        assertEq(rid, curRid(), "append: same requestId");
        assertEq(3, curSession().lineCount, "append: lines extended to 3");
        assertEq(3, _root.对话框界面.对话条数, "append: facade 条数 synced");
        assertEq(2, source.length, "append: caller-owned NPC dialogue array unchanged");
        assertEq(0, curSession().index, "append: legacy first-line restart retained");
        assertEq(oldRevision + 1, curSession().revision, "append: stale input revision invalidated");
    }

    private static function test_overwrite_newSession():Void {
        resetCalls();
        NativeDialogueService.handleAssign(rows(2), false);
        var rid:String = curRid();
        NativeDialogueService.handleAssign(rows(1), true);
        assertEq(1, countOp("hide"), "overwrite: old session hid once");
        var hide:Object = null;
        for (var i:Number = 0; i < recorded.length; i++) {
            if (recorded[i].payload.op == "hide") hide = recorded[i].payload;
        }
        assertEq(rid, hide.requestId, "overwrite: hide tombstones old request");
        assert(curRid() != rid, "overwrite: new requestId issued");
        assertEq(1, curSession().lineCount, "overwrite: lines replaced");
    }

    private static function test_action_validation():Void {
        resetCalls();
        NativeDialogueService.handleAssign(rows(3), false);
        var rid:String = curRid();
        var rev:Number = curRev();
        act("advance", "nd:999", ctxScene, rev);
        assertEq(0, curSession().index, "reject: wrong requestId");
        act("advance", rid, "sc.other", rev);
        assertEq(0, curSession().index, "reject: wrong sceneId");
        act("advance", rid, ctxScene, rev + 1);
        assertEq(0, curSession().index, "reject: future revision");
        act("bogus", rid, ctxScene, rev);
        assertEq(0, curSession().index, "reject: unknown verb");
        var h:Function = _root.gameCommands["nativeDialogueAction"];
        assert(typeof h == "function", "route: gameCommands handler installed");
    }

    private static function test_advance_to_finish():Void {
        resetCalls();
        NativeDialogueService.handleAssign(rows(2), false);
        var rid:String = curRid();
        act("advance", rid, ctxScene, curRev());
        assertEq(1, curSession().index, "advance: line 1 shown");
        var p:Object = lastPayload();
        assertEq(2, p.revision, "advance: revision incremented");
        assertEq(1, p.lineIndex, "advance: lineIndex 1");
        act("advance", rid, ctxScene, curRev());
        assert(curSession() == null, "finish: session cleared at last line");
        assertEq(1, countOp("hide"), "finish: hide sent");
        // 终态后再到的 advance/close 一律拒绝
        act("advance", rid, ctxScene, 99);
        assertEq(1, countOp("hide"), "finish: stale advance rejected");
        assert(_root.对话框界面._visible === false, "finish: facade hidden");
    }

    private static function test_stage_pause_and_event_once():Void {
        resetCalls();
        _root.暂停 = false;
        var ev:Object = {name:"NextStage", args:["a1","a2"]};
        var raw:Array = [{name:"军官", title:"", char:"卫兵", text:"冲", target:null, imageurl:""}];
        NativeDialogueService.beginStage(raw, ev);
        assert(_root.暂停 === true, "stage: claim pauses game");
        assertEq("dialogue", PauseManager.getObservationOwner(), "stage: owner=dialogue");
        var rid:String = curRid();
        act("advance", rid, ctxScene, curRev());   // 单行 → finish
        assertEq(1, published.length, "stage: event published once");
        assertEq("NextStage", published[0].name, "stage: event name");
        assert(published[0].args != null && published[0].args.length == 2,
            "stage: event params delivered via dispatcher publish");
        assert(_root.暂停 === false, "stage: pause released after finish");
    }

    private static function test_close_consumes_once():Void {
        resetCalls();
        var ev:Object = {name:"NextStage", args:null};
        NativeDialogueService.beginStage(
            [{name:"a", title:"", char:"卫兵", text:"t", target:null, imageurl:""}], ev);
        var rid:String = curRid();
        act("close", rid, ctxScene, curRev());
        assertEq(1, published.length, "close: event consumed once");
        act("close", rid, ctxScene, curRev() + 5);
        assertEq(1, published.length, "close: repeat rejected");
        act("advance", rid, ctxScene, 1);
        assertEq(1, published.length, "close: late advance rejected");
    }

    private static function test_cancel_never_publishes():Void {
        resetCalls();
        var ev:Object = {name:"NextStage", args:null};
        NativeDialogueService.beginStage(
            [{name:"a", title:"", char:"卫兵", text:"t", target:null, imageurl:""}], ev);
        assert(_root.暂停 === true, "cancel: paused during session");
        // 场景清理顺序：先清 followingEvent 再关闭
        _root.对话框界面.followingEvent = null;
        _root.对话框界面.关闭();
        assertEq(0, published.length, "cancel: event never published");
        assertEq(1, countOp("hide"), "cancel: hide sent");
        assert(_root.暂停 === false, "cancel: claim released");
        assert(curSession() == null, "cancel: session cleared");
    }

    private static function test_teardown_cancels():Void {
        resetCalls();
        var ev:Object = {name:"NextStage", args:null};
        NativeDialogueService.beginStage(
            [{name:"a", title:"", char:"卫兵", text:"t", target:null, imageurl:""}], ev);
        fireTeardown();   // SceneChanged → NativeInteractionContext teardown
        assertEq(0, published.length, "teardown: event never published");
        assertEq(1, countOp("hide"), "teardown: hide sent");
        assert(curSession() == null, "teardown: session cleared");
    }

    private static function test_web_overlap_ordering():Void {
        resetCalls();
        _root.暂停 = false;
        // 对白先开 → web 开 → 对白先完 → web 关
        NativeDialogueService.beginStage(
            [{name:"a", title:"", char:"卫兵", text:"t", target:null, imageurl:""}], null);
        var web:String = PauseManager.lease(true, "webpanel");
        var rid:String = curRid();
        act("advance", rid, ctxScene, curRev());
        assert(_root.暂停 === true, "D→W: web claim keeps pause after dialogue ends");
        PauseManager.releaseLease(web);
        assert(_root.暂停 === false, "D→W: unpaused after web release");
        // web 先开 → 对白开 → web 先关 → 对白完
        resetCalls();
        web = PauseManager.lease(true, "webpanel");
        NativeDialogueService.beginStage(
            [{name:"a", title:"", char:"卫兵", text:"t", target:null, imageurl:""}], null);
        PauseManager.releaseLease(web);
        assert(_root.暂停 === true, "W→D: dialogue claim keeps pause after web closes");
        rid = curRid();
        act("advance", rid, ctxScene, curRev());
        assert(_root.暂停 === false, "W→D: unpaused after dialogue finish");
        // 对白期间业务裸写 false（旧 onClose 型 bug 复现）不得降下暂停
        resetCalls();
        NativeDialogueService.beginStage(
            [{name:"a", title:"", char:"卫兵", text:"t", target:null, imageurl:""}], null);
        _root.暂停 = false;
        assert(_root.暂停 === true, "claim coerces stray false write");
        rid = curRid();
        act("advance", rid, ctxScene, curRev());
        assert(_root.暂停 === false, "claim release restores unowned base");
    }

    private static function test_reward_pending_overlap():Void {
        resetCalls();
        _root.暂停 = false;
        NativeDialogueService.beginStage(
            [{name:"a", title:"", char:"卫兵", text:"t", target:null, imageurl:""}], null);
        PauseManager.setRewardCommitPending(true);
        var rid:String = curRid();
        act("advance", rid, ctxScene, curRev());   // 对白结束于 pending 期
        assert(_root.暂停 === true, "reward: dialogue close cannot resume during pending");
        PauseManager.setRewardCommitPending(false);
        assert(_root.暂停 === false, "reward: resolved save restores unowned base");
        // 反向：pending 起 → 对白开 → pending 终 → 对白完
        resetCalls();
        PauseManager.setRewardCommitPending(true);
        NativeDialogueService.beginStage(
            [{name:"a", title:"", char:"卫兵", text:"t", target:null, imageurl:""}], null);
        PauseManager.setRewardCommitPending(false);
        assert(_root.暂停 === true, "reward end while claim active: stays paused");
        rid = curRid();
        act("advance", rid, ctxScene, curRev());
        assert(_root.暂停 === false, "claim release after reward resolves correctly");
    }

    private static function test_send_failure_finishes():Void {
        resetCalls();
        sendResult = false;
        var ev:Object = {name:"NextStage", args:null};
        NativeDialogueService.beginStage(
            [{name:"a", title:"", char:"卫兵", text:"t", target:null, imageurl:""}], ev);
        assertEq(1, published.length, "send-fail: event still consumed once (no softlock)");
        assert(curSession() == null, "send-fail: session finished");
        assert(_root.暂停 === false, "send-fail: claim released");
        sendResult = true;
    }

    private static function test_compat_facade():Void {
        resetCalls();
        // AVM1 同路径重绑：facade 被 authored MC 顶掉后 ensureCompat 自愈
        _fakeMc = _root.createEmptyMovieClip("__ndTestMc", _root.getNextHighestDepth());
        _fakeMc.onClose = function():Void { _root.暂停 = false; };
        _root.对话框界面 = _fakeMc;
        var c:Object = NativeDialogueService.ensureCompat();
        assert(_root.对话框界面 === c, "facade: rebound to plain Object");
        assert(typeof _root.对话框界面 != "movieclip", "facade: not a MovieClip");
        assert(_fakeMc._visible === false, "facade: authored clip hidden");
        _root.暂停 = true;
        _fakeMc.onClose();   // 已被桩化：不得清暂停
        assert(_root.暂停 === true, "facade: stubbed clip onClose cannot clear pause");
        _root.暂停 = false;
        // 成员面完整
        var need:Array = ["本轮对话内容","对话进度","对话条数","gotoAndStop","onClose",
            "下一句","关闭","刷新内容","打字","结束打字","刷新立绘","刷新外部导入立绘",
            "followingEvent","_visible"];
        for (var i:Number = 0; i < need.length; i++) {
            assert(Object.prototype.hasOwnProperty.call(c, need[i]),
                "facade: member " + need[i]);
        }
        // _visible 惰性影子：写 false 不终结活动会话
        NativeDialogueService.handleAssign(rows(1), false);
        c._visible = false;
        assert(curSession() != null, "facade: _visible write does not kill session");
        NativeDialogueService.cancelActive("test");
    }

    private static function test_merc_appearance_snapshot():Void {
        resetCalls();
        // 佣兵行：char="主角模板"，target=佣兵 MC —— 快照必须来自该佣兵
        _root.控制目标 = "hero";
        _root.gameworld.hero = {脸型:"玩家脸", 发型:"玩家发", 性别:"女", 头部装备:"玩家盔"};
        var merc:Object = {脸型:"佣兵脸", 发型:"佣兵发", 性别:"男",
            头部装备:"佣兵盔", 上装装备:"佣兵甲", 面具:"佣兵面具"};
        NativeDialogueService.handleAssign(
            [["佣兵甲", "佣兵", "主角模板", "报到", "普通", merc, ""]], false);
        var p:Object = lastPayload();
        assertEq("doll", p.portrait.kind, "merc: doll kind");
        assertEq("佣兵脸", p.portrait.appearance.face, "merc: face from target not player");
        assertEq("佣兵盔", p.portrait.appearance.head, "merc: head from target");
        assertEq("佣兵面具", p.portrait.appearance.keyMap["面具"],
            "merc: keyMap carries holder skin");
        // 无 target 的主角模板 → 回落玩家
        resetCalls();
        NativeDialogueService.handleAssign(
            [["主角", "", "主角模板", "……", "普通", null, ""]], false);
        p = lastPayload();
        assertEq("玩家脸", p.portrait.appearance.face, "hero: falls back to player");
        // 非人形佣兵：char=静态立绘 key，expr 槽是名字变体 → static
        resetCalls();
        NativeDialogueService.handleAssign(
            [["土匪乙", "盗贼", "堕落城盗贼", "吼", "土匪乙", null, ""]], false);
        p = lastPayload();
        assertEq("static", p.portrait.kind, "non-humanoid: static kind");
        assertEq("堕落城盗贼", p.portrait.key, "non-humanoid: portrait key");
        NativeDialogueService.cancelActive("test");
    }
    private static function test_real_dispatcher_reentry():Void {
        resetCalls();
        var prior:Object = _root.gameworld.dispatcher;
        var dispatcher:EventDispatcher = new EventDispatcher();
        _root.gameworld.dispatcher = dispatcher;
        var result:Object = {count:0, args:[]};
        dispatcher.subscribe("ContinueDialogue", function(a, b):Void {
            this.count++;
            this.args = [a,b];
            org.flashNight.arki.dialogue.NativeDialogueService.handleAssign(
                [["后续", "", "卫兵", "新会话", "普通", null, ""]], false);
        }, result);
        NativeDialogueService.beginStage([{name:"前句", char:"卫兵", text:"第一句"}],
            {name:"ContinueDialogue", args:["参数甲", 17]});
        var oldRequest:String = curRid();
        NativeDialogueService.finishSession();
        assertEq(1, result.count, "real dispatcher: following event delivered once");
        assertEq("参数甲", result.args[0], "real dispatcher: first argument");
        assertEq(17, result.args[1], "real dispatcher: second argument");
        assert(curSession() != null && curRid() != oldRequest, "reentry: new dialogue survives old finish");
        act("close", oldRequest, ctxScene, 1);
        assert(curSession() != null, "reentry: old close cannot finish new dialogue");
        NativeDialogueService.cancelActive("test");
        dispatcher.destroy();
        _root.gameworld.dispatcher = prior;
    }

    private static function test_appearance_frozen_at_entry():Void {
        resetCalls();
        var actor:Object = {性别:"女", 脸型:"佣兵脸甲", 发型:"佣兵发甲", 上装装备:"佣兵衣甲"};
        NativeDialogueService.handleAssign([
            ["甲", "", "主角模板", "第一句", "普通", actor, ""],
            ["甲", "", "主角模板", "第二句", "微笑", actor, ""]], false);
        actor.脸型 = "已改变";
        actor.上装装备 = "已卸载";
        NativeDialogueService.advance();
        assertEq("佣兵脸甲", lastPayload().portrait.appearance.face, "snapshot: next line retains detached actor face");
        assertEq("佣兵衣甲", lastPayload().portrait.appearance.body, "snapshot: next line retains detached equipment");
        assertEq("微笑", lastPayload().portrait.expression, "snapshot: each line retains its expression");
        NativeDialogueService.cancelActive("test");
    }

    private static function test_hero_shell_uses_authority():Void {
        resetCalls();
        // 入场竞态：hero MC 已占位但未初始化（空壳，字段全空）；
        // 权威源 = _root 身份 + 物品栏.装备栏 物品名，不得走 MC 空字段
        _root.控制目标 = "hero";
        _root.gameworld.hero = {性别:"", 脸型:"", 发型:"", 头部装备:null, 上装装备:null};
        _root.性别 = "男";
        _root.脸型 = "玩家脸甲";
        _root.发型 = "寸头";
        _root.物品栏 = {装备栏:{
            getNameString: function(slot:String):String {
                var t:Object = {头部装备:"战术目镜", 上装装备:"钛合金装甲",
                    下装装备:"钛合金护腿", 手部装备:"战术手套",
                    脚部装备:"军靴", 颈部装备:""};
                return t[slot] != undefined ? t[slot] : "";
            }
        }};
        NativeDialogueService.handleAssign(
            [["主角", "", "玩家", "进场", "普通", null, ""]], false);
        var p:Object = lastPayload();
        var ap:Object = p.portrait.appearance;
        assertEq("doll", p.portrait.kind, "shell: doll kind");
        assertEq("男", ap.gender, "shell: gender from _root, not ''→女 fallback");
        assertEq("玩家脸甲", ap.face, "shell: face from _root");
        assertEq("寸头", ap.hair, "shell: hair from _root");
        assertEq("钛合金装甲", ap.body, "shell: body from 装备栏 authority");
        assertEq("战术目镜", ap.head, "shell: head from 装备栏 authority");
        assertEq("军靴", ap.foot, "shell: foot from 装备栏 authority");
        assert(ap.keyMap == null, "shell: no keyMap without MC dressup fields");
        // target 直接指向空壳 MC（_name===控制目标）→ 仍走主角权威源
        resetCalls();
        var shell:Object = _root.gameworld.hero;
        shell._name = "hero";
        NativeDialogueService.handleAssign(
            [["主角", "", "主角模板", "自报", "普通", shell, ""]], false);
        ap = lastPayload().portrait.appearance;
        assertEq("钛合金装甲", ap.body, "shell-as-target: still authority equipment");
        assertEq("男", ap.gender, "shell-as-target: still authority gender");
        // hero MC 缺失（gameworld 里根本没有）→ 同样靠权威源出图
        resetCalls();
        delete _root.gameworld.hero;
        NativeDialogueService.handleAssign(
            [["主角", "", "玩家", "进场", "普通", null, ""]], false);
        ap = lastPayload().portrait.appearance;
        assertEq("钛合金装甲", ap.body, "mc-absent: equipment from 装备栏");
        assertEq("玩家脸甲", ap.face, "mc-absent: face from _root");
        NativeDialogueService.cancelActive("test");
    }

    private static function test_stranger_shell_never_player():Void {
        resetCalls();
        // 陌生空壳 target（非控制目标、无身份字段）：明确缺图，绝不套玩家。
        // 必须用真实 MovieClip：生产上陌生单位 target 恒为 MC（MercSpawner:386）；
        // 裸 {} 不是现实单位形态——那是 parseSingleDialogue 的行元数据 attrObj，
        // 归主角权威路径（见 test_stage_attrobj_player_line），不是缺图分支。
        _root.控制目标 = "hero";
        _root.gameworld.hero = {脸型:"玩家脸", 性别:"男", 上装装备:"钛合金装甲"};
        _root.性别 = "男";
        _root.脸型 = "玩家脸";
        _root.物品栏 = {装备栏:{getNameString: function(s:String):String {
            return "钛合金装甲";
        }}};
        var stranger:MovieClip = _root.createEmptyMovieClip(
            "__ndStranger", _root.getNextHighestDepth());
        NativeDialogueService.handleAssign(
            [["陌生佣兵", "佣兵", "主角模板", "……", "普通", stranger, ""]], false);
        var p:Object = lastPayload();
        assertEq("static", p.portrait.kind, "stranger: protocol-valid empty static slot keeps dialogue");
        assertEq("", p.portrait.key, "stranger: explicit missing, no player dressup");
        stranger.removeMovieClip();
        // 有身份的陌生佣兵仍用自己的字段，不得混入玩家
        resetCalls();
        var merc:Object = {性别:"女", 脸型:"佣兵脸乙", 上装装备:"佣兵衣乙"};
        NativeDialogueService.handleAssign(
            [["佣兵乙", "佣兵", "主角模板", "在", "普通", merc, ""]], false);
        p = lastPayload();
        assertEq("佣兵脸乙", p.portrait.appearance.face, "stranger-merc: own face");
        assertEq("佣兵衣乙", p.portrait.appearance.body, "stranger-merc: own body");
        assertEq("", p.portrait.appearance.head, "stranger-merc: empty head stays empty, not player 装备栏");
        NativeDialogueService.cancelActive("test");
    }

    private static function test_stage_attrobj_player_line():Void {
        resetCalls();
        // 生产入口形状回归：StageInfo.parseSingleDialogue 产出的 SubDialogue
        // 行 target=属性对象（attrObj），生产 XML 从不写外观字段 → 全 "" 元
        // 数据 → 归主角权威源，不得误判陌生单位而缺图（I4-F1 回归钉）。
        _root.控制目标 = "hero";
        _root.gameworld.hero = {性别:"", 脸型:"", 发型:"", 头部装备:null, 上装装备:null};
        _root.性别 = "男";
        _root.脸型 = "玩家脸甲";
        _root.发型 = "寸头";
        _root.物品栏 = {装备栏:{getNameString: function(s:String):String {
            return (s == "上装装备") ? "钛合金装甲" : "";
        }}};
        var raw:Array = [{Name:"$PC", Title:"$PC_TITLE", Char:"$PC_CHAR",
            Text:"先确认坐标。", ImageUrl:"", PrimaryWeapon:"G36"}];
        var parsed:Array =
            org.flashNight.arki.scene.StageInfo.parseSingleDialogue(raw);
        assert(parsed != null && parsed.length == 1,
            "stage-attr: parseSingleDialogue produced row");
        assert(parsed[0].target != null && parsed[0].target.长枪 == "G36",
            "stage-attr: target is attrObj carrying weapon fields");
        NativeDialogueService.beginStage(parsed, null);
        var p:Object = lastPayload();
        var ap:Object = p.portrait.appearance;
        assertEq("doll", p.portrait.kind, "stage-attr: $PC_CHAR row keeps doll portrait");
        assert(ap != null, "stage-attr: appearance not missing");
        assertEq("男", ap.gender, "stage-attr: gender from _root authority");
        assertEq("玩家脸甲", ap.face, "stage-attr: face from _root authority");
        assertEq("钛合金装甲", ap.body, "stage-attr: body from 装备栏 authority");
        assert(ap.keyMap == null,
            "stage-attr: attrObj weapon name never enters keyMap");
        assertEq("先确认坐标。", p.text, "stage-attr: text preserved");
        NativeDialogueService.cancelActive("test");
    }

    private static function test_custom_attrobj_keeps_own():Void {
        resetCalls();
        // 自定义 attrObj（作者写了外观属性）→ 用自身字段，不借玩家
        _root.控制目标 = "hero";
        _root.gameworld.hero = {性别:"男", 脸型:"玩家脸", 上装装备:"钛合金装甲"};
        _root.性别 = "男";
        _root.脸型 = "玩家脸";
        _root.物品栏 = {装备栏:{getNameString: function(s:String):String {
            return "钛合金装甲";
        }}};
        var attrObj:Object = {性别:"女", 脸型:"定制脸", 发型:"定制发",
            上装装备:"定制衣", 头部装备:"定制盔"};
        NativeDialogueService.handleAssign(
            [["访客", "", "主角模板", "问好", "普通", attrObj, ""]], false);
        var ap:Object = lastPayload().portrait.appearance;
        assertEq("doll", lastPayload().portrait.kind, "custom-attr: doll kind");
        assertEq("女", ap.gender, "custom-attr: own gender not player 男");
        assertEq("定制脸", ap.face, "custom-attr: own face");
        assertEq("定制衣", ap.body, "custom-attr: own body not player 钛甲");
        NativeDialogueService.cancelActive("test");
    }

    private static function test_same_name_not_hero():Void {
        resetCalls();
        // F3：异父同名 MC 与带 _name 裸对象不得冒充主角
        _root.控制目标 = "hero";
        _root.gameworld.hero = {性别:"女", 脸型:"玩家脸甲", 上装装备:"钛合金装甲"};
        _root.性别 = "女";
        _root.脸型 = "玩家脸甲";
        _root.物品栏 = {装备栏:{getNameString: function(s:String):String {
            return (s == "上装装备") ? "钛合金装甲" : "";
        }}};
        // _name==="hero" 但 _parent===_root ≠ gameworld → 无身份单位壳 → 缺图
        var holder:MovieClip = _root.createEmptyMovieClip(
            "__ndHolder", _root.getNextHighestDepth());
        var imposter:MovieClip = holder.createEmptyMovieClip("hero", 0);
        NativeDialogueService.handleAssign(
            [["冒名者", "", "主角模板", "……", "普通", imposter, ""]], false);
        var p:Object = lastPayload();
        assertEq("static", p.portrait.kind,
            "imposter-mc: same-name different-parent MC is not hero");
        assertEq("", p.portrait.key,
            "imposter-mc: missing image, no player dressup");
        holder.removeMovieClip();
        // 带 _name 的普通对象：不再是主角；带身份 → 按自身字段渲染（非玩家装备）
        resetCalls();
        var fake:Object = {_name:"hero", 性别:"女", 脸型:"冒牌脸"};
        NativeDialogueService.handleAssign(
            [["冒名者", "", "主角模板", "……", "普通", fake, ""]], false);
        p = lastPayload();
        assertEq("冒牌脸", p.portrait.appearance.face,
            "imposter-obj: own identity rendered, not hero-routed");
        assertEq("", p.portrait.appearance.body,
            "imposter-obj: no player equipment fill");
        NativeDialogueService.cancelActive("test");
    }

    private static function test_frozen_no_root_drift():Void {
        resetCalls();
        // 冻结在 capture 时刻：之后 _root 身份/装备变更不得漂移已冻结行
        _root.控制目标 = "hero";
        _root.gameworld.hero = {性别:"女", 脸型:"玩家脸甲", 上装装备:"钛合金装甲"};
        _root.性别 = "女";
        _root.脸型 = "玩家脸甲";
        _root.物品栏 = {装备栏:{getNameString: function(s:String):String {
            return (s == "上装装备") ? "钛合金装甲" : "";
        }}};
        NativeDialogueService.handleAssign([
            ["主角", "", "玩家", "第一句", "普通", null, ""],
            ["主角", "", "玩家", "第二句", "普通", null, ""]], false);
        _root.脸型 = "已改脸";
        _root.性别 = "男";
        _root.gameworld.hero.上装装备 = "已卸载";
        _root.物品栏.装备栏.getNameString = function(s:String):String { return "新装备"; };
        NativeDialogueService.advance();
        var ap:Object = lastPayload().portrait.appearance;
        assertEq("玩家脸甲", ap.face, "frozen: second line keeps entry face");
        assertEq("女", ap.gender, "frozen: second line keeps entry gender");
        assertEq("钛合金装甲", ap.body, "frozen: second line keeps entry equipment");
        NativeDialogueService.cancelActive("test");
    }

    private static function test_transport_and_stage_replacement():Void {
        resetCalls();
        NativeDialogueService.beginStage([{name:"剧情", char:"卫兵", text:"旧正文"}],
            {name:"AfterReplace", args:[3]});
        var before:String = curRid();
        NativeDialogueService.handleAssign(rows(1), true);
        assert(curRid() != before, "stage replacement: retires old request");
        assert(_root.暂停 === true, "stage replacement: preserves pause responsibility");
        assertEq(0, published.length, "stage replacement: does not publish early");
        var web:String = PauseManager.lease(true, "webpanel");
        _root.server.isSocketConnected = false;
        NativeDialogueService.onTransportDisconnected();
        assert(curSession() == null, "disconnect: no hidden dialogue remains");
        assertEq(1, published.length, "disconnect: following event delivered once");
        assertEq("AfterReplace", published[0].name, "replacement: preserves stage following event");
        assert(_root.暂停 === true, "disconnect: keeps another window pause");
        PauseManager.releaseLease(web);
        assert(_root.暂停 === false, "disconnect: no dialogue claim leak");
        NativeDialogueService.onTransportDisconnected();
        assertEq(1, published.length, "disconnect: repeat is idempotent");
        _root.server.isSocketConnected = true;
    }
}
