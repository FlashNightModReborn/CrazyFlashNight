import org.flashNight.arki.interaction.NativeInteractionContext;
import org.flashNight.arki.pause.PauseManager;
import org.flashNight.arki.dialogue.NativeDialogueAppearance;

/**
 * =============================================================================
 *  NativeDialogueService — native_dialogue 无头对白会话服务（AS2 权威侧）
 * -----------------------------------------------------------------------------
 *  契约（见 docs/对话框迁移与高清立绘治理-调研与施工准备-2026-09-12.md）：
 *    出向：sendTaskToNode("native_dialogue", payload, null)
 *      payload: {version:1, op:"show"|"hide", requestId:"nd:<正整数>", sceneId,
 *                revision:Number(同请求严格递增), lineIndex(0 起), lineCount,
 *                name, title, text,
 *                portrait:{kind:"static"|"doll", key, expression, appearance},
 *                imageAction:"keep"|"show"|"clear", imagePath, advanceKey?}
 *      hide 只需 requestId+sceneId 匹配；hide 后同一 requestId 不得再 show。
 *    入向：_root.gameCommands["nativeDialogueAction"]({task:"cmd",
 *          action:"nativeDialogueAction", requestId, sceneId, revision,
 *          verb:"advance"|"close"})。Host 只发动词，不执行剧情/奖励。
 *
 *  语义：
 *    - AS2 权威持有句序、人物、暂停责任与 finish/cancel。
 *    - 普通/任务对白不新增暂停；StageEvent 剧情对白经 beginStage() 持有
 *      PauseManager claim（OR 语义，见 PauseManager 头注释）。
 *    - finish（显式结束/末行 advance/发送失败兜底）：terminal→清 followingEvent
 *      →清会话→释放 claim→发 hide→最后才 publish 后续事件（重入安全，
 *      事件处理器再开对话时旧会话已不可见）。
 *    - cancel（场景取消/覆盖/compat 关闭）：terminal→清 followingEvent→释放
 *      claim→发 hide；绝不 publish。
 *    - followingEvent 永远只能由本服务在 finish 路径消费一次。
 *    - 临时失焦/Web 面板遮挡不发 hide（Host 侧 NativeHud 整体 Suspend）。
 *
 *  兼容面：
 *    _root.对话框界面 换成普通 Object facade（见 ensureCompat）；旧 authored
 *    MovieClip 由 初始化对话框界面 停住隐藏，AVM1 同路径重绑会重跑该初始化
 *    自动回到 facade。TaskPanelService 的 _visible 影子是惰性字段，不驱动会话。
 * =============================================================================
 */
class org.flashNight.arki.dialogue.NativeDialogueService {

    private static var _installed:Boolean = false;
    private static var _reqSeq:Number = 0;

    // 会话：{requestId, sceneId, revision, lines:Array, index:Number,
    //        mode:"ordinary"|"stage", leaseId:String|null,
    //        followingEvent:Object|null, terminal:Boolean}
    private static var _session:Object = null;

    // _root.对话框界面 facade（普通 Object，持于 _root.__nativeDialogueCompat）
    private static var _compat:Object = null;

    // 装到旧 MC 上的关闭桩：只做本地停住隐藏；持引用供 cancelActive 识别，
    // 防止 MC 分支回调桩自身造成无限递归。
    private static var _clipCloseStub:Function = null;

    // ── 安装 ────────────────────────────────────────────────────

    /** 幂等安装：场景 teardown 订阅 + cmd 路由 + facade 就位。 */
    public static function install():Void {
        if (_installed) return;
        _installed = true;
        NativeInteractionContext.install();
        NativeInteractionContext.onSceneTeardown(onSceneTeardown);
        if (_root.gameCommands == undefined) _root.gameCommands = {};
        _root.gameCommands["nativeDialogueAction"] = function(params:Object):Void {
            org.flashNight.arki.dialogue.NativeDialogueService.handleAction(params);
        };
        ensureCompat();
    }

    public static function isInstalled():Boolean {
        return _installed;
    }

    /** 测试/诊断只读观测面：活动会话的浅快照或 null；不暴露可变内部引用。 */
    public static function getSessionSnapshot():Object {
        var s:Object = _session;
        if (s == null) return null;
        return {
            requestId: s.requestId, sceneId: s.sceneId, revision: s.revision,
            index: s.index, lineCount: s.lines.length, mode: s.mode,
            terminal: s.terminal
        };
    }

    // ── 会话入口 ────────────────────────────────────────────────

    /**
     * 两个数组赋值入口的服务路由（对话文本.as 调用）。
     * @param rows      已归一化 7 元组行数组
     * @param overwrite true=覆盖（旧会话作废，不消费其 followingEvent）
     * @return 恒 true：服务一旦安装即接管，不走 legacy MovieClip 路径
     */
    public static function handleAssign(rows:Array, overwrite:Boolean):Boolean {
        install();
        if (rows == null) return true;
        if (_session != null && !_session.terminal) {
            if (overwrite === true) {
                // 旧 MovieClip 覆盖正文仍保留剧情后续；移交暂停责任，避免覆盖吞事件。
                if (_session.mode == "stage") {
                    var follow:Object = _session.followingEvent;
                    var leaseId:String = _session.leaseId;
                    _session.leaseId = null;
                    cancelSession("replace_stage_text");
                    beginSession(rows, "stage", follow, leaseId);
                    return true;
                }
                cancelSession("overwrite");
            } else {
                var incomingPortraits:Array = capturePortraits(rows);
                for (var i:Number = 0; i < rows.length; i++) {
                    _session.lines.push(rows[i]);
                    _session.portraits.push(incomingPortraits[i]);
                }
                // 旧入口追加数组后回到第 0 句；保持其行为，并递增 revision 拒绝旧行输入。
                if (!sendLine(0)) finishSession();
                return true;
            }
        }
        beginSession(rows, "ordinary", null);
        return true;
    }

    /**
     * StageEvent 剧情对白：AS2 侧持有可释放的暂停责任（claim），
     * followingEvent 只在显式 finish 时消费一次。
     * @param rawRows parseSingleDialogue 产出的原始行对象数组
     *        （{name,title,char,text,target,imageurl}），本函数内经
     *        _root.组装单次对话 归一化为 7 元组。
     */
    public static function beginStage(rawRows:Array, followingEvent:Object):Void {
        install();
        if (_session != null && !_session.terminal) cancelSession("superseded");
        var rows:Array = null;
        if (rawRows != null && rawRows.length > 0
                && typeof _root.组装单次对话 == "function") {
            rows = _root.组装单次对话(rawRows);
        }
        if (rows == null || rows.length == 0) {
            // 空对白不能软锁关卡：直接按 finish 语义消费一次后续事件
            publishFollow(followingEvent);
            return;
        }
        beginSession(rows, "stage", followingEvent);
    }

    // ── Host 入向动词 ───────────────────────────────────────────

    public static function handleAction(params:Object):Void {
        if (params == null) return;
        if (params.action != "nativeDialogueAction") return;
        var s:Object = _session;
        if (s == null || s.terminal) return;
        if (params.requestId !== s.requestId) return;
        if (params.sceneId !== s.sceneId) return;
        if (params.revision !== s.revision) return;
        if (params.verb == "advance") {
            advance();
        } else if (params.verb == "close") {
            finishSession();
        }
    }

    // ── 取消（场景切换 / compat 关闭 / 覆盖）────────────────────

    /** 供场景清理与 facade 调用：取消活动会话；服务缺席时兼容旧 MC 关闭。 */
    public static function cancelActive(reason:String):Void {
        if (_session != null && !_session.terminal) {
            cancelSession(reason);
            return;
        }
        var cur = _root.对话框界面;
        if (cur != null && cur !== _compat && typeof cur == "movieclip") {
            cur.followingEvent = null;
            if (typeof cur.关闭 == "function" && cur.关闭 !== _clipCloseStub) {
                cur.关闭();
            }
        }
    }

    // ── compat facade ───────────────────────────────────────────

    /**
     * 幂等建立/重绑 _root.对话框界面 facade（普通 Object）。
     * authored MovieClip（含 AVM1 同路径重绑回来的实例）停住+隐藏，
     * 其交互与 onClose 钩子全部换成安全桩——旧 onClose 裸写暂停并发布
     * followingEvent 的路径在 headless 下禁止复活。
     */
    public static function ensureCompat():Object {
        if (_compat == null) _compat = makeCompat();
        _root.__nativeDialogueCompat = _compat;
        if (_clipCloseStub == null) {
            // 只做 MC 本地收尾：停住+隐藏，不触发 onClose/暂停写/事件发布。
            _clipCloseStub = function():Void {
                this.stop();
                this._visible = false;
            };
        }
        var cur = _root.对话框界面;
        if (cur !== _compat && cur != null && typeof cur == "movieclip") {
            cur.stop();
            cur._visible = false;
            cur.刷新内容 = function():Void {};
            cur.打字 = function():Void {};
            cur.结束打字 = function():Void {};
            cur.下一句 = function():Void {};
            cur.onClose = function():Void {};
            cur.关闭 = _clipCloseStub;
        }
        _root.对话框界面 = _compat;
        syncCompat();
        return _compat;
    }

    private static function makeCompat():Object {
        var c:Object = {};
        c.本轮对话内容 = [];
        c.对话进度 = 0;
        c.对话条数 = 0;
        c.followingEvent = null;
        c._visible = false;
        c.gotoAndStop = function(label):Void {
            if (label == "close") {
                org.flashNight.arki.dialogue.NativeDialogueService.cancelActive("compat_close");
            }
        };
        c.刷新内容 = function():Void {};
        c.打字 = function():Void {};
        c.结束打字 = function():Void {};
        c.下一句 = function():Void {
            var svc = org.flashNight.arki.dialogue.NativeDialogueService;
            if (svc._session != null && !svc._session.terminal) svc.advance();
        };
        c.关闭 = function():Void {
            org.flashNight.arki.dialogue.NativeDialogueService.cancelActive("compat_close");
        };
        c.onClose = function():Void {
            org.flashNight.arki.dialogue.NativeDialogueService.finishSession();
        };
        c.刷新立绘 = function():Void {};
        c.刷新外部导入立绘 = function():Void {};
        return c;
    }

    private static function syncCompat():Void {
        if (_compat == null) return;
        var s:Object = _session;
        if (s != null && !s.terminal) {
            _compat.本轮对话内容 = s.lines;
            _compat.对话条数 = s.lines.length;
            _compat.对话进度 = s.index;
            _compat._visible = true;
        } else {
            _compat.本轮对话内容 = [];
            _compat.对话条数 = 0;
            _compat.对话进度 = 0;
            _compat._visible = false;
        }
    }

    // ── 内部：会话生命周期 ──────────────────────────────────────

    private static function beginSession(rows:Array, mode:String, followingEvent:Object, inheritedLease:String):Void {
        _reqSeq++;
        var s:Object = {
            requestId: "nd:" + _reqSeq,
            sceneId: NativeInteractionContext.getSceneId(),
            revision: 0,
            // NPC 会传持久对白数组；会话追加不能改写作者数据。
            lines: rows.concat(),
            portraits: capturePortraits(rows),
            index: 0,
            mode: mode,
            leaseId: inheritedLease == undefined ? null : inheritedLease,
            followingEvent: followingEvent,
            terminal: false
        };
        _session = s;
        if (mode == "stage" && s.leaseId == null) {
            s.leaseId = PauseManager.lease(true, "dialogue");
        }
        syncCompat();
        if (!sendLine(0)) finishSession(); // Host 不可达：按显式结束兜底，防剧情软锁
    }

    public static function advance():Void {
        var s:Object = _session;
        if (s == null || s.terminal) return;
        var next:Number = s.index + 1;
        if (next >= s.lines.length) {
            finishSession();
        } else if (!sendLine(next)) {
            finishSession();
        }
    }

    /** finish：terminal→清事件→清会话→放 claim→hide→publish（唯一消费点）。 */
    public static function finishSession():Void {
        var s:Object = _session;
        if (s == null || s.terminal) return;
        s.terminal = true;
        var ev:Object = (s.followingEvent != null) ? s.followingEvent
                        : ((_compat != null) ? _compat.followingEvent : null);
        s.followingEvent = null;
        if (_compat != null) _compat.followingEvent = null;
        _session = null;
        if (s.leaseId != null) PauseManager.releaseLease(s.leaseId);
        sendHide(s);
        syncCompat();
        publishFollow(ev);
    }

    /** cancel：terminal→清事件→清会话→放 claim→hide；绝不 publish。 */
    private static function cancelSession(reason:String):Void {
        var s:Object = _session;
        if (s == null || s.terminal) return;
        s.terminal = true;
        s.followingEvent = null;
        if (_compat != null) _compat.followingEvent = null;
        _session = null;
        if (s.leaseId != null) PauseManager.releaseLease(s.leaseId);
        sendHide(s);
        syncCompat();
    }

    private static function onSceneTeardown():Void {
        cancelActive("scene_teardown");
    }

    /** 对端已不可达，按现有发送失败语义结束，不能留下不可见的暂停责任。 */
    public static function onTransportDisconnected():Void {
        finishSession();
    }

    // ── 内部：wire ──────────────────────────────────────────────

    private static function sendLine(index:Number):Boolean {
        var s:Object = _session;
        if (s == null || s.terminal) return false;
        var row:Array = s.lines[index];
        if (row == null) return false;
        s.revision++;
        s.index = index;
        var img = row[6];
        var imageAction:String = "keep";
        var imagePath:String = "";
        if (typeof img == "string" && img != "") {
            if (img == "close") imageAction = "clear";
            else { imageAction = "show"; imagePath = img; }
        }
        var payload:Object = {
            version: 1,
            op: "show",
            requestId: s.requestId,
            sceneId: s.sceneId,
            revision: s.revision,
            lineIndex: index,
            lineCount: s.lines.length,
            name: row[0] == "角色名" ? String(_root.角色名) : ((row[0] != undefined) ? String(row[0]) : ""),
            title: (row[1] != undefined) ? String(row[1]) : "",
            text: (row[3] != undefined) ? String(row[3]) : "",
            portrait: s.portraits[index],
            imageAction: imageAction,
            imagePath: imagePath
        };
        var keyCode:Number = org.flashNight.arki.key.KeyManager.getKeySetting("互动键");
        if (!isNaN(keyCode)) payload.advanceKey = keyCode;
        syncCompat();
        return send(payload);
    }

    private static function sendHide(s:Object):Void {
        send({
            version: 1,
            op: "hide",
            requestId: s.requestId,
            sceneId: s.sceneId
        });
    }

    /** 入口即冻结每位说话人的独立外观；后续换行不再追已卸载或换装的 MC。 */
    private static function capturePortraits(rows:Array):Array {
        var result:Array = [];
        for (var i:Number = 0; i < rows.length; i++) {
            var row:Array = rows[i];
            result.push(NativeDialogueAppearance.build(row[2], row[4], row[5],
                row[0] == undefined ? "" : String(row[0])));
        }
        return result;
    }

    private static function send(payload:Object):Boolean {
        var sm:Object = _root.server;
        if (sm == undefined || !sm.isSocketConnected
                || typeof sm.sendTaskToNode != "function") return false;
        return sm.sendTaskToNode("native_dialogue", payload, null) === true;
    }

    private static function publishFollow(ev:Object):Void {
        if (ev == null || ev.name == null || ev.name == "") return;
        var d:Object = (_root.gameworld != null) ? _root.gameworld.dispatcher : null;
        if (d == null) return;
        if (ev.args != null && ev.args.length > 0) {
            d.publish.apply(d, [String(ev.name)].concat(ev.args));
        } else {
            d.publish(String(ev.name));
        }
    }
}
