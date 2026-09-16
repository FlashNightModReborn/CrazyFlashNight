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
 *   - Host 不可达（发送失败）时按显式结束兜底、防剧情软锁；
 *   - wire v2：caps 闩/socket generation、book 物化与 epoch、mutation 确认
 *     五元校验与 status 三态、线性化终态（stale/未来/缺失 epoch 拒绝、
 *     旧 finish 只补 hide）、advance no-op、set/book/append 失败分类。
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

    // ── v2 装夹 ──
    // sendTaskWithCallback 出站捕获：{type,payload,callback,timeoutMs,sentAt,fired}；
    // callback 由测试手动触发 applied/rejected/超时/迟到。出向帧（sentOps）与
    // 入向动作各自 FIFO，跨方向交叉由测试顺序显式编排（无随机洗牌）。
    public static var sentOps:Array = null;
    // sendTaskWithCallback 底层发送闸门（false → 桩同步回调 send failed）
    public static var cbSendResult:Boolean = true;
    // 可手动推进的墙钟（毫秒）；advanceClock 驱动 callback 超时
    public static var clockMs:Number = 0;
    // 连接代令牌序号（bumpConn 每次生成新 xmlSocket 身份）
    public static var connGen:Number = 0;
    // §4.6 门禁装夹真值源：test_v2_business_gate 内经 _global 桩替换
    // SaveManager.getInstance().hasRewardCommitPending() 的返回值
    public static var rewardPending:Boolean = false;

    private static var _saved:Object = null;
    private static var _savedCtx = undefined;
    private static var _savedSaveMgr = undefined;
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
        sentOps = [];
        cbSendResult = true;
        clockMs = 0;
        published = [];
        sendResult = true;
        NativeDialogueService.forceSnapshot = false;
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
            xmlSocket: {gen: 0},
            sendTaskToNode: function(type, payload, cb):Boolean {
                org.flashNight.arki.dialogue.NativeDialogueServiceTest.recorded.push(
                    {type:type, payload:payload});
                return org.flashNight.arki.dialogue.NativeDialogueServiceTest.sendResult;
            },
            sendTaskWithCallback: function(type, payload, extra, cb, timeoutMs):Void {
                var T = org.flashNight.arki.dialogue.NativeDialogueServiceTest;
                if (!this.isSocketConnected) {
                    cb({success:false, error:"socket not connected"});
                    return;
                }
                if (T.cbSendResult === false) {
                    cb({success:false, error:"send failed"});
                    return;
                }
                T.sentOps.push({type:type, payload:payload, callback:cb,
                    timeoutMs:timeoutMs, sentAt:T.clockMs, fired:false});
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

        // §4.6 门禁桩兜底恢复（正常路径在用例末尾已还原）
        var nsS:Object = (g.org != null && g.org.flashNight != null
            && g.org.flashNight.neur != null && g.org.flashNight.neur.Server != null)
            ? g.org.flashNight.neur.Server : null;
        if (nsS != null && _savedSaveMgr !== undefined) {
            nsS.SaveManager = _savedSaveMgr;
        }
        _savedSaveMgr = undefined;
        rewardPending = false;

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

    // ── v2 装夹辅助 ─────────────────────────────────────────────

    /** 换连接代：生成新的 xmlSocket 身份令牌（不重发 caps → 旧代闩失效）。 */
    private static function bumpConn():Void {
        connGen++;
        _root.server.xmlSocket = {gen: connGen};
    }

    /** v2 会话前置：新连接代 + 下发含 book 的 caps。 */
    private static function v2Setup():Void {
        resetCalls();
        bumpConn();
        NativeDialogueService.applyCaps(["snapshot", "book"]);
    }

    /** 断连清闩（生产清闩路径 = socket close → onTransportDisconnected）。 */
    private static function clearCaps():Void {
        NativeDialogueService.onTransportDisconnected();
        bumpConn();
    }

    private static function lastSentOp():Object {
        return sentOps[sentOps.length - 1];
    }

    /** 触发确认帧 applied 应答（按文档 §4.3 ack 形状回填回显字段）。 */
    private static function ackApplied(entry:Object, rowCount:Number):Void {
        entry.fired = true;
        var ep:Object = entry.payload;
        var resp:Object = {
            success:true, requestId:ep.requestId, sceneId:ep.sceneId,
            op:ep.op, status:"applied"
        };
        if (ep.epoch != undefined) {
            resp.requestedEpoch = ep.epoch;
            resp.appliedEpoch = ep.epoch;
        }
        if (rowCount != undefined && !isNaN(rowCount)) resp.rowCount = rowCount;
        entry.callback(resp);
    }

    /** 触发确认帧 rejected 应答。 */
    private static function ackRejected(entry:Object, reason:String):Void {
        entry.fired = true;
        var ep:Object = entry.payload;
        entry.callback({
            success:true, requestId:ep.requestId, sceneId:ep.sceneId,
            op:ep.op, status:"rejected", reason:reason
        });
    }

    /** 推进装夹墙钟；越过期限的未决回调收到 callback timeout。 */
    private static function advanceClock(ms:Number):Void {
        clockMs += ms;
        var n:Number = sentOps.length;
        for (var i:Number = 0; i < n; i++) {
            var e:Object = sentOps[i];
            if (!e.fired && e.timeoutMs != undefined && e.timeoutMs > 0
                    && clockMs - e.sentAt >= e.timeoutMs) {
                e.fired = true;
                e.callback({success:false, error:"callback timeout"});
            }
        }
    }

    /** v2 合法终态刺激：{verb:"finish", epoch, finalIndex, reason}。 */
    private static function v2Finish(rid:String, sid:String, epoch, finalIndex,
                                     reason:String):Void {
        NativeDialogueService.handleAction({
            task:"cmd", action:"nativeDialogueAction",
            requestId:rid, sceneId:sid, verb:"finish",
            epoch:epoch, finalIndex:finalIndex, reason:reason});
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
        test_prefetch_piggyback();

        // ── wire v2（以上 v1 套件原样保留）──
        test_v2_caps_latch();
        test_v2_book_materialize();
        test_v2_epoch_append_set();
        test_v2_finish_linearization();
        test_v2_terminal_finish_resends_hide();
        test_v2_mutation_ack_paths();
        test_v2_status_query_three_way();
        test_v2_stale_callback_ignored();
        test_v2_advance_noop();
        test_v2_failure_classification();
        test_v2_business_gate();
        test_v2_cross_direction_fifo();

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

    private static function test_prefetch_piggyback():Void {
        resetCalls();
        // 下一句有立绘、无新配图：prefetch 仅含 portrait
        NativeDialogueService.handleAssign([
            ["NPC0", "称号", "卫兵", "第0句", "普通", null, ""],
            ["NPC1", "称号", "军需官", "第1句", "微笑", null, ""]], false);
        var p:Object = lastPayload();
        assert(p.prefetch != null, "prefetch: present when next line exists");
        assertEq("static", p.prefetch.portrait.kind, "prefetch: next portrait kind");
        assertEq("军需官", p.prefetch.portrait.key, "prefetch: next portrait key");
        assertEq("微笑", p.prefetch.portrait.expression, "prefetch: next portrait expression");
        assert(p.prefetch.imageAction == undefined,
            "prefetch: keep next image carries no imageAction");
        assert(p.prefetch.imagePath == undefined,
            "prefetch: keep next image carries no imagePath");
        // 末句：prefetch 不挂
        NativeDialogueService.advance();
        p = lastPayload();
        assertEq(1, p.lineIndex, "prefetch: advanced to last line");
        assert(p.prefetch == undefined, "prefetch: absent on last line");

        // 下一句显式换新配图：prefetch 带 imageAction=show + imagePath
        resetCalls();
        NativeDialogueService.handleAssign([
            ["NPC0", "称号", "卫兵", "第0句", "普通", null, ""],
            ["NPC1", "称号", "军需官", "第1句", "普通", null, "img/cg_01.png"]], false);
        p = lastPayload();
        assertEq("军需官", p.prefetch.portrait.key,
            "prefetch: portrait carried alongside image");
        assertEq("show", p.prefetch.imageAction, "prefetch: imageAction show for new image");
        assertEq("img/cg_01.png", p.prefetch.imagePath, "prefetch: imagePath carried");

        // 下一句配图 close（clear）：不带 image 字段，立绘仍捎带
        resetCalls();
        NativeDialogueService.handleAssign([
            ["NPC0", "称号", "卫兵", "第0句", "普通", null, ""],
            ["NPC1", "称号", "军需官", "第1句", "普通", null, "close"]], false);
        p = lastPayload();
        assert(p.prefetch != null, "prefetch: portrait-only when next clears image");
        assertEq("军需官", p.prefetch.portrait.key, "prefetch: portrait kept over close image");
        assert(p.prefetch.imageAction == undefined,
            "prefetch: close next image carries no imageAction");
        assert(p.prefetch.imagePath == undefined,
            "prefetch: close next image carries no imagePath");

        // 下一句无立绘（key 为空）但有新配图：prefetch 仅含 image 字段
        resetCalls();
        NativeDialogueService.handleAssign([
            ["NPC0", "称号", "卫兵", "第0句", "普通", null, ""],
            ["旁白", "", "", "旁白句", "普通", null, "img/cg_02.png"]], false);
        p = lastPayload();
        assert(p.prefetch != null, "prefetch: image-only when next has no portrait");
        assert(p.prefetch.portrait == undefined, "prefetch: empty-key next portrait omitted");
        assertEq("show", p.prefetch.imageAction, "prefetch: image-only imageAction show");
        assertEq("img/cg_02.png", p.prefetch.imagePath, "prefetch: image-only imagePath");

        // 下一句既无立绘又无新配图：prefetch 整体不挂
        resetCalls();
        NativeDialogueService.handleAssign([
            ["NPC0", "称号", "卫兵", "第0句", "普通", null, ""],
            ["旁白", "", "", "旁白句", "普通", null, ""]], false);
        p = lastPayload();
        assert(p.prefetch == undefined,
            "prefetch: absent when next has neither portrait nor image");
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

    // ── wire v2 用例 ────────────────────────────────────────────

    private static function test_v2_caps_latch():Void {
        // 未见本代 caps → v1（默认态，不试探 book）
        resetCalls();
        NativeDialogueService.handleAssign(rows(1), false);
        assertEq("v1", curSession().wire, "caps: no caps -> v1 wire");
        assertEq(0, sentOps.length, "caps: v1 uses sendTaskToNode only");
        assertEq("show", lastPayload().op, "caps: v1 show emitted");
        NativeDialogueService.cancelActive("t");

        // 本代 caps 含 book → v2 book
        v2Setup();
        NativeDialogueService.handleAssign(rows(2), false);
        var s:Object = curSession();
        assertEq("v2", s.wire, "caps: book caps -> v2 wire");
        assertEq(1, sentOps.length, "caps: book sent via callback channel");
        var p:Object = lastSentOp().payload;
        assertEq(2, p.version, "book: version 2");
        assertEq("book", p.op, "book: op");
        assertEq("inline", p.kind, "book: kind inline");
        assertEq(1, p.epoch, "book: epoch starts at 1");
        assertEq(0, p.startIndex, "book: startIndex 0");
        assertEq(s.requestId, p.requestId, "book: requestId bound");
        assertEq(s.sceneId, p.sceneId, "book: sceneId bound");
        assertEq("ordinary", p.mode, "book: mode carried");
        assertEq(2, p.lines.length, "book: lines materialized");
        assertEq("NPC0", p.lines[0].name, "book: line name");
        assertEq("卫兵", p.lines[0].portrait.key, "book: line portrait key");
        assertEq(0, countOp("show"), "caps: v2 sends no v1 show");
        NativeDialogueService.cancelActive("t");

        // v1 起头终身 v1：会话中补发 caps 不改既有会话 wire
        resetCalls();
        clearCaps();
        NativeDialogueService.handleAssign(rows(2), false);
        assertEq("v1", curSession().wire, "caps: session started v1");
        NativeDialogueService.applyCaps(["snapshot", "book"]);
        NativeDialogueService.advance();
        assertEq("v1", curSession().wire, "caps: mid-session caps keeps v1");
        assertEq("show", lastPayload().op, "caps: v1 advance still emits show");
        assertEq(0, sentOps.length, "caps: v1 session never uses callback channel");
        NativeDialogueService.cancelActive("t");

        // 换连接代未重发 caps → 旧代闩不生效 → v1；重发 → v2
        resetCalls();
        bumpConn();
        NativeDialogueService.handleAssign(rows(1), false);
        assertEq("v1", curSession().wire,
            "caps: new generation without caps -> v1");
        NativeDialogueService.cancelActive("t");
        resetCalls();
        NativeDialogueService.applyCaps(["snapshot", "book"]);
        NativeDialogueService.handleAssign(rows(1), false);
        assertEq("v2", curSession().wire, "caps: re-pushed caps -> v2");
        NativeDialogueService.cancelActive("t");

        // 断连清闩 → v1
        resetCalls();
        clearCaps();
        NativeDialogueService.handleAssign(rows(1), false);
        assertEq("v1", curSession().wire,
            "caps: latch cleared on disconnect -> v1");
        NativeDialogueService.cancelActive("t");

        // forceSnapshot：caps 在但配置强制 → v1
        resetCalls();
        NativeDialogueService.applyCaps(["snapshot", "book"]);
        NativeDialogueService.forceSnapshot = true;
        NativeDialogueService.handleAssign(rows(1), false);
        assertEq("v1", curSession().wire, "caps: forceSnapshot -> v1");
        NativeDialogueService.forceSnapshot = false;
        NativeDialogueService.cancelActive("t");
    }

    private static function test_v2_book_materialize():Void {
        v2Setup();
        var prevName = _root.角色名;
        _root.角色名 = "测试玩家";
        NativeDialogueService.handleAssign([
            null,
            ["角色名", "称号", undefined, "第一句", "普通", null, ""],
            ["旁白", "", "", "第二句", "普通", null, "close"],
            null,
            ["NPC2", "称号", "军需官", "第三句", "微笑", null, "img/cg_03.png"]
        ], false);
        _root.角色名 = prevName;
        var s:Object = curSession();
        assertEq("v2", s.wire, "mat: v2 wire");
        assertEq(3, s.rowCount, "mat: normalized rowCount skips null rows");
        var p:Object = lastSentOp().payload;
        assertEq(3, p.lines.length, "mat: book lines skip null rows");
        assertEq("测试玩家", p.lines[0].name,
            "mat: 角色名 placeholder resolved at materialize time");
        assertEq("static", p.lines[0].portrait.kind,
            "mat: missing char -> static slot");
        assertEq("", p.lines[0].portrait.key,
            "mat: missing char -> empty key");
        assertEq("clear", p.lines[1].imageAction,
            "mat: close image -> clear");
        assertEq("show", p.lines[2].imageAction, "mat: new image -> show");
        assertEq("img/cg_03.png", p.lines[2].imagePath,
            "mat: imagePath carried");
        assertEq("军需官", p.lines[2].portrait.key, "mat: portrait key");
        assertEq("微笑", p.lines[2].portrait.expression,
            "mat: expression kept");
        assertEq("第三句", p.lines[2].text, "mat: text carried");
        NativeDialogueService.cancelActive("t");

        // 规范化后空集 → 不发 book，直接 finishSession（孤儿 hide 同兜底形）
        v2Setup();
        NativeDialogueService.handleAssign([null, null], false);
        assert(curSession() == null, "mat: empty normalized set finishes");
        assertEq(0, sentOps.length, "mat: empty set sends no book");
        assertEq(1, countOp("hide"), "mat: empty set emits orphan hide");
        assertEq(2, lastPayload().version, "mat: orphan hide carries v2 tag");
        assertEq(0, published.length, "mat: empty set publishes nothing");
    }

    private static function test_v2_epoch_append_set():Void {
        v2Setup();
        org.flashNight.arki.key.KeyManager.refreshKeySettings(
            [["互动键", "互动键", 69]], null, null);
        NativeDialogueService.handleAssign(rows(2), false);
        var book:Object = lastSentOp();
        assertEq(69, book.payload.advanceKey, "epoch: book carries advanceKey");
        ackApplied(book, 2);
        assert(curSession().bookSettled === true,
            "epoch: applied settles book");
        assertEq(0, curSession().pendingCount, "epoch: applied clears pending");

        // append：发送前 epoch 递增，baseEpoch=递增前值，restartIndex 回第 0 句
        NativeDialogueService.handleAssign(rows(2), false);
        var ap:Object = lastSentOp();
        assertEq("append", ap.payload.op, "append: op");
        assertEq(1, ap.payload.baseEpoch, "append: baseEpoch = previous epoch");
        assertEq(2, ap.payload.epoch, "append: epoch bumped before send");
        assertEq(0, ap.payload.restartIndex, "append: restartIndex 0");
        assertEq(2, ap.payload.lines.length, "append: only appended rows");
        assertEq("第0句", ap.payload.lines[0].text, "append: appended text");
        assertEq(2, curSession().epoch,
            "append: session epoch advanced without ack");
        assertEq(4, curSession().rowCount,
            "append: normalized count accumulates");
        assertEq(0, curSession().index, "append: index back to line 0");
        ackApplied(ap, 4);

        // set：白名单字段变更不动行集、不 bump epoch
        NativeDialogueService.notifyAdvanceKeyChanged(88);
        var setOp:Object = lastSentOp();
        assertEq("set", setOp.payload.op, "set: op");
        assertEq(88, setOp.payload.advanceKey, "set: advanceKey carried");
        assert(setOp.payload.epoch == undefined, "set: no epoch field");
        assert(setOp.payload.baseEpoch == undefined, "set: no baseEpoch field");
        assertEq(2, curSession().epoch, "set: epoch not bumped");
        assertEq(88, curSession().advanceKey, "set: sent value latched");
        ackApplied(setOp);
        assert(curSession().setPending === false,
            "set: applied clears setPending");
        var n:Number = sentOps.length;
        NativeDialogueService.notifyAdvanceKeyChanged(88);
        assertEq(n, sentOps.length, "set: same value not resent");
        NativeDialogueService.cancelActive("t");
    }

    private static function test_v2_finish_linearization():Void {
        v2Setup();
        NativeDialogueService.handleAssign(rows(3), false);
        ackApplied(lastSentOp(), 3);
        var rid:String = curRid();

        // 缺失/非整数/过去/未来 epoch 全部拒绝，会话续存且零副作用
        v2Finish(rid, ctxScene, undefined, 2, "advance_past_end");
        assert(curSession() != null, "lin: missing epoch rejected");
        v2Finish(rid, ctxScene, 1.5, 2, "advance_past_end");
        assert(curSession() != null, "lin: non-integer epoch rejected");
        v2Finish(rid, ctxScene, 0, 2, "advance_past_end");
        assert(curSession() != null, "lin: stale epoch rejected");
        v2Finish(rid, ctxScene, 7, 2, "advance_past_end");
        assert(curSession() != null, "lin: future epoch rejected");
        v2Finish(rid, ctxScene, 1, 1, "advance_past_end");
        assert(curSession() != null,
            "lin: finalIndex != rowCount-1 rejected");
        v2Finish(rid, ctxScene, 1, 5, "close");
        assert(curSession() != null, "lin: close out-of-range rejected");
        v2Finish(rid, ctxScene, 1, 2, "bogus");
        assert(curSession() != null, "lin: unknown reason rejected");
        assertEq(0, countOp("hide"), "lin: rejects never emit hide");
        assertEq(0, published.length, "lin: rejects never publish");

        // v2 只收 finish 动词：v1 的 advance/close 一律无效
        act("advance", rid, ctxScene, 1);
        assert(curSession() != null && curSession().index == 0,
            "lin: v1 advance verb rejected on v2");
        act("close", rid, ctxScene, 1);
        assert(curSession() != null, "lin: v1 close verb rejected on v2");
        assertEq(0, countOp("hide"), "lin: wrong-verb rejects emit nothing");

        // 合法 close → 走既有 finishSession 顺序
        v2Finish(rid, ctxScene, 1, 1, "close");
        assert(curSession() == null, "lin: legal close commits finish");
        assertEq(1, countOp("hide"), "lin: finish emits hide");
        assertEq(2, lastPayload().version, "lin: v2 hide carries version 2");

        // stage 会话：stale finish 不放 claim/不发事件，当代 epoch finish 成立
        v2Setup();
        NativeDialogueService.beginStage(
            [{name:"a", char:"卫兵", text:"0"}, {name:"a", char:"卫兵", text:"1"}],
            {name:"NextStage", args:null});
        ackApplied(lastSentOp(), 2);
        rid = curRid();
        assert(_root.暂停 === true, "lin: stage claim held");
        NativeDialogueService.handleAssign(rows(2), false);   // append epoch2 在途
        v2Finish(rid, ctxScene, 1, 3, "advance_past_end");    // 旧代终态
        assert(curSession() != null, "lin: stale finish cannot end new epoch");
        assert(_root.暂停 === true, "lin: stale finish keeps claim");
        assertEq(0, published.length, "lin: stale finish never publishes");
        assertEq(0, countOp("hide"), "lin: stale finish emits nothing");
        v2Finish(rid, ctxScene, 2, 3, "advance_past_end");    // 当代合法终态
        assert(curSession() == null, "lin: current-epoch finish commits");
        assertEq(1, published.length, "lin: finish publishes once");
        assertEq("NextStage", published[0].name, "lin: published event");
        assert(_root.暂停 === false, "lin: finish releases claim");
    }

    private static function test_v2_terminal_finish_resends_hide():Void {
        v2Setup();
        NativeDialogueService.beginStage(
            [{name:"a", char:"卫兵", text:"0"}], {name:"NextStage", args:null});
        var rid:String = curRid();
        ackApplied(lastSentOp(), 1);
        v2Finish(rid, ctxScene, 1, 0, "advance_past_end");
        assertEq(1, published.length, "dup: event published once");
        assertEq(1, countOp("hide"), "dup: first hide");

        // 已提交会话的重复 finish（Host closing 重试同一份冻结请求）→ 只补 hide
        v2Finish(rid, ctxScene, 1, 0, "advance_past_end");
        assertEq(2, countOp("hide"), "dup: terminal finish resends matching hide");
        assertEq(1, published.length, "dup: never republishes event");
        v2Finish(rid, ctxScene, 1, 0, "advance_past_end");
        assertEq(3, countOp("hide"), "dup: each retry resends hide once");
        assertEq(1, published.length, "dup: still single publish");
        // sceneId 不符的旧 finish → 不补发
        v2Finish(rid, "sc.other", 1, 0, "advance_past_end");
        assertEq(3, countOp("hide"), "dup: mismatched sceneId not resent");

        // 新会话已开后旧 rid 的 finish 仍只补旧 hide，不动新会话
        resetCalls();
        NativeDialogueService.applyCaps(["snapshot", "book"]);
        NativeDialogueService.handleAssign(rows(1), false);
        var rid2:String = curRid();
        assert(rid2 != rid, "dup: new session new rid");
        v2Finish(rid, ctxScene, 1, 0, "advance_past_end");
        assertEq(1, countOp("hide"), "dup: old-rid finish resends old hide only");
        assertEq(rid, lastPayload().requestId,
            "dup: resent hide tombstones old rid");
        assert(curSession() != null && curRid() == rid2,
            "dup: new session untouched");
        assertEq(0, published.length, "dup: no publish on resend");
        NativeDialogueService.cancelActive("t");
    }

    private static function test_v2_mutation_ack_paths():Void {
        // applied：清 pending、置采用标记
        v2Setup();
        NativeDialogueService.handleAssign(rows(2), false);
        var book:Object = lastSentOp();
        assert(curSession().bookSettled === false, "ack: book pending pre-ack");
        assertEq(1, curSession().pendingCount, "ack: pending registered");
        ackApplied(book, 2);
        assert(curSession().bookSettled === true, "ack: applied settles book");
        assertEq(0, curSession().pendingCount, "ack: applied clears pending");

        // rejected：book 首次采用前 → 降级 v1 快照序列
        v2Setup();
        NativeDialogueService.handleAssign(rows(2), false);
        var rid:String = curRid();
        ackRejected(lastSentOp(), "malformed");
        assertEq("v1", curSession().wire, "ack: book rejected downgrades v1");
        assertEq("show", lastPayload().op, "ack: downgrade emits v1 show");
        assertEq(1, lastPayload().version, "ack: v1 show shape");
        assertEq(rid, lastPayload().requestId, "ack: downgrade keeps requestId");
        NativeDialogueService.advance();
        assertEq(1, lastPayload().lineIndex,
            "ack: downgraded session continues v1 flow");
        NativeDialogueService.cancelActive("t");

        // 底层发送失败（同步 send failed）→ 同一降级路径
        v2Setup();
        cbSendResult = false;
        NativeDialogueService.handleAssign(rows(2), false);
        cbSendResult = true;
        assertEq("v1", curSession().wire, "ack: send-failed book falls back v1");
        assertEq("show", lastPayload().op, "ack: fallback emits v1 show");
        assertEq(0, curSession().pendingCount,
            "ack: send-failed leaves no ghost pending");
        NativeDialogueService.cancelActive("t");

        // 回执缺 status → 结果未知：转 status 查询而非直接分类
        v2Setup();
        NativeDialogueService.handleAssign(rows(2), false);
        var b2:Object = lastSentOp();
        b2.callback({success:true, requestId:b2.payload.requestId,
            sceneId:b2.payload.sceneId, op:"book"});
        assertEq("status", lastSentOp().payload.op,
            "ack: indeterminate ack escalates to status query");
        NativeDialogueService.cancelActive("t");

        // socket 断开：book 无路 → v1 兜底同样失败 → finishSession 防软锁
        v2Setup();
        _root.server.isSocketConnected = false;
        NativeDialogueService.beginStage(
            [{name:"a", char:"卫兵", text:"0"}], {name:"Down", args:null});
        _root.server.isSocketConnected = true;
        assert(curSession() == null, "ack: unreachable host finishes session");
        assertEq(1, published.length,
            "ack: send-failure fallback consumes event once");
        assert(_root.暂停 === false, "ack: send-failure releases claim");
    }

    private static function test_v2_status_query_three_way():Void {
        // 超时 → status 查询；appliedEpoch≥请求代际 → 视为已采用补确认
        v2Setup();
        NativeDialogueService.handleAssign(rows(2), false);
        advanceClock(3100);
        var st:Object = lastSentOp();
        assertEq("status", st.payload.op, "status: timeout issues query");
        assertEq(1, st.payload.queryEpoch, "status: queryEpoch = book epoch");
        st.callback({success:true, requestId:st.payload.requestId,
            sceneId:st.payload.sceneId, state:"active",
            appliedEpoch:1, rowCount:2});
        assert(curSession().bookSettled === true,
            "status: appliedEpoch>=epoch confirms adoption");
        assertEq("v2", curSession().wire, "status: confirmed stays v2");
        NativeDialogueService.cancelActive("t");

        // 明确未采用（appliedEpoch 低于请求代际）→ 失败分类（book → 降级 v1）
        v2Setup();
        NativeDialogueService.handleAssign(rows(2), false);
        advanceClock(3100);
        st = lastSentOp();
        st.callback({success:true, requestId:st.payload.requestId,
            sceneId:st.payload.sceneId, state:"active",
            appliedEpoch:0, rowCount:0});
        assertEq("v1", curSession().wire,
            "status: not-adopted book downgrades v1");
        assertEq("show", lastPayload().op, "status: downgrade emits v1 show");
        NativeDialogueService.cancelActive("t");

        // 仍未知（应答缺 appliedEpoch）→ 保留托管、不 finishSession
        v2Setup();
        NativeDialogueService.handleAssign(rows(2), false);
        advanceClock(3100);
        st = lastSentOp();
        st.callback({success:true, requestId:st.payload.requestId,
            sceneId:st.payload.sceneId, state:"unknown"});
        assert(curSession() != null, "status: indeterminate keeps custody");
        assertEq("v2", curSession().wire, "status: custody stays v2");
        assertEq(0, countOp("hide"), "status: custody never finishes");

        // 查询自身也超时 → 仍托管，绝不伪装玩家已结束
        advanceClock(3100);
        assert(curSession() != null, "status: query timeout keeps custody");
        assertEq(0, countOp("hide"), "status: still no hide after query timeout");
        assertEq(0, published.length, "status: custody never publishes");
        NativeDialogueService.cancelActive("t");

        // 会话已变：旧会话查询应答落在 dead 会话 → 忽略
        v2Setup();
        NativeDialogueService.handleAssign(rows(1), false);
        advanceClock(3100);
        st = lastSentOp();
        var rid1:String = curRid();
        NativeDialogueService.cancelActive("t");
        NativeDialogueService.handleAssign(rows(1), false);
        st.callback({success:true, requestId:rid1,
            sceneId:ctxScene, state:"active", appliedEpoch:1});
        assert(curSession() != null && curRid() != rid1,
            "status: dead-session query answer ignored");
        NativeDialogueService.cancelActive("t");
    }

    private static function test_v2_stale_callback_ignored():Void {
        v2Setup();
        NativeDialogueService.handleAssign(rows(1), false);
        var oldBook:Object = lastSentOp();
        var rid1:String = curRid();
        // 会话终结后旧回调抵达 → 不得撞新会话（会话对象身份校验）
        v2Finish(rid1, ctxScene, 1, 0, "advance_past_end");
        NativeDialogueService.handleAssign(rows(1), false);
        var rid2:String = curRid();
        assert(rid2 != rid1, "stale: new session new rid");
        var newBook:Object = lastSentOp();
        oldBook.callback({success:true, requestId:rid1, sceneId:ctxScene,
            op:"book", requestedEpoch:1, appliedEpoch:1, status:"applied"});
        assert(curSession() != null && curRid() == rid2,
            "stale: dead-session ack cannot touch new session");
        assert(curSession().bookSettled === false,
            "stale: dead-session ack does not settle new book");

        // 连接代不符的应答 → 忽略（生产上换代伴随断线收口；
        // 此处仅验证身份校验不放行，pending 等待自身超时/断线兜底）
        ackApplied(newBook, 1);
        NativeDialogueService.notifyAdvanceKeyChanged(88);
        var setOp:Object = lastSentOp();
        assert(curSession().setPending === true, "stale: set wait registered");
        bumpConn();
        setOp.callback({success:true, requestId:rid2, sceneId:ctxScene,
            op:"set", status:"applied"});
        assert(curSession().setPending === true,
            "stale: conn-mismatched ack ignored");
        NativeDialogueService.cancelActive("t");

        // requestId/sceneId/操作代际不符 → 忽略；全对上才清 pending
        v2Setup();
        NativeDialogueService.handleAssign(rows(1), false);
        var rid3:String = curRid();
        ackApplied(lastSentOp(), 1);
        NativeDialogueService.notifyAdvanceKeyChanged(77);
        var set2:Object = lastSentOp();
        set2.callback({success:true, requestId:"nd:9999", sceneId:ctxScene,
            op:"set", status:"applied"});
        assert(curSession().setPending === true,
            "stale: wrong-requestId ack ignored");
        set2.callback({success:true, requestId:rid3, sceneId:"sc.other",
            op:"set", status:"applied"});
        assert(curSession().setPending === true,
            "stale: wrong-sceneId ack ignored");
        set2.callback({success:true, requestId:rid3, sceneId:ctxScene,
            op:"set", status:"applied"});
        assert(curSession().setPending === false,
            "stale: matching ack resolves set wait");
        NativeDialogueService.handleAssign(rows(1), false);   // append epoch2
        var ap:Object = lastSentOp();
        ap.callback({success:true, requestId:rid3, sceneId:ctxScene,
            op:"append", requestedEpoch:99, appliedEpoch:99,
            status:"applied", rowCount:2});
        assertEq(1, curSession().pendingCount,
            "stale: epoch-mismatched ack leaves append pending");
        ap.callback({success:true, requestId:rid3, sceneId:ctxScene,
            op:"append", requestedEpoch:2, appliedEpoch:2,
            status:"applied", rowCount:2});
        assertEq(0, curSession().pendingCount,
            "stale: matching epoch ack resolves pending");
        NativeDialogueService.cancelActive("t");
    }

    private static function test_v2_advance_noop():Void {
        v2Setup();
        NativeDialogueService.handleAssign(rows(3), false);
        ackApplied(lastSentOp(), 3);
        var nOut:Number = sentOps.length;
        var nIn:Number = recorded.length;
        NativeDialogueService.advance();
        assertEq(nOut, sentOps.length, "v2 advance: no callback-channel wire");
        assertEq(nIn, recorded.length, "v2 advance: no v1 wire");
        assertEq(0, curSession().index, "v2 advance: index untouched");
        assert(curSession() != null, "v2 advance: session survives");
        _root.对话框界面.下一句();
        assertEq(nOut, sentOps.length, "v2 facade 下一句: no wire out");
        assertEq(nIn, recorded.length, "v2 facade 下一句: no v1 wire");
        assert(curSession() != null, "v2 facade 下一句: session survives");
        NativeDialogueService.cancelActive("t");

        // 对照：v1 会话的 advance/facade 保持旧行为
        resetCalls();
        NativeDialogueService.onTransportDisconnected();
        bumpConn();
        NativeDialogueService.handleAssign(rows(2), false);
        NativeDialogueService.advance();
        assertEq(1, lastPayload().lineIndex, "v1 contrast: advance sends line 1");
        NativeDialogueService.cancelActive("t");
    }

    private static function test_v2_failure_classification():Void {
        // set 被拒 → 恢复上一个有效值，不结束剧情
        v2Setup();
        org.flashNight.arki.key.KeyManager.refreshKeySettings(
            [["互动键", "互动键", 69]], null, null);
        NativeDialogueService.handleAssign(rows(2), false);
        ackApplied(lastSentOp(), 2);
        NativeDialogueService.notifyAdvanceKeyChanged(88);
        var setOp:Object = lastSentOp();
        assertEq(88, curSession().advanceKey, "fail: sent value latched");
        ackRejected(setOp, "bad_key");
        assert(curSession() != null, "fail: set rejection keeps session");
        assertEq(69, curSession().advanceKey,
            "fail: set rejection restores previous valid key");
        assertEq(0, countOp("hide"), "fail: set rejection emits nothing");
        NativeDialogueService.notifyAdvanceKeyChanged(90);
        assertEq("set", lastSentOp().payload.op,
            "fail: later rebind still sends set");
        NativeDialogueService.cancelActive("t");

        // append 被拒 → 保住已接受内容与 stage 义务：finishSession 收尾
        v2Setup();
        NativeDialogueService.beginStage(
            [{name:"a", char:"卫兵", text:"0"}], {name:"Kept", args:null});
        ackApplied(lastSentOp(), 1);
        NativeDialogueService.handleAssign(rows(1), false);
        assertEq("append", lastSentOp().payload.op, "fail: append sent");
        ackRejected(lastSentOp(), "overflow");
        assert(curSession() == null, "fail: append rejection finishes session");
        assertEq(1, countOp("hide"), "fail: append rejection emits hide");
        assertEq(2, lastPayload().version, "fail: rejection hide is v2");
        assertEq(1, published.length,
            "fail: stage following event consumed once");
        assertEq("Kept", published[0].name,
            "fail: stage obligation preserved");
        assert(_root.暂停 === false, "fail: claim released on finish");

        // book 首拒降级 v1 后，后续 wire 全走 v1 形状
        v2Setup();
        NativeDialogueService.handleAssign(rows(2), false);
        ackRejected(lastSentOp(), "unsupported");
        assertEq("v1", curSession().wire, "fail: book reject latches v1");
        assertEq("show", lastPayload().op, "fail: downgrade emits v1 show");
        assertEq(1, lastPayload().version, "fail: v1 show version");
        NativeDialogueService.handleAssign(rows(1), false);   // v1 追加路径
        assertEq("show", lastPayload().op,
            "fail: post-downgrade append uses v1 show");
        assertEq(0, lastPayload().lineIndex,
            "fail: v1 append restarts at line 0");
        // sentOps 为累计日志：原始 book 记录保留，降级后不得新增回调帧
        assertEq(1, sentOps.length,
            "fail: post-downgrade never touches callback channel");
        NativeDialogueService.cancelActive("t");
    }

    private static function test_v2_cross_direction_fifo():Void {
        // 出向帧与入向动作各自 FIFO；交叉点由测试顺序显式编排。
        // 交叉一：finish(epoch1) 在 append 前抵达 → 终态成立；同 rid 后续
        //         追加意图落到新会话（旧 rid 永不复活）
        v2Setup();
        NativeDialogueService.handleAssign(rows(2), false);
        ackApplied(lastSentOp(), 2);
        var rid:String = curRid();
        v2Finish(rid, ctxScene, 1, 1, "advance_past_end");
        assert(curSession() == null, "xdir: finish before append commits");
        NativeDialogueService.handleAssign(rows(2), false);
        var rid2:String = curRid();
        assert(rid2 != rid, "xdir: post-finish assign opens new session");
        assertEq("book", lastSentOp().payload.op,
            "xdir: new session sends book not append");

        // 交叉二：append 先到（epoch 已推进）→ 旧 epoch finish 被拒，
        //         当代 epoch finish 成立；在途 append 的迟到 ack 落终态被忽略
        ackApplied(lastSentOp(), 2);
        NativeDialogueService.handleAssign(rows(1), false);   // append epoch2 在途
        var ap:Object = lastSentOp();
        v2Finish(rid2, ctxScene, 1, 2, "advance_past_end");
        assert(curSession() != null,
            "xdir: pre-append finish stale after epoch bump");
        v2Finish(rid2, ctxScene, 2, 2, "advance_past_end");
        assert(curSession() == null,
            "xdir: current-epoch finish commits over in-flight append");
        ap.callback({success:true, requestId:rid2, sceneId:ctxScene,
            op:"append", requestedEpoch:2, appliedEpoch:2,
            status:"applied", rowCount:3});
        assert(curSession() == null,
            "xdir: late append ack on terminal session ignored");
        assertEq(2, countOp("hide"), "xdir: one hide per committed finish");
        assertEq(0, published.length, "xdir: ordinary sessions publish none");
    }

    private static function test_v2_business_gate():Void {
        // §4.6：新增收口路径不得绕 rewardPending 门禁——defer +
        // 解除后重新核验身份与 epoch 再提交；cancel/teardown 撤销义务。
        // _global 桩 SaveManager 单例（同 NativeInteractionContext 桩约定）；
        // PauseManager.setRewardCommitPending 建真实暂停域；pending 解除后的
        // 冲刷由 tryAwaitingCommit 直调代行（生产唤醒点 = ServerManager 帧泵）。
        var g:Object = _global;
        if (g.org.flashNight.neur == null) g.org.flashNight.neur = {};
        if (g.org.flashNight.neur.Server == null) g.org.flashNight.neur.Server = {};
        var smNs:Object = g.org.flashNight.neur.Server;
        var savedSM = smNs.SaveManager;
        _savedSaveMgr = savedSM;
        smNs.SaveManager = {
            getInstance: function():Object {
                return {hasRewardCommitPending: function():Boolean {
                    return org.flashNight.arki.dialogue.NativeDialogueServiceTest
                        .rewardPending === true;
                }};
            }
        };

        // 一：append 被拒遭门禁 → 等待业务提交；解除后重验提交一次
        v2Setup();
        rewardPending = true;
        NativeDialogueService.beginStage(
            [{name:"a", char:"卫兵", text:"0"}], {name:"Kept", args:null});
        ackApplied(lastSentOp(), 1);
        PauseManager.setRewardCommitPending(true);
        NativeDialogueService.handleAssign(rows(1), false);   // append epoch2 在途
        ackRejected(lastSentOp(), "overflow");
        var s:Object = curSession();
        assert(s != null, "gate: append rejection deferred while pending");
        assert(s != null && s.awaitingCommit === true,
            "gate: awaiting-commit flag latched");
        assertEq(0, countOp("hide"), "gate: deferred finish emits no hide");
        assertEq(0, published.length,
            "gate: deferred finish emits no publish");
        assert(_root.暂停 === true, "gate: claim still held during defer");
        rewardPending = false;
        PauseManager.setRewardCommitPending(false);
        NativeDialogueService.tryAwaitingCommit();   // 代行帧泵冲刷
        assert(curSession() == null,
            "gate: pending release commits deferred finish");
        assertEq(1, countOp("hide"), "gate: commit emits hide");
        assertEq(1, published.length, "gate: commit publishes once");
        assertEq("Kept", published[0].name, "gate: event preserved");
        assert(_root.暂停 === false, "gate: claim released on commit");

        // 二：cancel 撤销义务——pending 中取消会话，解除后不得补发
        v2Setup();
        rewardPending = true;
        NativeDialogueService.beginStage(
            [{name:"a", char:"卫兵", text:"0"}], {name:"Revoked", args:null});
        ackApplied(lastSentOp(), 1);
        PauseManager.setRewardCommitPending(true);
        NativeDialogueService.handleAssign(rows(1), false);
        ackRejected(lastSentOp(), "overflow");
        s = curSession();
        assert(s != null && s.awaitingCommit === true,
            "gate: second defer latched");
        NativeDialogueService.cancelActive("t");
        assert(curSession() == null, "gate: cancel kills session");
        assertEq(0, published.length, "gate: cancel never publishes");
        rewardPending = false;
        PauseManager.setRewardCommitPending(false);
        NativeDialogueService.tryAwaitingCommit();
        assertEq(0, published.length,
            "gate: release after cancel republishes nothing");

        // 三：epoch 已推进 → 待提交义务丢弃（旧代终态裁决不压新代内容）
        v2Setup();
        rewardPending = true;
        NativeDialogueService.handleAssign(rows(1), false);
        ackApplied(lastSentOp(), 1);
        PauseManager.setRewardCommitPending(true);
        NativeDialogueService.handleAssign(rows(1), false);   // append epoch2
        ackRejected(lastSentOp(), "overflow");
        s = curSession();
        assert(s != null && s.awaitingCommit === true,
            "gate: defer latched for epoch-2 rejection");
        NativeDialogueService.handleAssign(rows(1), false);   // append epoch3 推进
        rewardPending = false;
        PauseManager.setRewardCommitPending(false);
        NativeDialogueService.tryAwaitingCommit();
        assert(curSession() != null,
            "gate: epoch-moved obligation dropped, session survives");
        assertEq(0, countOp("hide"), "gate: dropped obligation emits no hide");
        NativeDialogueService.cancelActive("t");

        // 恢复桩与真值源
        smNs.SaveManager = savedSM;
        _savedSaveMgr = undefined;
        rewardPending = false;
    }
}
